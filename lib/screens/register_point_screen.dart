import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_cancellable_tile_provider/flutter_map_cancellable_tile_provider.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../models/field_point.dart';
import '../models/municipio_ibge.dart';
import '../providers/questionnaire_provider.dart';
import '../services/geo_municipio.dart';
import '../services/ibge_service.dart';
import '../services/location_service.dart';
import '../services/point_storage_service.dart';
import '../services/point_sync_service.dart';

/// Projeto disponível para o aplicador: os projetos dos questionários que o
/// painel liberou para ele (mesma regra do servidor em api/points).
class ProjetoDoApp {
  final int id;
  final String nome;
  const ProjetoDoApp(this.id, this.nome);

  static List<ProjetoDoApp> doProvider(QuestionnaireProvider provider) {
    final vistos = <int, String>{};
    for (final q in provider.questionnaires) {
      if (q.projectId != null) {
        vistos.putIfAbsent(q.projectId!, () => (q.projectName ?? '').isEmpty ? 'Projeto ${q.projectId}' : q.projectName!);
      }
    }
    final lista = vistos.entries.map((e) => ProjetoDoApp(e.key, e.value)).toList()
      ..sort((a, b) => a.nome.compareTo(b.nome));
    return lista;
  }
}

/// Registro de um ponto de campo: nome, tipo, projeto, município e posição
/// (GPS ou toque no mapa). Salva no aparelho primeiro; a fila envia ao
/// painel quando houver internet.
class RegisterPointScreen extends StatefulWidget {
  /// Projeto já escolhido (registro a partir da coleta de um questionário).
  final int? projectId;

  const RegisterPointScreen({super.key, this.projectId});

  @override
  State<RegisterPointScreen> createState() => _RegisterPointScreenState();
}

class _RegisterPointScreenState extends State<RegisterPointScreen> {
  static const _verde = Color(0xFF8FAE5D);
  static const _azul = Color(0xFF23345F);

  final _nome = TextEditingController();
  final _buscaMunicipio = TextEditingController();
  final _mapa = MapController();

  List<ProjetoDoApp> _projetos = const [];
  int? _projectId;
  String _tipo = 'comunidade';
  MunicipioIbge? _municipio;
  List<MunicipioIbge> _todosMunicipios = const [];
  List<MunicipioIbge> _sugestoes = const [];
  bool _carregandoMunicipios = true;

  String? _malha;
  List<List<LatLng>> _contornos = const [];
  LatLng? _posicao;
  String? _origem;
  bool _buscandoGps = false;
  bool _salvando = false;

  @override
  void initState() {
    super.initState();
    _projetos = ProjetoDoApp.doProvider(context.read<QuestionnaireProvider>());
    _projectId = widget.projectId ?? (_projetos.length == 1 ? _projetos.first.id : null);
    IbgeService.municipios().then((lista) {
      if (!mounted) return;
      setState(() {
        _todosMunicipios = lista;
        _carregandoMunicipios = false;
      });
    });
  }

  @override
  void dispose() {
    _nome.dispose();
    _buscaMunicipio.dispose();
    super.dispose();
  }

  Future<void> _escolherMunicipio(MunicipioIbge m) async {
    FocusScope.of(context).unfocus();
    setState(() {
      _municipio = m;
      _buscaMunicipio.text = m.rotulo;
      _sugestoes = const [];
      _malha = null;
      _contornos = const [];
    });
    final malha = await IbgeService.malha(m.codigo);
    if (!mounted || _municipio?.codigo != m.codigo) return;
    final contornos = malha == null
        ? <List<LatLng>>[]
        : GeoMunicipio.contornos(malha).map((anel) => anel.map((p) => LatLng(p[0], p[1])).toList()).toList();
    setState(() {
      _malha = malha;
      _contornos = contornos;
    });
    if (contornos.isNotEmpty && _posicao == null) {
      _mover(() => _mapa.fitCamera(CameraFit.bounds(
            bounds: LatLngBounds.fromPoints(contornos.expand((c) => c).toList()),
            padding: const EdgeInsets.all(24),
          )));
    }
  }

  Future<void> _usarGps() async {
    setState(() => _buscandoGps = true);
    final r = await LocationService.obterPosicao();
    if (!mounted) return;
    setState(() => _buscandoGps = false);
    if (!r.ok) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(r.erro ?? 'GPS indisponível.')));
      return;
    }
    final p = LatLng(r.position!.latitude, r.position!.longitude);
    setState(() {
      _posicao = p;
      _origem = 'gps';
    });
    _mover(() => _mapa.move(p, 15));
  }

  /// O mapa ainda pode não estar montado: mover é só conveniência
  void _mover(void Function() acao) {
    try {
      acao();
    } catch (e) {
      print('⚠️ Mapa ainda não pronto: $e');
    }
  }

  /// null = sem malha para conferir
  bool? get _dentro {
    if (_posicao == null || _malha == null) return null;
    return GeoMunicipio.contem(_malha, _posicao!.latitude, _posicao!.longitude);
  }

  Future<void> _salvar() async {
    final nome = _nome.text.trim();
    String? erro;
    if (_projectId == null) {
      erro = 'Escolha o projeto.';
    } else if (_municipio == null) {
      erro = 'Escolha o município.';
    } else if (nome.isEmpty) {
      erro = 'Informe o nome do ponto.';
    }
    if (erro != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(erro)));
      return;
    }

    if (_dentro == false) {
      final seguir = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Fora do município'),
          content: Text('A posição marcada fica fora de ${_municipio!.rotulo}. Salvar assim mesmo?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Corrigir')),
            TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Salvar')),
          ],
        ),
      );
      if (seguir != true || !mounted) return;
    }

    setState(() => _salvando = true);
    final projeto = _projetos.where((p) => p.id == _projectId).firstOrNull;
    final ponto = FieldPoint(
      // Gerado UMA vez, aqui: todo reenvio usa o mesmo valor e o painel
      // atualiza em vez de duplicar
      clientId: const Uuid().v4(),
      projectId: _projectId!,
      projectName: projeto?.nome,
      codigoIbge: _municipio!.codigo,
      municipioNome: _municipio!.nome,
      uf: _municipio!.uf,
      nome: nome.length > 150 ? nome.substring(0, 150) : nome,
      tipo: _tipo,
      latitude: _posicao?.latitude,
      longitude: _posicao?.longitude,
      origemCoord: _posicao == null ? null : _origem,
      dentroMunicipio: _dentro,
      createdAt: DateTime.now(),
    );

    // 1. Sempre no aparelho primeiro
    await PointStorageService.salvar(ponto);
    // 2. Tenta enviar já; sem internet, a sincronização envia depois
    unawaited(PointSyncService.enviarPendentes().catchError((_) => 0));

    if (!mounted) return;
    Navigator.pop(context, ponto);
  }

  @override
  Widget build(BuildContext context) {
    final dentro = _dentro;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Registrar ponto'),
        backgroundColor: _verde,
        foregroundColor: Colors.white,
      ),
      // SingleChildScrollView, não ListView: o ListView só monta o mapa quando
      // ele aparece na tela, e o MapController ainda não pode ser usado antes
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_projetos.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(12),
                child: Text('Nenhum projeto disponível. Atualize os questionários com internet: '
                    'os pontos são registrados nos projetos dos seus questionários.'),
              ),
            ),
          DropdownButtonFormField<int>(
            value: _projectId,
            decoration: const InputDecoration(labelText: 'Projeto', border: OutlineInputBorder()),
            items: [for (final p in _projetos) DropdownMenuItem(value: p.id, child: Text(p.nome, overflow: TextOverflow.ellipsis))],
            onChanged: widget.projectId != null ? null : (v) => setState(() => _projectId = v),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _buscaMunicipio,
            decoration: InputDecoration(
              labelText: 'Município',
              hintText: _carregandoMunicipios ? 'Carregando lista...' : 'Digite o nome',
              border: const OutlineInputBorder(),
              helperText: !_carregandoMunicipios && _todosMunicipios.isEmpty
                  ? 'Sem internet: a lista de municípios é baixada na primeira vez com conexão.'
                  : null,
            ),
            onChanged: (t) => setState(() {
              _municipio = null;
              _sugestoes = MunicipioIbge.buscar(_todosMunicipios, t, limite: 8);
            }),
          ),
          for (final m in _sugestoes)
            ListTile(dense: true, title: Text(m.rotulo), onTap: () => _escolherMunicipio(m)),
          const SizedBox(height: 12),
          TextField(
            controller: _nome,
            maxLength: 150,
            decoration: const InputDecoration(labelText: 'Nome do ponto', border: OutlineInputBorder()),
          ),
          DropdownButtonFormField<String>(
            value: _tipo,
            decoration: const InputDecoration(labelText: 'Tipo', border: OutlineInputBorder()),
            items: [for (final t in kTiposPonto) DropdownMenuItem(value: t, child: Text(kRotulosTipoPonto[t]!))],
            onChanged: (v) => setState(() => _tipo = v ?? 'comunidade'),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Text(
                  _posicao == null
                      ? 'Toque no mapa ou use o GPS para marcar a posição (opcional).'
                      : '${_posicao!.latitude.toStringAsFixed(6)}, ${_posicao!.longitude.toStringAsFixed(6)}'
                          ' (${_origem == 'gps' ? 'GPS' : 'marcado no mapa'})',
                  style: const TextStyle(fontSize: 12, color: _azul),
                ),
              ),
              TextButton.icon(
                onPressed: _buscandoGps ? null : _usarGps,
                icon: _buscandoGps
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.my_location),
                label: const Text('Minha localização'),
              ),
            ],
          ),
          if (dentro == false)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text('⚠ A posição fica fora do município escolhido.',
                  style: TextStyle(color: Colors.red, fontWeight: FontWeight.w600)),
            ),
          SizedBox(
            height: 320,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: FlutterMap(
                mapController: _mapa,
                options: MapOptions(
                  initialCenter: const LatLng(-14.5, -51.5),
                  initialZoom: 4,
                  onTap: (_, latlng) => setState(() {
                    _posicao = latlng;
                    _origem = 'mapa';
                  }),
                ),
                children: [
                  // Sem internet os tiles não carregam; o contorno guardado e o
                  // marcador continuam aparecendo
                  TileLayer(
                    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'br.com.sxdata.app',
                    tileProvider: CancellableNetworkTileProvider(),
                  ),
                  if (_contornos.isNotEmpty)
                    PolygonLayer(polygons: [
                      for (final c in _contornos)
                        Polygon(
                          points: c,
                          color: _verde.withOpacity(0.15),
                          borderColor: _verde,
                          borderStrokeWidth: 2,
                          isFilled: true,
                        ),
                    ]),
                  if (_posicao != null)
                    MarkerLayer(markers: [
                      Marker(
                        point: _posicao!,
                        width: 40,
                        height: 40,
                        child: Icon(Icons.location_on, size: 40, color: dentro == false ? Colors.red : _azul),
                      ),
                    ]),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: _salvando ? null : _salvar,
            style: ElevatedButton.styleFrom(
              backgroundColor: _verde,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            icon: const Icon(Icons.save),
            label: const Text('Salvar ponto'),
          ),
        ],
      ),
      ),
    );
  }
}

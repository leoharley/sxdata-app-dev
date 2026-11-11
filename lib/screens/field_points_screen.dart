import 'package:flutter/material.dart';

import '../models/field_point.dart';
import '../services/point_storage_service.dart';
import '../services/point_sync_service.dart';
import 'register_point_screen.dart';

/// Pontos de campo do aparelho e do painel, com a situação de envio.
class FieldPointsScreen extends StatefulWidget {
  const FieldPointsScreen({super.key});

  @override
  State<FieldPointsScreen> createState() => _FieldPointsScreenState();
}

class _FieldPointsScreenState extends State<FieldPointsScreen> {
  static const _verde = Color(0xFF8FAE5D);
  static const _azul = Color(0xFF23345F);

  List<FieldPoint> _pontos = const [];
  bool _carregando = true;
  String? _mensagem;

  @override
  void initState() {
    super.initState();
    _carregar(sincronizar: true);
  }

  Future<void> _carregar({bool sincronizar = false}) async {
    setState(() => _carregando = true);
    if (sincronizar) {
      await PointSyncService.enviarPendentes();
      final ok = await PointSyncService.atualizarDoServidor();
      _mensagem = !ok
          ? 'Sem conexão com o painel: mostrando os pontos guardados no aparelho.'
          : PointSyncService.ultimoErro;
    }
    final pontos = await PointStorageService.todos()
      ..sort((a, b) => a.nome.toLowerCase().compareTo(b.nome.toLowerCase()));
    if (!mounted) return;
    setState(() {
      _pontos = pontos;
      _carregando = false;
    });
  }

  Future<void> _registrar() async {
    final novo = await Navigator.push<FieldPoint>(
      context,
      MaterialPageRoute(builder: (_) => const RegisterPointScreen()),
    );
    if (novo != null) await _carregar();
  }

  @override
  Widget build(BuildContext context) {
    final pendentes = _pontos.where((p) => !p.isSynced).length;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pontos de campo'),
        backgroundColor: _verde,
        foregroundColor: Colors.white,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _registrar,
        backgroundColor: _verde,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_location_alt),
        label: const Text('Registrar ponto'),
      ),
      body: RefreshIndicator(
        onRefresh: () => _carregar(sincronizar: true),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
          children: [
            if (_carregando) const LinearProgressIndicator(color: _verde),
            if (_mensagem != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(_mensagem!, style: const TextStyle(fontSize: 12, color: Colors.orange)),
              ),
            if (pendentes > 0)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text('$pendentes ponto(s) ainda não enviado(s) ao painel. Puxe para baixo para enviar.',
                    style: const TextStyle(fontSize: 12, color: _azul)),
              ),
            if (!_carregando && _pontos.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Text('Nenhum ponto registrado ainda.\nUse "Registrar ponto" para marcar comunidades, '
                    'localidades e equipamentos e vincular coletas a eles.',
                    textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
              ),
            for (final p in _pontos) _item(p),
          ],
        ),
      ),
    );
  }

  Widget _item(FieldPoint p) {
    final (cor, rotulo) = switch (p.syncStatus) {
      'synced' => (const Color(0xFF198754), 'Enviado'),
      'error' => (Colors.red, 'Recusado'),
      _ => (Colors.orange, 'Pendente'),
    };
    return Card(
      child: ListTile(
        leading: Icon(
          p.tipo == 'equipamento' ? Icons.home_work : (p.tipo == 'localidade' ? Icons.place : Icons.groups),
          color: _azul,
        ),
        title: Text(p.nome),
        subtitle: Text([
          kRotulosTipoPonto[p.tipo] ?? p.tipo,
          if (p.municipioRotulo.isNotEmpty) p.municipioRotulo,
          if (p.projectName != null) p.projectName!,
          if (!p.temCoordenada) 'sem coordenada',
          if (p.coletas > 0) '${p.coletas} coleta(s)',
          if (p.dentroMunicipio == false) '⚠ fora do município',
          if (p.aviso != null && !p.isSynced) p.aviso!,
        ].join(' · ')),
        trailing: Text(rotulo, style: TextStyle(color: cor, fontSize: 12, fontWeight: FontWeight.w600)),
      ),
    );
  }
}

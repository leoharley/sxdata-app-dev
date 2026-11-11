import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/municipio_ibge.dart';

/// Lista de municípios e malhas (contornos) do IBGE, guardadas no aparelho.
///
/// As duas APIs do IBGE liberam CORS, então funcionam também na versão web.
/// Com internet, o app baixa e guarda; sem internet, usa o que já guardou
/// (por isso a malha é baixada quando o aplicador escolhe o município).
class IbgeService {
  IbgeService._();

  static const String _urlMunicipios =
      'https://servicodados.ibge.gov.br/api/v1/localidades/municipios?view=nivelado';
  static const String _urlMalha =
      'https://servicodados.ibge.gov.br/api/v3/malhas/municipios/{codigo}'
      '?formato=application/vnd.geo%2Bjson&qualidade=intermediaria';

  static const String _chaveMunicipios = 'ibge_municipios_v1';
  static const String _prefixoMalha = 'ibge_malha_';

  static List<MunicipioIbge>? _memoria;

  /// Lista completa. Do aparelho se já baixada; senão baixa (precisa de
  /// internet). Lista vazia = nunca baixada e sem internet agora.
  static Future<List<MunicipioIbge>> municipios() async {
    if (_memoria != null) return _memoria!;
    final prefs = await SharedPreferences.getInstance();
    final guardado = prefs.getString(_chaveMunicipios);
    if (guardado != null) {
      try {
        final lista = (jsonDecode(guardado) as List)
            .map(MunicipioIbge.fromCompact)
            .whereType<MunicipioIbge>()
            .toList();
        if (lista.isNotEmpty) return _memoria = lista;
      } catch (_) {}
    }

    try {
      final r = await http.get(Uri.parse(_urlMunicipios)).timeout(const Duration(seconds: 40));
      if (r.statusCode != 200) return const [];
      final lista = (jsonDecode(utf8.decode(r.bodyBytes)) as List)
          .map(MunicipioIbge.fromIbgeNivelado)
          .whereType<MunicipioIbge>()
          .toList();
      if (lista.isEmpty) return const [];
      await prefs.setString(_chaveMunicipios, jsonEncode(lista.map((m) => m.toCompact()).toList()));
      return _memoria = lista;
    } catch (e) {
      print('⚠️ Lista de municípios do IBGE indisponível: $e');
      return const [];
    }
  }

  static Future<MunicipioIbge?> municipio(int codigo) async {
    for (final m in await municipios()) {
      if (m.codigo == codigo) return m;
    }
    return null;
  }

  /// GeoJSON do município (texto), do aparelho ou do IBGE. null = sem
  /// internet e ainda não guardado.
  static Future<String?> malha(int codigo, {bool buscar = true}) async {
    final prefs = await SharedPreferences.getInstance();
    final guardada = prefs.getString('$_prefixoMalha$codigo');
    if (guardada != null && guardada.isNotEmpty) return guardada;
    if (!buscar) return null;

    try {
      final r = await http
          .get(Uri.parse(_urlMalha.replaceFirst('{codigo}', '$codigo')))
          .timeout(const Duration(seconds: 20));
      if (r.statusCode != 200) return null;
      final texto = utf8.decode(r.bodyBytes);
      final json = jsonDecode(texto);
      if (json is! Map || json['type'] == null) return null;
      await prefs.setString('$_prefixoMalha$codigo', texto); // ~5 KB por município
      return texto;
    } catch (e) {
      print('⚠️ Malha do município $codigo indisponível: $e');
      return null;
    }
  }
}

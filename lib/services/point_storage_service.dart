import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/field_point.dart';

/// Pontos de campo guardados no aparelho (SharedPreferences: no Android/iOS
/// e também na versão web, onde vira localStorage).
///
/// Mesmo cuidado das coletas (LocalStorageService): toda gravação passa por
/// uma fila, para uma sincronização em andamento não regravar a lista lida
/// antes de um ponto novo existir; e item que esta versão não lê é mantido
/// como está, nunca apagado.
class PointStorageService {
  PointStorageService._();

  static const String chave = 'field_points';

  static Future<void> _lock = Future<void>.value();

  @visibleForTesting
  static void resetWriteQueueForTesting() {
    _lock = Future<void>.value();
  }

  static Future<T> _comLock<T>(Future<T> Function() acao) {
    final completer = Completer<T>();
    _lock = _lock.then((_) async {
      try {
        completer.complete(await acao());
      } catch (e, s) {
        completer.completeError(e, s);
      }
    });
    return completer.future;
  }

  static Future<List<FieldPoint>> todos() async {
    final prefs = await SharedPreferences.getInstance();
    return _ler(prefs).$1;
  }

  /// (legíveis, ilegíveis preservados)
  static (List<FieldPoint>, List<dynamic>) _ler(SharedPreferences prefs) {
    final texto = prefs.getString(chave);
    if (texto == null || texto.isEmpty) return (<FieldPoint>[], <dynamic>[]);
    dynamic lista;
    try {
      lista = jsonDecode(texto);
    } catch (_) {
      lista = null;
    }
    if (lista is! List) return (<FieldPoint>[], <dynamic>[texto]);

    final pontos = <FieldPoint>[];
    final outros = <dynamic>[];
    for (final item in lista) {
      try {
        pontos.add(FieldPoint.fromJson(Map<String, dynamic>.from(item as Map)));
      } catch (_) {
        outros.add(item);
      }
    }
    return (pontos, outros);
  }

  static Future<void> _gravar(SharedPreferences prefs, List<FieldPoint> pontos, List<dynamic> outros) async {
    // Texto inteiro ilegível: guarda uma cópia antes de sobrescrever
    final soTexto = outros.length == 1 && outros.first is String;
    if (soTexto) {
      await prefs.setString('${chave}_corrompido_${DateTime.now().millisecondsSinceEpoch}', outros.first as String);
    }
    await prefs.setString(chave, jsonEncode([
      ...pontos.map((p) => p.toJson()),
      if (!soTexto) ...outros,
    ]));
  }

  /// Insere ou substitui pelo client_id.
  static Future<void> salvar(FieldPoint ponto) => salvarVarios([ponto]);

  static Future<void> salvarVarios(List<FieldPoint> novos) => _comLock(() async {
        final prefs = await SharedPreferences.getInstance();
        final (pontos, outros) = _ler(prefs);
        for (final n in novos) {
          final i = pontos.indexWhere((p) => p.clientId == n.clientId);
          if (i >= 0) {
            pontos[i] = n;
          } else {
            pontos.add(n);
          }
        }
        await _gravar(prefs, pontos, outros);
      });

  /// Substitui a lista inteira (depois de mesclar com o servidor).
  static Future<void> substituirTodos(List<FieldPoint> Function(List<FieldPoint> atuais) mesclar) =>
      _comLock(() async {
        final prefs = await SharedPreferences.getInstance();
        final (pontos, outros) = _ler(prefs);
        await _gravar(prefs, mesclar(pontos), outros);
      });

  static Future<FieldPoint?> porClientId(String clientId) async {
    for (final p in await todos()) {
      if (p.clientId == clientId) return p;
    }
    return null;
  }
}

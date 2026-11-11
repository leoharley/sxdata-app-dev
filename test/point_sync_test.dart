import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sxdata/models/field_point.dart';
import 'package:sxdata/models/form_response.dart';
import 'package:sxdata/models/question.dart';
import 'package:sxdata/providers/form_provider.dart';
import 'package:sxdata/services/local_storage_service.dart';
import 'package:sxdata/services/point_storage_service.dart';
import 'package:sxdata/services/point_sync_service.dart';

/// Fila dos pontos de campo contra um painel simulado (api/points e
/// api/forms), incluindo a ordem "pontos antes das coletas".
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _Painel painel;
  late Directory docs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    // A sincronização olha a fila de fotos do aparelho antes das coletas
    docs = await Directory.systemTemp.createTemp('sxdata_pontos_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => docs.path,
    );
    LocalStorageService.resetWriteQueueForTesting();
    PointStorageService.resetWriteQueueForTesting();
    painel = _Painel();
  });

  tearDown(() async {
    if (await docs.exists()) await docs.delete(recursive: true);
  });

  FieldPoint ponto(String id) => FieldPoint(
        clientId: id,
        projectId: 4,
        codigoIbge: 1713601,
        nome: 'Ponto $id',
        createdAt: DateTime(2026, 11, 1),
      );

  FormResponse coleta(int id, {String? ponto}) => FormResponse(
        id: id,
        questionnaireId: 17,
        appliedBy: 9,
        consentGiven: true,
        clientId: 'coleta-$id',
        pointClientId: ponto,
        startedAt: DateTime(2026, 11, 1, 8),
        completedAt: DateTime(2026, 11, 1, 8, 10),
        responses: const [],
      );

  Future<T> comPainel<T>(Future<T> Function() f) => http.runWithClient(f, () => painel.client);

  test('ponto confirmado sai da fila com o id do painel', () async {
    await PointStorageService.salvar(ponto('a'));
    expect(await comPainel(PointSyncService.enviarPendentes), 1);
    final salvo = (await PointStorageService.porClientId('a'))!;
    expect(salvo.isSynced, isTrue);
    expect(salvo.serverId, 1);
  });

  test('reenvio usa o mesmo client_id (painel não duplica)', () async {
    painel.falhar = true;
    await PointStorageService.salvar(ponto('a'));
    await comPainel(PointSyncService.enviarPendentes);
    expect((await PointStorageService.porClientId('a'))!.isPending, isTrue);

    painel.falhar = false;
    await comPainel(PointSyncService.enviarPendentes);
    expect(painel.pontos.map((p) => p['client_id']), ['a', 'a']);
    expect((await PointStorageService.porClientId('a'))!.isSynced, isTrue);
  });

  test('403 marca o ponto como recusado e ele não é reenviado em loop', () async {
    painel.status = 403;
    await PointStorageService.salvar(ponto('a'));
    await comPainel(PointSyncService.enviarPendentes);
    expect((await PointStorageService.porClientId('a'))!.syncStatus, 'error');

    painel.status = 200;
    await comPainel(PointSyncService.enviarPendentes);
    expect(painel.pontos, hasLength(1));
  });

  test('sincronização envia os pontos ANTES das coletas', () async {
    await PointStorageService.salvar(ponto('a'));
    await LocalStorageService.saveFormResponse(coleta(1, ponto: 'a'));

    await comPainel(() => FormProvider().syncPendingForms());

    expect(painel.ordem, ['points', 'forms']);
    expect(painel.coletas.single['point_client_id'], 'a');
    expect((await LocalStorageService.getFormResponseById(1))!.syncStatus, 'synced');
  });

  test('ponto que falha não segura a coleta (o painel completa o vínculo)', () async {
    painel.falhar = true;
    await PointStorageService.salvar(ponto('a'));
    await LocalStorageService.saveFormResponse(coleta(1, ponto: 'a'));

    await comPainel(() => FormProvider().syncPendingForms());

    expect((await LocalStorageService.getFormResponseById(1))!.syncStatus, 'synced');
    expect(painel.coletas.single['point_client_id'], 'a');
    expect((await PointStorageService.porClientId('a'))!.isPending, isTrue);
  });

  test('ponto escolhido vale só para a próxima coleta nova', () {
    final provider = FormProvider();
    final perguntas = <Question>[];
    provider.vincularProximaColetaAoPonto('a');
    provider.startForm(17, 9, perguntas);
    expect(provider.currentForm!.pointClientId, 'a');

    provider.startForm(17, 9, perguntas);
    expect(provider.currentForm!.pointClientId, isNull);
  });

  test('pontos do servidor entram no aparelho sem apagar os pendentes', () async {
    await PointStorageService.salvar(ponto('local'));
    painel.remotos = [
      {'id': 5, 'client_id': 'outro-aplicador', 'project_id': 4, 'codigo_ibge': 1713601, 'nome': 'Remoto'},
    ];
    expect(await comPainel(() => PointSyncService.atualizarDoServidor()), isTrue);
    final todos = {for (final p in await PointStorageService.todos()) p.clientId: p};
    expect(todos.keys, containsAll(['local', 'outro-aplicador']));
    expect(todos['local']!.isPending, isTrue);
    expect(todos['outro-aplicador']!.isSynced, isTrue);
  });
}

class _Painel {
  bool falhar = false;
  int status = 200;
  final List<String> ordem = [];
  final List<Map<String, dynamic>> pontos = [];
  final List<Map<String, dynamic>> coletas = [];
  List<Map<String, dynamic>> remotos = [];
  int _id = 1;

  late final http.Client client = MockClient((req) async {
    final caminho = req.url.path;
    if (caminho.endsWith('/points/submit')) {
      ordem.add('points');
      pontos.add(jsonDecode(req.body) as Map<String, dynamic>);
      if (falhar) return http.Response(jsonEncode({'success': false, 'message': 'falha'}), 500);
      if (status != 200) {
        return http.Response(jsonEncode({'success': false, 'message': 'Sem acesso'}), status);
      }
      return http.Response(jsonEncode({'success': true, 'id': _id++, 'dentro_municipio': true}), 200);
    }
    if (caminho.endsWith('/points')) {
      return http.Response(jsonEncode({'success': true, 'data': remotos}), 200);
    }
    if (caminho.endsWith('/forms/submit')) {
      ordem.add('forms');
      coletas.add(jsonDecode(req.body) as Map<String, dynamic>);
      return http.Response(
          jsonEncode({'success': true, 'id': 100 + coletas.length, 'missing_media': []}), 200);
    }
    return http.Response('{}', 404);
  });
}

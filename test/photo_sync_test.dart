import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sxdata/models/form_response.dart';
import 'package:sxdata/providers/form_provider.dart';
import 'package:sxdata/services/local_storage_service.dart';
import 'package:sxdata/services/photo_storage_service.dart';

/// Foto de evidência registrada que não chegava ao painel.
///
/// Cada cenário de ponta a ponta roda a sincronização real (FormProvider →
/// PhotoStorageService → ApiService) contra um servidor simulado, que guarda
/// as fotos recebidas e responde como o painel (incluindo missing_media).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory docs;
  late _Servidor servidor;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    docs = await Directory.systemTemp.createTemp('sxdata_fotos_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => docs.path,
    );
    servidor = _Servidor();
  });

  tearDown(() async {
    if (await docs.exists()) await docs.delete(recursive: true);
  });

  Future<File> fotoNoAparelho(String nome) async {
    final f = File('${docs.path}/camera_$nome.jpg');
    await f.writeAsBytes(List<int>.generate(64, (i) => i));
    return f;
  }

  FormResponse coleta(int id, {String? foto}) => FormResponse(
        id: id,
        questionnaireId: 17,
        appliedBy: 9,
        consentGiven: true,
        clientId: 'client-$id',
        syncStatus: 'pending',
        photoPath: foto,
        startedAt: DateTime(2026, 10, 18, 8),
        completedAt: DateTime(2026, 10, 18, 8, 10),
        responses: const [],
      );

  Future<String> statusDa(int id) async =>
      (await LocalStorageService.getFormResponseById(id))!.syncStatus;

  Future<void> sincronizar() => http.runWithClient(
        () => FormProvider().syncPendingForms(),
        () => servidor.client,
      );

  test('foto que falhou uma vez é reenviada e a coleta é confirmada',
      () async {
    final nome = await PhotoStorageService.savePhotoOffline(
        await fotoNoAparelho('a'), 1);
    await PhotoStorageService.updatePhotoSyncStatus(nome, 'error');
    await LocalStorageService.saveFormResponse(coleta(1, foto: nome));

    await sincronizar();

    expect(servidor.fotos, contains(nome));
    expect(await statusDa(1), 'synced');
  });

  test('foto com problema segura só a própria coleta', () async {
    final nome = await PhotoStorageService.savePhotoOffline(
        await fotoNoAparelho('b'), 2);
    servidor.recusar.add(nome);
    await LocalStorageService.saveFormResponse(coleta(2, foto: nome));
    await LocalStorageService.saveFormResponse(coleta(3));

    await sincronizar();

    expect(await statusDa(2), isNot('synced'));
    expect(await statusDa(3), 'synced',
        reason: 'a coleta sem foto não pode ficar presa pela foto da outra');
  });

  test('coleta antiga com caminho do aparelho em photo_path: a foto sobe',
      () async {
    final arquivo = await fotoNoAparelho('c');
    await LocalStorageService.saveFormResponse(coleta(4, foto: arquivo.path));

    await sincronizar();

    final enviada = servidor.coletas.single;
    expect(enviada['photo_path'], isNot(contains('/')));
    expect(servidor.fotos, contains(enviada['photo_path']));
    expect(await statusDa(4), 'synced');
  });

  test('servidor sem a foto da coleta: a foto volta para a fila e sobe',
      () async {
    final nome = await PhotoStorageService.savePhotoOffline(
        await fotoNoAparelho('d'), 5);
    // O app achava que a foto tinha subido; o servidor não tem o arquivo
    await PhotoStorageService.updatePhotoSyncStatus(nome, 'synced');
    await LocalStorageService.saveFormResponse(coleta(5, foto: nome));

    await sincronizar();
    expect(await statusDa(5), isNot('synced'),
        reason: 'não pode confirmar a coleta com a foto faltando no painel');

    await sincronizar();
    expect(servidor.fotos, contains(nome));
    expect(await statusDa(5), 'synced');
  });

  test('servidor gravou a foto com outro nome: a coleta cita esse nome',
      () async {
    final nome = await PhotoStorageService.savePhotoOffline(
        await fotoNoAparelho('e'), 6);
    servidor.renomear[nome] = 'renomeada_$nome';
    await LocalStorageService.saveFormResponse(coleta(6, foto: nome));

    await sincronizar();

    expect(servidor.coletas.single['photo_path'], 'renomeada_$nome');
    expect(await statusDa(6), 'synced');
  });

  group('peças', () {
    test('pendingMediaOfForm: foto pendente e partes do áudio web', () {
      final f = coleta(1, foto: 'photo_1.jpg')
          .copyWith(audioPath: 'audio_web_123_p1.m4a');
      expect(FormProvider.pendingMediaOfForm(f, {}), isEmpty);
      expect(FormProvider.pendingMediaOfForm(f, {'outra.jpg'}), isEmpty);
      expect(FormProvider.pendingMediaOfForm(f, {'photo_1.jpg'}),
          ['photo_1.jpg']);
      expect(FormProvider.pendingMediaOfForm(f, {'audio_web_123_p3.m4a'}),
          ['audio_web_123_p3.m4a']);
      expect(FormProvider.pendingMediaOfForm(f, {'audio_web_1234_p1.m4a'}),
          isEmpty);
    });

    test('foto cujo arquivo sumiu não prende coleta (lost)', () async {
      final arquivo = await fotoNoAparelho('f');
      final nome = await PhotoStorageService.savePhotoOffline(arquivo, 7);
      await File('${docs.path}/offline_photos/$nome').delete();
      expect(await PhotoStorageService.pendingFilenames(), isEmpty);
    });

    test('setPhoto sem formulário avisa; clearPhoto tira a foto', () {
      final p = FormProvider();
      expect(p.setPhoto('photo_1.jpg'), isFalse);
      expect(coleta(1, foto: 'x.jpg').copyWith(clearPhotoPath: true).photoPath,
          isNull);
      expect(coleta(1, foto: 'x.jpg').copyWith().photoPath, 'x.jpg');
    });

    test('replaceMediaReference troca só o campo que citava o nome', () async {
      await LocalStorageService.saveFormResponse(
          coleta(8, foto: 'a.jpg').copyWith(photoPath2: 'b.jpg'));
      expect(await LocalStorageService.replaceMediaReference('a.jpg', 'a2.jpg'),
          1);
      final f = (await LocalStorageService.getFormResponseById(8))!;
      expect(f.photoPath, 'a2.jpg');
      expect(f.photoPath2, 'b.jpg');
    });
  });
}

/// Painel simulado: guarda as fotos recebidas e responde ao forms/submit
/// com missing_media, como o Forms.php.
class _Servidor {
  final Set<String> fotos = {};
  final Set<String> recusar = {};
  final Map<String, String> renomear = {};
  final List<Map<String, dynamic>> coletas = [];
  int _proximoId = 100;

  late final http.Client client = MockClient((req) async {
    final caminho = req.url.path;

    if (caminho.endsWith('/photos/upload')) {
      final corpo = latin1.decode(req.bodyBytes);
      final nome = RegExp(r'filename="([^"]+)"').firstMatch(corpo)!.group(1)!;
      if (recusar.contains(nome)) {
        return http.Response(jsonEncode({'success': false, 'message': 'x'}), 500);
      }
      final gravado = renomear[nome] ?? nome;
      fotos.add(gravado);
      return http.Response(
          jsonEncode({'success': true, 'filename': gravado}), 200);
    }

    if (caminho.endsWith('/forms/submit')) {
      final json = jsonDecode(req.body) as Map<String, dynamic>;
      coletas.add(json);
      final faltando = [json['photo_path'], json['photo_path_2']]
          .whereType<String>()
          .where((n) => n.isNotEmpty && !fotos.contains(n))
          .toList();
      return http.Response(
          jsonEncode({
            'success': true,
            'id': _proximoId++,
            'missing_media': faltando,
          }),
          200);
    }

    return http.Response('{}', 404);
  });
}

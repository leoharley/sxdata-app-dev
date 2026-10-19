import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sxdata/models/form_response.dart';
import 'package:sxdata/services/local_storage_service.dart';

/// Atualizar o app não pode perder coletas pendentes.
///
/// O armazenamento é uma lista JSON na chave 'form_responses', regravada
/// inteira a cada alteração. Antes:
/// - um registro que a versão nova não conseguisse ler era pulado na
///   leitura e APAGADO na gravação seguinte;
/// - no saveFormResponse, um único registro ilegível fazia a lista
///   recomeçar vazia: salvar a próxima entrevista apagava TODAS as pendentes.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // Exatamente o formato gravado pela versão 1.0.0+3 (nov/2025, 3138e70):
  // sem client_id, audio_path, server_id.
  Map<String, dynamic> coletaV1(int id, {String? foto}) => {
        'id': id,
        'questionnaire_id': 16,
        'respondent_name': null,
        'respondent_email': null,
        'applied_by': 5,
        'latitude': -10.70,
        'longitude': -48.41,
        'location_name': null,
        'photo_path': foto,
        'photo_path_2': null,
        'consent_given': true,
        'sync_status': 'pending',
        'started_at': '2025-11-25T09:00:00.000',
        'completed_at': '2025-11-25T09:20:00.000',
        'edited_at': null,
        'responses': [
          {'question_id': 300, 'response_text': 'Sim', 'response_number': null,
            'response_date': null, 'response_datetime': null,
            'selected_options': null},
        ],
      };

  Future<void> gravar(List<dynamic> lista) async =>
      SharedPreferences.setMockInitialValues(
          {'flutter.form_responses': jsonEncode(lista)});

  FormResponse nova(int id) => FormResponse(
        id: id,
        questionnaireId: 17,
        appliedBy: 9,
        consentGiven: true,
        syncStatus: 'pending',
        startedAt: DateTime(2026, 10, 19, 9),
        completedAt: DateTime(2026, 10, 19, 9, 10),
        responses: const [],
      );

  test('coletas da versão 1.0.0+3 são lidas pela versão nova', () async {
    await gravar([coletaV1(1, foto: 'form_1_photo1_1.jpg'), coletaV1(2)]);

    final pendentes = await LocalStorageService.getFormResponses();

    expect(pendentes.map((f) => f.id), [1, 2]);
    expect(pendentes.first.photoPath, 'form_1_photo1_1.jpg');
    expect(pendentes.first.responses.single.responseText, 'Sim');
  });

  test('números gravados como texto/inteiro (navegador) continuam legíveis',
      () async {
    final c = coletaV1(3)
      ..['questionnaire_id'] = '16'
      ..['latitude'] = -10
      ..['responses'] = [
        {'question_id': '300', 'response_number': 35, 'selected_options': 'A'},
      ];
    await gravar([c]);

    final f = (await LocalStorageService.getFormResponses()).single;
    expect(f.questionnaireId, 16);
    expect(f.latitude, -10.0);
    expect(f.responses.single.responseNumber, 35.0);
    expect(f.responses.single.selectedOptions, ['A']);
  });

  test('salvar entrevista nova não apaga coleta que esta versão não lê',
      () async {
    final ilegivel = {'id': 9, 'algo': 'formato de uma versão futura'};
    await gravar([coletaV1(1), ilegivel]);

    await LocalStorageService.saveFormResponse(nova(50));
    await LocalStorageService.updateFormSyncStatus(1, 'synced', serverId: 7);

    final prefs = await SharedPreferences.getInstance();
    final bruto = jsonDecode(prefs.getString('form_responses')!) as List;
    expect(bruto.any((e) => e is Map && e['algo'] == ilegivel['algo']),
        isTrue,
        reason: 'o registro ilegível fica');
    final ids = (await LocalStorageService.getFormResponses()).map((f) => f.id);
    expect(ids, containsAll([1, 50]));
  });

  test('lista corrompida é guardada antes de ser sobrescrita', () async {
    SharedPreferences.setMockInitialValues(
        {'flutter.form_responses': '[{"id":1, corrompido'});

    await LocalStorageService.saveFormResponse(nova(51));

    final prefs = await SharedPreferences.getInstance();
    final copia = prefs.getKeys().where((k) => k.startsWith('form_responses_corrompido_'));
    expect(copia, hasLength(1));
    expect(prefs.getString(copia.single), '[{"id":1, corrompido');
  });

  test('gravações simultâneas não perdem a coleta nova', () async {
    await gravar([coletaV1(1)]);

    await Future.wait([
      LocalStorageService.updateFormSyncStatus(1, 'synced', serverId: 7),
      LocalStorageService.saveFormResponse(nova(52)),
      LocalStorageService.updateFormResponse(
          FormResponse.fromJson(coletaV1(1)).copyWith(photoPath: 'x.jpg')),
    ]);

    final ids = (await LocalStorageService.getFormResponses()).map((f) => f.id);
    expect(ids, containsAll([1, 52]));
  });
}

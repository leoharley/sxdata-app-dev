import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sxdata/models/question.dart';
import 'package:sxdata/models/questionnaire.dart';
import 'package:sxdata/models/user.dart';
import 'package:sxdata/providers/auth_provider.dart';
import 'package:sxdata/providers/form_provider.dart';
import 'package:sxdata/screens/photo_capture_screen.dart';
import 'package:sxdata/services/local_storage_service.dart';

/// "Requer foto" no painel: o app não pode finalizar a coleta sem foto.
///
/// A checagem existia mas estava comentada: a coleta subia sem foto mesmo
/// com o questionário exigindo (ex.: respostas 146 e 147 do questionário 17).
void main() {
  Questionnaire questionario({required bool requerFoto}) => Questionnaire(
        id: 17,
        title: 'TESTE 2',
        description: '',
        createdBy: 1,
        status: 'active',
        requiresConsent: false,
        requiresLocation: false,
        requiresPhoto: requerFoto,
        version: '1',
        createdAt: DateTime(2026, 9, 30),
        updatedAt: DateTime(2026, 9, 30),
        questions: [
          Question(id: 1, questionnaireId: 17, questionText: 'Nome',
              questionType: 'text', isRequired: false, orderIndex: 1),
        ],
      );

  setUp(() => SharedPreferences.setMockInitialValues({}));

  // A fonte do ambiente de teste é larga: o texto da caixa de altura fixa da
  // segunda foto quebra em mais linhas e "estoura". Não é deste teste.
  Future<void> semEstouroDeLayout(Future<void> Function() corpo) async {
    final original = FlutterError.onError;
    FlutterError.onError = (d) {
      if (!d.exceptionAsString().contains('overflowed')) original?.call(d);
    };
    try {
      await corpo();
    } finally {
      FlutterError.onError = original;
    }
  }

  Future<FormProvider> abrir(WidgetTester tester, Questionnaire q,
      {String? foto}) async {
    final form = FormProvider()..startForm(q.id, 9, q.questions);
    if (foto != null) form.setPhoto(foto);
    final auth = AuthProvider()
      ..setUser(User(id: 9, username: 'aplicador3', email: 'a@a.com',
          fullName: 'Aplicador3', role: 'aplicador', isActive: true));

    tester.view.physicalSize = const Size(1440, 3600); // fonte de teste é larga
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: form),
        ChangeNotifierProvider.value(value: auth),
      ],
      child: MaterialApp(home: PhotoCaptureScreen(questionnaire: q)),
    ));
    await tester.pump();
    return form;
  }

  Future<void> finalizar(WidgetTester tester) async {
    await tester.tap(find.text('Finalizar'));
    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 300)));
    await tester.pump();
  }

  testWidgets('"Requer foto" sem foto: não finaliza e explica o motivo',
      (tester) => semEstouroDeLayout(() async {
    final form = await abrir(tester, questionario(requerFoto: true));

    await finalizar(tester);

    expect(find.text('Este questionário exige foto. Tire a foto para finalizar.'),
        findsOneWidget);
    expect(form.currentForm, isNotNull, reason: 'a coleta continua aberta');
    final salvas = await tester.runAsync(LocalStorageService.getFormResponses);
    expect(salvas, isEmpty, reason: 'nada pode ser salvo para envio');
  }));

  testWidgets('"Requer foto" com foto: finaliza',
      (tester) => semEstouroDeLayout(() async {
    await abrir(tester, questionario(requerFoto: true), foto: 'photo_1.jpg');

    await finalizar(tester);

    final salvas = await tester.runAsync(LocalStorageService.getFormResponses);
    expect(salvas!.single.photoPath, 'photo_1.jpg');
  }));

  testWidgets('foto opcional: finaliza sem foto',
      (tester) => semEstouroDeLayout(() async {
    await abrir(tester, questionario(requerFoto: false));

    await finalizar(tester);

    final salvas = await tester.runAsync(LocalStorageService.getFormResponses);
    expect(salvas, hasLength(1));
  }));

  test('regra: edição não exige foto nova', () {
    bool faltando(bool requer, bool edicao, String? foto) =>
        PhotoCaptureScreen.fotoObrigatoriaFaltando(
            requiresPhoto: requer, isEditMode: edicao, photoPath: foto);

    expect(faltando(true, false, null), isTrue);
    expect(faltando(true, false, '  '), isTrue);
    expect(faltando(true, false, 'photo_1.jpg'), isFalse);
    expect(faltando(false, false, null), isFalse);
    expect(faltando(true, true, null), isFalse);
  });
}

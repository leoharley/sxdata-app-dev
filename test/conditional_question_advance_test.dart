import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sxdata/models/question.dart';
import 'package:sxdata/models/question_option.dart';
import 'package:sxdata/models/questionnaire.dart';
import 'package:sxdata/models/user.dart';
import 'package:sxdata/providers/auth_provider.dart';
import 'package:sxdata/providers/form_provider.dart';
import 'package:sxdata/screens/question_screen.dart';

/// "Próxima" não avançava na pergunta aberta que aparece por lógica condicional.
///
/// Caso real: questionário 18 (Diagnóstico de Viabilidade Técnica), P4 = "Não"
/// mostra a P5 (opcional). Na P5, "Próxima" não fazia nada.
///
/// A física do PageView guardava a lista de perguntas visíveis do PRIMEIRO
/// build (sem a P5). O Scrollable só troca a física quando muda o tipo, então
/// ela continuava avaliando essa lista velha: no índice da P5 enxergava a P6
/// (obrigatória, sem resposta) e travava a animação do nextPage() sem aviso.
void main() {
  QuestionOption opcao(int id, int questionId, String texto, String valor) =>
      QuestionOption(
        id: id,
        optionText: texto,
        optionValue: valor,
        orderIndex: id,
      );

  // Estrutura igual à devolvida por GET /api/questionnaires (ids reais)
  Questionnaire questionario() => Questionnaire(
        id: 18,
        title: 'Diagnóstico de Viabilidade Técnica',
        description: '',
        createdBy: 1,
        status: 'active',
        requiresConsent: false,
        requiresLocation: false,
        requiresPhoto: false,
        version: '1',
        createdAt: DateTime(2026, 10, 1),
        updatedAt: DateTime(2026, 10, 1),
        questions: [
          Question(id: 457, questionnaireId: 18, questionText: 'Nome Completo',
              questionType: 'text', isRequired: true, orderIndex: 1),
          Question(id: 458, questionnaireId: 18, questionText: 'Telefone de contato',
              questionType: 'number', isRequired: true, orderIndex: 2),
          Question(id: 459, questionnaireId: 18, questionText: 'Endereço da residência',
              questionType: 'text', isRequired: true, orderIndex: 3),
          Question(id: 460, questionnaireId: 18,
              questionText: 'O(a) entrevistado(a) é o(a) responsável pela família?',
              questionType: 'radio', isRequired: true, orderIndex: 4,
              options: [opcao(1, 460, 'Sim', 'sim'), opcao(2, 460, 'Não', 'não')]),
          Question(id: 461, questionnaireId: 18,
              questionText: 'Qual é o nome do(a) responsável pela família?',
              questionType: 'text', isRequired: false, orderIndex: 5,
              conditionalLogic: {
                'visibility': {
                  'operator': 'AND',
                  'conditions': [
                    {'question': '460', 'operator': 'equals', 'value': 'Não'},
                  ],
                },
                'required': null,
              }),
          Question(id: 462, questionnaireId: 18,
              questionText: 'Qual é a condição de ocupação do imóvel?',
              questionType: 'radio', isRequired: true, orderIndex: 6,
              options: [
                opcao(3, 462, 'Próprio', 'próprio'),
                opcao(4, 462, 'Outra', 'outra'),
              ]),
          Question(id: 597, questionnaireId: 18, questionText: "Especifique 'Outra'",
              questionType: 'text', isRequired: false, orderIndex: 7,
              conditionalLogic: {
                'visibility': {
                  'operator': 'AND',
                  'conditions': [
                    {'question': '462', 'operator': 'equals', 'value': 'Outra'},
                  ],
                },
                'required': null,
              }),
          Question(id: 463, questionnaireId: 18,
              questionText: 'Quantos cômodos possui a casa?',
              questionType: 'text', isRequired: true, orderIndex: 8),
        ],
      );

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    // Gravador de áudio e tela sempre ligada: plugins sem implementação no teste
    messenger.setMockMethodCallHandler(
        const MethodChannel('com.llfbandit.record/messages'), (_) async => null);
    for (final api in ['toggle', 'isEnabled']) {
      messenger.setMockMessageHandler(
        'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.$api',
        (_) async => const StandardMessageCodec()
            .encodeMessage(<Object?>[api == 'isEnabled' ? false : null]),
      );
    }
  });

  Future<void> abrir(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 2560); // fonte de teste é larga
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final auth = AuthProvider()
      ..setUser(User(
        id: 9,
        username: 'aplicador3',
        email: 'a@a.com',
        fullName: 'Aplicador3',
        role: 'aplicador',
        isActive: true,
      ));

    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => FormProvider()),
        ChangeNotifierProvider.value(value: auth),
      ],
      child: MaterialApp(
        home: QuestionScreen(questionnaire: questionario(), currentQuestionIndex: 0),
      ),
    ));
    await tester.pump(); // post-frame: inicializa o FormProvider
    await tester.pump(const Duration(milliseconds: 100));
  }

  Future<void> proxima(WidgetTester tester) async {
    await tester.tap(find.text('Próxima'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400)); // animação do nextPage
  }

  Future<void> digitar(WidgetTester tester, String texto) async {
    await tester.enterText(find.byType(TextField).last, texto);
    await tester.pump();
  }

  testWidgets('P4 = "Não" mostra a P5, e "Próxima" na P5 leva à P6',
      (tester) async {
    await abrir(tester);

    expect(find.text('Nome Completo'), findsOneWidget);
    await digitar(tester, 'Maria');
    await proxima(tester);

    await digitar(tester, '93991234567');
    await proxima(tester);

    await digitar(tester, 'Rua A, 10');
    await proxima(tester);

    expect(find.text('O(a) entrevistado(a) é o(a) responsável pela família?'),
        findsOneWidget);
    await tester.tap(find.text('Não'));
    await tester.pump();
    await proxima(tester);

    // P5: só aparece por causa do "Não"
    expect(find.text('Qual é o nome do(a) responsável pela família?'),
        findsOneWidget);
    await digitar(tester, 'José');
    await proxima(tester);

    expect(find.text('Qual é a condição de ocupação do imóvel?'), findsOneWidget,
        reason: '"Próxima" na P5 tem que levar à P6');
  });

  testWidgets('P5 é opcional: "Próxima" avança mesmo sem resposta',
      (tester) async {
    await abrir(tester);

    await digitar(tester, 'Maria');
    await proxima(tester);
    await digitar(tester, '93991234567');
    await proxima(tester);
    await digitar(tester, 'Rua A, 10');
    await proxima(tester);
    await tester.tap(find.text('Não'));
    await tester.pump();
    await proxima(tester);

    expect(find.text('Qual é o nome do(a) responsável pela família?'),
        findsOneWidget);
    await proxima(tester);

    expect(find.text('Qual é a condição de ocupação do imóvel?'), findsOneWidget);
  });
}

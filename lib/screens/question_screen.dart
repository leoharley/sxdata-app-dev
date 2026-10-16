import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/questionnaire.dart';
import '../models/question.dart';
import '../providers/form_provider.dart';
import '../providers/stratification_provider.dart';
import '../widgets/question_widgets.dart';
import 'photo_capture_screen.dart';
import 'form_completed_screen.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../providers/auth_provider.dart';
import '../services/location_service.dart';
import '../services/platform_caps.dart';
import '../services/web_media_store/web_media_store.dart';
import '../utils/phone_format.dart';
import '../widgets/location_required_dialog.dart';

class QuestionScreen extends StatefulWidget {
  final Questionnaire questionnaire;
  final int currentQuestionIndex;

  const QuestionScreen({
    super.key,
    required this.questionnaire,
    required this.currentQuestionIndex,
  });

  @override
  State<QuestionScreen> createState() => _QuestionScreenState();
}

class _QuestionScreenState extends State<QuestionScreen>
    with WidgetsBindingObserver {
  late PageController _pageController;
  final Map<int, dynamic> _currentAnswers = {};
  int _currentVisibleIndex = 0;
  bool _isInitialized = false;

  // Audio recording
  final AudioRecorder _audioRecorder = AudioRecorder();
  bool _isRecording = false;
  String? _audioPath;
  Timer? _recordingTimer;
  int _recordingSeconds = 0;

  // Web: gravação por segmentos com tela ativa (docs/plano_versao_web.md).
  // Cada segmento vai para o IndexedDB assim que fechado — interrupção
  // (ligação, troca de aba) nunca perde o que já foi gravado.
  int _webSegmentSeq = 0;
  String? _webSessionId;
  String? _webFirstSegmentFilename;
  String _webAudioExt = 'm4a';

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: 0);
    WidgetsBinding.instance.addObserver(this);

    // Tela ativa durante toda a aplicação (nativo e web): não deixar a tela
    // apagar no meio da entrevista/gravação.
    WakelockPlus.enable();

    // Aquecer o GPS desde já, em vez de partir do zero na finalização: o
    // primeiro fix pode levar bem mais de meio minuto num aparelho parado, e
    // esperar isso no fim da entrevista era o que fazia a captura falhar.
    if (widget.questionnaire.requiresLocation) {
      LocationService.limpar();
      LocationService.iniciarAquecimento();
    }

    print('🚀 === QUESTION SCREEN INICIADO ===');
    print('📝 Número de questões: ${widget.questionnaire.questions.length}');

    // Debug das questões
    for (int i = 0; i < widget.questionnaire.questions.length; i++) {
      final question = widget.questionnaire.questions[i];
      print('📝 [$i] ID ${question.id}: "${question.questionText}"');
      if (question.hasConditionalLogic) {
        print('🔧   Lógica: ${question.conditionalLogicSummary}');
      }
    }

    // Inicializar FormProvider IMEDIATAMENTE
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeFormProvider();
    });
  }

  void _initializeFormProvider() {
    print('📄 === INICIALIZANDO FORM PROVIDER ===');

    try {
      final formProvider = Provider.of<FormProvider>(context, listen: false);
      final authProvider = Provider.of<AuthProvider>(context, listen: false);

      // VERIFICAR SE ESTÁ EM MODO DE EDIÇÃO
      if (formProvider.isEditMode) {
        print('✏️ MODO DE EDIÇÃO DETECTADO - Mantendo respostas existentes');
        print('📝 Respostas carregadas: ${formProvider.responses.length}');
        print('📝 Formulário atual: ${formProvider.currentForm}');

        // Verificar se já existe um formulário atual
        if (formProvider.currentForm == null) {
          // Se não existe, criar um novo formulário para edição
          print('📝 Criando formulário de edição...');
          formProvider.startForm(
            widget.questionnaire.id,
            authProvider.user!.id,
            widget.questionnaire.questions,
          );
        } else {
          // Se já existe, apenas inicializar as questões
          print('📝 Formulário já existe, inicializando questões...');
          formProvider.initialize(widget.questionnaire.questions);
        }

        // Executar lógica condicional com as respostas já carregadas
        formProvider.debugConditionalLogic();

        setState(() {
          _isInitialized = true;
        });

        // Iniciar gravação de áudio automaticamente
        _startRecording();

        print('✅ Modo de edição inicializado com ${formProvider.responses.length} respostas');
        return;
      }

      // Se NÃO está em modo de edição, limpar e criar novo formulário
      print('📝 MODO NOVO FORMULÁRIO - Limpando dados anteriores');
      formProvider.clearForm();

      print('🚀 Iniciando formulário com ID do questionário: ${widget.questionnaire.id}');
      print('👤 ID do usuário: ${authProvider.user!.id}');
      print('📝 Questões: ${widget.questionnaire.questions.length}');

      formProvider.startForm(
        widget.questionnaire.id,
        authProvider.user!.id,
        widget.questionnaire.questions,
      );

      // Verificar se inicialização foi bem-sucedida
      if (formProvider.currentForm != null && formProvider.questions.isNotEmpty) {
        print('✅ FormProvider inicializado com sucesso');
        print('   - Formulário ativo: SIM');
        print('   - Questões carregadas: ${formProvider.questions.length}');
        print('   - Questionário ID: ${formProvider.currentForm!.questionnaireId}');
        print('   - Aplicado por: ${formProvider.currentForm!.appliedBy}');

        // Debug inicial da lógica condicional
        formProvider.debugConditionalLogic();

        setState(() {
          _isInitialized = true;
        });

        // Iniciar gravação de áudio automaticamente
        _startRecording();

        print('✅ Inicialização completa');
      } else {
        print('❌ Falha na inicialização:');
        print('   - Formulário ativo: ${formProvider.currentForm != null}');
        print('   - Questões: ${formProvider.questions.length}');
        
        // Tentar método de fallback
        print('🔄 Tentando método de fallback...');
        formProvider.initialize(widget.questionnaire.questions);
        
        if (formProvider.questions.isNotEmpty) {
          print('⚠️ Fallback parcial funcionou, mas sem formulário ativo');
          setState(() {
            _isInitialized = true;
          });
        }
      }
    } catch (e, stackTrace) {
      print('❌ Erro na inicialização: $e');
      print('📋 Stack trace: $stackTrace');
      
      // Em caso de erro, tentar ainda o método compatível
      try {
        print('🆘 Tentando recuperação com método compatível...');
        final formProvider = Provider.of<FormProvider>(context, listen: false);
        formProvider.initialize(widget.questionnaire.questions);
        
        if (formProvider.questions.isNotEmpty) {
          print('🔧 Recuperação parcial bem-sucedida');
          setState(() {
            _isInitialized = true;
          });
        }
      } catch (recoveryError) {
        print('💥 Falha total na recuperação: $recoveryError');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<FormProvider>(
      builder: (context, formProvider, child) {
        // Aguardar inicialização
        if (!_isInitialized) {
          return _buildLoadingScreen();
        }

        // Verificar se há questões
        if (formProvider.questions.isEmpty) {
          return _buildErrorScreen('Nenhuma questão encontrada');
        }

        // Obter questões visíveis
        final visibleQuestions = <Question>[];
        for (int i = 0; i < formProvider.questions.length; i++) {
          if (formProvider.isQuestionVisible(i)) {
            visibleQuestions.add(formProvider.questions[i]);
          }
        }

        print(
          '👁️ Questões visíveis: ${visibleQuestions.length} de ${formProvider.questions.length}',
        );

        // Se não há questões visíveis
        if (visibleQuestions.isEmpty) {
          return _buildNoVisibleQuestionsScreen(formProvider);
        }

        // Verificar índice atual
        if (_currentVisibleIndex >= visibleQuestions.length) {
          _currentVisibleIndex = 0;
        }

        return Scaffold(
          body: SafeArea(
            child: Column(
              children: [
                _buildHeader(),
                Expanded(
                  child: PageView.builder(
                    controller: _pageController,
                    // Bloqueia o deslize para a PRÓXIMA questão enquanto a
                    // questão obrigatória atual não for respondida (o botão
                    // "Próxima" já valida; o gesto não validava). Voltar
                    // deslizando continua permitido.
                    physics: _BlockForwardSwipePhysics(
                      canAdvance: () => _canAdvanceFromCurrentQuestion(
                        visibleQuestions,
                        formProvider,
                      ),
                    ),
                    itemCount: visibleQuestions.length,
                    onPageChanged: (index) {
                      // Fechar o teclado herdado da questão anterior quando a
                      // nova questão não usa digitação (múltipla escolha,
                      // checkbox, data). Tipos desconhecidos caem no campo de
                      // texto, então só fechamos nos tipos conhecidos sem
                      // teclado.
                      const typesWithoutKeyboard = {
                        'radio',
                        'checkbox',
                        'date',
                        'datetime',
                      };
                      if (index >= 0 && index < visibleQuestions.length) {
                        final newType = visibleQuestions[index]
                            .questionType
                            .toLowerCase()
                            .trim();
                        if (typesWithoutKeyboard.contains(newType)) {
                          FocusManager.instance.primaryFocus?.unfocus();
                        }
                      }
                      setState(() {
                        _currentVisibleIndex = index;
                      });
                    },
                    itemBuilder: (context, index) {
                      final question = visibleQuestions[index];
                      final originalIndex = _getOriginalIndex(
                        question,
                        formProvider,
                      );

                      return _buildQuestionPage(
                        question,
                        index,
                        originalIndex,
                        visibleQuestions.length,
                        formProvider,
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildLoadingScreen() {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            const Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Carregando questionário...'),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorScreen(String message) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error, color: Colors.red, size: 64),
                    const SizedBox(height: 16),
                    Text(message, style: const TextStyle(fontSize: 18)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoVisibleQuestionsScreen(FormProvider formProvider) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.visibility_off,
                      color: Colors.orange,
                      size: 64,
                    ),
                    const SizedBox(height: 16),
                    const Text('Nenhuma questão visível'),
                    const SizedBox(height: 8),
                    const Text(
                      'Baseado nas respostas, não há questões disponíveis.',
                      style: TextStyle(color: Colors.grey),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        ElevatedButton(
                          onPressed: () {
                            print('🔍 === DEBUG COMPLETO ===');
                            formProvider.debugConditionalLogic();
                          },
                          child: const Text('Debug'),
                        ),
                        ElevatedButton(
                          onPressed: () {
                            print('🧪 === TESTE GERAL ===');
                            formProvider.testConditionalLogic();
                          },
                          child: const Text('Teste'),
                        ),
                        ElevatedButton(
                          onPressed: () {
                            print('🧪 === TESTE JSON ESPECÍFICO ===');
                            formProvider.testSpecificJSON();
                          },
                          child: const Text('JSON'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.all(20),
    decoration: const BoxDecoration(color: Color(0xFFF5F5F5)),
    child: Column(
      children: [
        Row(
          children: [
            // Espaço vazio à esquerda
            const Expanded(child: SizedBox()),

            // Imagem centralizada
            Image.asset(
              'assets/images/logo_socialx.png',
              width: 120,
              fit: BoxFit.contain,
            ),

            // Espaço à direita com ícone
            Expanded(
              child: Align(
                alignment: Alignment.centerRight,
                child: const Icon(Icons.quiz, color: Color(0xFF8FAE5D), size: 24),
              ),
            ),
          ],
        ),
        // Indicador de gravação de áudio.
        //
        // Só indicador: não responde a toque. Antes, tocar aqui encerrava a
        // gravação, e um toque acidental no meio da entrevista cortava o áudio
        // sem que o aplicador percebesse. A gravação agora termina apenas com
        // a finalização do questionário.
        if (_isRecording)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.red.shade300),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: const BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Gravando ${_formatRecordingTime(_recordingSeconds)}',
                      style: TextStyle(
                        color: Colors.red.shade700,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
          ),
      ],
    ),
  );
}

  /// Retorna true se a questão visível atual permite avançar por gesto:
  /// não obrigatória ou já respondida. Mesma regra do botão "Próxima".
  bool _canAdvanceFromCurrentQuestion(
    List<Question> visibleQuestions,
    FormProvider formProvider,
  ) {
    if (_currentVisibleIndex < 0 ||
        _currentVisibleIndex >= visibleQuestions.length) {
      return true;
    }

    final question = visibleQuestions[_currentVisibleIndex];
    final originalIndex = _getOriginalIndex(question, formProvider);
    if (originalIndex < 0) return true;

    final questionState = formProvider.getQuestionState(originalIndex);
    final isRequired = questionState?.required ?? question.isRequired;
    final response = formProvider.getResponse(question.id);
    final filled = response != null && response.toString().trim().isNotEmpty;

    // Telefone pela metade não passa, mesmo em pergunta opcional
    if (filled && question.questionType.toLowerCase().trim() == 'phone') {
      return isValidPhone(response.toString());
    }

    if (!isRequired) return true;
    return filled;
  }

  int _getOriginalIndex(Question question, FormProvider formProvider) {
    for (int i = 0; i < formProvider.questions.length; i++) {
      if (formProvider.questions[i].id == question.id) {
        return i;
      }
    }
    return -1;
  }

  Widget _buildQuestionPage(
    Question question,
    int visibleIndex,
    int originalIndex,
    int totalVisible,
    FormProvider formProvider,
  ) {
    if (originalIndex < 0) {
      return const Center(child: Text('Erro: questão não encontrada'));
    }

    final questionState = formProvider.getQuestionState(originalIndex);
    final isRequired = questionState?.required ?? question.isRequired;

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Progresso
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF8FAE5D),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'Pergunta ${visibleIndex + 1} de $totalVisible',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Texto da questão
                  Text(
                    question.questionText,
                    style: const TextStyle(
                      fontSize: 18,
                      color: Color(0xFF23345F),
                      height: 1.4,
                      fontWeight: FontWeight.w600,
                    ),
                  ),

                  // Obrigatório
                  if (isRequired)
                    const Padding(
                      padding: EdgeInsets.only(top: 5),
                      child: Text(
                        '* Campo obrigatório',
                        style: TextStyle(color: Colors.red, fontSize: 12),
                      ),
                    ),

                  const SizedBox(height: 20),

                  // Debug da questão
               /*   Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'ID: ${question.id}, Índice: $originalIndex → $visibleIndex',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.blue.shade700,
                          ),
                        ),
                        Text(
                          'Estado: visible=${questionState?.visible}, required=${questionState?.required}',
                          style: TextStyle(
                            fontSize: 11,
                            color: const Color(0xFF5A7536),
                          ),
                        ),
                        if (question.hasConditionalLogic)
                          Text(
                            'Lógica: ${question.conditionalLogicSummary}',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.purple.shade700,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10), */

                  // Widget da questão
                  QuestionWidget(
                    question: question,
                    initialValue: formProvider.getResponse(question.id),
                    onChanged: (value) {
                      print('📝 === RESPOSTA ALTERADA ===');
                      print('📝 Questão ${question.id}: "$value"');

                      // Capturar opção recém-selecionada antes de atualizar o estado
                      final justSelected =
                          _getJustSelectedOption(question.id, value);

                      setState(() {
                        _currentAnswers[question.id] = value;
                      });

                      // Salvar resposta no FormProvider
                      formProvider.setResponse(
                        question.id,
                        value,
                        question.questionType,
                      );

                      print('📝 Resposta salva, aguardando reavaliação...');

                      // Verificar cota de estratificação (alerta não bloqueante)
                      if (justSelected != null) {
                        _checkStratificationQuota(question.id, justSelected);
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
          _buildNavigationButtons(
            visibleIndex,
            totalVisible,
            originalIndex,
            formProvider,
          ),
        ],
      ),
    );
  }

  Widget _buildNavigationButtons(
    int visibleIndex,
    int totalVisible,
    int originalIndex,
    FormProvider formProvider,
  ) {
    final isFirstQuestion = visibleIndex == 0;
    final isLastQuestion = visibleIndex == totalVisible - 1;

    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Row(
        children: [
          if (!isFirstQuestion)
            Expanded(
              child: OutlinedButton(
                onPressed: () {
                  _pageController.previousPage(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                  );
                },
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  side: const BorderSide(color: Colors.grey),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text(
                  'Anterior',
                  style: TextStyle(color: Colors.grey, fontSize: 16),
                ),
              ),
            ),

          if (!isFirstQuestion) const SizedBox(width: 10),

          Expanded(
            flex: isFirstQuestion ? 1 : 2,
            child: ElevatedButton(
              onPressed: () => _handleNext(
                visibleIndex,
                totalVisible,
                originalIndex,
                isLastQuestion,
                formProvider,
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF8FAE5D),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                elevation: 2,
              ),
              child: Text(
                isLastQuestion
                    ? (formProvider.isEditMode ? 'Atualizar' : 'Finalizar')
                    : 'Próxima',
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _handleNext(
    int visibleIndex,
    int totalVisible,
    int originalIndex,
    bool isLastQuestion,
    FormProvider formProvider,
  ) async {
    if (originalIndex < 0) return;

    final currentQuestion = formProvider.questions[originalIndex];
    final questionState = formProvider.getQuestionState(originalIndex);
    final isRequired = questionState?.required ?? currentQuestion.isRequired;

    print('🚀 Tentativa de avanço: questão $originalIndex');

    // Verificar obrigatoriedade
    if (isRequired) {
      final response = formProvider.getResponse(currentQuestion.id);
      if (response == null || response.toString().trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Por favor, responda esta questão obrigatória'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
    }

    // Telefone pela metade não passa, mesmo em pergunta opcional
    if (currentQuestion.questionType.toLowerCase().trim() == 'phone') {
      final response = formProvider.getResponse(currentQuestion.id);
      final text = response?.toString().trim() ?? '';
      if (text.isNotEmpty && !isValidPhone(text)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Informe o telefone com DDD'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
    }

    if (isLastQuestion) {
      // Validação final
      final validation = formProvider.validateAllResponses();
      if (!validation.isValid) {
        final errors = validation.errors.take(3).join('\n');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erros:\n$errors'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
        return;
      }

      // Parar gravação de áudio e salvar caminho
      if (_isRecording) {
        if (PlatformCaps.hasContinuousAudioRecording) {
          final audioPath = await _stopRecording();
          if (audioPath != null) {
            formProvider.setAudio(audioPath);
            print('🎤 Áudio salvo no formulário: $audioPath');
          }
        } else {
          // Web: fecha a gravação e vincula o arquivo ao formulário.
          final firstSegment = await _finishWebRecording();
          if (firstSegment != null) {
            formProvider.setAudio(firstSegment);
            print('🎤 Web: áudio vinculado ao formulário: $firstSegment');
          }
        }
      } else if (_audioPath != null) {
        // Rede de segurança: a gravação não deveria parar antes da
        // finalização, mas se tiver parado (falha do gravador, interrupção do
        // sistema), o arquivo já gravado é anexado em vez de se perder.
        formProvider.setAudio(_audioPath!);
        print('🎤 Áudio (parado manualmente) salvo no formulário: $_audioPath');
      }

      // Finalizar formulário
      if (widget.questionnaire.requiresPhoto) {
        // Para questionários com foto, navegar para captura de foto
        if (!mounted) return;
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) =>
                PhotoCaptureScreen(questionnaire: widget.questionnaire),
          ),
        );
      } else {
        // Sem foto: capturar a localização (se exigida) antes de submeter.
        // A captura via PhotoCaptureScreen não acontece aqui, então fazemos aqui.
        final temLocalizacao = await _captureLocationIfRequired(formProvider);
        if (!temLocalizacao) {
          // Sem coordenadas em questionário que as exige: não finaliza. O
          // aplicador volta ao questionário com tudo preenchido preservado.
          return;
        }
        // Para questionários sem foto, submeter e navegar
        await _submitAndNavigate(formProvider);
      }
    } else {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  /// Captura a localização GPS quando o questionário exige (requiresLocation),
  /// mas o fluxo não passa pela PhotoCaptureScreen (que já captura por conta própria).
  /// Sem isso, questionários com "Capturar Localização" ligado e "Requer Foto"
  /// desligado nunca registravam as coordenadas.
  ///
  /// Retorna true quando é permitido finalizar: o questionário não exige
  /// localização, ou as coordenadas foram efetivamente capturadas. Quando exige
  /// e a captura falha, retorna false — a finalização fica bloqueada, com o
  /// motivo exibido e a opção de tentar de novo (ver [_ensureLocationOrBlock]).
  Future<bool> _captureLocationIfRequired(FormProvider formProvider) async {
    if (!widget.questionnaire.requiresLocation) return true;
    return _ensureLocationOrBlock(formProvider);
  }

  /// Tenta capturar as coordenadas em laço: a cada falha explica o motivo ao
  /// aplicador e oferece tentar de novo. Só libera a finalização com as
  /// coordenadas gravadas — ou com o formulário marcado como "Sem localização",
  /// quando o aplicador decide concluir sem sinal de GPS.
  Future<bool> _ensureLocationOrBlock(FormProvider formProvider) async {
    // Edição: a localização é a da entrevista, nunca a do momento da
    // correção. Se a entrevista ficou sem coordenadas, continua sem.
    if (formProvider.isEditMode) {
      print('📍 Edição - mantendo a localização original da entrevista');
      return true;
    }

    while (true) {
      // Já capturada (ex.: edição com localização preservada)? Não recapturar.
      if (formProvider.currentForm?.latitude != null) {
        print('📍 Localização já definida, mantendo a existente');
        return true;
      }

      final falha = await _tryCaptureLocation(formProvider);
      if (falha == null) return true;

      if (!mounted) return false;
      final decisao = await showLocationRequiredDialog(context, falha);

      switch (decisao) {
        case LocationDialogAction.retry:
          continue;
        case LocationDialogAction.finishWithout:
          formProvider.markLocationUnavailable();
          print('📍 Finalizando sem coordenadas por decisão do aplicador');
          return true;
        case LocationDialogAction.cancel:
        case null:
          print('📍 Aplicador voltou ao questionário — não finalizou');
          return false;
      }
    }
  }

  /// Executa uma tentativa de captura. Retorna null em caso de sucesso, ou a
  /// mensagem do motivo da falha (já escrita para o aplicador).
  ///
  /// A estratégia em etapas — e o motivo de cada uma — está em
  /// [LocationService.obterPosicao].
  Future<String?> _tryCaptureLocation(FormProvider formProvider) async {
    // A busca pode levar dezenas de segundos; sem aviso, o aplicador acha que
    // o app travou e sai da tela.
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Obtendo localização...'),
          backgroundColor: Color(0xFF8FAE5D),
          duration: Duration(seconds: 30),
        ),
      );
    }

    final resultado = await LocationService.obterPosicao();

    if (mounted) {
      ScaffoldMessenger.of(context).clearSnackBars();
    }

    if (resultado.ok) {
      final p = resultado.position!;
      formProvider.setLocation(p.latitude, p.longitude, '');
      return null;
    }
    return resultado.erro;
  }

  Future<void> _submitAndNavigate(FormProvider formProvider) async {
  print('📤 === SUBMETENDO FORMULÁRIO SEM FOTO ===');
  print('✏️ Modo de edição: ${formProvider.isEditMode}');
  print('✏️ ID do formulário em edição: ${formProvider.editingFormId}');

  // Verificar se há formulário ou respostas para submeter
  final hasResponses = formProvider.responses.isNotEmpty;
  final hasForm = formProvider.currentForm != null;

  print('📊 Status antes da submissão:');
  print('   - Formulário ativo: $hasForm');
  print('   - ID do formulário: ${formProvider.currentForm?.id}');
  print('   - Respostas coletadas: ${formProvider.responses.length}');
  print('   - Questões processadas: ${formProvider.questions.length}');

  if (!hasResponses && !hasForm) {
    print('⚠️ Nenhum dado para submeter, navegando direto');
    _navigateToCompletedScreen();
    return;
  }

  // Mostrar loading
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Row(
        children: [
          const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          ),
          const SizedBox(width: 16),
          Text(formProvider.isEditMode ? 'Atualizando respostas...' : 'Salvando respostas...'),
        ],
      ),
      backgroundColor: const Color(0xFF8FAE5D),
      duration: const Duration(seconds: 10),
    ),
  );

  try {
    bool success = false;

    // SEMPRE submeter diretamente, SEM criar novo formulário
    print('📤 Submetendo formulário existente (ID: ${formProvider.currentForm?.id})...');
    success = await formProvider.submitForm();

    // Remover snackbar de loading
    ScaffoldMessenger.of(context).clearSnackBars();

    if (success) {
      print('✅ Formulário submetido com sucesso');
      _navigateToCompletedScreen();
    } else {
      print('❌ Falha ao submeter formulário');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(formProvider.isEditMode
            ? 'Erro ao atualizar formulário. Tente novamente.'
            : 'Erro ao salvar formulário. Tente novamente.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  } catch (e) {
    print('❌ Erro durante submissão: $e');
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Erro inesperado: $e'),
        backgroundColor: Colors.red,
      ),
    );
  }
}

  void _navigateToCompletedScreen() {
    // Se está em modo de edição, apenas voltar para a tela anterior
    // indicando que a edição foi bem-sucedida
    final formProvider = Provider.of<FormProvider>(context, listen: false);
    if (formProvider.isEditMode) {
      print('✅ Modo de edição - voltando para tela anterior com sucesso');
      Navigator.pop(context, true); // Retorna true indicando sucesso
      return;
    }

    // Se não está em modo de edição, navegar para a tela de conclusão
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => FormCompletedScreen(
          questionnaire: widget.questionnaire,
        ),
      ),
    );
  }

  /// Retorna a string da opção recém-selecionada comparando com o estado
  /// anterior em [_currentAnswers]. Para radio retorna o valor diretamente;
  /// para checkbox retorna o item adicionado na última interação.
  String? _getJustSelectedOption(int questionId, dynamic newValue) {
    if (newValue == null) return null;

    if (newValue is String) {
      return newValue.isNotEmpty ? newValue : null;
    }

    if (newValue is List) {
      final prev = _currentAnswers[questionId];
      final prevList = (prev is List) ? prev.cast<String>() : <String>[];
      final newList = newValue.cast<String>();
      final added = newList.where((v) => !prevList.contains(v)).toList();
      return added.isNotEmpty ? added.first : null;
    }

    return null;
  }

  /// Exibe um SnackBar de alerta (não bloqueante) quando a cota do estrato
  /// selecionado já foi atingida, conforme dados de estratificação carregados.
  void _checkStratificationQuota(int questionId, String optionValue) {
    final stratProvider =
        Provider.of<StratificationProvider>(context, listen: false);
    if (!stratProvider.hasStratification) return;

    final alert = stratProvider.getQuotaAlert(questionId, optionValue);
    if (alert == null) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Atenção: A cota para ${alert['optionLabel']} na categoria '
          '${alert['categoryName']} já foi atingida '
          '(${alert['currentCount']}/${alert['targetQuota']}).',
        ),
        backgroundColor: Colors.orange.shade700,
        duration: const Duration(seconds: 4),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Audio Recording
  // ---------------------------------------------------------------------------

  Future<void> _startRecording() async {
    // Web: gravação por segmentos com tela ativa, salvos no IndexedDB.
    if (!PlatformCaps.hasContinuousAudioRecording) {
      await _startWebSegment();
      return;
    }

    try {
      final status = await Permission.microphone.request();
      if (!status.isGranted) {
        print('🎤 Permissão de microfone negada');
        return;
      }

      if (await _audioRecorder.hasPermission()) {
        final appDocDir = await getApplicationDocumentsDirectory();
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final path = '${appDocDir.path}/recording_$timestamp.m4a';

        await _audioRecorder.start(
          const RecordConfig(
            encoder: AudioEncoder.aacLc,
            bitRate: 64000,
            sampleRate: 22050,
          ),
          path: path,
        );

        _audioPath = path;
        _recordingSeconds = 0;
        _recordingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
          setState(() {
            _recordingSeconds++;
          });
        });

        setState(() {
          _isRecording = true;
        });

        print('🎤 Gravação iniciada: $path');
      }
    } catch (e) {
      print('❌ Erro ao iniciar gravação: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Web: gravação por segmentos (tela ativa)
  // ---------------------------------------------------------------------------

  /// Inicia um novo segmento de gravação na web. O prompt de microfone do
  /// navegador aparece na primeira chamada.
  Future<void> _startWebSegment() async {
    try {
      if (!await _audioRecorder.hasPermission()) {
        print('🎤 Web: permissão de microfone negada — seguindo sem áudio');
        return;
      }

      _webSessionId ??= DateTime.now().millisecondsSinceEpoch.toString();

      // Safari grava mp4/aac; Chrome, webm/opus.
      var encoder = AudioEncoder.aacLc;
      if (await _audioRecorder.isEncoderSupported(encoder)) {
        _webAudioExt = 'm4a';
      } else {
        encoder = AudioEncoder.opus;
        _webAudioExt = 'webm';
      }

      await _audioRecorder.start(
        RecordConfig(encoder: encoder, bitRate: 64000, sampleRate: 22050),
        path: '',
      );

      _recordingTimer ??= Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) {
          setState(() {
            _recordingSeconds++;
          });
        }
      });

      // Sem corte periódico: a gravação corre do início ao fim do
      // questionário, num arquivo só.
      //
      // Existia aqui um flush a cada 60 s, pensado para limitar a perda em um
      // fechamento abrupto da página. O efeito colateral era grave: só o
      // primeiro segmento é vinculado ao formulário (audio_path), e o painel
      // ainda não recebe os demais — na prática, todo áudio depois do primeiro
      // minuto sumia. Perder um minuto em caso raro custava menos que perder
      // a entrevista inteira em todos os casos.

      if (mounted) {
        setState(() {
          _isRecording = true;
        });
      }
      print('🎤 Web: segmento iniciado (sessão $_webSessionId, .$_webAudioExt)');
    } catch (e) {
      print('❌ Web: erro ao iniciar gravação: $e');
    }
  }

  /// Fecha o segmento atual e persiste no IndexedDB.
  Future<void> _flushWebSegment() async {
    if (!_isRecording) return;
    try {
      final blobUrl = await _audioRecorder.stop();
      if (mounted) {
        setState(() {
          _isRecording = false;
        });
      }
      if (blobUrl == null || blobUrl.isEmpty) return;

      _webSegmentSeq++;
      final filename =
          'audio_web_${_webSessionId}_p$_webSegmentSeq.$_webAudioExt';
      final size = await WebMediaStore.saveFromBlobUrl(
        blobUrl: blobUrl,
        filename: filename,
        kind: 'audio',
      );
      _webFirstSegmentFilename ??= filename;
      print('🎤 Web: segmento salvo — $filename ($size bytes)');
    } catch (e) {
      print('❌ Web: erro ao salvar segmento: $e');
    }
  }

  /// Encerra a gravação web: fecha o áudio e retorna o nome do arquivo
  /// vinculado ao formulário (audio_path).
  ///
  /// No caminho normal existe um arquivo só, do início ao fim do questionário.
  /// Se houve interrupção (aba oculta/tela bloqueada), os arquivos seguintes
  /// compartilham o mesmo prefixo de sessão.
  Future<String?> _finishWebRecording() async {
    _recordingTimer?.cancel();
    _recordingTimer = null;
    await _flushWebSegment();
    final first = _webFirstSegmentFilename;
    _webSessionId = null; // impede reinício via observer após finalizar
    return first;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (PlatformCaps.hasContinuousAudioRecording) return;

    // Web: aba oculta/tela bloqueada → fecha e salva o segmento atual
    // (nada do que já foi falado se perde); ao voltar, novo segmento.
    if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused) {
      _flushWebSegment();
    } else if (state == AppLifecycleState.resumed &&
        !_isRecording &&
        _webSessionId != null) {
      _startWebSegment();
    }
  }

  Future<String?> _stopRecording() async {
    try {
      if (!_isRecording) return null;

      _recordingTimer?.cancel();
      _recordingTimer = null;

      final path = await _audioRecorder.stop();

      setState(() {
        _isRecording = false;
      });

      print('🎤 Gravação finalizada: $path (${_recordingSeconds}s)');
      return path;
    } catch (e) {
      print('❌ Erro ao parar gravação: $e');
      setState(() {
        _isRecording = false;
      });
      return null;
    }
  }

  String _formatRecordingTime(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    WakelockPlus.disable();
    _recordingTimer?.cancel();
    if (_isRecording) {
      _audioRecorder.stop();
    }
    _audioRecorder.dispose();
    _pageController.dispose();
    // Manter o GPS ligado depois de sair da tela consome bateria à toa.
    LocationService.pararAquecimento();
    super.dispose();
  }
}

/// Physics que impede o deslize para a página SEGUINTE quando [canAdvance]
/// retorna false (questão obrigatória sem resposta), mas mantém livre o
/// deslize para a página anterior. Bloqueia tanto o arrasto quanto o "fling".
class _BlockForwardSwipePhysics extends PageScrollPhysics {
  final bool Function() canAdvance;

  const _BlockForwardSwipePhysics({required this.canAdvance, super.parent});

  @override
  _BlockForwardSwipePhysics applyTo(ScrollPhysics? ancestor) {
    return _BlockForwardSwipePhysics(
      canAdvance: canAdvance,
      parent: buildParent(ancestor),
    );
  }

  @override
  double applyPhysicsToUserOffset(ScrollMetrics position, double offset) {
    // offset negativo = dedo arrastando rumo à próxima página
    if (offset < 0 && !canAdvance()) {
      return 0;
    }
    return super.applyPhysicsToUserOffset(position, offset);
  }

  @override
  double applyBoundaryConditions(ScrollMetrics position, double value) {
    // O PageView nos coloca como parent da PageScrollPhysics dele, que NÃO
    // delega createBallisticSimulation — então um fling ainda avançava de
    // página. applyBoundaryConditions É delegado e roda a cada frame (arrasto
    // e animação): aqui fixamos o teto na página atual. A "âncora" via ceil
    // permite que um deslize para trás abandonado se reacomode na página
    // atual, sem nunca cruzar para a seguinte.
    if (!canAdvance() && value > position.pixels) {
      final double pageWidth = position.viewportDimension;
      final double maxAllowed =
          ((position.pixels / pageWidth) - 0.001).ceilToDouble() * pageWidth;
      if (value > maxAllowed) {
        return value - maxAllowed;
      }
    }
    return super.applyBoundaryConditions(position, value);
  }
}

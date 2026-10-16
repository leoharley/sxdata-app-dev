import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/form_response.dart';
import '../models/question_response.dart';
import '../models/question.dart';
import '../models/questionnaire.dart';
import '../models/conditional_logic.dart';
import '../services/conditional_logic_engine.dart';
import '../services/local_storage_service.dart';
import '../services/api_service.dart';
import '../services/photo_storage_service.dart';
import '../services/platform_caps.dart';
import '../services/web_media_store/web_media_store.dart';
import 'package:path_provider/path_provider.dart';

class FormProvider with ChangeNotifier {
  FormResponse? _currentForm;
  final Map<int, QuestionResponse> _responses = {};
  bool _isSubmitting = false;

  // Campos para lógica condicional
  List<Question> _questions = [];
  Map<int, QuestionState> _questionStates = {};

  // Campos para modo de edição
  bool _isEditMode = false;
  String? _editingFormId;

  FormResponse? get currentForm => _currentForm;
  Map<int, QuestionResponse> get responses => _responses;
  bool get isSubmitting => _isSubmitting;
  List<Question> get questions => _questions;
  Map<int, QuestionState> get questionStates => _questionStates;
  bool get isEditMode => _isEditMode;
  String? get editingFormId => _editingFormId;

  FormResponse? _lastCompletedForm;
  Map<int, QuestionResponse> _lastCompletedResponses = {};

  // ADICIONAR estes getters:
  FormResponse? get lastCompletedForm => _lastCompletedForm;
  Map<int, QuestionResponse> get lastCompletedResponses =>
      _lastCompletedResponses;

  /// Inicia um novo formulário com lógica condicional
  void startForm(int questionnaireId, int userId, List<Question> questions) {
    print('🚀 ========================================');
    print('🚀 === INICIANDO FORMULÁRIO (startForm) ===');
    print('🚀 ========================================');
    print('🚀 CHAMADA: ${DateTime.now().toIso8601String()}');
    print('🚀 Stack Trace para rastrear múltiplas chamadas:');
    print('🚀 ${StackTrace.current}');
    print('📋 Questionnaire ID: $questionnaireId');
    print('👤 User ID: $userId');
    print('📝 Questions: ${questions.length}');
    print('✏️ Modo de edição: $_isEditMode');
    print('✏️ ID do formulário em edição: $_editingFormId');
    print('✏️ Formulário atual (_currentForm): $_currentForm');
    print('✏️ ID do formulário atual: ${_currentForm?.id}');

    try {
      // Se está em modo de edição, preservar o formulário existente COM O ID ORIGINAL
      if (_isEditMode && _editingFormId != null) {
        print('✏️ MODO DE EDIÇÃO - Preservando formulário existente');

        // Converter _editingFormId para int se necessário
        int? formId;
        if (_editingFormId is int) {
          formId = _editingFormId as int;
        } else if (_editingFormId is String) {
          formId = int.tryParse(_editingFormId!);
        }

        print('✏️ === ID CRÍTICO ===');
        print('✏️ _editingFormId original: $_editingFormId');
        print('✏️ formId convertido: $formId');

        if (formId == null) {
          print('❌ ERRO CRÍTICO: Não foi possível converter o ID para edição!');
          throw Exception('ID de edição inválido: $_editingFormId');
        }

        if (_currentForm?.id == formId) {
          // Formulário original já carregado por loadFormForEdit: mantê-lo.
          // Recriá-lo aqui descartava coordenadas, data de início, fotos e
          // client_id da entrevista.
          print('✅ Formulário original já carregado - mantendo os dados da entrevista');
        } else {
          // Não deveria acontecer (toda entrada de edição chama
          // loadFormForEdit). Sem o original não há coordenadas: a edição
          // não captura posição nova e o servidor mantém as que já tem.
          print('⚠️ Edição sem o formulário original carregado');
          _currentForm = FormResponse(
            id: formId,
            questionnaireId: questionnaireId,
            appliedBy: userId,
            consentGiven: true, // Já tinha dado consentimento antes
            startedAt: DateTime.now(),
          );
        }

        // VERIFICAÇÃO DE SEGURANÇA IMEDIATA
        if (_currentForm!.id != formId) {
          print('❌ ERRO CRÍTICO: FormResponse não preservou o ID!');
          print('   ID esperado: $formId');
          print('   ID obtido: ${_currentForm!.id}');
          throw Exception('FormResponse alterou o ID durante criação');
        }

        print('✅ Formulário de edição criado com ID: ${_currentForm!.id}');
        print('✅ Respostas preservadas: ${_responses.length}');
        // NÃO limpar as respostas em modo de edição
      } else {
        print('📝 MODO NOVO FORMULÁRIO');
        _currentForm = FormResponse(
          questionnaireId: questionnaireId,
          appliedBy: userId,
          consentGiven: false,
          // Gerado UMA vez, aqui, no nascimento da coleta — não no envio.
          // Persistido junto com ela, então todo reenvio manda o mesmo
          // valor e o backend deduplica em vez de duplicar.
          clientId: const Uuid().v4(),
          startedAt: DateTime.now(),
        );
        print('📝 client_id gerado: ${_currentForm!.clientId}');
        print('📝 Novo formulário criado com ID: ${_currentForm!.id}');
        _responses.clear();
      }

      // CORREÇÃO: Ordenar perguntas por order_index antes de processar
      _questions = List<Question>.from(questions)
        ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));

      print('📝 === PERGUNTAS ORDENADAS ===');
      for (int i = 0; i < _questions.length; i++) {
        final q = _questions[i];
        print(
          '📝 Índice $i: ID ${q.id}, Order ${q.orderIndex} - "${q.questionText}"',
        );
        if (q.hasConditionalLogic) {
          print('🔧   Lógica: ${q.conditionalLogicSummary}');
        }
      }

      // Inicializar estados das perguntas
      _initializeQuestionStates();

      print('✅ Formulário iniciado com sucesso');
      notifyListeners();
    } catch (e, stackTrace) {
      print('❌ Erro ao iniciar formulário: $e');
      print('📋 Stack trace: $stackTrace');
      rethrow;
    }
  }

  /// Carrega um formulário existente para edição
  void loadFormForEdit(FormResponse existingForm, Questionnaire questionnaire) {
    print('📝 === CARREGANDO FORMULÁRIO PARA EDIÇÃO ===');
    print('📋 Form ID: ${existingForm.id}');
    print('📋 Questionário: ${questionnaire.title}');

    try {
      // Carregar o formulário existente
      _currentForm = existingForm;

      // Ordenar perguntas
      _questions = List<Question>.from(questionnaire.questions)
        ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));

      print('📝 ${_questions.length} perguntas carregadas');

      // Carregar respostas existentes
      _responses.clear();
      for (final response in existingForm.responses) {
        _responses[response.questionId] = response;
        print('📝 Resposta carregada para questão ${response.questionId}: ${response.getValue()}');
      }

      print('📝 ${_responses.length} respostas carregadas');

      // Inicializar estados das perguntas
      _initializeQuestionStates();

      print('✅ Formulário carregado para edição com sucesso');
      notifyListeners();
    } catch (e, stackTrace) {
      print('❌ Erro ao carregar formulário para edição: $e');
      print('📋 Stack trace: $stackTrace');
      rethrow;
    }
  }

  /// Método compatível para inicialização sem questões (para compatibilidade)
  void initialize(List<Question> questions) {
    print('🔄 === INICIALIZANDO FORM PROVIDER (MÉTODO COMPATÍVEL) ===');
    print('🔄 Modo de edição: $_isEditMode');
    print('🔄 Respostas atuais: ${_responses.length}');

    if (questions.isEmpty) {
      print('⚠️ Lista de questões vazia');
      _questions.clear();
      _questionStates.clear();
      if (!_isEditMode) {
        _responses.clear();
      }
      notifyListeners();
      return;
    }

    try {
      // PRESERVAR respostas se estiver em modo de edição
      final savedResponses = _isEditMode ? Map<int, QuestionResponse>.from(_responses) : null;

      if (_isEditMode) {
        print('✏️ Preservando ${savedResponses!.length} respostas para modo de edição');
      }

      // Limpar estados anteriores (mas preservar respostas em modo de edição)
      if (!_isEditMode) {
        _responses.clear();
      }
      _questionStates.clear();

      // Ordenar perguntas por order_index
      _questions = List<Question>.from(questions)
        ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));

      // Restaurar respostas se estiver em modo de edição
      if (_isEditMode && savedResponses != null) {
        _responses.clear();
        _responses.addAll(savedResponses);
        print('✏️ Respostas restauradas: ${_responses.length}');
      }

      print('📝 Questões ordenadas: ${_questions.length}');
      for (int i = 0; i < _questions.length; i++) {
        final q = _questions[i];
        print('📝 [$i] ID ${q.id}, Order ${q.orderIndex}: "${q.questionText}"');
      }

      // Inicializar estados
      _initializeQuestionStates();

      print('✅ Inicialização compatível concluída');
      notifyListeners();
    } catch (e, stackTrace) {
      print('❌ Erro na inicialização compatível: $e');
      print('📋 Stack trace: $stackTrace');

      // Em caso de erro, limpar tudo
      _questions.clear();
      _questionStates.clear();
      _responses.clear();
      notifyListeners();
    }
  }

  /// Inicializa os estados das perguntas
  void _initializeQuestionStates() {
    print('🔧 === INICIALIZANDO ESTADOS DAS PERGUNTAS ===');

    _questionStates.clear();

    for (int i = 0; i < _questions.length; i++) {
      final question = _questions[i];
      _questionStates[i] = QuestionState(
        visible: true,
        required: question.isRequired,
        originalRequired: question.isRequired,
      );

      print(
        '📝 Pergunta $i (ID ${question.id}): visible=true, required=${question.isRequired}',
      );
      if (question.hasConditionalLogic) {
        print('🔧 Tem lógica condicional: ${question.conditionalLogicSummary}');
      }
    }

    // Executar lógica condicional inicial mesmo sem respostas
    print('🔧 Executando lógica condicional inicial...');
    _executeConditionalLogic();

    print('✅ Estados inicializados para ${_questionStates.length} perguntas');
  }

  /// Executa a lógica condicional quando uma resposta muda
  void _executeConditionalLogic() {
    if (_questions.isEmpty) return;

    print('🎯 === EXECUTANDO LÓGICA CONDICIONAL ===');

    // Converter respostas para o formato esperado pelo engine
    final Map<int, dynamic> responseValues = {};
    _responses.forEach((questionId, response) {
      responseValues[questionId] = response.getValue();
    });

    print('📝 Respostas para análise: $responseValues');

    // Debug adicional das perguntas sendo processadas
    print('📝 === PERGUNTAS PARA PROCESSAMENTO ===');
    for (int i = 0; i < _questions.length; i++) {
      final q = _questions[i];
      final hasResponse = responseValues.containsKey(q.id);
      final responseValue = responseValues[q.id];
      print(
        '📝 [$i] ID ${q.id}: "${q.questionText}" - Resposta: ${hasResponse ? responseValue : "SEM RESPOSTA"}',
      );
    }

    // Executar lógica condicional usando o engine
    final newStates = ConditionalLogicEngine.executeLogic(
      _questions,
      responseValues,
    );

    // Verificar se houve mudanças
    bool hasChanges = false;
    newStates.forEach((index, newState) {
      final currentState = _questionStates[index];
      if (currentState?.visible != newState.visible ||
          currentState?.required != newState.required) {
        hasChanges = true;
        final question = _questions[index];
        print(
          '🔄 Mudança detectada na pergunta $index (ID ${question.id}): '
          'visible ${currentState?.visible} → ${newState.visible}, '
          'required ${currentState?.required} → ${newState.required}',
        );
      }
    });

    if (hasChanges) {
      _questionStates = newStates;
      print('✅ Estados atualizados, notificando listeners');

      // Debug dos estados finais
      print('📊 === ESTADOS FINAIS ===');
      for (int i = 0; i < _questions.length; i++) {
        final question = _questions[i];
        final state = _questionStates[i]!;
        print(
          '📊 [$i] ID ${question.id}: visible=${state.visible}, required=${state.required}',
        );
      }

      notifyListeners();
    } else {
      print('ℹ️ Nenhuma mudança nos estados');
    }
  }

  /// Verifica se uma pergunta está visível
  bool isQuestionVisible(int questionIndex) {
    if (questionIndex < 0 || questionIndex >= _questions.length) {
      print(
        '⚠️ isQuestionVisible: índice $questionIndex fora do range (0-${_questions.length - 1})',
      );
      return false;
    }

    final visible = _questionStates[questionIndex]?.visible ?? true;
    final question = _questions[questionIndex];

    print(
      '👁️ isQuestionVisible($questionIndex) - ID ${question.id}: $visible',
    );
    return visible;
  }

  /// Verifica se uma pergunta é obrigatória (considerando lógica condicional)
  bool isQuestionRequired(int questionIndex) {
    if (questionIndex < 0 || questionIndex >= _questions.length) {
      print('⚠️ isQuestionRequired: índice $questionIndex fora do range');
      return false;
    }

    final required = _questionStates[questionIndex]?.required ?? false;
    final question = _questions[questionIndex];

    print(
      '⚠️ isQuestionRequired($questionIndex) - ID ${question.id}: $required',
    );
    return required;
  }

  /// Retorna o estado de uma pergunta
  QuestionState? getQuestionState(int questionIndex) {
    if (questionIndex < 0 || questionIndex >= _questions.length) {
      print('⚠️ getQuestionState: índice $questionIndex fora do range');
      return null;
    }

    return _questionStates[questionIndex];
  }

  /// Retorna apenas as perguntas visíveis
  List<Question> getVisibleQuestions() {
    final visibleQuestions = <Question>[];

    for (int i = 0; i < _questions.length; i++) {
      if (isQuestionVisible(i)) {
        visibleQuestions.add(_questions[i]);
      }
    }

    print(
      '👁️ Perguntas visíveis: ${visibleQuestions.length} de ${_questions.length}',
    );

    // Debug das perguntas visíveis
    print('👁️ === PERGUNTAS VISÍVEIS ===');
    for (int i = 0; i < visibleQuestions.length; i++) {
      final q = visibleQuestions[i];
      print('👁️ [$i] ID ${q.id}: "${q.questionText}"');
    }

    return visibleQuestions;
  }

  /// Valida se pode avançar para próxima pergunta
  bool canAdvanceFromQuestion(int questionIndex) {
    if (questionIndex < 0 || questionIndex >= _questions.length) {
      print('⚠️ canAdvanceFromQuestion: índice $questionIndex fora do range');
      return true;
    }

    final question = _questions[questionIndex];
    final state = _questionStates[questionIndex];

    // Se pergunta não está visível, pode avançar
    if (state?.visible != true) {
      print('ℹ️ Pode avançar: pergunta $questionIndex não está visível');
      return true;
    }

    // Se pergunta é obrigatória, verificar se foi respondida
    if (state?.required == true) {
      final response = _responses[question.id];
      final isEmpty = response?.isEmpty ?? true;

      if (isEmpty) {
        print(
          '❌ Não pode avançar: pergunta $questionIndex é obrigatória e não foi respondida',
        );
        return false;
      }
    }

    print('✅ Pode avançar da pergunta $questionIndex');
    return true;
  }

  /// Valida todas as respostas considerando lógica condicional
  ValidationResult validateAllResponses() {
    print('✅ === VALIDANDO TODAS AS RESPOSTAS ===');

    if (_questions.isEmpty) {
      return const ValidationResult(isValid: true, errors: [], warnings: []);
    }

    // Converter respostas para o formato esperado
    final Map<int, dynamic> responseValues = {};
    _responses.forEach((questionId, response) {
      responseValues[questionId] = response.getValue();
    });

    // Usar o engine para validação
    return ConditionalLogicEngine.validateResponses(_questions, responseValues);
  }

  /// Define o consentimento
  void setConsent(bool consent) {
    print('📋 Definindo consentimento: $consent');

    if (_currentForm != null) {
      try {
        _currentForm = _currentForm!.copyWith(consentGiven: consent);
        print('✅ Consentimento definido');
        notifyListeners();
      } catch (e) {
        print('❌ Erro ao definir consentimento: $e');
      }
    } else {
      print('⚠️ Tentativa de definir consentimento sem formulário ativo');
    }
  }

  /// Define uma resposta para uma questão
  void setResponse(int questionId, dynamic value, String type) {
    print('📝 === DEFININDO RESPOSTA ===');
    print('📝 Pergunta ID: $questionId');
    print('📊 Valor: $value (tipo: $type)');

    try {
      QuestionResponse response;

      switch (type.toLowerCase().trim()) {
        case 'text':
        case 'textarea':
        case 'phone':
          response = QuestionResponse(
            questionId: questionId,
            responseText: value?.toString(),
          );
          break;
        case 'number':
          response = QuestionResponse(
            questionId: questionId,
            responseNumber: double.tryParse(value?.toString() ?? ''),
          );
          break;
        case 'date':
          response = QuestionResponse(
            questionId: questionId,
            responseDate: value is DateTime ? value : null,
          );
          break;
        case 'datetime':
          response = QuestionResponse(
            questionId: questionId,
            responseDatetime: value is DateTime ? value : null,
          );
          break;
        case 'radio':
          response = QuestionResponse(
            questionId: questionId,
            selectedOptions: value != null ? [value.toString()] : [],
          );
          break;
        case 'checkbox':
          List<String> options = [];
          if (value is List) {
            options = value.map((v) => v.toString()).toList();
          } else if (value != null) {
            options = [value.toString()];
          }
          response = QuestionResponse(
            questionId: questionId,
            selectedOptions: options,
          );
          break;
        default:
          print('⚠️ Tipo de questão não reconhecido: $type, usando texto');
          response = QuestionResponse(
            questionId: questionId,
            responseText: value?.toString(),
          );
      }

      _responses[questionId] = response;
      print(
        '✅ Resposta salva para questão $questionId: ${response.getValue()}',
      );

      // Debug das respostas antes de executar lógica
      print('📊 === RESPOSTAS ATUAIS ===');
      _responses.forEach((id, resp) {
        print('📊 ID $id: ${resp.getValue()}');
      });

      // Executar lógica condicional após cada resposta
      print('🔧 Executando lógica condicional após resposta...');
      _executeConditionalLogic();
    } catch (e, stackTrace) {
      print('❌ Erro ao salvar resposta: $e');
      print('📋 Stack trace: $stackTrace');
    }
  }

  /// Método compatível para obter resposta (para compatibilidade)
  dynamic getResponse(int questionId) {
    final response = _responses[questionId];
    return response?.getValue();
  }

  /// Define a localização
  void setLocation(double latitude, double longitude, String? locationName) {
    print('📍 Definindo localização: $latitude, $longitude');

    // Na edição a localização é a da entrevista. Capturar de novo gravava a
    // posição de onde a correção foi feita, e várias coletas editadas no
    // mesmo lugar acabavam com a mesma coordenada. A proteção fica aqui, e
    // não em cada tela, para valer também para botões de "tentar de novo".
    if (_isEditMode) {
      print('📍 Edição - localização original preservada, posição nova ignorada');
      return;
    }

    if (_currentForm != null) {
      try {
        _currentForm = _currentForm!.copyWith(
          latitude: latitude,
          longitude: longitude,
          locationName: locationName,
        );
        print('✅ Localização definida');
        notifyListeners();
      } catch (e) {
        print('❌ Erro ao definir localização: $e');
      }
    } else {
      print('⚠️ Tentativa de definir localização sem formulário ativo');
    }
  }

  /// Marca o formulário como concluído sem coordenadas, quando o GPS não pegou
  /// sinal e o aplicador optou por finalizar mesmo assim.
  ///
  /// Latitude e longitude ficam nulas e `location_name` vai como
  /// "Sem localização": no painel isso distingue um questionário em que a
  /// captura falhou de um que simplesmente nunca exigiu localização — os dois
  /// chegariam com as coordenadas em branco.
  void markLocationUnavailable() {
    if (_isEditMode) {
      return; // edição mantém o que a entrevista registrou
    }

    if (_currentForm == null) {
      print('⚠️ Tentativa de marcar "sem localização" sem formulário ativo');
      return;
    }

    try {
      _currentForm = _currentForm!.copyWith(locationName: kSemLocalizacao);
      print('📍 Formulário marcado como "$kSemLocalizacao"');
      notifyListeners();
    } catch (e) {
      print('❌ Erro ao marcar formulário sem localização: $e');
    }
  }

  /// Define a foto
  void setPhoto(String photoPath) {
    print('📸 Definindo foto: $photoPath');

    if (_currentForm != null) {
      try {
        _currentForm = _currentForm!.copyWith(photoPath: photoPath);
        print('✅ Foto definida');
        notifyListeners();
      } catch (e) {
        print('❌ Erro ao definir foto: $e');
      }
    } else {
      print('⚠️ Tentativa de definir foto sem formulário ativo');
    }
  }

  /// Define a segunda foto
  void setPhoto2(String photoPath2) {
    print('📸 Definindo segunda foto: $photoPath2');

    if (_currentForm != null) {
      try {
        _currentForm = _currentForm!.copyWith(photoPath2: photoPath2);
        print('✅ Segunda foto definida');
        notifyListeners();
      } catch (e) {
        print('❌ Erro ao definir segunda foto: $e');
      }
    } else {
      print('⚠️ Tentativa de definir segunda foto sem formulário ativo');
    }
  }

  /// Define o caminho do áudio gravado
  void setAudio(String audioPath) {
    print('🎤 Definindo áudio: $audioPath');

    if (_currentForm != null) {
      try {
        _currentForm = _currentForm!.copyWith(audioPath: audioPath);
        print('✅ Áudio definido');
        notifyListeners();
      } catch (e) {
        print('❌ Erro ao definir áudio: $e');
      }
    } else {
      print('⚠️ Tentativa de definir áudio sem formulário ativo');
    }
  }

  /// Salva o áudio offline no diretório do app
  Future<String?> saveAudioOffline(String audioPath) async {
    print('🎤 === SALVANDO ÁUDIO OFFLINE ===');

    // Web: sem sistema de arquivos — o MediaStore (IndexedDB) assume na
    // Fase 2 do plano web (docs/plano_versao_web.md).
    if (!PlatformCaps.hasFileSystem) {
      print('🎤 Web: armazenamento de áudio em arquivo indisponível');
      return null;
    }

    if (_currentForm == null) {
      print('❌ Nenhum formulário ativo para salvar áudio');
      return null;
    }

    try {
      final File audioFile = File(audioPath);

      if (!await audioFile.exists()) {
        print('❌ Arquivo de áudio não encontrado: $audioPath');
        return null;
      }

      final int formId =
          _currentForm!.id ?? DateTime.now().millisecondsSinceEpoch;

      // Salvar no diretório de documentos do app
      final appDocDir = await getApplicationDocumentsDirectory();
      final audioDir = Directory('${appDocDir.path}/offline_audios');
      if (!await audioDir.exists()) {
        await audioDir.create(recursive: true);
      }
      final String extension = audioPath.split('.').last;
      final String filename = 'audio_${formId}_${DateTime.now().millisecondsSinceEpoch}.$extension';
      final String destPath = '${audioDir.path}/$filename';

      await audioFile.copy(destPath);
      print('✅ Áudio salvo offline como: $filename');

      _currentForm = _currentForm!.copyWith(audioPath: filename);
      notifyListeners();
      return filename;
    } catch (e, stackTrace) {
      print('❌ Erro ao salvar áudio offline: $e');
      print('📋 Stack trace: $stackTrace');
      return null;
    }
  }

  void clearPreservedData() {
    print('🧹 Limpando dados preservados');
    _lastCompletedForm = null;
    _lastCompletedResponses.clear();
  }

  /// Salva a foto offline
  Future<String?> savePhotoOffline(String photoPath, {String photoType = 'photo1'}) async {
    print('📸 === SALVANDO FOTO OFFLINE ===');
    print('📸 Tipo: $photoType');

    // Web: sem sistema de arquivos — o MediaStore (IndexedDB) assume na
    // Fase 2 do plano web (docs/plano_versao_web.md).
    if (!PlatformCaps.hasFileSystem) {
      print('📸 Web: armazenamento de foto em arquivo indisponível');
      return null;
    }

    if (_currentForm == null) {
      print('❌ Nenhum formulário ativo para salvar foto');
      return null;
    }

    try {
      final File photoFile = File(photoPath);

      if (!await photoFile.exists()) {
        print('❌ Arquivo de foto não encontrado: $photoPath');
        return null;
      }

      // Gerar um ID temporário para o formulário se não tiver
      final int formId =
          _currentForm!.id ?? DateTime.now().millisecondsSinceEpoch;

      // Salvar foto localmente usando o PhotoStorageService com o tipo correto
      final String offlineFilename = await PhotoStorageService.savePhotoOffline(
        photoFile,
        formId,
        photoType: photoType,
      );

      print('✅ Foto $photoType salva offline com filename: $offlineFilename');

      // Atualizar o formulário com o filename offline no campo correto
      if (photoType == 'photo1') {
        _currentForm = _currentForm!.copyWith(photoPath: offlineFilename);
      } else if (photoType == 'photo2') {
        _currentForm = _currentForm!.copyWith(photoPath2: offlineFilename);
      }

      notifyListeners();
      return offlineFilename;
    } catch (e, stackTrace) {
      print('❌ Erro ao salvar foto offline: $e');
      print('📋 Stack trace: $stackTrace');
      return null;
    }
  }

  /// Submete o formulário (sem foto)
  Future<bool> submitForm() async {
    return await submitFormWithPhoto(null);
  }

  /// Submete o formulário com foto
  Future<bool> submitFormWithPhoto(String? uploadedPhotoFilename) async {
    print('📤 ========================================');
    print('📤 === INICIANDO SUBMISSÃO DO FORMULÁRIO ===');
    print('📤 ========================================');
    print('📸 Filename da foto enviada: $uploadedPhotoFilename');
    print('✏️ MODO DE EDIÇÃO ATIVO: $_isEditMode');
    print('✏️ ID DO FORMULÁRIO EM EDIÇÃO: $_editingFormId');
    print('✏️ Já está submetendo: $_isSubmitting');
    print('📋 ID DO _currentForm: ${_currentForm?.id}');
    print('📋 ID DO _currentForm (tipo): ${_currentForm?.id.runtimeType}');

    // PROTEÇÃO CONTRA MÚLTIPLAS SUBMISSÕES
    if (_isSubmitting) {
      print('⚠️ ⚠️ ⚠️ SUBMISSÃO JÁ EM ANDAMENTO - Ignorando chamada duplicada');
      return false;
    }

    if (_currentForm == null) {
      print('❌ ❌ ❌ Nenhum formulário ativo para submeter');
      return false;
    }

    // CORREÇÃO CRÍTICA: Se está em modo de edição mas o ID é null, recuperar do _editingFormId
    if (_isEditMode && _currentForm!.id == null && _editingFormId != null) {
      print('⚠️ ⚠️ ⚠️ CORREÇÃO: Modo de edição ativo mas formulário sem ID!');
      print('⚠️ _editingFormId: $_editingFormId');
      print('⚠️ _currentForm.id: ${_currentForm!.id}');

      // Converter _editingFormId para int
      int? recoveredId;
      if (_editingFormId is int) {
        recoveredId = _editingFormId as int;
      } else if (_editingFormId is String) {
        recoveredId = int.tryParse(_editingFormId!);
      }

      if (recoveredId != null) {
        print('⚠️ RECUPERANDO ID de _editingFormId: $recoveredId');
        _currentForm = _currentForm!.copyWith(id: recoveredId);
        print('✅ ID recuperado com sucesso: ${_currentForm!.id}');
      } else {
        print('❌ ERRO CRÍTICO: Não foi possível recuperar o ID!');
        throw Exception('ERRO CRÍTICO: Modo de edição ativo mas não foi possível recuperar ID!');
      }
    }

    // Validar respostas com lógica condicional antes de submeter
    final validation = validateAllResponses();
    if (!validation.isValid) {
      print('❌ Validação falhou:');
      for (final error in validation.errors) {
        print('  - $error');
      }
      return false;
    }

    _isSubmitting = true;
    notifyListeners();

    bool localSaveSuccess = false;
    bool syncSuccess = false;
    FormResponse formToSave;

    try {
      print('📋 ========================================');
      print('📋 === PREPARANDO FORMULÁRIO PARA SUBMISSÃO ===');
      print('📋 ========================================');
      print('📋 ESTADO CRÍTICO DO PROVIDER:');
      print('📋 - _isEditMode: $_isEditMode');
      print('📋 - _editingFormId: $_editingFormId');
      print('📋 - _currentForm: $_currentForm');
      print('📋 - _currentForm.id: ${_currentForm?.id}');
      print('📋 - _currentForm.id (tipo): ${_currentForm?.id.runtimeType}');
      print('📋 Respostas disponíveis: ${_responses.length}');
      print('📋 Respostas coletadas:');
      _responses.forEach((questionId, response) {
        print(
          '   - Questão $questionId: ${response.displayValue} (tipo: ${response.responseText != null
              ? 'texto'
              : response.responseNumber != null
              ? 'número'
              : response.selectedOptions != null
              ? 'opções'
              : 'outro'})',
        );
      });

      // Lidar com fotos offline (primeira e segunda foto)
      String? finalPhotoFilename =
          uploadedPhotoFilename ?? _currentForm!.photoPath;
      String? finalPhotoFilename2 = _currentForm!.photoPath2;
      String? finalAudioFilename = _currentForm!.audioPath;

      // PROCESSAR PRIMEIRA FOTO
      if (_currentForm!.photoPath != null &&
          _currentForm!.photoPath!.isNotEmpty) {
        final String photoPath = _currentForm!.photoPath!;

        print('📸 === PROCESSANDO FOTO 1 ===');
        print('📸 Caminho da foto 1: $photoPath');

        // Se o photoPath é um caminho completo, significa que é uma foto local que precisa ser salva offline
        if (photoPath.contains('/') && !photoPath.startsWith('http')) {
          print('📸 Foto 1 local detectada, salvando offline...');

          try {
            final String? offlineFilename = await savePhotoOffline(photoPath, photoType: 'photo1');
            if (offlineFilename != null) {
              finalPhotoFilename = offlineFilename;
              print('✅ Foto 1 salva offline como: $offlineFilename');
            } else {
              print('⚠️ Falha ao salvar foto 1 offline, usando caminho original');
              finalPhotoFilename = photoPath;
            }
          } catch (e) {
            print('❌ Erro ao salvar foto 1 offline: $e');
            finalPhotoFilename = photoPath; // Fallback para caminho original
          }
        } else {
          // Já é um filename do servidor ou offline
          print('📸 Foto 1 já processada (filename): $photoPath');
          finalPhotoFilename = photoPath;
        }
      } else {
        print('📸 Nenhuma foto 1 no formulário');
      }

      // PROCESSAR SEGUNDA FOTO
      if (_currentForm!.photoPath2 != null &&
          _currentForm!.photoPath2!.isNotEmpty) {
        final String photoPath2 = _currentForm!.photoPath2!;

        print('📸 === PROCESSANDO FOTO 2 ===');
        print('📸 Caminho da foto 2: $photoPath2');

        // Se o photoPath2 é um caminho completo, significa que é uma foto local que precisa ser salva offline
        if (photoPath2.contains('/') && !photoPath2.startsWith('http')) {
          print('📸 Foto 2 local detectada, salvando offline...');

          try {
            final String? offlineFilename2 = await savePhotoOffline(photoPath2, photoType: 'photo2');
            if (offlineFilename2 != null) {
              finalPhotoFilename2 = offlineFilename2;
              print('✅ Foto 2 salva offline como: $offlineFilename2');
            } else {
              print('⚠️ Falha ao salvar foto 2 offline, usando caminho original');
              finalPhotoFilename2 = photoPath2;
            }
          } catch (e) {
            print('❌ Erro ao salvar foto 2 offline: $e');
            finalPhotoFilename2 = photoPath2; // Fallback para caminho original
          }
        } else {
          // Já é um filename do servidor ou offline
          print('📸 Foto 2 já processada (filename): $photoPath2');
          finalPhotoFilename2 = photoPath2;
        }
      } else {
        print('📸 Nenhuma foto 2 no formulário');
      }

      // PROCESSAR ÁUDIO
      if (_currentForm!.audioPath != null &&
          _currentForm!.audioPath!.isNotEmpty) {
        final String audioPath = _currentForm!.audioPath!;

        print('🎤 === PROCESSANDO ÁUDIO ===');
        print('🎤 Caminho do áudio: $audioPath');

        if (audioPath.contains('/') && !audioPath.startsWith('http')) {
          print('🎤 Áudio local detectado, salvando offline...');

          try {
            final String? offlineFilename = await saveAudioOffline(audioPath);
            if (offlineFilename != null) {
              finalAudioFilename = offlineFilename;
              print('✅ Áudio salvo offline como: $offlineFilename');
            } else {
              print('⚠️ Falha ao salvar áudio offline, usando caminho original');
              finalAudioFilename = audioPath;
            }
          } catch (e) {
            print('❌ Erro ao salvar áudio offline: $e');
            finalAudioFilename = audioPath;
          }
        } else {
          print('🎤 Áudio já processado (filename): $audioPath');
          finalAudioFilename = audioPath;
        }
      } else {
        print('🎤 Nenhum áudio no formulário');
      }

      // Preparar formulário para salvamento
      // Se estiver em modo de edição, GARANTIR que usa o ID existente
      print('📝 ========================================');
      print('📝 === PREPARAR FORMULÁRIO PARA SALVAMENTO ===');
      print('📝 ========================================');
      print('📝 ESTADO COMPLETO:');
      print('📝 - _isEditMode: $_isEditMode');
      print('📝 - _editingFormId: $_editingFormId (tipo: ${_editingFormId.runtimeType})');
      print('📝 - _currentForm: $_currentForm');
      print('📝 - _currentForm.id: ${_currentForm?.id} (tipo: ${_currentForm?.id.runtimeType})');
      print('📝 ========================================');

      if (_isEditMode && _editingFormId != null) {
        print('✏️ ✏️ ✏️ === MODO DE EDIÇÃO ATIVO ===');
        print('✏️ _editingFormId: $_editingFormId (tipo: ${_editingFormId.runtimeType})');
        print('✏️ _currentForm.id ANTES: ${_currentForm?.id}');

        // Garantir que o ID seja int (pode vir como String do storage)
        int? editId;
        if (_editingFormId is int) {
          editId = _editingFormId as int?;
          print('✏️ ID já é int: $editId');
        } else if (_editingFormId is String) {
          editId = int.tryParse(_editingFormId!);
          print('✏️ ID convertido de String para int: $editId');
        }

        // FALLBACK: Se por algum motivo editId é null, usar o ID do currentForm
        if (editId == null && _currentForm?.id != null) {
          editId = _currentForm!.id;
          print('✏️ FALLBACK: Usando ID de _currentForm: $editId');
        }

        print('✏️ ID FINAL que será usado para SOBRESCREVER: $editId');

        formToSave = _currentForm!.copyWith(
          id: editId, // ← CRÍTICO: Usar ID existente para sobrescrever
          syncStatus: 'pending', // Manter como pending para sincronizar depois
          // A data da entrevista é a original; a edição fica em editedAt.
          // Antes completedAt virava a data da edição e a planilha mostrava
          // a entrevista no dia em que foi corrigida.
          completedAt: _currentForm!.completedAt ?? DateTime.now(),
          // O servidor só aplica uma edição mais nova que a última recebida
          editedAt: DateTime.now(),
          responses: _responses.values.toList(),
          photoPath: finalPhotoFilename,
          photoPath2: finalPhotoFilename2,
          audioPath: finalAudioFilename,
        );

        print('✏️ formToSave DEPOIS do copyWith:');
        print('   - id: ${formToSave.id} (DEVE SER O MESMO QUE $editId)');
        print('   - questionnaireId: ${formToSave.questionnaireId}');

        // VERIFICAÇÃO DE SEGURANÇA
        if (formToSave.id != editId) {
          print('❌ ERRO CRÍTICO: O ID do formulário mudou!');
          print('   Esperado: $editId');
          print('   Obtido: ${formToSave.id}');
          throw Exception('ID do formulário não foi preservado no modo de edição');
        }
      } else {
        print('📝 MODO NOVO FORMULÁRIO - Criando novo registro');
        formToSave = _currentForm!.copyWith(
          syncStatus: 'pending', // SEMPRE inicia como pending
          completedAt: DateTime.now(),
          responses: _responses.values.toList(),
          photoPath: finalPhotoFilename,
          photoPath2: finalPhotoFilename2,
          audioPath: finalAudioFilename,
        );
      }

      print('📋 === FORMULÁRIO PREPARADO PARA SALVAMENTO ===');
      print('   - Modo: ${_isEditMode ? "EDIÇÃO" : "NOVO"}');
      print('   - ID do formulário: ${formToSave.id}');
      print('   - ID do questionário: ${formToSave.questionnaireId}');
      print('   - Aplicado por: ${formToSave.appliedBy}');
      print('   - Respostas: ${formToSave.responses.length}');
      print('   - Consentimento: ${formToSave.consentGiven}');
      print(
        '   - Localização: ${formToSave.latitude}, ${formToSave.longitude}',
      );
      print('   - Foto 1 (filename): ${formToSave.photoPath}');
      print('   - Foto 2 (filename): ${formToSave.photoPath2}');
      print('   - Status inicial: ${formToSave.syncStatus}');
      print('   - Iniciado em: ${formToSave.startedAt}');
      print('   - Concluído em: ${formToSave.completedAt}');

      // 1. SEMPRE salvar localmente primeiro - CRÍTICO!
      print('💾 === SALVANDO LOCALMENTE (OFFLINE FIRST) ===');
      try {
        print('📄 Chamando LocalStorageService.saveFormResponse...');
        await LocalStorageService.saveFormResponse(formToSave);
        localSaveSuccess = true;
        print('✅ === SALVO LOCALMENTE COM SUCESSO ===');
      } catch (e, stackTrace) {
        print('❌ === ERRO CRÍTICO NO SALVAMENTO LOCAL ===');
        print('❌ Erro: $e');
        print('📋 Stack trace: $stackTrace');
        localSaveSuccess = false;

        // Tentar salvamento com dados mínimos como fallback
        print('🆘 === TENTATIVA DE SALVAMENTO MÍNIMO ===');
        try {
          final simpleForm = FormResponse(
            questionnaireId: _currentForm!.questionnaireId,
            appliedBy: _currentForm!.appliedBy,
            consentGiven: _currentForm!.consentGiven,
            syncStatus: 'pending',
            startedAt: _currentForm!.startedAt,
            completedAt: DateTime.now(),
            responses: _responses.values.toList(),
            photoPath: finalPhotoFilename,
            photoPath2: finalPhotoFilename2,
          );

          await LocalStorageService.saveFormResponse(simpleForm);
          localSaveSuccess = true;
          formToSave = simpleForm;
          print('✅ Salvamento mínimo bem-sucedido');
        } catch (alternativeError) {
          print('💥 FALHA TOTAL no salvamento: $alternativeError');
          // NÃO lançar exceção aqui - vamos tentar continuar
          localSaveSuccess = false;
        }
      }

      // LEOHARLEY: COMENTEI ABAIXO PARA EVITAR QUE O FORMULÁRIO SEJA SUBMETIDO AUTOMATICAMENTE APOS CONCLUIDO, SOMENTE PELO BOTÃO DE SINCRONIZAR

      // 2. Tentar sincronizar com servidor (se possível) - SEM UPLOAD DE FOTO
      // As fotos agora são sincronizadas separadamente pelo PhotoStorageService

      /*if (localSaveSuccess) {
        print('🌐 === TENTANDO SINCRONIZAR FORMULÁRIO COM SERVIDOR ===');
        try {
          final result = await ApiService.submitForm(formToSave);
          
          if (result['success'] == true) {
            print('✅ Formulário sincronizado com servidor com sucesso');
            syncSuccess = true;
            
            // Atualizar status para 'synced' apenas se conseguiu sincronizar
            if (formToSave.id != null) {
              try {
                await LocalStorageService.updateFormSyncStatus(
                  formToSave.id!, 'synced'
                );
                print('✅ Status local atualizado para \'synced\'');
              } catch (e) {
                print('⚠️ Erro ao atualizar status local, mas sincronização foi bem-sucedida: $e');
              }
            }
          } else {
            print('⚠️ Servidor retornou erro: ${result['message']}');
            syncSuccess = false;
          }
        } catch (e) {
          print('⚠️ Erro ao sincronizar formulário com servidor (modo OFFLINE): $e');
          syncSuccess = false;
          // Em modo offline, isso é esperado - não é um erro crítico
        }
      }

      // 3. Limpar formulário atual APENAS se salvou localmente com sucesso
      if (localSaveSuccess) {
        print('🧹 === LIMPANDO FORMULÁRIO ATUAL ===');
        _currentForm = null;
        _responses.clear();
        _questions.clear();
        _questionStates.clear();
        print('✅ Formulário atual limpo');
      } else {
        print('⚠️ Não limpando formulário - salvamento local falhou');
      }

      */

      // Status final
      print('📊 === SUBMISSÃO CONCLUÍDA ===');
      print('   - Salvo localmente: $localSaveSuccess');
      print('   - Sincronizado: $syncSuccess');
      print('   - Formulário limpo: $localSaveSuccess');
      print('   - Foto offline: ${finalPhotoFilename != null}');

      // LIMPAR MODO DE EDIÇÃO APÓS SUBMISSÃO BEM-SUCEDIDA
      if (localSaveSuccess && _isEditMode) {
        print('✏️ Limpando modo de edição após submissão');
        clearEditMode();
      }

      notifyListeners();

      // Retorna true se pelo menos salvou localmente
      return localSaveSuccess;
    } catch (e, stackTrace) {
      print('❌ === ERRO DURANTE SUBMISSÃO ===');
      print('❌ Erro: $e');
      print('📋 Stack trace: $stackTrace');

      // Se chegou aqui, algo deu muito errado
      // Tentar uma última vez salvar localmente se não conseguiu antes
      if (!localSaveSuccess && _currentForm != null) {
        print('🆘 === TENTATIVA DE SALVAMENTO DE EMERGÊNCIA ===');
        try {
          final emergencyForm = _currentForm!.copyWith(
            syncStatus: 'pending',
            completedAt: DateTime.now(),
            responses: _responses.values.toList(),
            photoPath: uploadedPhotoFilename ?? _currentForm!.photoPath,
            photoPath2: _currentForm!.photoPath2,
          );

          print('📄 Tentando salvar formulário de emergência...');
          await LocalStorageService.saveFormResponse(emergencyForm);
          print('✅ Salvamento de emergência bem-sucedido');

          // Limpar apenas se conseguiu salvar
          _currentForm = null;
          _responses.clear();
          _questions.clear();
          _questionStates.clear();
          localSaveSuccess = true;
          notifyListeners();

          return true; // Conseguiu salvar na tentativa de emergência
        } catch (emergencyError) {
          print(
            '💥 FALHA TOTAL: Não foi possível salvar nem em emergência: $emergencyError',
          );
          return false;
        }
      }

      return localSaveSuccess; // Retorna se conseguiu salvar localmente antes do erro
    } finally {
      print('📚 ========================================');
      print('📚 === FIM DA SUBMISSÃO (FINALLY) ===');
      print('📚 ========================================');
      print('📚 - _isSubmitting ANTES de resetar: $_isSubmitting');
      _isSubmitting = false;
      print('📚 - _isSubmitting DEPOIS de resetar: $_isSubmitting');
      print('📚 - _isEditMode: $_isEditMode');
      print('📚 - _editingFormId: $_editingFormId');
      print('📚 - localSaveSuccess: $localSaveSuccess');
      print('📚 ========================================');
      notifyListeners();
    }
  }

  /// Limpa o formulário atual
  void clearForm() {
    print('🧹 Limpando formulário');
    _currentForm = null;
    _responses.clear();
    _questions.clear();
    _questionStates.clear();
    notifyListeners();
  }

  /// Carregar respostas existentes para edição
  void loadExistingResponses(Map<int, QuestionResponse> existingResponses) {
    print('📝 === CARREGANDO RESPOSTAS EXISTENTES PARA EDIÇÃO ===');
    print('📝 Número de respostas: ${existingResponses.length}');

    _responses.clear();
    _responses.addAll(existingResponses);

    print('✅ Respostas carregadas com sucesso');
    notifyListeners();
  }

  /// Definir modo de edição
  void setEditMode(String formId) {
    print('✏️ Ativando modo de edição para formulário: $formId');
    _isEditMode = true;
    _editingFormId = formId;
    notifyListeners();
  }

  /// Limpar modo de edição
  void clearEditMode() {
    print('✏️ Desativando modo de edição');
    _isEditMode = false;
    _editingFormId = null;
    notifyListeners();
  }

  /// Verifica se há formulários pendentes de sincronização
  /// Coletas ainda NÃO confirmadas pelo painel — é o que a tela principal
  /// mostra e o que a sincronização reenvia.
  ///
  /// Lê só as pendentes: as já enviadas continuam salvas no aparelho, mas
  /// não são carregadas aqui (ver [getSyncedForms] e a tela "Enviadas").
  Future<List<FormResponse>> getPendingForms() async {
    try {
      // 'error' e 'offline' também aguardam envio — não podem sumir da
      // tela nem ficar de fora do reenvio.
      return [
        ...await LocalStorageService.getFormResponsesByStatus('pending'),
        ...await LocalStorageService.getFormResponsesByStatus('offline'),
        ...await LocalStorageService.getFormResponsesByStatus('error'),
      ];
    } catch (e, stackTrace) {
      print('❌ Erro ao buscar formulários pendentes: $e');
      print('📋 Stack trace: $stackTrace');
      return [];
    }
  }

  /// Coletas já confirmadas pelo painel. Carregadas sob demanda, apenas
  /// quando o usuário abre a tela de enviadas.
  Future<List<FormResponse>> getSyncedForms() async {
    try {
      return await LocalStorageService.getFormResponsesByStatus('synced');
    } catch (e) {
      print('❌ Erro ao buscar formulários enviados: $e');
      return [];
    }
  }

  /// Resumo por status, sem instanciar as coletas.
  Future<Map<String, int>> getFormCounts() =>
      LocalStorageService.getFormCountsByStatus();

  /// Sincroniza apenas fotos pendentes
  Future<int> syncPendingPhotosOnly() async {
    print('📸 === SINCRONIZAÇÃO ESPECÍFICA DE FOTOS ===');

    // Web: fotos pendentes vivem no IndexedDB
    if (!PlatformCaps.hasFileSystem) {
      return await syncWebPendingMedia('photo');
    }

    try {
      // Debug antes da sincronização
      print('📸 Debug antes da sincronização:');
      await PhotoStorageService.debugPrintPhotos();

      // Executar sincronização
      final syncedCount = await PhotoStorageService.syncPendingPhotos();

      // Debug após sincronização
      print('📸 Debug após sincronização:');
      await PhotoStorageService.debugPrintPhotos();

      print('📸 Resultado: $syncedCount fotos sincronizadas');
      return syncedCount;
    } catch (e, stackTrace) {
      print('❌ Erro na sincronização de fotos: $e');
      print('📋 Stack trace: $stackTrace');
      return 0;
    }
  }

  /// Versão web: sincroniza mídias pendentes ([kind] = 'photo' ou 'audio')
  /// guardadas no IndexedDB pelo WebMediaStore. Cada item enviado com
  /// sucesso é removido — o que resta é pendente por definição (retry
  /// natural), mesmo contrato do nativo.
  Future<int> syncWebPendingMedia(String kind) async {
    if (PlatformCaps.hasFileSystem) return 0;

    try {
      final filenames = await WebMediaStore.listPendingFilenames(kind);
      print('🌐 $kind pendentes no IndexedDB: ${filenames.length}');

      int synced = 0;
      for (final filename in filenames) {
        try {
          final bytes = await WebMediaStore.readBytes(filename);
          if (bytes == null || bytes.isEmpty) {
            print('⚠️ $filename sem bytes — removendo registro órfão');
            await WebMediaStore.delete(filename);
            continue;
          }

          final result = kind == 'photo'
              ? await ApiService.uploadPhotoBytes(bytes, filename)
              : await ApiService.uploadAudioBytes(bytes, filename);

          if (result['success'] == true ||
              result.containsKey('filename') ||
              result.containsKey('file_name') ||
              result.containsKey('path')) {
            await WebMediaStore.delete(filename);
            synced++;
            print('✅ $kind $filename sincronizado e removido do IndexedDB');
          } else {
            print('❌ Resposta inválida do servidor para $filename: $result');
          }
        } catch (e) {
          print('❌ Erro ao sincronizar $kind $filename: $e');
        }
      }
      return synced;
    } catch (e, stackTrace) {
      print('❌ Erro na sincronização web de $kind: $e');
      print('📋 Stack trace: $stackTrace');
      return 0;
    }
  }

  /// Sincroniza áudios pendentes (arquivos em offline_audios/).
  /// Cada arquivo enviado com sucesso é removido localmente, então o que
  /// resta no diretório é, por definição, pendente — isso dá retry natural
  /// sem precisar de metadados como os das fotos.
  Future<int> syncPendingAudios() async {
    print('🎤 === SINCRONIZANDO ÁUDIOS PENDENTES ===');

    // Web: nada em disco para sincronizar (Fase 2 do plano web troca por
    // MediaStore/IndexedDB).
    if (!PlatformCaps.hasFileSystem) return 0;

    try {
      final appDocDir = await getApplicationDocumentsDirectory();
      final audioDir = Directory('${appDocDir.path}/offline_audios');

      if (!await audioDir.exists()) {
        print('🎤 Diretório de áudios offline não existe, nada a sincronizar');
        return 0;
      }

      final audioFiles = audioDir.listSync().whereType<File>().toList();
      print('🎤 ${audioFiles.length} áudios pendentes para sincronizar');

      int syncedCount = 0;

      for (final audioFile in audioFiles) {
        final filename = audioFile.path.split(Platform.pathSeparator).last;
        try {
          print('📤 Enviando áudio: $filename');
          final result = await ApiService.uploadAudio(audioFile);

          if (result['success'] == true ||
              result.containsKey('filename') ||
              result.containsKey('file_name') ||
              result.containsKey('path')) {
            await audioFile.delete();
            syncedCount++;
            print('✅ Áudio $filename sincronizado e removido localmente');
          } else {
            print('❌ Resposta inválida do servidor para áudio $filename: $result');
          }
        } catch (e) {
          print('❌ Erro ao sincronizar áudio $filename: $e');
        }
      }

      print('✅ Sincronização de áudios concluída: $syncedCount de ${audioFiles.length}');
      return syncedCount;
    } catch (e, stackTrace) {
      print('❌ Erro durante sincronização de áudios: $e');
      print('📋 Stack trace: $stackTrace');
      return 0;
    }
  }

  /// Diagnóstico completo de fotos
  Future<void> debugPhotosFullDiagnostic() async {
    print('🔍 === DIAGNÓSTICO COMPLETO DE FOTOS ===');

    try {
      // 1. Verificar estatísticas
      final stats = await PhotoStorageService.getPhotosStats();
      print('📊 Estatísticas: $stats');

      // 2. Listar fotos pendentes
      final pendingPhotos = await PhotoStorageService.getPendingPhotos();
      print('📸 Fotos pendentes: ${pendingPhotos.length}');

      for (int i = 0; i < pendingPhotos.length; i++) {
        final photo = pendingPhotos[i];
        print('📸 [$i] ${photo['filename']}:');
        print('   - Form ID: ${photo['formId']}');
        print('   - Local Path: ${photo['localPath']}');
        print('   - Status: ${photo['syncStatus']}');
        print('   - File Size: ${photo['fileSize']}');

        // Verificar se arquivo existe
        final File photoFile = File(photo['localPath']);
        final bool exists = await photoFile.exists();
        print('   - Arquivo existe: $exists');

        if (exists) {
          final int currentSize = await photoFile.length();
          print('   - Tamanho atual: $currentSize bytes');
        }
      }

      // 3. Debug completo
      await PhotoStorageService.debugPrintPhotos();
    } catch (e, stackTrace) {
      print('❌ Erro no diagnóstico: $e');
      print('📋 Stack trace: $stackTrace');
    }

    print('🔍 === FIM DIAGNÓSTICO ===');
  }

  /// Sincroniza formulários e fotos pendentes
  /// Motivo real da última falha de sincronização, para a interface poder
  /// dizer o que aconteceu.
  ///
  /// Antes, cada erro do laço era só impresso no console e a contagem ficava
  /// em zero — o aplicador via "verifique sua conexão" mesmo com sessão
  /// expirada, erro 500 ou payload rejeitado, e não tinha como agir.
  String? _lastSyncError;
  String? get lastSyncError => _lastSyncError;

  /// Reenvia UMA coleta específica, mesmo já confirmada.
  ///
  /// Seguro por causa do client_id: o backend reconhece a coleta pela chave
  /// de idempotência e devolve o registro existente em vez de duplicar.
  /// Serve para quando há dúvida se a coleta chegou ao painel — inclusive
  /// para as que versões antigas marcaram como enviadas sem confirmação.
  Future<({bool success, String message})> resendForm(FormResponse form) async {
    try {
      var paraEnviar = form;

      // Coleta antiga sem client_id: atribui e PERSISTE antes de enviar,
      // senão cada reenvio viraria um registro novo no painel.
      if (paraEnviar.clientId == null && paraEnviar.id != null) {
        paraEnviar = paraEnviar.copyWith(clientId: const Uuid().v4());
        await LocalStorageService.updateFormResponse(paraEnviar);
        print('🔑 client_id atribuído no reenvio: ${paraEnviar.clientId}');
      }

      print('🔄 Reenviando coleta ${paraEnviar.id}...');
      final result = await ApiService.submitForm(paraEnviar);

      if (result['success'] != true) {
        return (
          success: false,
          message: result['message']?.toString() ??
              'O servidor recusou o reenvio.',
        );
      }

      final serverId = FormResponse.extractServerId(result);
      if (serverId == null) {
        return (
          success: false,
          message: 'O servidor respondeu sem confirmar o registro. '
              'A coleta continua salva no aparelho.',
        );
      }

      if (paraEnviar.id != null) {
        await LocalStorageService.updateFormSyncStatus(
          paraEnviar.id!,
          'synced',
          serverId: serverId,
          syncedAt: DateTime.now(),
        );
      }

      final duplicada = result['duplicated'] == true;
      return (
        success: true,
        message: duplicada
            ? 'Esta coleta já estava no painel (registro #$serverId).'
            : 'Coleta enviada e confirmada no painel (registro #$serverId).',
      );
    } on PermanentSubmitException catch (e) {
      return (success: false, message: e.message);
    } catch (e) {
      return (
        success: false,
        message: e.toString().replaceAll('Exception: ', ''),
      );
    }
  }

  Future<int> syncPendingForms() async {
    print('🔄 === SINCRONIZAÇÃO COMPLETA (FORMULÁRIOS + FOTOS) ===');
    print('🔄 Timestamp: ${DateTime.now()}');
    _lastSyncError = null;

    try {
      int totalSynced = 0;

      // 1. Sincronizar formulários pendentes PRIMEIRO
      print('📋 === FASE 1: SINCRONIZANDO FORMULÁRIOS ===');

      List<FormResponse> pendingForms;
      try {
        pendingForms = await getPendingForms();
        print('📋 ${pendingForms.length} formulários pendentes encontrados');
      } catch (e, stackTrace) {
        print('❌ ERRO CRÍTICO ao buscar formulários pendentes: $e');
        print('📋 Stack trace: $stackTrace');
        _lastSyncError = 'Não foi possível ler os formulários salvos: $e';
        return 0; // Retorna 0 se não conseguir buscar
      }

      if (pendingForms.isEmpty) {
        print('⚠️ Nenhum formulário pendente para sincronizar');
        // Continua para sincronizar fotos
      }

      // ORDEM IMPORTA: fotos e áudios sobem ANTES dos formulários.
      //
      // Antes o formulário era marcado 'synced' na fase 1 e as mídias só
      // subiam nas fases 2 e 3. Se a mídia falhasse, a coleta já tinha saído
      // da fila de pendentes: sumia do app com foto/áudio nunca enviados.
      print('📸 === PRÉ-FASE: ENVIANDO MÍDIAS ANTES DOS FORMULÁRIOS ===');
      int mediaSyncedCount = 0;
      bool mediaFailed = false;
      try {
        mediaSyncedCount += await PhotoStorageService.syncPendingPhotos();
        mediaSyncedCount += await syncPendingAudios();
        if (!PlatformCaps.hasFileSystem) {
          mediaSyncedCount += await syncWebPendingMedia('photo');
          mediaSyncedCount += await syncWebPendingMedia('audio');
        }
        // Sobrou mídia pendente? Então algum envio falhou.
        final stats = await PhotoStorageService.getPhotosStats();
        var pendentes = (stats['pending'] ?? 0) + (stats['error'] ?? 0);

        // Na web os áudios ficam no IndexedDB, fora das estatísticas de
        // fotos — sem esta checagem a trava deixava passar formulário com
        // áudio ainda no aparelho.
        if (!PlatformCaps.hasFileSystem) {
          pendentes += await WebMediaStore.pendingCount('audio');
        }
        if (pendentes > 0) {
          mediaFailed = true;
          print('⚠️ $pendentes mídia(s) ainda pendente(s) após o envio');
        }
      } catch (e, stackTrace) {
        mediaFailed = true;
        print('❌ ERRO ao enviar mídias: $e');
        print('📋 Stack trace: $stackTrace');
        _lastSyncError = 'Erro ao enviar fotos/áudios: '
            '${e.toString().replaceAll('Exception: ', '')}';
      }

      if (mediaFailed) {
        // Não envia os formulários: eles seriam confirmados e sairiam da
        // fila enquanto a mídia correspondente continua no aparelho.
        print('🛑 Envio de formulários adiado: há mídias pendentes');
        _lastSyncError ??=
            'Algumas fotos ou áudios não foram enviados. As respostas '
            'continuam salvas no aparelho — tente novamente com melhor sinal.';
        return mediaSyncedCount;
      }

      int formsSyncedCount = 0;
      for (int i = 0; i < pendingForms.length; i++) {
        var form = pendingForms[i];

        try {
          // Coletas salvas por versões anteriores não têm client_id.
          // Atribui um agora e PERSISTE antes de enviar — se a resposta
          // se perder, o reenvio usa o mesmo valor e o backend deduplica.
          if (form.clientId == null && form.id != null) {
            form = form.copyWith(clientId: const Uuid().v4());
            await LocalStorageService.updateFormResponse(form);
            print('🔑 client_id atribuído à coleta ${form.id}: '
                '${form.clientId}');
          }

          print('📋 === SINCRONIZANDO FORMULÁRIO ${i + 1}/${pendingForms.length} ===');
          print('📋 ID do formulário: ${form.id}');
          print('📋 Questionário ID: ${form.questionnaireId}');
          print('📋 Aplicado por: ${form.appliedBy}');
          print('📋 Respostas: ${form.responses.length}');
          print('📋 Status atual: ${form.syncStatus}');

          // Debug do JSON antes de enviar
          final formMap = form.toJson();
          print('📋 JSON preparado para envio (${formMap.toString().length} caracteres)');

          // Tentar sincronizar com o servidor
          print('🌐 Enviando para API...');
          final result = await ApiService.submitForm(form);

          print('📋 Resposta da API: $result');

          if (result['success'] == true) {
            // Prova de gravação: o id do registro criado no painel. Alguns
            // backends devolvem em 'data', outros na raiz.
            final serverId = FormResponse.extractServerId(result);

            if (serverId == null) {
              // 200 sem identificador: provavelmente gravou, mas não dá para
              // provar. Mantém pendente — reenviar é melhor que perder.
              print('⚠️ Servidor confirmou sem devolver id do registro; '
                  'formulário ${form.id} permanece pendente');
              _lastSyncError ??=
                  'O servidor respondeu sem confirmar o registro. As '
                  'respostas continuam salvas no aparelho.';
            } else if (form.id != null) {
              // duplicated:true é SUCESSO — o backend reconheceu o
              // client_id de um envio anterior e devolveu o id que já
              // existia. Significa que a coleta ESTÁ no painel.
              final duplicada = result['duplicated'] == true;

              await LocalStorageService.updateFormSyncStatus(
                form.id!,
                'synced',
                serverId: serverId,
                syncedAt: DateTime.now(),
              );
              formsSyncedCount++;
              print(duplicada
                  ? '✅ Formulário ${form.id} JÁ ESTAVA no painel '
                      '(dedup por client_id, id: $serverId)'
                  : '✅ Formulário ${form.id} confirmado no painel '
                      '(id do servidor: $serverId)');
            } else {
              print('⚠️ Formulário sincronizado mas sem ID local');
            }
          } else {
            print('⚠️ Falha ao sincronizar formulário ${form.id}: ${result['message']}');
            _lastSyncError = result['message']?.toString() ??
                'O servidor recusou o formulário sem informar o motivo.';
          }
        } on PermanentSubmitException catch (e) {
          // Reenviar o mesmo corpo daria o mesmo erro. Marca a coleta para
          // não repetir a cada sincronização — ela CONTINUA no aparelho,
          // nada é descartado, e o aplicador é avisado.
          print('🛑 Erro permanente no formulário ${form.id}: ${e.message}');
          if (form.id != null) {
            await LocalStorageService.updateFormSyncStatus(form.id!, 'error');
          }
          _lastSyncError = e.message;
        } catch (e, stackTrace) {
          print('❌ Erro ao sincronizar formulário ${form.id}: $e');
          print('📋 Stack trace: $stackTrace');
          _lastSyncError = e.toString().replaceAll('Exception: ', '');
        }
      }

      totalSynced += formsSyncedCount;
      print('📋 === RESULTADO FASE 1 ===');
      print('📋 Formulários sincronizados: $formsSyncedCount de ${pendingForms.length}');

      // As mídias já subiram na pré-fase, antes dos formulários.
      totalSynced += mediaSyncedCount;

      print('📊 === SINCRONIZAÇÃO COMPLETA CONCLUÍDA ===');
      print(
        '   - Formulários sincronizados: $formsSyncedCount de ${pendingForms.length}',
      );
      print('   - Fotos processadas: executado (verificar logs acima)');
      print('   - Áudios processados: executado (verificar logs acima)');
      print('   - Total de itens sincronizados: $totalSynced');

      return totalSynced;
    } catch (e, stackTrace) {
      print('❌ Erro durante sincronização completa: $e');
      print('📋 Stack trace: $stackTrace');
      return 0;
    }
  }

  // ========== MÉTODOS DE DEBUG ==========

  /// Debug do estado atual
  void debugPrintCurrentState() {
    print('🔍 Estado atual do FormProvider:');
    print('   - Formulário ativo: ${_currentForm != null}');
    print('   - Perguntas: ${_questions.length}');
    print('   - Respostas: ${_responses.length}');
    print('   - Estados: ${_questionStates.length}');
    print('   - Enviando: $_isSubmitting');

    if (_currentForm != null) {
      print('   - Questionário ID: ${_currentForm!.questionnaireId}');
      print('   - Aplicado por: ${_currentForm!.appliedBy}');
      print('   - Consentimento: ${_currentForm!.consentGiven}');
    }

    _responses.forEach((questionId, response) {
      print('   - Questão $questionId: ${response.toString()}');
    });

    print('🔧 Estados das perguntas:');
    _questionStates.forEach((index, state) {
      final question = index < _questions.length ? _questions[index] : null;
      if (question != null) {
        print('   - Pergunta $index (ID ${question.id}): $state');
      } else {
        print('   - Pergunta $index: $state');
      }
    });
  }

  /// Debug do storage local
  Future<void> debugPrintLocalStorage() async {
    print('🔍 === DEBUG STORAGE LOCAL VIA FORMPROVIDER ===');
    try {
      final forms = await LocalStorageService.getFormResponses();
      print('📋 Total de formulários encontrados: ${forms.length}');

      final pending = forms.where((f) => f.syncStatus == 'pending').length;
      final synced = forms.where((f) => f.syncStatus == 'synced').length;

      print('   - Pendentes: $pending');
      print('   - Sincronizados: $synced');

      for (var form in forms) {
        print(
          '   - ID: ${form.id}, Status: ${form.syncStatus}, Questionário: ${form.questionnaireId}, Respostas: ${form.responses.length}',
        );
      }
    } catch (e) {
      print('❌ Erro no debug do storage: $e');
    }
    print('🔍 === FIM DEBUG FORMPROVIDER ===');
  }

  /// Teste de salvamento do formulário atual
  Future<bool> testSaveCurrentForm() async {
    if (_currentForm == null) {
      print('❌ Nenhum formulário ativo para testar');
      return false;
    }

    print('🧪 === TESTE DE SALVAMENTO DO FORMULÁRIO ATUAL ===');
    try {
      final testForm = _currentForm!.copyWith(
        id: DateTime.now().millisecondsSinceEpoch,
        syncStatus: 'test',
        completedAt: DateTime.now(),
        responses: _responses.values.toList(),
      );

      await LocalStorageService.saveFormResponse(testForm);

      // Verificar se foi salvo
      final forms = await LocalStorageService.getFormResponses();
      final found = forms.any((f) => f.id == testForm.id);

      if (found) {
        print('✅ Teste do formulário atual PASSOU');

        // Limpar o teste
        final filteredForms = forms.where((f) => f.id != testForm.id).toList();
        final prefs = await SharedPreferences.getInstance();
        if (filteredForms.isEmpty) {
          await prefs.remove('form_responses');
        } else {
          final jsonList = filteredForms.map((f) => f.toJson()).toList();
          final jsonString = jsonEncode(jsonList);
          await prefs.setString('form_responses', jsonString);
        }

        return true;
      } else {
        print('❌ Teste do formulário atual FALHOU');
        return false;
      }
    } catch (e) {
      print('❌ Erro no teste: $e');
      return false;
    }
  }

  /// MÉTODO DE TESTE: Testa a lógica condicional com dados mockados
  void testConditionalLogic() {
    print('🧪 === TESTE DA LÓGICA CONDICIONAL ===');

    if (_questions.isEmpty) {
      print('❌ Nenhuma questão disponível para teste');
      return;
    }

    print('🧪 Testando com o formato JSON correto...');

    // Exemplo do JSON fornecido pelo usuário:
    // {"visibility":{"operator":"AND","conditions":[{"question":0,"operator":"equals","value":"teste"}]},"required":null}

    print(
      '🧪 Simulando JSON: {"visibility":{"operator":"AND","conditions":[{"question":0,"operator":"equals","value":"teste"}]},"required":null}',
    );

    // Encontrar questões com lógica condicional
    for (int i = 0; i < _questions.length; i++) {
      final question = _questions[i];

      if (question.hasConditionalLogic) {
        print('🧪 === TESTANDO QUESTÃO $i (ID ${question.id}) ===');
        print('🧪 Texto: "${question.questionText}"');
        print('🧪 JSON da lógica: ${question.conditionalLogic}');

        final logic = question.parsedConditionalLogic!;

        if (logic.visibility != null) {
          print('🧪 Regras de visibilidade encontradas:');
          for (var condition in logic.visibility!.conditions) {
            print(
              '   - Questão ID ${condition.questionId} ${condition.operator} "${condition.value}"',
            );

            // Testar cenário 1: Condição VERDADEIRA
            final testResponsesTrue = <int, dynamic>{
              condition.questionId: condition.value,
            };
            print(
              '🧪 TESTE 1: Resposta questão ${condition.questionId} = "${condition.value}"',
            );
            final resultTrue = ConditionalLogicEngine.executeLogic(
              _questions,
              testResponsesTrue,
            );
            final stateTrue = resultTrue[i];
            print(
              '🧪 Resultado: visible=${stateTrue?.visible}, required=${stateTrue?.required}',
            );
            print('');

            // Testar cenário 2: Condição FALSA
            final testResponsesFalse = <int, dynamic>{
              condition.questionId: 'outro_valor_diferente',
            };
            print(
              '🧪 TESTE 2: Resposta questão ${condition.questionId} = "outro_valor_diferente"',
            );
            final resultFalse = ConditionalLogicEngine.executeLogic(
              _questions,
              testResponsesFalse,
            );
            final stateFalse = resultFalse[i];
            print(
              '🧪 Resultado: visible=${stateFalse?.visible}, required=${stateFalse?.required}',
            );
            print('');

            // Testar cenário 3: Sem resposta
            final testResponsesEmpty = <int, dynamic>{};
            print(
              '🧪 TESTE 3: Sem resposta para questão ${condition.questionId}',
            );
            final resultEmpty = ConditionalLogicEngine.executeLogic(
              _questions,
              testResponsesEmpty,
            );
            final stateEmpty = resultEmpty[i];
            print(
              '🧪 Resultado: visible=${stateEmpty?.visible}, required=${stateEmpty?.required}',
            );
            print('');
          }
        }

        if (logic.required != null) {
          print('🧪 Regras de obrigatoriedade encontradas:');
          for (var condition in logic.required!.conditions) {
            print(
              '   - Questão ID ${condition.questionId} ${condition.operator} "${condition.value}"',
            );
          }
        }

        print('🧪 === FIM TESTE QUESTÃO $i ===');
        print('');
      }
    }

    print('🧪 === FIM TESTE GERAL ===');
  }

  /// Testa especificamente o JSON fornecido pelo usuário
  void testSpecificJSON() {
    print('🧪 === TESTE ESPECÍFICO DO JSON FORNECIDO ===');

    // JSON do usuário: {"visibility":{"operator":"AND","conditions":[{"question":0,"operator":"equals","value":"teste"}]},"required":null}

    final testJson = {
      "visibility": {
        "operator": "AND",
        "conditions": [
          {"question": 0, "operator": "equals", "value": "teste"},
        ],
      },
      "required": null,
    };

    print('🧪 JSON de teste: $testJson');

    try {
      // Testar parsing do JSON
      final logic = ConditionalLogic.fromJson(testJson);
      print('✅ JSON parseado com sucesso');
      print('🧪 Tem regras de visibilidade: ${logic.visibility != null}');
      print('🧪 Tem regras de obrigatoriedade: ${logic.required != null}');

      if (logic.visibility != null) {
        print('🧪 Operador: ${logic.visibility!.operator}');
        print('🧪 Condições: ${logic.visibility!.conditions.length}');

        for (int i = 0; i < logic.visibility!.conditions.length; i++) {
          final condition = logic.visibility!.conditions[i];
          print('🧪 Condição $i:');
          print('   - Questão ID: ${condition.questionId}');
          print('   - Operador: ${condition.operator}');
          print('   - Valor: "${condition.value}"');
        }

        // Testar avaliação
        print('🧪 === TESTANDO AVALIAÇÃO ===');

        // Cenário 1: Questão 0 = "teste" (deve ser true)
        final responses1 = {0: "teste"};
        print('🧪 Teste 1: Questão 0 = "teste"');
        final result1 = logic.visibility!.evaluate(responses1);
        print('🧪 Resultado: $result1 (esperado: true)');

        // Cenário 2: Questão 0 = "outro" (deve ser false)
        final responses2 = {0: "outro"};
        print('🧪 Teste 2: Questão 0 = "outro"');
        final result2 = logic.visibility!.evaluate(responses2);
        print('🧪 Resultado: $result2 (esperado: false)');

        // Cenário 3: Sem resposta (deve ser false)
        final responses3 = <int, dynamic>{};
        print('🧪 Teste 3: Sem resposta');
        final result3 = logic.visibility!.evaluate(responses3);
        print('🧪 Resultado: $result3 (esperado: false)');
      }
    } catch (e, stackTrace) {
      print('❌ Erro ao testar JSON: $e');
      print('📋 Stack trace: $stackTrace');
    }

    print('🧪 === FIM TESTE ESPECÍFICO ===');
  }

  /// Força a re-execução da lógica condicional com logs detalhados
  void debugConditionalLogic() {
    print('🔧 === DEBUG DETALHADO DA LÓGICA CONDICIONAL ===');

    if (_questions.isEmpty) {
      print('❌ Nenhuma questão carregada');
      return;
    }

    print('📝 Questões carregadas: ${_questions.length}');
    for (int i = 0; i < _questions.length; i++) {
      final q = _questions[i];
      print('[$i] ID ${q.id}: "${q.questionText}"');
      print('     Tipo: ${q.questionType}');
      print('     Order: ${q.orderIndex}');
      print('     Required: ${q.isRequired}');
      print('     Tem lógica: ${q.hasConditionalLogic}');

      if (q.hasConditionalLogic) {
        print('     JSON lógica: ${q.conditionalLogic}');

        try {
          final parsedLogic = q.parsedConditionalLogic;
          if (parsedLogic != null) {
            print('     Lógica parseada: OK');
            if (parsedLogic.visibility != null) {
              print(
                '     Regras visibilidade: ${parsedLogic.visibility!.conditions.length}',
              );
              for (var cond in parsedLogic.visibility!.conditions) {
                print(
                  '       - Questão ${cond.questionId} ${cond.operator} "${cond.value}"',
                );
              }
            }
            if (parsedLogic.required != null) {
              print(
                '     Regras obrigatoriedade: ${parsedLogic.required!.conditions.length}',
              );
            }
          } else {
            print('     ❌ Falha ao parsear lógica');
          }
        } catch (e) {
          print('     ❌ Erro ao analisar lógica: $e');
        }
      }
      print('');
    }

    print('📋 Respostas atuais: ${_responses.length}');
    _responses.forEach((id, response) {
      print(
        'Questão $id: "${response.getValue()}" (${response.getValue().runtimeType})',
      );
    });

    print('📊 Estados atuais: ${_questionStates.length}');
    _questionStates.forEach((index, state) {
      final q = _questions[index];
      print(
        '[$index] ID ${q.id}: visible=${state.visible}, required=${state.required}',
      );
    });

    // Forçar execução da lógica
    print('🔧 Forçando execução da lógica...');
    _executeConditionalLogic();

    print('🔧 === FIM DEBUG ===');
  }

  /// Debug específico para uma pergunta por ID
  void debugQuestionById(int questionId) {
    print('🔍 === DEBUG ESPECÍFICO DA PERGUNTA ID $questionId ===');

    // Encontrar a pergunta
    final questionIndex = _questions.indexWhere((q) => q.id == questionId);
    if (questionIndex == -1) {
      print('❌ Pergunta ID $questionId não encontrada!');
      return;
    }

    final question = _questions[questionIndex];
    final state = _questionStates[questionIndex];

    print('📝 Pergunta ID $questionId encontrada no índice: $questionIndex');
    print('📝 Texto: "${question.questionText}"');
    print('📝 Tem lógica condicional: ${question.hasConditionalLogic}');
    print('📝 Estado atual: $state');

    if (question.hasConditionalLogic) {
      print('🔧 Lógica condicional: ${question.conditionalLogicSummary}');
      print('🔧 JSON da lógica: ${question.conditionalLogic}');

      // Verificar dependências
      final logic = question.parsedConditionalLogic;
      if (logic != null) {
        if (logic.visibility != null) {
          print('👁️ Regras de visibilidade:');
          for (var condition in logic.visibility!.conditions) {
            final depResponse = _responses[condition.questionId];
            print(
              '   - Pergunta ${condition.questionId} ${condition.operator} ${condition.value}',
            );
            print('   - Resposta atual: ${depResponse?.getValue()}');
          }
        }

        if (logic.required != null) {
          print('⚠️ Regras de obrigatoriedade:');
          for (var condition in logic.required!.conditions) {
            final depResponse = _responses[condition.questionId];
            print(
              '   - Pergunta ${condition.questionId} ${condition.operator} ${condition.value}',
            );
            print('   - Resposta atual: ${depResponse?.getValue()}');
          }
        }
      }
    }

    print('🔍 === FIM DEBUG PERGUNTA ID $questionId ===');
  }

  /// Método de compatibilidade - debug da pergunta ID 8
  void debugQuestionId8() {
    debugQuestionById(8);
  }
}

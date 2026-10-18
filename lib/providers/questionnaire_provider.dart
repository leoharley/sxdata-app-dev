import 'package:flutter/foundation.dart';
import '../models/questionnaire.dart';
import '../services/api_service.dart';
import '../services/local_storage_service.dart';

class QuestionnaireProvider with ChangeNotifier {
  List<Questionnaire> _questionnaires = [];
  bool _isLoading = false;
  String? _error;
  bool _isFromCache = false;

  List<Questionnaire> get questionnaires => _questionnaires;
  bool get isLoading => _isLoading;
  String? get error => _error;

  /// True quando a lista exibida veio do cache local porque o servidor não
  /// respondeu. Nesse estado a lista pode conter questionários já
  /// desativados no painel — a tela deve avisar que está desatualizada.
  bool get isFromCache => _isFromCache;

  Future<void> loadQuestionnaires() async {
    print('🔄 Starting to load questionnaires...');
    
    _isLoading = true;
    _error = null;
    _isFromCache = false;
    notifyListeners();

    // A lista salva no aparelho aparece na hora; a do servidor a substitui
    // quando chegar. Com sinal fraco, esperar o servidor deixava o aplicador
    // olhando "Carregando questionários..." até o prazo da chamada estourar.
    try {
      final salvos = await LocalStorageService.getQuestionnaires();
      if (salvos.isNotEmpty) {
        _questionnaires = salvos;
        _isLoading = false;
        notifyListeners();
      }
    } catch (e) {
      print('⚠️ Cache de questionários ilegível: $e');
    }

    try {
      print('🌐 Attempting to load from server...');
      
      // Try to load from server first
      final serverData = await ApiService.getQuestionnaires();

      print('📡 Server response received:');
      print('📡 Success: ${serverData['success']}');
      print('📡 Data type: ${serverData['data'].runtimeType}');
      
      if (serverData['data'] is List) {
        final dataList = serverData['data'] as List;
        print('📡 Data length: ${dataList.length}');
        
        if (dataList.isNotEmpty) {
          print('📡 First item keys: ${(dataList.first as Map).keys.toList()}');
          print('📡 First item title: ${dataList.first['title']}');
          
          // Verificar se há questões no primeiro item
          if (dataList.first['questions'] != null) {
            final questions = dataList.first['questions'] as List;
            print('📡 First questionnaire has ${questions.length} questions');
            if (questions.isNotEmpty) {
              print('📡 First question: ${questions.first}');
            }
          }
        }
      }
      
      if (serverData['success'] == true) {
        print('✅ Server request successful');

        // Lista vazia é uma RESPOSTA VÁLIDA, não um erro: significa que o
        // usuário não tem nenhum questionário ativo disponível. Tratá-la
        // como falha fazia o app cair no cache e ressuscitar questionários
        // já desativados no painel (com o status "active" antigo gravado).
        final dataList = (serverData['data'] as List?) ?? const [];
        {
          print('🔄 Converting ${dataList.length} questionnaires...');

          _questionnaires = [];

          for (int i = 0; i < dataList.length; i++) {
            try {
              final rawData = dataList[i] as Map<String, dynamic>;
              print('🔄 Converting questionnaire $i: ${rawData['title']}');
              print('📋 Raw questionnaire data: $rawData');
              
              final questionnaire = Questionnaire.fromJson(rawData);
              _questionnaires.add(questionnaire);
              
              print('✅ Questionnaire $i converted successfully:');
              print('   - Title: ${questionnaire.title}');
              print('   - Questions: ${questionnaire.questions.length}');
              
              // Log das questões
              for (int j = 0; j < questionnaire.questions.length; j++) {
                final q = questionnaire.questions[j];
                print('   - Question $j: ${q.questionText} (type: ${q.questionType}, options: ${q.options.length})');
              }
              
            } catch (conversionError, stackTrace) {
              print('❌ Error converting questionnaire $i: $conversionError');
              print('📋 Raw data: ${dataList[i]}');
              print('📋 Stack trace: $stackTrace');
              // Continue com os outros questionários mesmo se um falhar
            }
          }
          
          print('✅ Successfully converted ${_questionnaires.length} questionnaires');
          print('📊 Final questionnaires list:');
          for (int i = 0; i < _questionnaires.length; i++) {
            print('   $i: ${_questionnaires[i].title} (${_questionnaires[i].questions.length} questions)');
          }
          
          // RECONCILIAÇÃO: grava exatamente a lista que o servidor mandou,
          // substituindo o cache inteiro. Questionários que não vieram
          // (desativados no painel ou com acesso revogado) somem daqui.
          // Só acontece em resposta bem-sucedida — falha de rede cai no
          // catch e preserva o cache.
          try {
            await LocalStorageService.saveQuestionnaires(_questionnaires);
            print('💾 Cache reconciliado com o servidor: '
                '${_questionnaires.length} questionário(s) disponíveis');
          } catch (storageError) {
            print('⚠️ Failed to save to local storage: $storageError');
          }
        }
      } else {
        print('❌ Server request failed: ${serverData['message'] ?? 'Unknown error'}');
        throw Exception(serverData['message'] ?? 'Failed to load from server');
      }
    } catch (e, stackTrace) {
      print('❌ Error loading from server: $e');
      print('📋 Stack trace: $stackTrace');
      print('🔄 Attempting to load from local storage...');
      
      // Fallback ao cache: NUNCA apagar aqui. A chamada falhou, então não
      // sabemos o que mudou no painel — apagar deixaria o coletor sem
      // nenhum questionário em campo. O cache fica como está até uma
      // resposta bem-sucedida reconciliar.
      try {
        _questionnaires = await LocalStorageService.getQuestionnaires();
        _isFromCache = _questionnaires.isNotEmpty;
        print('💾 Exibindo ${_questionnaires.length} questionário(s) do cache '
            '(offline; podem estar desatualizados)');

        if (_questionnaires.isEmpty) {
          _error = 'Não foi possível carregar os questionários';
          print('⚠️ No questionnaires found in local storage either');
        }
      } catch (localError) {
        print('❌ Failed to load from local storage: $localError');
        _error = 'Não foi possível carregar os questionários';
        _questionnaires = [];
      }
    } finally {
      _isLoading = false;
      
      print('🏁 Load questionnaires finished');
      print('📊 Final state: ${_questionnaires.length} questionnaires, error: $_error');
      
      // Log final detalhado
      if (_questionnaires.isNotEmpty) {
        print('📋 Final questionnaires summary:');
        for (int i = 0; i < _questionnaires.length; i++) {
          final q = _questionnaires[i];
          print('   $i: ${q.title}');
          print('      - ID: ${q.id}');
          print('      - Questions: ${q.questions.length}');
          print('      - Requires photo: ${q.requiresPhoto}');
          print('      - Status: ${q.status}');
          
          for (int j = 0; j < q.questions.length; j++) {
            final question = q.questions[j];
            print('      - Q$j: ${question.questionText} (${question.questionType})');
          }
        }
      } else {
        print('📋 No questionnaires in final state');
      }
      
      notifyListeners();
    }
  }

  Questionnaire? getQuestionnaireById(int id) {
    try {
      final questionnaire = _questionnaires.firstWhere((q) => q.id == id);
      print('✅ Found questionnaire: ${questionnaire.title} with ${questionnaire.questions.length} questions');
      return questionnaire;
    } catch (e) {
      print('❌ Questionnaire with id $id not found');
      print('📋 Available questionnaires: ${_questionnaires.map((q) => '${q.id}: ${q.title}').toList()}');
      return null;
    }
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  Future<void> refresh() async {
    await loadQuestionnaires();
  }
}
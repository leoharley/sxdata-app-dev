import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/questionnaire.dart';
import '../models/form_response.dart';

class LocalStorageService {
  static const String _questionnairesKey = 'questionnaires';
  static const String _formsKey = 'form_responses';

  // Questionnaires
  static Future<void> saveQuestionnaires(List<Questionnaire> questionnaires) async {
    try {
      print('💾 Salvando ${questionnaires.length} questionários');
      final prefs = await SharedPreferences.getInstance();
      final jsonList = questionnaires.map((q) => q.toJson()).toList();
      final jsonString = jsonEncode(jsonList);
      await prefs.setString(_questionnairesKey, jsonString);
      print('✅ Questionários salvos com sucesso');
    } catch (e, stackTrace) {
      print('❌ Erro ao salvar questionários: $e');
      print('📋 Stack trace: $stackTrace');
      rethrow;
    }
  }

  static Future<List<Questionnaire>> getQuestionnaires() async {
    try {
      print('📖 === CARREGANDO QUESTIONÁRIOS DO STORAGE LOCAL ===');
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString(_questionnairesKey);

      if (jsonString == null) {
        print('⚠️ Nenhum questionário encontrado no storage local');
        return [];
      }

      print('📋 JSON encontrado com ${jsonString.length} caracteres');

      final jsonList = jsonDecode(jsonString) as List<dynamic>;
      print('📋 Lista JSON decodificada com ${jsonList.length} questionários');

      final questionnaires = <Questionnaire>[];
      for (int i = 0; i < jsonList.length; i++) {
        try {
          final json = jsonList[i] as Map<String, dynamic>;
          print('📋 Processando questionário $i: ${json['title']}');

          // Debug: verificar se as questões existem
          if (json['questions'] != null) {
            final questions = json['questions'] as List;
            print('   - ${questions.length} questões encontradas');

            // Debug: verificar opções da primeira questão se existir
            if (questions.isNotEmpty) {
              final firstQuestion = questions[0] as Map<String, dynamic>;
              print('   - Primeira questão: ${firstQuestion['question_text']}');
              print('   - Tipo: ${firstQuestion['question_type']}');

              if (firstQuestion['options'] != null) {
                final options = firstQuestion['options'] as List;
                print('   - Opções encontradas: ${options.length}');

                if (options.isNotEmpty) {
                  print('   - Primeira opção: ${options[0]}');
                }
              } else {
                print('   - ⚠️ NENHUMA OPÇÃO ENCONTRADA NA PRIMEIRA QUESTÃO!');
              }
            }
          } else {
            print('   - ⚠️ NENHUMA QUESTÃO ENCONTRADA!');
          }

          final questionnaire = Questionnaire.fromJson(json);
          questionnaires.add(questionnaire);
          print('✅ Questionário $i carregado com ${questionnaire.questions.length} questões');

          // Debug adicional: verificar opções após parsing
          if (questionnaire.questions.isNotEmpty) {
            final firstQ = questionnaire.questions[0];
            print('   - Após parsing: ${firstQ.options.length} opções na primeira questão');
          }

        } catch (e, stackTrace) {
          print('❌ Erro ao processar questionário $i: $e');
          print('📋 Stack trace: $stackTrace');
        }
      }

      print('✅ === ${questionnaires.length} QUESTIONÁRIOS CARREGADOS COM SUCESSO ===');
      return questionnaires;
    } catch (e, stackTrace) {
      print('❌ Erro ao carregar questionários do storage local: $e');
      print('📋 Stack trace: $stackTrace');
      return [];
    }
  }

  /// Grava a lista de coletas SEM perder o que esta versão não conseguiu ler.
  ///
  /// Toda gravação lê a lista, altera e regrava a lista inteira. Um registro
  /// que a leitura pula (formato inesperado de uma versão anterior) ficava
  /// de fora e era APAGADO na gravação seguinte. Agora ele é mantido como
  /// está; e se o texto inteiro não for JSON válido, uma cópia é guardada
  /// antes de sobrescrever. Nenhuma coleta pendente some numa atualização.
  static Future<bool> _persistForms(
      SharedPreferences prefs, List<FormResponse> forms) async {
    final atual = prefs.getString(_formsKey);
    final preservados = <dynamic>[];

    if (atual != null && atual.isNotEmpty) {
      dynamic lista;
      try {
        lista = jsonDecode(atual);
      } catch (_) {
        lista = null;
      }
      if (lista is List) {
        // Os legíveis já estão em [forms] (vieram de getFormResponses);
        // só o que esta versão não consegue ler precisa ser preservado.
        for (final item in lista) {
          try {
            FormResponse.fromJson(item as Map<String, dynamic>);
          } catch (_) {
            preservados.add(item);
          }
        }
      } else {
        final chave = '${_formsKey}_corrompido_'
            '${DateTime.now().millisecondsSinceEpoch}';
        await prefs.setString(chave, atual);
        print('⚠️ Coletas em formato inválido guardadas em $chave');
      }
    }

    if (preservados.isNotEmpty) {
      print('⚠️ ${preservados.length} coleta(s) que esta versão não lê '
          'foram mantidas como estavam');
    }
    final json = [...forms.map((f) => f.toJson()), ...preservados];
    return prefs.setString(_formsKey, jsonEncode(json));
  }

  // Form Responses - VERSÃO CORRIGIDA
  //
  // Pela mesma fila das outras gravações: sem ela, salvar uma coleta nova
  // enquanto a sincronização atualiza status regravava a lista lida ANTES
  // da coleta nova existir, e ela sumia.
  static Future<void> saveFormResponse(FormResponse form) =>
      _withFormsLock(() => _saveFormResponse(form));

  static Future<void> _saveFormResponse(FormResponse form) async {
    try {
      print('💾 === INICIANDO SALVAMENTO DE FORMULÁRIO ===');
      print('📋 QuestionÃ¡rio ID: ${form.questionnaireId}');
      print('📋 Aplicado por: ${form.appliedBy}');
      print('📋 Respostas: ${form.responses.length}');
      print('📋 Status de sincronização: ${form.syncStatus}');
      print('📋 ID do formulário: ${form.id}');
      
      // Verificar se SharedPreferences está funcionando
      final prefs = await SharedPreferences.getInstance();
      print('✅ SharedPreferences obtido com sucesso');
      
      // Gerar um ID único se não tiver
      final formWithId = form.id == null 
          ? form.copyWith(id: DateTime.now().millisecondsSinceEpoch)
          : form;
      
      print('📋 Formulário com ID: ${formWithId.id}');
      
      // Carregar formas existentes
      print('📖 Carregando formulários existentes...');
      // Leitura tolerante, registro a registro. Antes, UM registro ilegível
      // fazia esta função recomeçar com a lista vazia e gravar só a coleta
      // nova: todas as pendentes anteriores eram apagadas.
      final List<FormResponse> existingForms = await getFormResponses();
      print('✅ ${existingForms.length} formulários existentes carregados');
      
      // Verificar se já existe um formulário com o mesmo ID
      print('🔍 === VERIFICANDO DUPLICAÇÃO ===');
      print('🔍 Formulário sendo salvo - ID: ${formWithId.id} (tipo: ${formWithId.id.runtimeType})');
      print('🔍 Total de formulários existentes: ${existingForms.length}');

      // Listar todos os IDs existentes para comparação
      for (int i = 0; i < existingForms.length; i++) {
        print('🔍 Formulário existente[$i] - ID: ${existingForms[i].id} (tipo: ${existingForms[i].id.runtimeType})');
      }

      bool formExists = false;
      for (int i = 0; i < existingForms.length; i++) {
        print('🔍 Comparando: ${existingForms[i].id} == ${formWithId.id} ?');
        if (existingForms[i].id == formWithId.id) {
          print('🔄 ✅ MATCH ENCONTRADO! Atualizando formulário existente com ID: ${formWithId.id}');
          existingForms[i] = formWithId;
          formExists = true;
          break;
        } else {
          print('🔍 ❌ Não é igual (${existingForms[i].id} != ${formWithId.id})');
        }
      }

      // Se não existe, adicionar à lista
      if (!formExists) {
        print('➕ ⚠️ NENHUM MATCH ENCONTRADO - Adicionando novo formulário à lista');
        print('➕ ID do novo formulário: ${formWithId.id}');
        existingForms.add(formWithId);
      } else {
        print('🔄 ✅ FORMULÁRIO FOI SUBSTITUÍDO, NÃO ADICIONADO');
      }
      
      print('📋 Total de formulários para salvar: ${existingForms.length}');
      
      // Salvar no SharedPreferences
      print('💾 Salvando no SharedPreferences...');
      final saveResult = await _persistForms(prefs, existingForms);
      print('📋 Resultado do salvamento: $saveResult');
      
      if (saveResult) {
        print('✅ === FORMULÁRIO SALVO COM SUCESSO ===');
        print('📋 ID salvo: ${formWithId.id}');
        print('📋 Total de formulários no storage: ${existingForms.length}');
        
        // Verificação imediata para confirmar salvamento
        final verification = prefs.getString(_formsKey);
        if (verification != null) {
          final verificationList = jsonDecode(verification) as List<dynamic>;
          print('✅ Verificação: ${verificationList.length} formulários confirmados no storage');
        } else {
          print('❌ ERRO: Verificação falhou - nada encontrado no storage após salvamento');
        }
      } else {
        print('❌ ERRO: SharedPreferences.setString retornou false');
        throw Exception('Falha ao salvar no SharedPreferences');
      }
      
    } catch (e, stackTrace) {
      print('❌ === ERRO DURANTE SALVAMENTO ===');
      print('❌ Erro: $e');
      print('📋 Stack trace: $stackTrace');
      rethrow;
    }
  }

  static Future<List<FormResponse>> getFormResponses() async {
    try {
      print('📖 === CARREGANDO FORMULÁRIOS DO STORAGE ===');
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString(_formsKey);
      
      if (jsonString == null || jsonString.isEmpty) {
        print('⚠️ Nenhuma resposta encontrada no storage local');
        return [];
      }
      
      print('📋 JSON encontrado com ${jsonString.length} caracteres');
      
      try {
        final jsonList = jsonDecode(jsonString) as List<dynamic>;
        print('📋 Lista JSON decodificada com ${jsonList.length} itens');
        
        final forms = <FormResponse>[];
        for (int i = 0; i < jsonList.length; i++) {
          try {
            final form = FormResponse.fromJson(jsonList[i] as Map<String, dynamic>);
            forms.add(form);
            print('✅ Formulário $i carregado (ID: ${form.id}, Status: ${form.syncStatus})');
          } catch (e) {
            print('❌ Erro ao carregar formulário $i: $e');
            // Continua com os outros
          }
        }
        
        print('✅ === ${forms.length} FORMULÁRIOS CARREGADOS COM SUCESSO ===');
        return forms;
        
      } catch (e) {
        print('❌ Erro ao decodificar JSON: $e');
        print('📋 JSON problemático (primeiros 200 chars): ${jsonString.substring(0, jsonString.length > 200 ? 200 : jsonString.length)}');
        return [];
      }
      
    } catch (e, stackTrace) {
      print('❌ === ERRO DURANTE CARREGAMENTO ===');
      print('❌ Erro: $e');
      print('📋 Stack trace: $stackTrace');
      return [];
    }
  }

  /// Carrega SOMENTE os formulários com o status pedido.
  ///
  /// A tela principal só precisa dos pendentes. Carregar tudo e filtrar
  /// depois obrigava a instanciar cada coleta já enviada — com todas as
  /// respostas — a cada abertura, e a lista só cresce em campo.
  /// Aqui o filtro é feito sobre o JSON cru, antes do parsing.
  static Future<List<FormResponse>> getFormResponsesByStatus(
    String status,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString(_formsKey);
      if (jsonString == null || jsonString.isEmpty) return [];

      final jsonList = jsonDecode(jsonString) as List<dynamic>;
      final forms = <FormResponse>[];

      for (final item in jsonList) {
        if (item is! Map<String, dynamic>) continue;
        // Filtra ANTES de construir o objeto.
        if ((item['sync_status'] as String? ?? 'pending') != status) continue;
        try {
          forms.add(FormResponse.fromJson(item));
        } catch (e) {
          print('❌ Erro ao carregar formulário ${item['id']}: $e');
        }
      }

      print('📋 ${forms.length} formulário(s) com status "$status"');
      return forms;
    } catch (e) {
      print('❌ Erro ao carregar formulários por status: $e');
      return [];
    }
  }

  /// Conta os formulários por status sem instanciar nenhum objeto.
  ///
  /// É o que a tela principal usa para o resumo — percorre o JSON e conta,
  /// sem montar as respostas de cada coleta.
  static Future<Map<String, int>> getFormCountsByStatus() async {
    final counts = <String, int>{'pending': 0, 'synced': 0, 'error': 0};
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString(_formsKey);
      if (jsonString == null || jsonString.isEmpty) return counts;

      final jsonList = jsonDecode(jsonString) as List<dynamic>;

      // As enviadas são contadas SEM repetição, pelo registro do painel
      // (server_id) ou pela chave de idempotência (client_id). O aparelho
      // pode ter mais de uma cópia local da mesma coleta, e o número
      // mostrado precisa bater com o que existe no painel.
      final enviadasUnicas = <String>{};

      for (final item in jsonList) {
        if (item is! Map) continue;
        final status = item['sync_status'] as String? ?? 'pending';

        if (status == 'synced') {
          final serverId = item['server_id'];
          final clientId = item['client_id'];
          final chave = serverId != null
              ? 'srv:$serverId'
              : (clientId != null ? 'cli:$clientId' : 'loc:${item['id']}');
          enviadasUnicas.add(chave);
          continue;
        }

        counts[status] = (counts[status] ?? 0) + 1;
      }

      counts['synced'] = enviadasUnicas.length;
      return counts;
    } catch (e) {
      print('❌ Erro ao contar formulários: $e');
      return counts;
    }
  }

  /// Serializa as escritas na chave de formulários.
  ///
  /// Todas elas fazem read-modify-write do array inteiro (SharedPreferences
  /// não tem update parcial). Sem esta fila, salvar uma coleta nova enquanto
  /// a sincronização atualiza status regravava a lista lida ANTES da nova
  /// coleta existir — e a resposta sumia do app sem nunca ter sido enviada.
  static Future<void> _formsLock = Future<void>.value();

  /// Testes de widget: cada teste roda numa zona de relógio simulado, e um
  /// Future agenda seus .then na zona onde nasceu. A fila criada no teste
  /// anterior nunca mais andaria. No app há uma zona só.
  @visibleForTesting
  static void resetWriteQueueForTesting() {
    _formsLock = Future<void>.value();
  }

  static Future<T> _withFormsLock<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _formsLock = _formsLock.then((_) async {
      try {
        completer.complete(await action());
      } catch (e, s) {
        completer.completeError(e, s);
      }
    });
    return completer.future;
  }

  static Future<void> updateFormSyncStatus(
    int formId,
    String status, {
    int? serverId,
    DateTime? syncedAt,
  }) =>
      _withFormsLock(
          () => _updateFormSyncStatus(formId, status, serverId, syncedAt));

  static Future<void> _updateFormSyncStatus(
    int formId,
    String status,
    int? serverId,
    DateTime? syncedAt,
  ) async {
    try {
      print('🔄 === ATUALIZANDO STATUS DE SINCRONIZAÇÃO ===');
      print('📋 Form ID: $formId');
      print('📋 Novo status: $status');

      List<FormResponse> forms = await getFormResponses();
      print('📋 ${forms.length} formulários carregados para atualização');

      bool formFound = false;
      for (int i = 0; i < forms.length; i++) {
        if (forms[i].id == formId) {
          print('✅ Formulário encontrado na posição $i');
          forms[i] = forms[i].copyWith(
            syncStatus: status,
            // Prova de gravação no painel: id do registro criado no
            // servidor e quando a confirmação chegou.
            serverId: serverId,
            syncedAt: syncedAt,
          );
          formFound = true;
          break;
        }
      }

      if (!formFound) {
        print('❌ Formulário com ID $formId não encontrado');
        throw Exception('Formulário não encontrado');
      }

      final prefs = await SharedPreferences.getInstance();
      final result = await _persistForms(prefs, forms);

      if (result) {
        print('✅ === STATUS ATUALIZADO COM SUCESSO ===');
      } else {
        print('❌ Falha ao salvar status atualizado');
        throw Exception('Falha ao salvar');
      }

    } catch (e, stackTrace) {
      print('❌ === ERRO DURANTE ATUALIZAÇÃO DE STATUS ===');
      print('❌ Erro: $e');
      print('📋 Stack trace: $stackTrace');
      rethrow;
    }
  }

  /// Atualizar um formulário existente (pela fila das gravações)
  static Future<void> updateFormResponse(FormResponse form) =>
      _withFormsLock(() => _updateFormResponse(form));

  static Future<void> _updateFormResponse(FormResponse form) async {
    try {
      print('🔄 === ATUALIZANDO FORMULÁRIO ===');
      print('📋 Form ID: ${form.id}');

      if (form.id == null) {
        throw Exception('Formulário sem ID não pode ser atualizado');
      }

      List<FormResponse> forms = await getFormResponses();
      print('📋 ${forms.length} formulários carregados');

      bool formFound = false;
      for (int i = 0; i < forms.length; i++) {
        if (forms[i].id == form.id) {
          print('✅ Formulário encontrado na posição $i - atualizando');
          forms[i] = form;
          formFound = true;
          break;
        }
      }

      if (!formFound) {
        print('❌ Formulário com ID ${form.id} não encontrado');
        throw Exception('Formulário não encontrado');
      }

      final prefs = await SharedPreferences.getInstance();
      final result = await _persistForms(prefs, forms);

      if (result) {
        print('✅ === FORMULÁRIO ATUALIZADO COM SUCESSO ===');
      } else {
        print('❌ Falha ao salvar formulário atualizado');
        throw Exception('Falha ao salvar');
      }

    } catch (e, stackTrace) {
      print('❌ === ERRO DURANTE ATUALIZAÇÃO DE FORMULÁRIO ===');
      print('❌ Erro: $e');
      print('📋 Stack trace: $stackTrace');
      rethrow;
    }
  }

  /// Troca o nome de uma mídia em todas as coletas que a citam.
  ///
  /// O servidor grava a foto com outro nome quando já existe um arquivo com
  /// o mesmo nome e conteúdo diferente. Sem esta troca a coleta continuaria
  /// citando o arquivo de outra pessoa (ou um que não existe).
  static Future<int> replaceMediaReference(String oldName, String newName) =>
      _withFormsLock(() async {
        final forms = await getFormResponses();
        var changed = 0;
        for (var i = 0; i < forms.length; i++) {
          final f = forms[i];
          if (f.photoPath == oldName ||
              f.photoPath2 == oldName ||
              f.audioPath == oldName) {
            // copyWith ignora null: só troca o campo que citava o nome antigo
            forms[i] = f.copyWith(
              photoPath: f.photoPath == oldName ? newName : null,
              photoPath2: f.photoPath2 == oldName ? newName : null,
              audioPath: f.audioPath == oldName ? newName : null,
            );
            changed++;
          }
        }
        if (changed > 0) {
          final prefs = await SharedPreferences.getInstance();
          await _persistForms(prefs, forms);
          print('📸 $oldName → $newName em $changed coleta(s)');
        }
        return changed;
      });

  /// Obter um formulário específico por ID
  static Future<FormResponse?> getFormResponseById(int formId) async {
    try {
      print('🔍 === BUSCANDO FORMULÁRIO POR ID ===');
      print('📋 Form ID: $formId');

      final forms = await getFormResponses();

      for (var form in forms) {
        if (form.id == formId) {
          print('✅ Formulário encontrado');
          return form;
        }
      }

      print('⚠️ Formulário não encontrado');
      return null;

    } catch (e, stackTrace) {
      print('❌ Erro ao buscar formulário: $e');
      print('📋 Stack trace: $stackTrace');
      return null;
    }
  }

  // Métodos utilitários
  static Future<void> clearQuestionnaires() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_questionnairesKey);
      print('🧹 Questionários limpos do storage local');
    } catch (e) {
      print('❌ Erro ao limpar questionários: $e');
    }
  }

  static Future<void> clearFormResponses() async {
    try {
      print('🧹 === LIMPANDO FORMULÁRIOS DO STORAGE ===');
      final prefs = await SharedPreferences.getInstance();
      final result = await prefs.remove(_formsKey);
      print('📋 Resultado da limpeza: $result');
      
      // Verificar se realmente foi limpo
      final verification = prefs.getString(_formsKey);
      if (verification == null) {
        print('✅ Formulários limpos com sucesso');
      } else {
        print('❌ Erro: ainda há dados após limpeza');
      }
    } catch (e) {
      print('❌ Erro ao limpar respostas: $e');
    }
  }

  static Future<void> clearAll() async {
    try {
      await clearQuestionnaires();
      await clearFormResponses();
      print('🧹 Todo o storage local limpo');
    } catch (e) {
      print('❌ Erro ao limpar storage: $e');
    }
  }

  // Debug melhorado
  static Future<void> debugPrintStorage() async {
    try {
      print('🔍 === DEBUG STORAGE DETALHADO ===');
      
      // Debug dos questionários
      final questionnaires = await getQuestionnaires();
      print('📋 Questionários: ${questionnaires.length}');
      for (var q in questionnaires) {
        print('   - ${q.title} (ID: ${q.id}, ${q.questions.length} questões)');
      }
      
      // Debug dos formulários  
      final forms = await getFormResponses();
      print('📝 Formulários: ${forms.length}');
      for (var f in forms) {
        print('   - ID: ${f.id}, Questionário: ${f.questionnaireId}, Status: ${f.syncStatus}, Respostas: ${f.responses.length}');
        print('     Iniciado: ${f.startedAt}');
        print('     Concluído: ${f.completedAt}');
        print('     Aplicador: ${f.appliedBy}');
        if (f.latitude != null && f.longitude != null) {
          print('     Localização: ${f.latitude}, ${f.longitude}');
        }
        if (f.photoPath != null) {
          print('     Foto: ${f.photoPath}');
        }
      }
      
      // Debug do SharedPreferences diretamente
      final prefs = await SharedPreferences.getInstance();
      final rawFormsData = prefs.getString(_formsKey);
      print('📋 Dados brutos no SharedPreferences:');
      print('   - Chave $_formsKey existe: ${rawFormsData != null}');
      if (rawFormsData != null) {
        print('   - Tamanho: ${rawFormsData.length} caracteres');
        print('   - Primeiros 100 chars: ${rawFormsData.substring(0, rawFormsData.length > 100 ? 100 : rawFormsData.length)}');
      }
      
      // Listar todas as chaves do SharedPreferences
      final allKeys = prefs.getKeys();
      print('📋 Todas as chaves no SharedPreferences: $allKeys');
      
      print('🔍 === FIM DEBUG DETALHADO ===');
    } catch (e) {
      print('❌ Erro no debug do storage: $e');
    }
  }

  // Método para testar salvamento
  static Future<bool> testSaveFormResponse() async {
    try {
      print('🧪 === TESTE DE SALVAMENTO ===');
      
      // Criar um formulário de teste
      final testForm = FormResponse(
        id: 999999,
        questionnaireId: 1,
        appliedBy: 1,
        consentGiven: true,
        syncStatus: 'test',
        startedAt: DateTime.now(),
        completedAt: DateTime.now(),
        responses: [],
      );
      
      print('📋 Salvando formulário de teste...');
      await saveFormResponse(testForm);
      
      print('📋 Verificando se foi salvo...');
      final forms = await getFormResponses();
      final testFormFound = forms.any((f) => f.id == 999999);
      
      if (testFormFound) {
        print('✅ Teste PASSOU: formulário salvo e recuperado com sucesso');
        
        // Limpar o teste
        final filteredForms = forms.where((f) => f.id != 999999).toList();
        final prefs = await SharedPreferences.getInstance();
        if (filteredForms.isEmpty) {
          await prefs.remove(_formsKey);
        } else {
          final jsonList = filteredForms.map((f) => f.toJson()).toList();
          final jsonString = jsonEncode(jsonList);
          await prefs.setString(_formsKey, jsonString);
        }
        print('🧹 Formulário de teste removido');
        
        return true;
      } else {
        print('❌ Teste FALHOU: formulário não foi encontrado após salvamento');
        return false;
      }
      
    } catch (e) {
      print('❌ Teste FALHOU com erro: $e');
      return false;
    }
  }
}
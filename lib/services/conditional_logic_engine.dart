import '../models/question.dart';
import '../models/conditional_logic.dart';

class ConditionalLogicEngine {
  /// Executa a lógica condicional para todas as questões e retorna os novos estados
  static Map<int, QuestionState> executeLogic(
    List<Question> questions,
    Map<int, dynamic> responses,
  ) {
    print('🎯 === EXECUTANDO LÓGICA CONDICIONAL ===');
    print('📝 Questões: ${questions.length}');
    print('📋 Respostas disponíveis: ${responses.length}');

    // Debug das respostas recebidas
    print('📋 === RESPOSTAS RECEBIDAS ===');
    responses.forEach((questionId, value) {
      print('📋 Questão ID $questionId: "$value" (${value.runtimeType})');
    });

    final Map<int, QuestionState> newStates = {};

    // Processar cada questão por índice
    for (int index = 0; index < questions.length; index++) {
      final question = questions[index];

      print('🔧 === PROCESSANDO QUESTÃO $index ===');
      print('🔧 ID: ${question.id}');
      print('🔧 Texto: "${question.questionText}"');
      print('🔧 Tem lógica: ${question.hasConditionalLogic}');

      // Estado inicial (padrão)
      bool visible = true;
      bool required = question.isRequired;

      // Aplicar lógica condicional se existir
      if (question.hasConditionalLogic) {
        final logic = question.parsedConditionalLogic!;
        print('🔧 Aplicando lógica condicional...');

        // Avaliar regras de visibilidade
        if (logic.visibility != null) {
          print('👁️ === AVALIANDO VISIBILIDADE ===');
          visible = _evaluateRule(logic.visibility!, responses, questions);
          print('👁️ Resultado visibilidade: $visible');
        }

        // Avaliar regras de obrigatoriedade (apenas se visível)
        if (visible && logic.required != null) {
          print('⚠️ === AVALIANDO OBRIGATORIEDADE ===');
          required = _evaluateRule(logic.required!, responses, questions);
          print('⚠️ Resultado obrigatoriedade: $required');
        } else if (!visible) {
          required = false; // Questão invisível não pode ser obrigatória
          print('⚠️ Questão invisível, required=false');
        }
      } else {
        print('ℹ️ Sem lógica condicional, usando valores padrão');
      }

      newStates[index] = QuestionState(
        visible: visible,
        required: required,
        originalRequired: question.isRequired,
      );

      print(
        '✅ Estado final questão $index: visible=$visible, required=$required',
      );
      print('');
    }

    print('🎯 === LÓGICA CONDICIONAL CONCLUÍDA ===');
    print('📊 Estados processados: ${newStates.length}');
    return newStates;
  }

  /// Avalia uma regra condicional específica
  static bool _evaluateRule(
    ConditionalRule rule,
    Map<int, dynamic> responses,
    List<Question> questions,
  ) {
    print('🔍 === AVALIANDO REGRA ===');
    print('🔍 Operador: ${rule.operator}');
    print('🔍 Condições: ${rule.conditions.length}');

    if (rule.conditions.isEmpty) {
      print('⚠️ Regra sem condições, retornando true');
      return true;
    }

    final List<bool> results = [];

    for (int i = 0; i < rule.conditions.length; i++) {
      final condition = rule.conditions[i];
      print('🔍 --- Condição $i ---');
      print('🔍 Questão ID: ${condition.questionId}');
      print('🔍 Operador: ${condition.operator}');
      print('🔍 Valor esperado: "${condition.value}"');

      // Obter resposta da questão referenciada
      final response = responses[condition.questionId];
      print('📝 Resposta encontrada: "$response" (${response.runtimeType})');

      // Avaliar condição
      final conditionResult = _evaluateCondition(condition, response, questions);
      print('🔍 Resultado da condição $i: $conditionResult');

      results.add(conditionResult);
    }

    // Aplicar operador lógico
    bool finalResult;
    if (rule.operator.toUpperCase() == 'OR') {
      finalResult = results.any((result) => result);
      print('🔍 Operador OR: [${results.join(', ')}] = $finalResult');
    } else {
      // Default: AND
      finalResult = results.every((result) => result);
      print('🔍 Operador AND: [${results.join(', ')}] = $finalResult');
    }

    print('🔍 === FIM AVALIAÇÃO REGRA: $finalResult ===');
    return finalResult;
  }

  /// Avalia uma condição específica
  static bool _evaluateCondition(
    ConditionalCondition condition,
    dynamic response,
    List<Question>? questions,
  ) {
    print('🔍 Avaliando condição detalhada:');
    print('   - Resposta: "$response" (tipo: ${response.runtimeType})');
    print('   - Operador: ${condition.operator}');
    print(
      '   - Valor esperado: "${condition.value}" (tipo: ${condition.value.runtimeType})',
    );

    // Se não há resposta, alguns operadores podem ainda ser verdadeiros
    if (response == null) {
      final result =
          condition.operator == 'not_equals' ||
          condition.operator == 'not_contains' ||
          condition.operator == 'is_empty';
      print('🔍 Resposta NULL, resultado para ${condition.operator}: $result');
      return result;
    }

    // Tentar encontrar o valor correto nas opções da questão
    dynamic valueToCompare = condition.value;

    if (questions != null) {
      // Buscar a questão referenciada
      final referencedQuestion = questions.firstWhere(
        (q) => q.id == condition.questionId,
        orElse: () => questions.first, // fallback
      );

      if (referencedQuestion.id == condition.questionId && referencedQuestion.options.isNotEmpty) {
        print('🔍 Buscando valor correspondente nas opções da questão ${condition.questionId}');

        // Procurar uma opção cujo text corresponda ao valor esperado
        final normalizedExpectedValue = _normalizeText(condition.value);

        for (final option in referencedQuestion.options) {
          final normalizedText = _normalizeText(option.optionText);

          // Se o text da opção corresponde ao valor esperado, usar o value da opção
          if (normalizedText == normalizedExpectedValue) {
            valueToCompare = option.optionValue ?? option.optionText;
            print('🔍 ✅ Encontrado! text="${option.optionText}" → value="$valueToCompare"');
            break;
          }
        }
      }
    }

    print('🔍 Valor final para comparação: "$valueToCompare"');

    bool result = false;
    switch (condition.operator.toLowerCase()) {
      case 'equals':
        result = _compareEquals(response, valueToCompare);
        break;

      case 'not_equals':
        result = !_compareEquals(response, valueToCompare);
        break;

      case 'contains':
        result = _compareContains(response, valueToCompare);
        break;

      case 'not_contains':
        result = !_compareContains(response, condition.value);
        break;

      case 'greater_than':
        result = _compareGreaterThan(response, condition.value);
        break;

      case 'less_than':
        result = _compareLessThan(response, condition.value);
        break;

      case 'greater_than_or_equal':
        result = _compareGreaterThanOrEqual(response, condition.value);
        break;

      case 'less_than_or_equal':
        result = _compareLessThanOrEqual(response, condition.value);
        break;

      case 'is_empty':
        result = _isEmpty(response);
        break;

      case 'is_not_empty':
        result = !_isEmpty(response);
        break;

      default:
        print('⚠️ Operador não reconhecido: ${condition.operator}');
        result = false;
    }

    print('🔍 Resultado final da condição: $result');
    return result;
  }

  // Normalizar texto para comparação (remove espaços extras, converte para minúsculas)
  static String _normalizeText(dynamic text) {
    if (text == null) return '';
    return text.toString().toLowerCase().trim().replaceAll(RegExp(r'\s+'), ' ');
  }

  // Métodos de comparação melhorados
  static bool _compareEquals(dynamic response, dynamic value) {
    print('🔍 Comparando EQUALS:');
    print('   Response original: "$response" (${response?.runtimeType})');
    print('   Value original: "$value" (${value?.runtimeType})');

    if (response is List) {
      // Para checkbox, verificar se lista contém o valor
      final normalizedValue = _normalizeText(value);
      print('   Value normalizado: "$normalizedValue"');

      final result = response.any((item) {
        final normalizedItem = _normalizeText(item);
        print('   Comparando item lista: "$normalizedItem" == "$normalizedValue"');
        return normalizedItem == normalizedValue;
      });

      print('🔍 Lista contém "${value}": $result (lista: $response)');
      return result;
    }

    // Comparação padrão (case-insensitive, trim e normalização de espaços)
    final responseStr = _normalizeText(response);
    final valueStr = _normalizeText(value);

    print('   Response normalizado: "$responseStr" (${responseStr.length} chars)');
    print('   Value normalizado: "$valueStr" (${valueStr.length} chars)');

    final result = responseStr == valueStr;
    print('🔍 "$responseStr" equals "$valueStr": $result');

    return result;
  }

  static bool _compareContains(dynamic response, dynamic value) {
    print('🔍 Comparando CONTAINS:');
    print('   Response: "$response"');
    print('   Value: "$value"');

    if (response is List) {
      final normalizedValue = _normalizeText(value);

      final result = response.any((item) {
        final normalizedItem = _normalizeText(item);
        final contains = normalizedItem.contains(normalizedValue);
        print('   Item lista "$normalizedItem" contém "$normalizedValue": $contains');
        return contains;
      });

      print('🔍 Lista contém substring "${value}": $result');
      return result;
    }

    final normalizedResponse = _normalizeText(response);
    final normalizedValue = _normalizeText(value);

    print('   Response normalizado: "$normalizedResponse"');
    print('   Value normalizado: "$normalizedValue"');

    final result = normalizedResponse.contains(normalizedValue);
    print('🔍 "${normalizedResponse}" contém "${normalizedValue}": $result');

    return result;
  }

  static bool _compareGreaterThan(dynamic response, dynamic value) {
    final responseNum = _parseNumber(response);
    final valueNum = _parseNumber(value);

    if (responseNum == null || valueNum == null) {
      print(
        '🔍 Não foi possível converter para números: response=$response, value=$value',
      );
      return false;
    }

    final result = responseNum > valueNum;
    print('🔍 $responseNum > $valueNum: $result');
    return result;
  }

  static bool _compareLessThan(dynamic response, dynamic value) {
    final responseNum = _parseNumber(response);
    final valueNum = _parseNumber(value);

    if (responseNum == null || valueNum == null) {
      print(
        '🔍 Não foi possível converter para números: response=$response, value=$value',
      );
      return false;
    }

    final result = responseNum < valueNum;
    print('🔍 $responseNum < $valueNum: $result');
    return result;
  }

  static bool _compareGreaterThanOrEqual(dynamic response, dynamic value) {
    final responseNum = _parseNumber(response);
    final valueNum = _parseNumber(value);

    if (responseNum == null || valueNum == null) {
      print(
        '🔍 Não foi possível converter para números: response=$response, value=$value',
      );
      return false;
    }

    final result = responseNum >= valueNum;
    print('🔍 $responseNum >= $valueNum: $result');
    return result;
  }

  static bool _compareLessThanOrEqual(dynamic response, dynamic value) {
    final responseNum = _parseNumber(response);
    final valueNum = _parseNumber(value);

    if (responseNum == null || valueNum == null) {
      print(
        '🔍 Não foi possível converter para números: response=$response, value=$value',
      );
      return false;
    }

    final result = responseNum <= valueNum;
    print('🔍 $responseNum <= $valueNum: $result');
    return result;
  }

  static bool _isEmpty(dynamic response) {
    if (response == null) return true;
    if (response is String) return response.trim().isEmpty;
    if (response is List) return response.isEmpty;
    return false;
  }

  static double? _parseNumber(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  /// Valida todas as respostas considerando lógica condicional
  static ValidationResult validateResponses(
    List<Question> questions,
    Map<int, dynamic> responses,
  ) {
    print('✅ === VALIDANDO RESPOSTAS COM LÓGICA CONDICIONAL ===');

    final List<String> errors = [];
    final List<String> warnings = [];

    // Executar lógica condicional para obter estados atuais
    final states = executeLogic(questions, responses);

    // Validar cada questão visível e obrigatória
    for (int index = 0; index < questions.length; index++) {
      final question = questions[index];
      final state = states[index]!;

      // Pular questões não visíveis
      if (!state.visible) {
        print('ℹ️ Pulando validação da questão ${question.id} (não visível)');
        continue;
      }

      // Verificar se questão obrigatória foi respondida
      if (state.required) {
        final response = responses[question.id];

        if (_isResponseEmpty(response, question.questionType)) {
          errors.add(
            'A questão "${question.questionText}" é obrigatória e deve ser respondida',
          );
          print('❌ Questão obrigatória ${question.id} não respondida');
        } else {
          print('✅ Questão obrigatória ${question.id} respondida');
        }
      }
    }

    print(
      '✅ Validação concluída: ${errors.length} erros, ${warnings.length} avisos',
    );

    return ValidationResult(
      isValid: errors.isEmpty,
      errors: errors,
      warnings: warnings,
    );
  }

  /// Verifica se uma resposta está vazia baseada no tipo da questão
  static bool _isResponseEmpty(dynamic response, String questionType) {
    print('🔍 Verificando se resposta está vazia:');
    print('   - Resposta: "$response" (tipo: ${response.runtimeType})');
    print('   - Tipo questão: $questionType');
    
    if (response == null) {
      print('   - Resultado: VAZIO (null)');
      return true;
    }

    switch (questionType.toLowerCase()) {
      case 'text':
      case 'textarea':
      case 'email':
      case 'phone':
        final isEmpty = response is! String || response.trim().isEmpty;
        print('   - Resultado: ${isEmpty ? "VAZIO" : "PREENCHIDO"}');
        return isEmpty;

      case 'number':
        final isEmpty = response is! num &&
            (response is! String || double.tryParse(response) == null);
        print('   - Resultado: ${isEmpty ? "VAZIO" : "PREENCHIDO"}');
        return isEmpty;

      case 'date':
      case 'datetime':
        final isEmpty = response is! DateTime &&
            (response is! String || DateTime.tryParse(response) == null);
        print('   - Resultado: ${isEmpty ? "VAZIO" : "PREENCHIDO"}');
        return isEmpty;

      case 'radio':
      case 'select':
        final isEmpty = response is! String || response.trim().isEmpty;
        print('   - Resultado: ${isEmpty ? "VAZIO" : "PREENCHIDO"}');
        return isEmpty;

      case 'checkbox':
        // Checkbox pode vir como List ou String
        bool isEmpty;
        if (response is List) {
          isEmpty = response.isEmpty;
          print('   - Checkbox como List: ${response.length} itens, vazio=$isEmpty');
        } else if (response is String) {
          isEmpty = response.trim().isEmpty;
          print('   - Checkbox como String: "$response", vazio=$isEmpty');
        } else {
          isEmpty = true; // Qualquer outro tipo é considerado vazio
          print('   - Checkbox tipo inesperado: ${response.runtimeType}, considerando vazio');
        }
        print('   - Resultado final: ${isEmpty ? "VAZIO" : "PREENCHIDO"}');
        return isEmpty;

      default:
        // Para tipos não reconhecidos, verificar se é string não-vazia
        bool isEmpty;
        if (response is String) {
          isEmpty = response.trim().isEmpty;
          print('   - Tipo desconhecido como String, vazio=$isEmpty');
        } else if (response is List) {
          isEmpty = response.isEmpty;
          print('   - Tipo desconhecido como List, vazio=$isEmpty');
        } else {
          isEmpty = false; // Se tem valor e não é string/list vazia, considerar válido
          print('   - Tipo desconhecido (${response.runtimeType}), considerando válido');
        }
        print('   - Resultado final: ${isEmpty ? "VAZIO" : "PREENCHIDO"}');
        return isEmpty;
    }
  }
}

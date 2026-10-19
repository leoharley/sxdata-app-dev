class QuestionResponse {
  final int? id;
  final int questionId;
  final String? responseText;
  final double? responseNumber;
  final DateTime? responseDate;
  final DateTime? responseDatetime;
  final List<String>? selectedOptions;

  QuestionResponse({
    this.id,
    required this.questionId,
    this.responseText,
    this.responseNumber,
    this.responseDate,
    this.responseDatetime,
    this.selectedOptions,
  });

  factory QuestionResponse.fromJson(Map<String, dynamic> json) {
    try {
      // Tolerante a números gravados como texto, inteiro ou double: uma
      // resposta ilegível tornaria a coleta inteira ilegível (e ela não
      // subiria). Ver FormResponse.fromJson.
      int? asInt(dynamic v) => v == null
          ? null
          : (v is num ? v.toInt() : int.tryParse(v.toString()));
      final questionId = asInt(json['question_id']);
      if (questionId == null) {
        throw FormatException('resposta sem question_id: $json');
      }
      final numero = json['response_number'];
      final opcoes = json['selected_options'];
      return QuestionResponse(
        id: asInt(json['id']),
        questionId: questionId,
        responseText: json['response_text']?.toString(),
        responseNumber: numero == null
            ? null
            : (numero is num
                ? numero.toDouble()
                : double.tryParse(numero.toString())),
        responseDate: json['response_date'] != null
            ? DateTime.tryParse(json['response_date'].toString())
            : null,
        responseDatetime: json['response_datetime'] != null
            ? DateTime.tryParse(json['response_datetime'].toString())
            : null,
        selectedOptions: opcoes is List
            ? opcoes.map((option) => option.toString()).toList()
            : (opcoes == null ? null : [opcoes.toString()]),
      );
    } catch (e, stackTrace) {
      print('❌ Erro ao parsear QuestionResponse: $e');
      print('📋 JSON: $json');
      print('📋 Stack trace: $stackTrace');
      rethrow;
    }
  }

  Map<String, dynamic> toJson() {
    try {
      return {
        if (id != null) 'id': id,
        'question_id': questionId,
        'response_text': responseText,
        'response_number': responseNumber,
        'response_date': responseDate?.toIso8601String(),
        'response_datetime': responseDatetime?.toIso8601String(),
        'selected_options': selectedOptions,
      };
    } catch (e, stackTrace) {
      print('❌ Erro ao serializar QuestionResponse: $e');
      print('📋 Stack trace: $stackTrace');
      rethrow;
    }
  }

  // Método para obter o valor da resposta como string para display
  String get displayValue {
    if (responseText != null && responseText!.isNotEmpty) {
      return responseText!;
    }
    if (responseNumber != null) {
      return responseNumber!.toString();
    }
    if (responseDate != null) {
      return '${responseDate!.day.toString().padLeft(2, '0')}/${responseDate!.month.toString().padLeft(2, '0')}/${responseDate!.year}';
    }
    if (responseDatetime != null) {
      return '${responseDatetime!.day.toString().padLeft(2, '0')}/${responseDatetime!.month.toString().padLeft(2, '0')}/${responseDatetime!.year} ${responseDatetime!.hour.toString().padLeft(2, '0')}:${responseDatetime!.minute.toString().padLeft(2, '0')}';
    }
    if (selectedOptions != null && selectedOptions!.isNotEmpty) {
      return selectedOptions!.join(', ');
    }
    return 'Sem resposta';
  }

  // Verifica se a resposta está vazia
  bool get isEmpty {
    return responseText == null && 
           responseNumber == null && 
           responseDate == null && 
           responseDatetime == null && 
           (selectedOptions == null || selectedOptions!.isEmpty);
  }

  @override
  String toString() {
    return 'QuestionResponse{questionId: $questionId, value: $displayValue}';
  }
}

extension QuestionResponseExtension on QuestionResponse {
  
  /// Retorna o valor da resposta em formato adequado para lógica condicional
  dynamic getValue() {
    if (selectedOptions != null && selectedOptions!.isNotEmpty) {
      // Para radio: retorna o primeiro item
      // Para checkbox: retorna a lista completa
      return selectedOptions!.length == 1 ? selectedOptions!.first : selectedOptions;
    }
    
    if (responseText != null && responseText!.isNotEmpty) {
      return responseText;
    }
    
    if (responseNumber != null) {
      return responseNumber;
    }
    
    if (responseDate != null) {
      return responseDate;
    }
    
    if (responseDatetime != null) {
      return responseDatetime;
    }
    
    return null;
  }
  
  /// Verifica se a resposta está vazia
  bool get isEmpty {
    if (selectedOptions != null && selectedOptions!.isNotEmpty) {
      return false;
    }
    
    if (responseText != null && responseText!.trim().isNotEmpty) {
      return false;
    }
    
    if (responseNumber != null) {
      return false;
    }
    
    if (responseDate != null) {
      return false;
    }
    
    if (responseDatetime != null) {
      return false;
    }
    
    return true;
  }
  
  /// Retorna uma representação em string do valor para debug
  String get displayValue {
    final value = getValue();
    if (value == null) return '(vazio)';
    if (value is List) return value.join(', ');
    return value.toString();
  }
}
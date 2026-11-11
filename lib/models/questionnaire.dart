import 'question.dart';

class Questionnaire {
  final int id;
  final String title;
  final String description;
  final int createdBy;
  final String status;
  final bool requiresConsent;
  final bool requiresLocation;
  final bool requiresPhoto;
  final int? estimatedTime;
  final String version;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<Question> questions;

  /// Projeto do questionário no painel (null = sem projeto). Os pontos de
  /// campo são por projeto: a coleta só vincula a ponto do mesmo projeto.
  final int? projectId;
  final String? projectName;

  Questionnaire({
    required this.id,
    required this.title,
    required this.description,
    required this.createdBy,
    required this.status,
    required this.requiresConsent,
    required this.requiresLocation,
    required this.requiresPhoto,
    this.estimatedTime,
    required this.version,
    required this.createdAt,
    required this.updatedAt,
    required this.questions,
    this.projectId,
    this.projectName,
  });

  // Método auxiliar para converter string em int
  static int _parseInt(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) {
      if (value.isEmpty || value == 'null') return 0;
      return int.tryParse(value) ?? 0;
    }
    return 0;
  }

  // Método auxiliar para converter string em bool (lidando com 't'/'f')
  static bool _parseBool(dynamic value) {
    if (value == null) return false;
    if (value is bool) return value;
    if (value is String) {
      return value.toLowerCase() == 't' || 
             value.toLowerCase() == 'true' || 
             value == '1';
    }
    if (value is int) return value == 1;
    return false;
  }

  // Método auxiliar para converter string em DateTime
  static DateTime _parseDateTime(dynamic value) {
    if (value == null) return DateTime.now();
    if (value is DateTime) return value;
    if (value is String) {
      try {
        return DateTime.parse(value);
      } catch (e) {
        print('Erro ao converter data: $value - $e');
        return DateTime.now();
      }
    }
    return DateTime.now();
  }

  factory Questionnaire.fromJson(Map<String, dynamic> json) {
    print('🔄 Parsing questionnaire: ${json['title']}');
    print('📋 Raw JSON: $json');
    
    try {
      // Parse das questões
      List<Question> questionsList = [];
      if (json['questions'] != null) {
        final questionsData = json['questions'] as List;
        print('📝 Found ${questionsData.length} questions');
        
        for (int i = 0; i < questionsData.length; i++) {
          try {
            final questionData = questionsData[i] as Map<String, dynamic>;
            print('📝 Parsing question $i: ${questionData['question_text']}');
            final question = Question.fromJson(questionData);
            questionsList.add(question);
            print('✅ Question $i parsed successfully');
          } catch (e, stackTrace) {
            print('❌ Error parsing question $i: $e');
            print('📋 Stack trace: $stackTrace');
            print('📋 Question data: ${questionsData[i]}');
          }
        }
      }

      final questionnaire = Questionnaire(
        id: _parseInt(json['id']),
        title: json['title']?.toString() ?? '',
        description: json['description']?.toString() ?? '',
        createdBy: _parseInt(json['created_by']),
        status: json['status']?.toString() ?? 'active',
        requiresConsent: _parseBool(json['requires_consent']),
        requiresLocation: _parseBool(json['requires_location']),
        requiresPhoto: _parseBool(json['requires_photo']),
        estimatedTime: json['estimated_time'] != null ? _parseInt(json['estimated_time']) : null,
        version: json['version']?.toString() ?? '1',
        createdAt: _parseDateTime(json['created_at']),
        updatedAt: _parseDateTime(json['updated_at']),
        questions: questionsList,
        projectId: _parseInt(json['project_id']) > 0 ? _parseInt(json['project_id']) : null,
        projectName: json['project_name']?.toString(),
      );

      print('✅ Questionnaire parsed successfully: ${questionnaire.title} with ${questionnaire.questions.length} questions');
      return questionnaire;
      
    } catch (e, stackTrace) {
      print('❌ Error in Questionnaire.fromJson: $e');
      print('📋 Stack trace: $stackTrace');
      print('📋 JSON data: $json');
      rethrow;
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'created_by': createdBy,
      'status': status,
      'requires_consent': requiresConsent,
      'requires_location': requiresLocation,
      'requires_photo': requiresPhoto,
      'estimated_time': estimatedTime,
      'version': version,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'questions': questions.map((q) => q.toJson()).toList(),
      'project_id': projectId,
      'project_name': projectName,
    };
  }

  @override
  String toString() {
    return 'Questionnaire{id: $id, title: $title, questionsCount: ${questions.length}}';
  }
}
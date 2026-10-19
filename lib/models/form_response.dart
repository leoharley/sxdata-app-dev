import 'question_response.dart';

/// Valor gravado em [FormResponse.locationName] (`location_name` no payload)
/// quando o questionário exigia localização mas o GPS não pegou sinal e o
/// aplicador concluiu mesmo assim.
///
/// Sem essa marca, o registro chegaria ao painel apenas com as coordenadas em
/// branco — indistinguível de um questionário que nunca pediu localização.
/// Se o painel for exibir/filtrar por isso, o texto precisa bater exatamente.
const String kSemLocalizacao = 'Sem localização';

class FormResponse {
  final int? id;
  final int questionnaireId;
  final String? respondentName;
  final String? respondentEmail;
  final int appliedBy;
  final double? latitude;
  final double? longitude;
  final String? locationName;
  final String? photoPath;
  final String? photoPath2;
  final String? audioPath;
  final bool consentGiven;

  /// UUID gerado NO APARELHO quando a coleta é criada (não no envio) e
  /// persistido junto com ela.
  ///
  /// É a chave de idempotência do backend (coluna client_id, UNIQUE). O
  /// mesmo formulário reenvia SEMPRE o mesmo valor, inclusive depois de
  /// fechar o app ou reiniciar o aparelho — assim um reenvio após resposta
  /// perdida devolve o registro já gravado em vez de duplicar.
  final String? clientId;

  /// 'pending'  = ainda não confirmado pelo painel (inclui tentativas que
  ///              falharam); é o que a fila reenvia.
  /// 'synced'   = o servidor CONFIRMOU a gravação. Só então some da fila.
  final String syncStatus;

  /// ID do registro criado no painel, devolvido pelo POST de envio.
  /// É a prova de que a resposta chegou lá — null enquanto não confirmada.
  final int? serverId;

  /// Quando a confirmação do servidor chegou.
  final DateTime? syncedAt;

  final DateTime startedAt;
  final DateTime? completedAt;
  final DateTime? editedAt;
  final List<QuestionResponse> responses;

  /// True quando o painel confirmou a gravação desta coleta.
  bool get isConfirmedByServer => syncStatus == 'synced';

  /// Extrai do retorno do POST o id do registro criado no painel — a prova
  /// de que a resposta chegou lá. Aceita os nomes de chave mais comuns e
  /// procura também dentro de 'data', porque o formato varia entre
  /// endpoints. Retorna null quando não há identificador: nesse caso a
  /// coleta NÃO pode ser dada como enviada.
  static int? extractServerId(dynamic source) {
    if (source is! Map) return null;

    for (final key in const [
      'id',
      'form_id',
      'form_response_id',
      'response_id',
      'inserted_id',
    ]) {
      final value = source[key];
      if (value is int && value > 0) return value;
      if (value is num && value > 0) return value.toInt();
      if (value is String) {
        final parsed = int.tryParse(value);
        if (parsed != null && parsed > 0) return parsed;
      }
    }

    // O id costuma vir aninhado em 'data'.
    return extractServerId(source['data']);
  }

  FormResponse({
    this.id,
    required this.questionnaireId,
    this.respondentName,
    this.respondentEmail,
    required this.appliedBy,
    this.latitude,
    this.longitude,
    this.locationName,
    this.photoPath,
    this.photoPath2,
    this.audioPath,
    required this.consentGiven,
    this.clientId,
    this.syncStatus = 'pending',
    this.serverId,
    this.syncedAt,
    required this.startedAt,
    this.completedAt,
    this.editedAt,
    this.responses = const [],
  });

  // Método copyWith para facilitar atualizações
  FormResponse copyWith({
    int? id,
    int? questionnaireId,
    String? respondentName,
    String? respondentEmail,
    int? appliedBy,
    double? latitude,
    double? longitude,
    String? locationName,
    String? photoPath,
    String? photoPath2,
    String? audioPath,
    bool? consentGiven,
    String? clientId,
    String? syncStatus,
    int? serverId,
    DateTime? syncedAt,
    DateTime? startedAt,
    DateTime? completedAt,
    DateTime? editedAt,
    List<QuestionResponse>? responses,
    // null em photoPath significa "manter"; para TIRAR a foto, use estes
    bool clearPhotoPath = false,
    bool clearPhotoPath2 = false,
  }) {
    return FormResponse(
      id: id ?? this.id,
      questionnaireId: questionnaireId ?? this.questionnaireId,
      respondentName: respondentName ?? this.respondentName,
      respondentEmail: respondentEmail ?? this.respondentEmail,
      appliedBy: appliedBy ?? this.appliedBy,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      locationName: locationName ?? this.locationName,
      photoPath: clearPhotoPath ? null : (photoPath ?? this.photoPath),
      photoPath2: clearPhotoPath2 ? null : (photoPath2 ?? this.photoPath2),
      audioPath: audioPath ?? this.audioPath,
      consentGiven: consentGiven ?? this.consentGiven,
      clientId: clientId ?? this.clientId,
      syncStatus: syncStatus ?? this.syncStatus,
      serverId: serverId ?? this.serverId,
      syncedAt: syncedAt ?? this.syncedAt,
      startedAt: startedAt ?? this.startedAt,
      completedAt: completedAt ?? this.completedAt,
      editedAt: editedAt ?? this.editedAt,
      responses: responses ?? this.responses,
    );
  }

  factory FormResponse.fromJson(Map<String, dynamic> json) {
    try {
      return FormResponse(
        id: json['id'] as int?,
        questionnaireId: json['questionnaire_id'] as int,
        respondentName: json['respondent_name'] as String?,
        respondentEmail: json['respondent_email'] as String?,
        appliedBy: json['applied_by'] as int,
        latitude: json['latitude'] as double?,
        longitude: json['longitude'] as double?,
        locationName: json['location_name'] as String?,
        photoPath: json['photo_path'] as String?,
        photoPath2: json['photo_path_2'] as String?,
        audioPath: json['audio_path'] as String?,
        consentGiven: json['consent_given'] as bool? ?? false,
        clientId: json['client_id'] as String?,
        syncStatus: json['sync_status'] as String? ?? 'pending',
        serverId: json['server_id'] as int?,
        syncedAt: json['synced_at'] != null
            ? DateTime.tryParse(json['synced_at'] as String)
            : null,
        startedAt: DateTime.parse(json['started_at'] as String),
        completedAt: json['completed_at'] != null
            ? DateTime.parse(json['completed_at'] as String)
            : null,
        editedAt: json['edited_at'] != null
            ? DateTime.parse(json['edited_at'] as String)
            : null,
        responses: (json['responses'] as List<dynamic>?)
            ?.map((r) => QuestionResponse.fromJson(r as Map<String, dynamic>))
            .toList() ?? [],
      );
    } catch (e, stackTrace) {
      print('❌ Erro ao parsear FormResponse: $e');
      print('📋 JSON: $json');
      print('📋 Stack trace: $stackTrace');
      rethrow;
    }
  }

  Map<String, dynamic> toJson() {
    try {
      return {
        if (id != null) 'id': id,
        'questionnaire_id': questionnaireId,
        'respondent_name': respondentName,
        'respondent_email': respondentEmail,
        'applied_by': appliedBy,
        'latitude': latitude,
        'longitude': longitude,
        'location_name': locationName,
        'photo_path': photoPath,
        'photo_path_2': photoPath2,
        'audio_path': audioPath,
        'consent_given': consentGiven,
        // Chave de idempotência: o backend deduplica reenvios por ela
        // (UNIQUE em client_id). Precisa ser o MESMO valor em toda
        // tentativa, por isso é persistido com a coleta.
        if (clientId != null) 'client_id': clientId,
        'sync_status': syncStatus,
        // Controle local de confirmação; o servidor ignora estes campos.
        if (serverId != null) 'server_id': serverId,
        if (syncedAt != null) 'synced_at': syncedAt!.toIso8601String(),
        'started_at': startedAt.toIso8601String(),
        'completed_at': completedAt?.toIso8601String(),
        'edited_at': editedAt?.toIso8601String(),
        'responses': responses.map((r) => r.toJson()).toList(),
      };
    } catch (e, stackTrace) {
      print('❌ Erro ao serializar FormResponse: $e');
      print('📋 Stack trace: $stackTrace');
      rethrow;
    }
  }

  @override
  String toString() {
    return 'FormResponse{id: $id, questionnaireId: $questionnaireId, appliedBy: $appliedBy, responses: ${responses.length}, syncStatus: $syncStatus}';
  }
}
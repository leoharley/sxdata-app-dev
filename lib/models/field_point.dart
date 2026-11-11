/// Ponto de campo do mapa integrado: comunidade, localidade ou equipamento
/// registrado pelo aplicador, ao qual as coletas podem ser vinculadas.
///
/// Dart puro (sem Flutter): testável isoladamente.
///
/// Contrato com o painel: docs/API_PONTOS.md do sxdata-painel-dev.
library;

const List<String> kTiposPonto = ['comunidade', 'localidade', 'equipamento', 'outro'];

const Map<String, String> kRotulosTipoPonto = {
  'comunidade': 'Comunidade',
  'localidade': 'Localidade',
  'equipamento': 'Equipamento',
  'outro': 'Outro',
};

class FieldPoint {
  /// UUID gerado NO APARELHO quando o ponto é registrado. É a chave de
  /// idempotência do servidor (field_points.client_id, UNIQUE) e o que a
  /// coleta envia em `point_client_id`.
  final String clientId;

  /// id do painel. Só existe depois que o servidor confirmou a gravação.
  final int? serverId;

  final int projectId;
  final String? projectName;
  final int codigoIbge;
  final String? municipioNome;
  final String? uf;
  final String nome;
  final String tipo;
  final double? latitude;
  final double? longitude;

  /// 'gps' (botão "usar minha localização") ou 'mapa' (toque no mapa).
  final String? origemCoord;

  /// Resposta do servidor: a coordenada cai no município? null = não validado.
  final bool? dentroMunicipio;

  /// 'pending' = ainda não confirmado pelo painel (é o que a fila envia);
  /// 'synced'  = confirmado (serverId preenchido);
  /// 'error'   = recusado de forma permanente (fica no aparelho, não reenvia).
  final String syncStatus;

  /// Último aviso ou erro do servidor, para mostrar ao aplicador.
  final String? aviso;

  final DateTime createdAt;
  final DateTime? updatedAt;

  /// Coletas vinculadas no painel (só nos pontos vindos do servidor).
  final int coletas;

  const FieldPoint({
    required this.clientId,
    this.serverId,
    required this.projectId,
    this.projectName,
    required this.codigoIbge,
    this.municipioNome,
    this.uf,
    required this.nome,
    this.tipo = 'comunidade',
    this.latitude,
    this.longitude,
    this.origemCoord,
    this.dentroMunicipio,
    this.syncStatus = 'pending',
    this.aviso,
    required this.createdAt,
    this.updatedAt,
    this.coletas = 0,
  });

  bool get isSynced => syncStatus == 'synced';
  bool get isPending => syncStatus == 'pending';
  bool get temCoordenada => latitude != null && longitude != null;
  String get municipioRotulo =>
      [municipioNome, uf].where((s) => s != null && s.isNotEmpty).join(' - ');

  FieldPoint copyWith({
    int? serverId,
    int? projectId,
    String? projectName,
    int? codigoIbge,
    String? municipioNome,
    String? uf,
    String? nome,
    String? tipo,
    double? latitude,
    double? longitude,
    String? origemCoord,
    bool? dentroMunicipio,
    String? syncStatus,
    String? aviso,
    DateTime? updatedAt,
    int? coletas,
    bool limparCoordenada = false,
    bool limparAviso = false,
  }) {
    return FieldPoint(
      clientId: clientId,
      serverId: serverId ?? this.serverId,
      projectId: projectId ?? this.projectId,
      projectName: projectName ?? this.projectName,
      codigoIbge: codigoIbge ?? this.codigoIbge,
      municipioNome: municipioNome ?? this.municipioNome,
      uf: uf ?? this.uf,
      nome: nome ?? this.nome,
      tipo: tipo ?? this.tipo,
      latitude: limparCoordenada ? null : (latitude ?? this.latitude),
      longitude: limparCoordenada ? null : (longitude ?? this.longitude),
      origemCoord: limparCoordenada ? null : (origemCoord ?? this.origemCoord),
      dentroMunicipio: dentroMunicipio ?? this.dentroMunicipio,
      syncStatus: syncStatus ?? this.syncStatus,
      aviso: limparAviso ? null : (aviso ?? this.aviso),
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      coletas: coletas ?? this.coletas,
    );
  }

  /// Corpo de POST api/points/submit.
  Map<String, dynamic> toApiJson() => {
        'client_id': clientId,
        'project_id': projectId,
        'codigo_ibge': codigoIbge.toString(),
        'nome': nome,
        'tipo': tipo,
        'latitude': latitude,
        'longitude': longitude,
        'origem_coord': temCoordenada ? origemCoord : null,
      };

  /// Gravação local (inclui o controle da fila).
  Map<String, dynamic> toJson() => {
        ...toApiJson(),
        if (serverId != null) 'server_id': serverId,
        'project_name': projectName,
        'municipio_nome': municipioNome,
        'uf': uf,
        'dentro_municipio': dentroMunicipio,
        'sync_status': syncStatus,
        'aviso': aviso,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt?.toIso8601String(),
        'coletas': coletas,
      };

  /// Leitura tolerante: aceita a gravação local e também um item de
  /// GET api/points (que traz `id` e `criado_em` em vez de `server_id` e
  /// `created_at`). Lança FormatException se faltar o essencial.
  factory FieldPoint.fromJson(Map<String, dynamic> json, {bool doServidor = false}) {
    final clientId = json['client_id']?.toString();
    final projectId = _asInt(json['project_id']);
    final codigo = _asInt(json['codigo_ibge']);
    final nome = json['nome']?.toString();
    if (clientId == null || clientId.isEmpty || projectId == null || codigo == null || nome == null) {
      throw FormatException('ponto sem client_id, projeto, município ou nome: $json');
    }
    final dentro = json['dentro_municipio'];
    return FieldPoint(
      clientId: clientId,
      serverId: _asInt(json['server_id']) ?? (doServidor ? _asInt(json['id']) : null),
      projectId: projectId,
      projectName: (json['project_name'] ?? json['projeto_nome'])?.toString(),
      codigoIbge: codigo,
      municipioNome: json['municipio_nome']?.toString(),
      uf: json['uf']?.toString(),
      nome: nome,
      tipo: kTiposPonto.contains(json['tipo']) ? json['tipo'] as String : 'outro',
      latitude: _asDouble(json['latitude']),
      longitude: _asDouble(json['longitude']),
      origemCoord: json['origem_coord']?.toString(),
      dentroMunicipio: dentro == null ? null : (dentro == true || dentro == 't' || dentro == 1 || dentro == 'true'),
      syncStatus: doServidor ? 'synced' : (json['sync_status']?.toString() ?? 'pending'),
      aviso: json['aviso']?.toString(),
      createdAt: _asDate(json['created_at']) ?? _asDate(json['criado_em']) ?? DateTime.now(),
      updatedAt: _asDate(json['updated_at']) ?? _asDate(json['atualizado_em']),
      coletas: _asInt(json['coletas']) ?? 0,
    );
  }

  static int? _asInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString());
  }

  static double? _asDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  static DateTime? _asDate(dynamic v) {
    if (v == null) return null;
    // "2026-11-11 01:36:31" do PostgreSQL também é aceito
    return DateTime.tryParse(v.toString().replaceFirst(' ', 'T'));
  }

  @override
  String toString() => 'FieldPoint{$clientId, $nome, $codigoIbge, $syncStatus}';
}

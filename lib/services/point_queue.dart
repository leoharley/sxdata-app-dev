import '../models/field_point.dart';

/// Regras puras da fila de pontos de campo (sem Flutter, sem rede, sem
/// armazenamento): o que enviar, em que ordem, como interpretar a resposta
/// do servidor e como juntar os pontos do aparelho com os do painel.
///
/// Ordem na sincronização: os pontos vão ANTES das coletas. Se um ponto não
/// subir, a coleta que o cita sobe assim mesmo: o painel guarda o
/// point_client_id e completa o vínculo quando o ponto chegar.
class PointQueue {
  PointQueue._();

  /// Pontos que a fila deve enviar, do mais antigo ao mais novo.
  static List<FieldPoint> paraEnviar(Iterable<FieldPoint> pontos) {
    final lista = pontos.where((p) => p.isPending).toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return lista;
  }

  /// id do ponto na resposta de POST api/points/submit, ou null. Sem id o
  /// ponto NÃO pode sair da fila: o servidor não provou que gravou.
  static int? extrairId(dynamic resposta) {
    if (resposta is! Map) return null;
    for (final chave in const ['id', 'point_id']) {
      final v = resposta[chave];
      if (v is int && v > 0) return v;
      if (v is num && v > 0) return v.toInt();
      if (v is String) {
        final n = int.tryParse(v);
        if (n != null && n > 0) return n;
      }
    }
    return extrairId(resposta['data']);
  }

  /// Ponto depois da resposta do servidor. Com id: 'synced'. Sem id ou com
  /// success=false: continua 'pending', com a mensagem em `aviso`.
  static FieldPoint aplicarResposta(FieldPoint ponto, Map<String, dynamic> resposta) {
    final id = resposta['success'] == true ? extrairId(resposta) : null;
    if (id == null) {
      return ponto.copyWith(
        syncStatus: 'pending',
        aviso: resposta['message']?.toString() ?? 'O servidor não confirmou o ponto.',
      );
    }
    final dentro = resposta['dentro_municipio'];
    final aviso = resposta['aviso']?.toString();
    return ponto.copyWith(
      serverId: id,
      syncStatus: 'synced',
      dentroMunicipio: dentro is bool ? dentro : null,
      aviso: aviso,
      limparAviso: aviso == null,
      updatedAt: DateTime.now(),
    );
  }

  /// Junta os pontos do aparelho com os de GET api/points, pelo client_id.
  ///
  /// - Ponto do aparelho ainda não confirmado (pending/error) vale o do
  ///   aparelho: é a versão mais nova, que ainda vai subir.
  /// - Confirmado: vale o do servidor (nome editado no painel, nº de coletas),
  ///   mantendo o aviso local.
  /// - Ponto só do servidor (registrado por outro aplicador): entra.
  /// - Ponto confirmado que sumiu do servidor (excluído no painel ou fora do
  ///   acesso) sai — EXCETO se for de um projeto que a consulta não cobriu.
  static List<FieldPoint> mesclar(
    List<FieldPoint> locais,
    List<FieldPoint> doServidor, {
    Set<int>? projetosConsultados,
    int? municipioConsultado,
  }) {
    final servidor = {for (final p in doServidor) p.clientId: p};
    final resultado = <FieldPoint>[];
    final vistos = <String>{};

    for (final local in locais) {
      vistos.add(local.clientId);
      final remoto = servidor[local.clientId];
      if (!local.isSynced) {
        resultado.add(local);
      } else if (remoto != null) {
        resultado.add(remoto.copyWith(aviso: local.aviso));
      } else {
        final coberto = (projetosConsultados == null || projetosConsultados.contains(local.projectId)) &&
            (municipioConsultado == null || municipioConsultado == local.codigoIbge);
        if (!coberto) resultado.add(local);
      }
    }
    for (final remoto in doServidor) {
      if (!vistos.contains(remoto.clientId)) resultado.add(remoto);
    }
    return resultado;
  }

  /// Pontos que podem receber a coleta de um questionário do projeto,
  /// opcionalmente só de um município, em ordem alfabética.
  static List<FieldPoint> doProjeto(Iterable<FieldPoint> pontos, int projectId, {int? codigoIbge}) {
    final lista = pontos
        .where((p) => p.projectId == projectId && p.syncStatus != 'error')
        .where((p) => codigoIbge == null || p.codigoIbge == codigoIbge)
        .toList()
      ..sort((a, b) => a.nome.toLowerCase().compareTo(b.nome.toLowerCase()));
    return lista;
  }
}

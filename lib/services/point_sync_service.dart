import '../models/field_point.dart';
import 'api_service.dart';
import 'point_queue.dart';
import 'point_storage_service.dart';

/// Envio dos pontos pendentes e atualização dos pontos do servidor.
///
/// Chamado no começo de FormProvider.syncPendingForms: os pontos sobem
/// ANTES das coletas, para o vínculo já sair completo. Se um ponto falhar, as
/// coletas sobem assim mesmo e o painel completa o vínculo depois.
class PointSyncService {
  PointSyncService._();

  /// Função de envio trocável nos testes.
  static Future<Map<String, dynamic>> Function(FieldPoint) enviar = ApiService.submitPoint;

  /// Função de consulta trocável nos testes.
  static Future<List<FieldPoint>> Function({int? projectId, int? codigoIbge}) buscar = ApiService.getPoints;

  static String? ultimoErro;

  /// Envia os pendentes, um a um, na ordem em que foram registrados.
  /// Devolve quantos o servidor confirmou.
  static Future<int> enviarPendentes() async {
    ultimoErro = null;
    var confirmados = 0;
    for (final ponto in PointQueue.paraEnviar(await PointStorageService.todos())) {
      try {
        final resposta = await enviar(ponto);
        final atualizado = PointQueue.aplicarResposta(ponto, resposta);
        await PointStorageService.salvar(atualizado);
        if (atualizado.isSynced) {
          confirmados++;
        } else {
          ultimoErro = atualizado.aviso;
        }
      } on PermanentSubmitException catch (e) {
        // Reenviar daria o mesmo erro: fica no aparelho, marcado, sem loop
        await PointStorageService.salvar(ponto.copyWith(syncStatus: 'error', aviso: e.message));
        ultimoErro = 'Ponto "${ponto.nome}": ${e.message}';
      } catch (e) {
        ultimoErro = 'Ponto "${ponto.nome}": ${e.toString().replaceAll('Exception: ', '')}';
      }
    }
    return confirmados;
  }

  /// Traz os pontos do servidor (só dos projetos a que o aplicador tem
  /// acesso) e junta com os do aparelho. Sem internet, nada muda.
  static Future<bool> atualizarDoServidor({int? projectId, int? codigoIbge}) async {
    try {
      final remotos = await buscar(projectId: projectId, codigoIbge: codigoIbge);
      await PointStorageService.substituirTodos((locais) => PointQueue.mesclar(
            locais,
            remotos,
            projetosConsultados: projectId == null ? null : {projectId},
            municipioConsultado: codigoIbge,
          ));
      return true;
    } catch (e) {
      print('⚠️ Pontos do servidor indisponíveis: $e');
      return false;
    }
  }
}

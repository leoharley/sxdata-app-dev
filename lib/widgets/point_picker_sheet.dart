import 'package:flutter/material.dart';

import '../models/field_point.dart';
import '../models/questionnaire.dart';
import '../screens/register_point_screen.dart';
import '../services/point_queue.dart';
import '../services/point_storage_service.dart';
import '../services/point_sync_service.dart';

/// Escolha do ponto de campo antes de começar a coleta.
///
/// Só aparece para questionário com projeto que já tem pontos. Devolve:
///   - (true, clientId)  → vincular ao ponto
///   - (true, null)      → seguir sem ponto
///   - null              → aplicador fechou: não começar a coleta
class PointPickerSheet {
  PointPickerSheet._();

  static Future<(bool, String?)?> escolher(BuildContext context, Questionnaire questionnaire) async {
    final projectId = questionnaire.projectId;
    if (projectId == null) return (true, null);

    // Com internet, traz os pontos de outros aplicadores do projeto; sem,
    // segue com os do aparelho (prazo curto para não travar o início)
    await PointSyncService.atualizarDoServidor(projectId: projectId)
        .timeout(const Duration(seconds: 6), onTimeout: () => false);
    final pontos = PointQueue.doProjeto(await PointStorageService.todos(), projectId);
    // Projeto sem pontos: não interrompe a coleta (pontos novos são
    // registrados em "Pontos de campo", no início)
    if (pontos.isEmpty) return (true, null);
    if (!context.mounted) return null;

    return showModalBottomSheet<(bool, String?)>(
      context: context,
      isScrollControlled: true,
      builder: (sheet) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(sheet).size.height * 0.75),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 20, 20, 4),
                child: Text('Vincular a um ponto de campo?',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: Color(0xFF23345F))),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20),
                child: Text('A coleta aparece no ponto, no mapa do painel. As coordenadas da coleta não mudam.',
                    style: TextStyle(fontSize: 12, color: Colors.grey)),
              ),
              const SizedBox(height: 8),
              ListTile(
                leading: const Icon(Icons.not_listed_location_outlined),
                title: const Text('Seguir sem ponto'),
                onTap: () => Navigator.pop(sheet, (true, null)),
              ),
              ListTile(
                leading: const Icon(Icons.add_location_alt, color: Color(0xFF8FAE5D)),
                title: const Text('Registrar novo ponto'),
                onTap: () async {
                  final novo = await Navigator.push<FieldPoint>(
                    sheet,
                    MaterialPageRoute(builder: (_) => RegisterPointScreen(projectId: projectId)),
                  );
                  if (novo != null && sheet.mounted) Navigator.pop(sheet, (true, novo.clientId));
                },
              ),
              const Divider(height: 1),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    if (pontos.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(20),
                        child: Text('Nenhum ponto neste projeto ainda.', style: TextStyle(color: Colors.grey)),
                      ),
                    for (final p in pontos)
                      ListTile(
                        leading: const Icon(Icons.place, color: Color(0xFF23345F)),
                        title: Text(p.nome),
                        subtitle: Text([
                          kRotulosTipoPonto[p.tipo] ?? p.tipo,
                          if (p.municipioRotulo.isNotEmpty) p.municipioRotulo,
                          if (!p.isSynced) 'ainda não enviado',
                        ].join(' · ')),
                        onTap: () => Navigator.pop(sheet, (true, p.clientId)),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

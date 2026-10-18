import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../providers/auth_provider.dart';
import '../providers/questionnaire_provider.dart';
import '../providers/form_provider.dart'; // Adicionar import do FormProvider
import '../providers/stats_provider.dart';
import '../widgets/app_header.dart';
import '../widgets/sync_status_card.dart';
import '../widgets/stats_cards.dart';
import '../widgets/questionnaire_list.dart';
import '../services/local_storage_service.dart';
import '../models/form_response.dart';
import 'questionnaire_preview_screen.dart';
import 'question_screen.dart';
import 'profile_screen.dart';
import 'history_screen.dart';
import 'sent_forms_screen.dart';
import 'settings_screen.dart';
import 'stats_screen.dart';
import 'stats_graphs_screen.dart';
import 'applicators_map_screen.dart';
import '../services/photo_storage_service.dart';
import 'question_analysis_screen.dart';
import '../services/api_service.dart';
import '../utils/ambiente.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with WidgetsBindingObserver {
  List<FormResponse> _pendingForms = [];

  /// Quantas coletas já foram confirmadas pelo painel. Vem de uma contagem
  /// sobre o JSON, sem instanciar as coletas — elas só são carregadas ao
  /// abrir a tela de enviadas.
  int _syncedCount = 0;
  bool _loadingPendingForms = true;
  bool _isSyncing = false;
  Map<String, int> _photosStats = {
    'total': 0,
    'pending': 0,
    'synced': 0,
    'error': 0,
  };
  bool _loadingPhotosStats = true;
  String _appVersion = '';
  StreamSubscription<ConnectivityResult>? _connectivitySub;
  bool _hasNetwork = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadData();
    _loadAppVersion();
    _watchConnectivity();
  }

  /// O app pode ficar aberto em segundo plano por horas. Ao voltar ao
  /// primeiro plano, recarrega a lista para refletir o que mudou no painel
  /// (ex.: questionário desativado) sem depender de fechar e abrir o app.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _hasNetwork) {
      print('▶️ App em primeiro plano — atualizando questionários do painel');
      Provider.of<QuestionnaireProvider>(context, listen: false)
          .loadQuestionnaires();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _connectivitySub?.cancel();
    super.dispose();
  }

  Future<void> _loadAppVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) {
        setState(() {
          _appVersion = info.version;
        });
      }
    } catch (e) {
      print('❌ Erro ao obter versão do app: $e');
    }
  }

  /// Observa a conectividade: quando a rede volta, recarrega os questionários
  /// do painel automaticamente, para que ajustes feitos lá (ex.: "requer foto",
  /// alteração de pergunta) cheguem ao app sem depender do Sincronizar manual.
  /// A sincronização de RESPOSTAS continua sendo apenas pelo botão.
  Future<void> _watchConnectivity() async {
    try {
      final initial = await Connectivity().checkConnectivity();
      _hasNetwork = initial != ConnectivityResult.none;
    } catch (e) {
      print('❌ Erro ao checar conectividade inicial: $e');
    }

    _connectivitySub = Connectivity().onConnectivityChanged.listen((result) {
      final hasNetwork = result != ConnectivityResult.none;
      if (hasNetwork && !_hasNetwork) {
        print('🌐 Rede detectada — atualizando questionários do painel');
        _refreshQuestionnairesOnReconnect();
      }
      _hasNetwork = hasNetwork;
    });
  }

  Future<void> _refreshQuestionnairesOnReconnect() async {
    final questionnaireProvider = Provider.of<QuestionnaireProvider>(
      context,
      listen: false,
    );
    await questionnaireProvider.loadQuestionnaires();

    if (mounted && questionnaireProvider.error == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Questionários atualizados com o painel'),
          backgroundColor: Color(0xFF8FAE5D),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _loadData() async {
    final questionnaireProvider = Provider.of<QuestionnaireProvider>(
      context,
      listen: false,
    );
    await questionnaireProvider.loadQuestionnaires();

    // Carregar formulários pendentes de sincronização
    await _loadPendingForms();

    // Carregar estatísticas para supervisores/administradores
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (_isSupervisorOrAdmin(authProvider.user?.role)) {
      final statsProvider = Provider.of<StatsProvider>(context, listen: false);
      if (authProvider.user?.id != null) {
        await statsProvider.loadUserStats(authProvider.user!.id);
      }
    }
  }

  Future<void> _loadPendingForms() async {
    try {
      setState(() {
        _loadingPendingForms = true;
        _loadingPhotosStats = true;
      });

      print('🔄 Carregando formulários pendentes de sincronização...');

      // Usar o FormProvider para buscar formulários pendentes
      final formProvider = Provider.of<FormProvider>(context, listen: false);

      // Sem debugPrintLocalStorage() aqui: ele carregava TODAS as coletas
      // (inclusive as já enviadas) só para imprimir, dobrando o trabalho de
      // abrir a tela e piorando conforme a lista cresce em campo.

      // Buscar formulários pendentes usando o FormProvider
      final pendingForms = await formProvider.getPendingForms();

      print(
        '✅ Encontrados ${pendingForms.length} formulários pendentes via FormProvider',
      );

      // NOVO: Carregar estatísticas de fotos
      try {
        final photosStats = await PhotoStorageService.getPhotosStats();
        print('📸 Estatísticas de fotos: $photosStats');

        setState(() {
          _photosStats = photosStats;
          _loadingPhotosStats = false;
        });
      } catch (e) {
        print('❌ Erro ao carregar estatísticas de fotos: $e');
        setState(() {
          _photosStats = {'total': 0, 'pending': 0, 'synced': 0, 'error': 0};
          _loadingPhotosStats = false;
        });
      }

      // Contagem leve: não carrega as coletas enviadas, só conta.
      final counts = await formProvider.getFormCounts();

      setState(() {
        _pendingForms = pendingForms;
        _syncedCount = counts['synced'] ?? 0;
        _loadingPendingForms = false;
      });
    } catch (e, stackTrace) {
      print('❌ Erro ao carregar formulários pendentes: $e');
      print('📋 Stack trace: $stackTrace');

      // Fallback: tentar carregar diretamente do LocalStorageService
      try {
        print('🔄 Tentando fallback direto do LocalStorageService...');
        // Só os estados que ainda precisam subir. Coletas já confirmadas
        // pelo painel não entram aqui — elas ficam na tela "Enviadas".
        final pendingForms = [
          ...await LocalStorageService.getFormResponsesByStatus('pending'),
          ...await LocalStorageService.getFormResponsesByStatus('offline'),
          ...await LocalStorageService.getFormResponsesByStatus('error'),
        ];

        print(
          '✅ Fallback: Encontrados ${pendingForms.length} formulários pendentes',
        );

        setState(() {
          _pendingForms = pendingForms;
          _loadingPendingForms = false;
          _loadingPhotosStats = false;
        });
      } catch (fallbackError) {
        print('❌ Erro no fallback: $fallbackError');
        setState(() {
          _pendingForms = [];
          _loadingPendingForms = false;
          _loadingPhotosStats = false;
        });
      }
    }
  }

  bool _isSupervisorOrAdmin(String? role) {
    return role == 'supervisor' || role == 'administrador' || role == 'admin';
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthProvider>(
      builder: (context, authProvider, child) {
        final user = authProvider.user;
        final isSupervisorOrAdmin = _isSupervisorOrAdmin(user?.role);

        return Scaffold(
          body: SafeArea(
            child: Column(
              children: [
                // Header fixo
                AppHeader(
                  onStatsPressed: () => _navigateToHistory(),
                  onSettingsPressed: () => _navigateToSettings(),
                  onProfilePressed: () => _navigateToProfile(),
                ),
                // Conteúdo scrollável
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _loadData,
                    child: CustomScrollView(
                      slivers: [
                        // Seção específica para supervisores/administradores
                        if (isSupervisorOrAdmin) ...[
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.all(20),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _buildWelcomeCard(user),
                                  const SizedBox(height: 20),
                                  _buildPendingFormsCard(),
                                  if (_syncedCount > 0) ...[
                                    const SizedBox(height: 20),
                                    _buildSentFormsCard(),
                                  ],
                                  const SizedBox(height: 20),
                                  _buildManagementOptions(context),
                                  const SizedBox(height: 20),
                                  _buildQuickStats(),
                                  const SizedBox(height: 25),
                                ],
                              ),
                            ),
                          ),
                        ] else ...[
                          // Layout original para aplicadores
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.all(20),
                              child: Column(
                                children: [
                                  _buildSessaoExpiradaBanner(),
                                  const SyncStatusCard(),

                                  /* const SizedBox(height: 10),
                                  _buildDebugButtons(), */
                                  const SizedBox(height: 20),
                                  // Card de Formulários Pendentes
                                  _buildPendingFormsCard(),
                                  // Coletas já confirmadas pelo painel.
                                  // Card próprio: continua acessível mesmo
                                  // com a fila de pendentes zerada.
                                  if (_syncedCount > 0) ...[
                                    const SizedBox(height: 20),
                                    _buildSentFormsCard(),
                                  ],
                                  const SizedBox(height: 20),
                                  Consumer<QuestionnaireProvider>(
                                    builder: (context, provider, child) {
                                      return StatsCards(
                                        questionnaires: provider.questionnaires,
                                      );
                                    },
                                  ),
                                  const SizedBox(height: 25),
                                ],
                              ),
                            ),
                          ),
                        ],

                        // Lista de questionários (comum para todos)
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (isSupervisorOrAdmin) ...[
                                  const Text(
                                    'Questionários Disponíveis',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF23345F),
                                    ),
                                  ),
                                  const SizedBox(height: 15),
                                ],
                                // Avisa quando a lista veio do cache: nesse
                                // estado ela pode conter questionários já
                                // desativados no painel.
                                Consumer<QuestionnaireProvider>(
                                  builder: (context, provider, child) {
                                    if (!provider.isFromCache) {
                                      return const SizedBox.shrink();
                                    }
                                    return Container(
                                      width: double.infinity,
                                      margin: const EdgeInsets.only(bottom: 12),
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF1F6EA),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Row(
                                        children: [
                                          Icon(Icons.cloud_off,
                                              size: 16,
                                              color: Color(0xFF8FAE5D)),
                                          SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              'Lista salva no aparelho. Conecte-se '
                                              'para ver os questionários atuais.',
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: Color(0xFF5A7536),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                                Consumer<QuestionnaireProvider>(
                                  builder: (context, provider, child) {
                                    if (provider.isLoading) {
                                      return Container(
                                        height: 200,
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          boxShadow: const [
                                            BoxShadow(
                                              color: Colors.black12,
                                              blurRadius: 8,
                                              offset: Offset(0, 2),
                                            ),
                                          ],
                                        ),
                                        child: const Center(
                                          child: Column(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              CircularProgressIndicator(),
                                              SizedBox(height: 16),
                                              Text(
                                                'Carregando questionários...',
                                                style: TextStyle(
                                                  color: Colors.grey,
                                                  fontSize: 16,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                    }

                                    return QuestionnaireList(
                                      questionnaires: provider.questionnaires,
                                      onQuestionnaireSelected: (questionnaire) {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (context) =>
                                                QuestionnairePreviewScreen(
                                                  questionnaire: questionnaire,
                                                ),
                                          ),
                                        );
                                      },
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                        ),

                        // Versão do aplicativo (no web, também o ambiente)
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 20),
                            child: Center(child: _buildRodapeVersao()),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// "Versão X". No web app acrescenta o ambiente (Produção, Evolução...),
  /// com um ponto colorido, para não confundir as duas versões publicadas.
  Widget _buildRodapeVersao() {
    const estilo = TextStyle(color: Colors.grey, fontSize: 12);
    if (_appVersion.isEmpty) {
      return const Text('', style: estilo);
    }
    if (!kIsWeb) {
      return Text('Versão $_appVersion', style: estilo);
    }

    final ambiente = Ambiente.daApi(ApiService.baseUrl);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            color: ambiente.cor,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Text('${ambiente.nome} · Versão $_appVersion', style: estilo),
      ],
    );
  }

  Widget _buildStatsItem(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(fontSize: 10, color: Colors.grey),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  /// Aviso fixo no topo enquanto o servidor considerar a sessão vencida.
  ///
  /// A sessão continua valendo localmente de propósito — derrubá-la tiraria o
  /// acesso ao que ainda não subiu. Mas o aplicador precisa saber, e um
  /// snackbar não serve: some em segundos e ele volta a coletar um dia inteiro
  /// de trabalho que não vai sincronizar.
  Widget _buildSessaoExpiradaBanner() {
    return Consumer<AuthProvider>(
      builder: (context, authProvider, _) {
        if (!authProvider.sessaoRejeitadaPeloServidor) {
          return const SizedBox.shrink();
        }

        return Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFFDECEA),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFD32F2F), width: 1.2),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.lock_clock, color: Color(0xFFD32F2F), size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Sessão expirada',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFB71C1C),
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Seus questionários continuam salvos no aparelho, mas '
                      'não vão subir para o painel até você entrar de novo.',
                      style: TextStyle(fontSize: 13, color: Color(0xFF7F2A25)),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.of(context)
                              .pushReplacementNamed('/login');
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFD32F2F),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: const Text(
                          'FAZER LOGIN NOVAMENTE',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Acesso às coletas já confirmadas pelo painel.
  ///
  /// Card próprio, FORA do card de pendentes: aquele esconde o conteúdo
  /// quando a fila zera, e o link ia junto — justamente quando o aplicador
  /// mais quer conferir o que foi enviado.
  ///
  /// As coletas não são carregadas aqui: só o contador, lido sem instanciar
  /// os objetos. A lista é montada ao abrir a tela.
  Widget _buildSentFormsCard() {
    if (_syncedCount == 0) return const SizedBox.shrink();

    return GestureDetector(
      onTap: _navigateToSentForms,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF198754).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.verified,
                    color: Color(0xFF198754), size: 20),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Coletas Enviadas',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF23345F),
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Confirmadas pelo painel',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF198754).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '$_syncedCount',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF198754),
                  ),
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.grey, size: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPendingFormsCard() {
    final totalPendingItems =
        _pendingForms.length + (_photosStats['pending'] ?? 0);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: totalPendingItems > 0
                        ? Colors.orange.withOpacity(0.1)
                        : const Color(0xFF8FAE5D).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    totalPendingItems > 0
                        ? Icons.cloud_upload_outlined
                        : Icons.cloud_done_outlined,
                    color: totalPendingItems > 0 ? Colors.orange : const Color(0xFF8FAE5D),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Pendentes de Sincronização',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF23345F),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _loadingPendingForms || _loadingPhotosStats
                            ? 'Verificando...'
                            : totalPendingItems == 0
                            ? 'Todos os dados estão sincronizados'
                            : '${_pendingForms.length} formulário${_pendingForms.length != 1 ? 's' : ''} e ${_photosStats['pending']} foto${_photosStats['pending'] != 1 ? 's' : ''} pendente${totalPendingItems != 1 ? 's' : ''}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_loadingPendingForms || _loadingPhotosStats)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: totalPendingItems > 0
                          ? Colors.orange.withOpacity(0.1)
                          : const Color(0xFF8FAE5D).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '$totalPendingItems',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: totalPendingItems > 0
                            ? Colors.orange
                            : const Color(0xFF8FAE5D),
                      ),
                    ),
                  ),
              ],
            ),

            // Mostrar breakdown de formulários e fotos se houver pendências
            if (totalPendingItems > 0) ...[
              const SizedBox(height: 16),
              const Divider(height: 1),
              const SizedBox(height: 12),

              // Estatísticas detalhadas
              Row(
                children: [
                  Expanded(
                    child: _buildStatsItem(
                      'Formulários',
                      '${_pendingForms.length}',
                      Icons.assignment_outlined,
                      _pendingForms.length > 0 ? Colors.orange : Colors.grey,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildStatsItem(
                      'Fotos',
                      '${_photosStats['pending']}',
                      Icons.photo_camera_outlined,
                      (_photosStats['pending'] ?? 0) > 0
                          ? Colors.orange
                          : Colors.grey,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // Lista dos formulários pendentes (apenas primeiros 3)
              if (_pendingForms.isNotEmpty) ...[
                ..._pendingForms
                    .take(3)
                    .map((form) => _buildPendingFormItem(form)),
              ],

              if (_pendingForms.length > 3) ...[
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: () => _showAllPendingForms(),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'Ver todos os formulários (${_pendingForms.length})',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF8FAE5D),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(
                          Icons.keyboard_arrow_down,
                          size: 16,
                          color: Color(0xFF8FAE5D),
                        ),
                      ],
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 12),

              // Botão de sincronizar
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isSyncing
                      ? null
                      : () async {
                          try {
                            setState(() {
                              _isSyncing = true;
                            });

                            final formProvider = Provider.of<FormProvider>(
                              context,
                              listen: false,
                            );

                            print('📱 === INICIANDO SINCRONIZAÇÃO DA DASHBOARD ===');

                            final formsResult = await formProvider
                                .syncPendingForms();

                            print('📱 Resultado da sincronização: $formsResult itens');

                            await _loadPendingForms();

                            if (mounted) {
                              final erro = formProvider.lastSyncError;

                              // Sessão expirada precisa de um caminho de saída:
                              // sem isso, o aplicador tentava sincronizar em
                              // laço achando que era falta de sinal.
                              final isTokenError = erro != null &&
                                  (erro.contains('HTTP 401') ||
                                      erro.contains('401') ||
                                      erro.contains('Invalid token') ||
                                      erro.contains('Token expirado'));

                              if (isTokenError) {
                                // Deixa o aviso permanente no topo até o
                                // aplicador refazer o login: um snackbar some
                                // em segundos e ele voltaria a coletar sem
                                // saber que nada vai subir.
                                Provider.of<AuthProvider>(context, listen: false)
                                    .marcarSessaoExpirada();
                              }

                              String message;
                              Color color;

                              if (formsResult > 0) {
                                message = 'Sincronização concluída! $formsResult ${formsResult == 1 ? 'item sincronizado' : 'itens sincronizados'}';
                                color = const Color(0xFF8FAE5D);
                              } else if (isTokenError) {
                                message = 'Sessão expirada. Faça login novamente para sincronizar.';
                                color = Colors.red;
                              } else if (erro != null) {
                                // Motivo real do servidor, em vez do genérico
                                // "verifique sua conexão" que mandava o
                                // aplicador procurar no lugar errado.
                                message = 'Não sincronizou: $erro';
                                color = Colors.red;
                              } else {
                                message = 'Nenhum item pendente para sincronizar.';
                                color = Colors.orange;
                              }

                              print('📱 Mostrando mensagem: $message');

                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(message),
                                  backgroundColor: color,
                                  duration: Duration(
                                    seconds: formsResult > 0 ? 4 : 8,
                                  ),
                                  action: isTokenError
                                      ? SnackBarAction(
                                          label: 'LOGIN',
                                          textColor: Colors.white,
                                          onPressed: () {
                                            Navigator.of(context)
                                                .pushReplacementNamed('/login');
                                          },
                                        )
                                      : null,
                                ),
                              );
                            }
                          } catch (e) {
                            print('❌ Erro na sincronização: $e');

                            // Verificar se é erro de token inválido
                            final isTokenError = e.toString().contains('Invalid token') ||
                                                 e.toString().contains('Token expirado') ||
                                                 e.toString().contains('401');

                            if (mounted) {
                              String errorMessage;

                              if (isTokenError) {
                                errorMessage = 'Sessão expirada. Faça login novamente para sincronizar.';
                              } else {
                                errorMessage = 'Erro na sincronização: ${e.toString().replaceAll('Exception: ', '')}';
                              }

                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(errorMessage),
                                  backgroundColor: Colors.red,
                                  duration: const Duration(seconds: 5),
                                  action: isTokenError
                                      ? SnackBarAction(
                                          label: 'LOGIN',
                                          textColor: Colors.white,
                                          onPressed: () {
                                            Navigator.of(context).pushReplacementNamed('/login');
                                          },
                                        )
                                      : null,
                                ),
                              );
                            }
                          } finally {
                            if (mounted) {
                              setState(() {
                                _isSyncing = false;
                              });
                            }
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF8FAE5D),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: _isSyncing
                      ? const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.white,
                                ),
                              ),
                            ),
                            SizedBox(width: 8),
                            Text(
                              'Sincronizando...',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        )
                      : const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.cloud_upload, size: 16),
                            SizedBox(width: 8),
                            Text(
                              'Sincronizar Tudo',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPendingFormItem(FormResponse form) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.orange.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.assignment_outlined,
            size: 16,
            color: Colors.orange.shade600,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Questionário ID: ${form.questionnaireId}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF23345F),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Respostas: ${form.responses.length} • Concluído: ${_formatDateTime(form.completedAt)}',
                  style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
          // Botão de editar
          IconButton(
            icon: Icon(
              Icons.edit_outlined,
              size: 18,
              color: Colors.blue.shade600,
            ),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: () => _editPendingForm(form),
            tooltip: 'Editar questionário',
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.orange.withOpacity(0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              _getStatusText(form.syncStatus),
              style: const TextStyle(
                fontSize: 9,
                color: Colors.orange,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime? dateTime) {
    if (dateTime == null) return 'N/A';
    return '${dateTime.day.toString().padLeft(2, '0')}/${dateTime.month.toString().padLeft(2, '0')} ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
  }

  String _getStatusText(String? status) {
    switch (status) {
      case 'pending':
        return 'PENDENTE';
      case 'offline':
        return 'OFFLINE';
      case 'error':
        return 'ERRO';
      case 'synced':
        return 'SINCRONIZADO';
      default:
        return 'AGUARDANDO';
    }
  }

  void _showAllPendingForms() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.7,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
          ),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Color(0xFFF0F0F0))),
              ),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Formulários Pendentes',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF23345F),
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(20),
                itemCount: _pendingForms.length,
                itemBuilder: (context, index) {
                  return _buildPendingFormItem(_pendingForms[index]);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Editar questionário pendente antes de submeter
  Future<void> _editPendingForm(FormResponse form) async {
    try {
      print('✏️ === EDITANDO QUESTIONÁRIO PENDENTE ===');
      print('📋 Questionário ID: ${form.questionnaireId}');
      print('📝 Respostas atuais: ${form.responses.length}');
      print('🆔 Form ID: ${form.id}');

      // Buscar o questionário completo
      final questionnaireProvider = Provider.of<QuestionnaireProvider>(
        context,
        listen: false,
      );

      await questionnaireProvider.loadQuestionnaires();

      final questionnaire = questionnaireProvider.questionnaires.firstWhere(
        (q) => q.id == form.questionnaireId,
        orElse: () => throw Exception('Questionário não encontrado'),
      );

      print('✅ Questionário encontrado: ${questionnaire.title}');

      // Carregar respostas existentes no FormProvider
      final formProvider = Provider.of<FormProvider>(context, listen: false);

      print('📝 === INICIANDO EDIÇÃO DE FORMULÁRIO ===');
      print('📝 ID do formulário: ${form.id}');
      print('📝 Questionário ID: ${form.questionnaireId}');
      print('📝 Número de respostas: ${form.responses.length}');

      if (form.id == null) {
        print('❌ ERRO: Formulário sem ID não pode ser editado');
        return;
      }

      // Carrega o formulário INTEIRO, não só as respostas. Antes só as
      // respostas eram carregadas: a tela de questões reaproveitava o último
      // formulário em memória (ou criava um vazio), e a edição saía com as
      // coordenadas, datas e fotos de outra entrevista — ou com a posição do
      // momento da edição. Várias coletas editadas no mesmo lugar ficavam com
      // a mesma coordenada.
      formProvider.setEditMode(form.id.toString());
      formProvider.loadFormForEdit(form, questionnaire);
      print('✅ Modo de edição ativado com ID: ${form.id}');

      // Navegar para a tela de questões
      if (!mounted) return;

      final result = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => QuestionScreen(
            questionnaire: questionnaire,
            currentQuestionIndex: 0,
          ),
        ),
      );

      // Limpar modo de edição
      formProvider.clearEditMode();

      // Se o usuário completou o questionário, recarregar a lista
      if (result == true) {
        print('✅ Questionário editado com sucesso');
        await _loadPendingForms();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Questionário editado com sucesso!'),
              backgroundColor: const Color(0xFF8FAE5D),
              duration: Duration(seconds: 2),
            ),
          );
        }
      } else {
        print('ℹ️ Edição cancelada pelo usuário');
      }
    } catch (e) {
      print('❌ Erro ao editar questionário: $e');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao carregar questionário: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Widget _buildWelcomeCard(dynamic user) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF8FAE5D), Color(0xFF5A7536)],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF8FAE5D).withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.admin_panel_settings,
              size: 28,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Bem-vindo, ${user?.fullName ?? 'Supervisor'}!',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _getRoleDescription(user?.role),
                  style: const TextStyle(fontSize: 14, color: Colors.white70),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Painel de Gestão',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white60,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildManagementOptions(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.all(20),
            child: Text(
              'Ferramentas de Gestão',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Color(0xFF23345F),
              ),
            ),
          ),
          _buildManagementOption(
            icon: Icons.analytics,
            title: 'Estatísticas Gerais',
            subtitle: 'Relatórios e métricas',
            color: const Color(0xFF8FAE5D),
            onTap: () => _navigateToStats(context),
          ),
          _buildManagementOption(
            icon: Icons.bar_chart,
            title: 'Gráficos Avançados',
            subtitle: 'Análise visual dos dados',
            color: Colors.blue,
            onTap: () => _navigateToStatsGraphs(context),
          ),
          _buildManagementOption(
            icon: Icons.quiz,
            title: 'Análise de Questões',
            subtitle: 'Estatísticas por questão',
            color: Colors.indigo,
            onTap: () => _navigateToQuestionAnalysis(context),
          ),
          _buildManagementOption(
            icon: Icons.map,
            title: 'Mapa de Aplicadores',
            subtitle: 'Áreas de atuação',
            color: Colors.purple,
            onTap: () => _navigateToApplicatorsMap(context),
            isLast: true,
          ),
        ],
      ),
    );
  }

  Widget _buildManagementOption({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
    bool isLast = false,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(isLast ? 16 : 0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          border: isLast
              ? null
              : const Border(bottom: BorderSide(color: Color(0xFFF0F0F0))),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, size: 24, color: color),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF23345F),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(fontSize: 13, color: Colors.grey),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios,
              size: 16,
              color: Colors.grey.shade400,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickStats() {
    return Consumer<StatsProvider>(
      builder: (context, statsProvider, child) {
        final stats = statsProvider.userStats?.summary;

        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Visão Rápida',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF23345F),
                ),
              ),
              const SizedBox(height: 16),
              if (statsProvider.isLoading)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: CircularProgressIndicator(),
                  ),
                )
              else if (statsProvider.error != null)
                Center(
                  child: Column(
                    children: [
                      Icon(
                        Icons.error_outline,
                        size: 32,
                        color: Colors.red[300],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Erro ao carregar dados',
                        style: TextStyle(color: Colors.red[700], fontSize: 14),
                      ),
                    ],
                  ),
                )
              else
                Row(
                  children: [
                    Expanded(
                      child: _buildQuickStatItem(
                        'Total Formulários',
                        '${stats?.totalForms ?? 0}',
                        Icons.assignment,
                        const Color(0xFF8FAE5D),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildQuickStatItem(
                        'Hoje',
                        '${stats?.todayForms ?? 0}',
                        Icons.today,
                        Colors.blue,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildQuickStatItem(
                        'Sucesso',
                        '${stats?.successRate ?? 0}%',
                        Icons.check_circle,
                        const Color(0xFF8FAE5D),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildQuickStatItem(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(fontSize: 10, color: Colors.grey),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  String _getRoleDescription(String? role) {
    switch (role) {
      case 'supervisor':
        return 'Supervisor de Campo';
      case 'administrador':
      case 'admin':
        return 'Administrador do Sistema';
      default:
        return 'Gestor';
    }
  }

  // Métodos de navegação
  _navigateToHistory() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const HistoryScreen()),
    );
  }

  _navigateToSentForms() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const SentFormsScreen()),
    );
    // Ao voltar, atualiza os contadores (o usuário pode ter sincronizado).
    if (mounted) await _loadPendingForms();
  }

  _navigateToSettings() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const SettingsScreen()),
    );
  }

  _navigateToProfile() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const ProfileScreen()),
    );
  }

  _navigateToStats(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const StatsScreen()),
    );
  }

  _navigateToStatsGraphs(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const StatsGraphsScreen()),
    );
  }

  _navigateToApplicatorsMap(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const BrazilMapScreen()),
    );
  }

  _navigateToQuestionAnalysis(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const QuestionAnalysisScreen()),
    );
  }
}

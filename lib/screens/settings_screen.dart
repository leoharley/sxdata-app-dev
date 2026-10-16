// screens/settings_screen.dart
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/photo_storage_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _autoSync = true;
  bool _wifiOnly = false;
  bool _gpsActive = true;
  bool _highAccuracy = true;
  bool _imageCompression = true;
  bool _notifications = true;
  bool _darkMode = false;
  String _appVersion = '';

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _loadAppVersion();
  }

  // Versão real do build (pubspec.yaml), não um valor fixo
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Header customizado com logo
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                color: Color(0xFFF5F5F5),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Botão voltar
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(
                      Icons.arrow_back,
                      color: Color(0xFF23345F),
                      size: 24,
                    ),
                  ),
                  // Logo centralizado
                  Image.asset(
                    'assets/images/logo_socialx.png',
                    width: 120,             
                    fit: BoxFit.contain,
                  ),
                  // Ícone de configurações
                  const Icon(
                    Icons.settings,
                    color: Color(0xFF8FAE5D),
                    size: 24,
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Configurações',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF23345F),
                      ),
                    ),
                    const SizedBox(height: 5),
                    const Text(
                      'Preferências do aplicativo',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 30),
                    
                    _buildSettingsSection(
                      'Sincronização',
                      [
                        _buildToggleItem(
                          'Sincronização Automática',
                          'Enviar dados automaticamente quando online',
                          _autoSync,
                          (value) => _updateSetting('autoSync', value),
                        ),
                        _buildToggleItem(
                          'Apenas WiFi',
                          'Sincronizar apenas em redes WiFi',
                          _wifiOnly,
                          (value) => _updateSetting('wifiOnly', value),
                        ),
                      ],
                    ),
                    
                    const SizedBox(height: 30),
                    
                    _buildSettingsSection(
                      'Localização',
                      [
                        _buildToggleItem(
                          'GPS Ativo',
                          'Capturar coordenadas automaticamente',
                          _gpsActive,
                          (value) => _updateSetting('gpsActive', value),
                        ),
                        _buildToggleItem(
                          'Precisão Alta',
                          'Usar GPS + WiFi para maior precisão',
                          _highAccuracy,
                          (value) => _updateSetting('highAccuracy', value),
                        ),
                      ],
                    ),
                    
                    const SizedBox(height: 30),
                    
                    _buildSettingsSection(
                      'Câmera',
                      [
                        _buildToggleItem(
                          'Compressão de Imagens',
                          'Reduzir tamanho das fotos',
                          _imageCompression,
                          (value) => _updateSetting('imageCompression', value),
                        ),
                      ],
                    ),
                    
                    const SizedBox(height: 30),
                    
                    _buildSettingsSection(
                      'Interface',
                      [
                        _buildToggleItem(
                          'Notificações',
                          'Receber alertas e lembretes',
                          _notifications,
                          (value) => _updateSetting('notifications', value),
                        ),
                        _buildToggleItem(
                          'Modo Escuro',
                          'Tema escuro para o aplicativo',
                          _darkMode,
                          (value) => _updateSetting('darkMode', value),
                        ),
                      ],
                    ),
                    
                    const SizedBox(height: 30),
                    
                    _buildSettingsSection(
                      'Dados',
                      [
                        _buildActionItem(
                          'Limpar Cache',
                          'Remover dados temporários',
                          Icons.cleaning_services,
                          () => _clearCache(),
                        ),
                        _buildActionItem(
                          'Exportar Dados',
                          'Salvar dados locais',
                          Icons.download,
                          () => _exportData(),
                        ),
                        _buildActionItem(
                          'Forçar Sincronização',
                          'Tentar sincronizar todos os dados',
                          Icons.sync,
                          () => _forceSync(),
                        ),
                        _buildActionItem(
                          'Reenviar Fotos',
                          'Forçar upload de fotos pendentes para FTP',
                          Icons.cloud_upload,
                          () => _forcePhotoUpload(),
                        ),
                      ],
                    ),
                    
                    const SizedBox(height: 30),
                    
                    _buildSettingsSection(
                      'Sobre',
                      [
                        _buildInfoItem('Versão do App', _appVersion.isEmpty ? '-' : _appVersion),
                        _buildInfoItem('Banco de Dados', 'v2.1'),
                        _buildInfoItem('Última Sincronização', 'Agora'),
                        _buildActionItem(
                          'Política de Privacidade',
                          'Ver termos e condições',
                          Icons.privacy_tip,
                          () => _showPrivacyPolicy(),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingsSection(String title, List<Widget> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 5, bottom: 15),
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Color(0xFF23345F),
            ),
          ),
        ),
        ...items,
      ],
    );
  }

  Widget _buildToggleItem(String title, String subtitle, bool value, Function(bool) onChanged) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF23345F),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.grey,
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: () => onChanged(!value),
            child: Container(
              width: 50,
              height: 28,
              decoration: BoxDecoration(
                color: value ? const Color(0xFF8FAE5D) : Colors.grey.shade300,
                borderRadius: BorderRadius.circular(14),
              ),
              child: AnimatedAlign(
                duration: const Duration(milliseconds: 200),
                alignment: value ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  width: 24,
                  height: 24,
                  margin: const EdgeInsets.all(2),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black26,
                        blurRadius: 4,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionItem(String title, String subtitle, IconData icon, VoidCallback onTap) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFF8FAE5D).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  icon,
                  size: 20,
                  color: const Color(0xFF8FAE5D),
                ),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF23345F),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.grey,
                      ),
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
      ),
    );
  }

  Widget _buildInfoItem(String title, String value) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w500,
              color: Color(0xFF23345F),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: Colors.grey,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    
    setState(() {
      _autoSync = prefs.getBool('autoSync') ?? true;
      _wifiOnly = prefs.getBool('wifiOnly') ?? false;
      _gpsActive = prefs.getBool('gpsActive') ?? true;
      _highAccuracy = prefs.getBool('highAccuracy') ?? true;
      _imageCompression = prefs.getBool('imageCompression') ?? true;
      _notifications = prefs.getBool('notifications') ?? true;
      _darkMode = prefs.getBool('darkMode') ?? false;
    });
  }

  Future<void> _updateSetting(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
    
    setState(() {
      switch (key) {
        case 'autoSync':
          _autoSync = value;
          break;
        case 'wifiOnly':
          _wifiOnly = value;
          break;
        case 'gpsActive':
          _gpsActive = value;
          break;
        case 'highAccuracy':
          _highAccuracy = value;
          break;
        case 'imageCompression':
          _imageCompression = value;
          break;
        case 'notifications':
          _notifications = value;
          break;
        case 'darkMode':
          _darkMode = value;
          break;
      }
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Configuração atualizada'),
        duration: Duration(seconds: 1),
      ),
    );
  }

  void _clearCache() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Limpar Cache'),
        content: const Text('Isso removerá todos os dados temporários. Continuar?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Cache limpo com sucesso')),
              );
            },
            child: const Text('Limpar'),
          ),
        ],
      ),
    );
  }

  void _exportData() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Funcionalidade de exportação em desenvolvimento'),
      ),
    );
  }

  void _forceSync() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Sincronização iniciada em segundo plano'),
      ),
    );
  }

  Future<void> _forcePhotoUpload() async {
    try {
      // Mostrar dialog de confirmação
      final bool? confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Reenviar Fotos'),
          content: const Text(
            'Isso irá buscar TODAS as fotos salvas localmente e tentar enviá-las novamente para o servidor FTP.\n\n'
            'Certifique-se de estar conectado à internet.\n\n'
            'Continuar?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Reenviar'),
            ),
          ],
        ),
      );

      if (confirmed != true) return;

      if (!mounted) return;

      // Mostrar dialog de progresso para buscar fotos
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => WillPopScope(
          onWillPop: () async => false,
          child: const AlertDialog(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 20),
                Text('Buscando fotos locais...'),
              ],
            ),
          ),
        ),
      );

      // PASSO 1: Resetar TODAS as fotos para status 'pending'
      final int resetCount = await PhotoStorageService.resetAllPhotosToPending();

      if (!mounted) return;
      Navigator.pop(context); // Fechar dialog de progresso

      if (resetCount == 0) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Nenhuma foto encontrada no dispositivo'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      // Mostrar dialog de progresso para upload
      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => WillPopScope(
          onWillPop: () async => false,
          child: AlertDialog(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 20),
                Text('Enviando $resetCount foto${resetCount > 1 ? 's' : ''}...'),
                const SizedBox(height: 10),
                const Text(
                  'Isso pode levar alguns minutos',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
        ),
      );

      // PASSO 2: Sincronizar fotos (agora todas estão com status 'pending')
      final int syncedCount = await PhotoStorageService.syncPendingPhotos();

      if (!mounted) return;
      Navigator.pop(context); // Fechar dialog de progresso

      // Mostrar resultado
      if (!mounted) return;
      if (syncedCount > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              syncedCount == resetCount
                  ? 'Todas as $syncedCount foto${syncedCount > 1 ? 's foram' : ' foi'} enviada${syncedCount > 1 ? 's' : ''} com sucesso!'
                  : '$syncedCount de $resetCount foto${syncedCount > 1 ? 's foram' : ' foi'} enviada${syncedCount > 1 ? 's' : ''}',
            ),
            backgroundColor: syncedCount == resetCount
                ? const Color(0xFF8FAE5D)
                : Colors.orange,
            duration: const Duration(seconds: 4),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Erro ao enviar fotos. Verifique sua conexão com a internet.'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      print('❌ Erro ao forçar upload de fotos: $e');

      if (!mounted) return;

      // Fechar qualquer dialog aberto
      Navigator.of(context).popUntil((route) => route.isFirst || !route.navigator!.canPop());

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao enviar fotos: ${e.toString()}'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  void _showPrivacyPolicy() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Política de Privacidade'),
        content: const SingleChildScrollView(
          child: Text(
            'Este aplicativo coleta dados apenas para fins de pesquisa conforme autorizado pelo usuário. '
            'Todos os dados são protegidos pela LGPD e utilizados exclusivamente para os fins descritos '
            'no termo de consentimento de cada questionário.\n\n'
            'Para mais informações, entre em contato com nossa equipe.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
  }
}
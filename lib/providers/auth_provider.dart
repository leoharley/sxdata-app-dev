import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../models/user.dart';
import '../services/api_service.dart';
import '../services/local_storage_service.dart';

class AuthProvider with ChangeNotifier {
  User? _user;
  bool _isAuthenticated = false;
  bool _isLoading = false;
  bool _isInitialized = false; // Para controlar se já verificou o status

  /// O servidor já recusou este token, mas a sessão local foi mantida para
  /// não bloquear o acesso ao que ainda não subiu.
  ///
  /// Existe porque a expiração era silenciosa: o app verificava o token na
  /// abertura, ouvia do servidor que tinha vencido e guardava a informação
  /// para si. O aplicador seguia coletando o dia inteiro e só descobria ao
  /// tentar sincronizar — quando descobria.
  bool _sessaoRejeitadaPeloServidor = false;

  User? get user => _user;
  bool get isAuthenticated => _isAuthenticated;
  bool get isLoading => _isLoading;
  bool get hasUser => _user != null;
  bool get isInitialized => _isInitialized;
  String? get userToken => null;
  bool get sessaoRejeitadaPeloServidor => _sessaoRejeitadaPeloServidor;

  /// Registra que o servidor recusou a sessão. Chamado na verificação de
  /// abertura e também quando uma sincronização volta com 401 — é comum a
  /// sessão vencer com o app já aberto.
  void marcarSessaoExpirada() {
    if (_sessaoRejeitadaPeloServidor) return;
    _sessaoRejeitadaPeloServidor = true;
    if (kDebugMode) {
      print('⚠️ Sessão marcada como expirada no servidor');
    }
    notifyListeners();
  }

  /// Verifica se o app foi atualizado e força logout se necessário
  Future<bool> _checkAppVersionAndForceLogoutIfUpdated() async {
    print('🔍 ========================================');
    print('🔍 INICIANDO VERIFICAÇÃO DE VERSÃO DO APP');
    print('🔍 ========================================');

    try {
      final prefs = await SharedPreferences.getInstance();

      print('📦 Obtendo informações do pacote...');
      // Na web isto baixa o version.json: sem prazo, uma rede conectada mas
      // sem resposta segurava a abertura do app. Estourou, segue sem checar.
      final PackageInfo packageInfo = await PackageInfo.fromPlatform()
          .timeout(const Duration(seconds: 5));

      // Versão completa: version+buildNumber (ex: 1.0.0+1)
      final String currentVersion = '${packageInfo.version}+${packageInfo.buildNumber}';
      final String? savedVersion = prefs.getString('app_version');

      print('🔍 === VERIFICANDO VERSÃO DO APP ===');
      print('📱 Versão atual do APK: $currentVersion');
      print('📱 packageInfo.version: ${packageInfo.version}');
      print('📱 packageInfo.buildNumber: ${packageInfo.buildNumber}');
      print('💾 Versão salva em SharedPreferences: $savedVersion');
      print('🔍 ========================================');

      if (savedVersion == null) {
        // Primeira instalação - salvar versão atual
        print('⚠️ PRIMEIRA INSTALAÇÃO DETECTADA');
        print('💾 Salvando versão atual: $currentVersion');
        await prefs.setString('app_version', currentVersion);
        print('✅ Versão salva com sucesso');
        return false; // Não houve atualização
      }

      print('🔍 Comparando versões...');
      print('   Salva: "$savedVersion"');
      print('   Atual: "$currentVersion"');
      print('   São iguais? ${savedVersion == currentVersion}');

      if (savedVersion != currentVersion) {
        // APP FOI ATUALIZADO - Forçar logout
        print('🆕 ========================================');
        print('🆕 === APP ATUALIZADO DETECTADO!!! ===');
        print('🆕 ========================================');
        print('📱 Versão anterior: $savedVersion');
        print('📱 Nova versão: $currentVersion');
        print('🚪 Forçando logout por segurança...');
        print('🆕 ========================================');

        // Fazer logout completo (limpar token)
        print('🧹 Removendo auth_token...');
        await prefs.remove('auth_token');
        print('🧹 Removendo login_timestamp...');
        await prefs.remove('login_timestamp');

        // Atualizar versão salva
        print('💾 Atualizando versão salva para: $currentVersion');
        await prefs.setString('app_version', currentVersion);

        // Verificar se salvou
        final String? verificacao = prefs.getString('app_version');
        print('✅ Verificação: versão salva agora é: $verificacao');

        // Resetar estado de autenticação
        _isAuthenticated = false;
        _user = null;

        print('✅ Logout forçado concluído!');
        print('🆕 ========================================');

        return true; // Houve atualização e logout
      }

      print('✅ Mesma versão - sem necessidade de logout');
      return false; // Não houve atualização

    } catch (e, stackTrace) {
      print('❌ ========================================');
      print('❌ ERRO ao verificar versão do app: $e');
      print('📋 Stack trace: $stackTrace');
      print('❌ ========================================');
      return false;
    }
  }

  Future<bool> login(String username, String password) async {
    _isLoading = true;
    notifyListeners();

    try {
      if (kDebugMode) {
        print('🔐 === INICIANDO LOGIN ===');
        print('👤 Usuário: $username');
      }

      // Tentar login online primeiro
      try {
        final response = await ApiService.login(username, password);

        if (kDebugMode) {
          print('📡 Resposta do servidor recebida');
          print('✅ Success: ${response['success']}');
        }

        if (response.containsKey('success') && response['success'] == true) {
          if (kDebugMode) {
            print('✅ Login online bem-sucedido');
          }

          _isAuthenticated = true;

          // Processar dados do usuário
          if (response.containsKey('user') && response['user'] != null) {
            if (kDebugMode) {
              print('📋 Dados do usuário encontrados');
            }

            try {
              _user = User.fromJson(response['user']);
              if (kDebugMode) {
                print('✅ Objeto User criado: ${_user?.id}');
              }
            } catch (userError) {
              if (kDebugMode) {
                print('❌ Erro ao criar User: $userError');
              }
              _user = null;
            }
          }

          // Salvar dados de autenticação E credenciais offline
          await _saveAuthData(response);
          await _saveOfflineCredentials(username, password);

          notifyListeners();

          if (kDebugMode) {
            print('✅ === LOGIN ONLINE CONCLUÍDO COM SUCESSO ===');
          }
          return true;
        } else {
          // Login online falhou (credenciais inválidas)
          if (kDebugMode) {
            print('❌ Login online falhou - credenciais inválidas');
            print('📝 Mensagem: ${response['message'] ?? 'Sem mensagem'}');
          }
          // Retorna false - não tenta offline se servidor respondeu que credenciais são inválidas
          return false;
        }
      } catch (networkError) {
        // Erro de rede - servidor não respondeu
        if (kDebugMode) {
          print('🌐 Erro de rede: $networkError');
          print('🔄 Tentando login offline...');
        }

        // Tentar login offline quando não há conexão
        final offlineResult = await _attemptOfflineLogin(username, password);

        if (offlineResult) {
          if (kDebugMode) {
            print('✅ === LOGIN OFFLINE BEM-SUCEDIDO ===');
          }
        } else {
          if (kDebugMode) {
            print('❌ === LOGIN OFFLINE FALHOU ===');
          }
        }

        return offlineResult;
      }
    } catch (e, stackTrace) {
      if (kDebugMode) {
        print('❌ Erro inesperado no login: $e');
        print('📋 Stack trace: $stackTrace');
      }
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Salvar credenciais offline (sem criptografia para simplificar)
  Future<void> _saveOfflineCredentials(String username, String password) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final saveUsername = await prefs.setString('offline_username', username);
      final savePassword = await prefs.setString('offline_password', password);

      if (kDebugMode) {
        print('💾 === SALVANDO CREDENCIAIS OFFLINE ===');
        print('📝 Username: $username - Resultado: $saveUsername');
        print('📝 Password: ${password.length} caracteres - Resultado: $savePassword');

        // Verificação imediata
        final verifyUsername = prefs.getString('offline_username');
        final verifyPassword = prefs.getString('offline_password');
        print('✅ Verificação imediata:');
        print('   Username recuperado: $verifyUsername');
        print('   Password recuperado existe: ${verifyPassword != null} (${verifyPassword?.length ?? 0} chars)');

        if (verifyUsername == username && verifyPassword == password) {
          print('✅ === CREDENCIAIS OFFLINE SALVAS E VERIFICADAS COM SUCESSO ===');
        } else {
          print('❌ === ERRO: CREDENCIAIS NÃO FORAM SALVAS CORRETAMENTE ===');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Erro ao salvar credenciais offline: $e');
      }
    }
  }

  // Tentar login offline
  Future<bool> _attemptOfflineLogin(String username, String password) async {
    try {
      if (kDebugMode) {
        print('🔍 === TENTANDO LOGIN OFFLINE ===');
      }

      final prefs = await SharedPreferences.getInstance();
      final savedUsername = prefs.getString('offline_username');
      final savedPassword = prefs.getString('offline_password');

      if (kDebugMode) {
        print('📋 Username salvo: $savedUsername');
        print('📋 Senha salva existe: ${savedPassword != null}');
        print('📋 Username digitado: $username');
        print('📋 Senha digitada existe: ${password.isNotEmpty}');
      }

      if (savedUsername == null || savedPassword == null) {
        if (kDebugMode) {
          print('❌ Nenhuma credencial offline salva');
        }
        return false;
      }

      // Verificar se o username corresponde
      if (savedUsername != username) {
        if (kDebugMode) {
          print('❌ Usuário não corresponde ao salvo offline');
          print('   Esperado: $savedUsername');
          print('   Recebido: $username');
        }
        return false;
      }

      // Verificar se a senha corresponde
      if (savedPassword != password) {
        if (kDebugMode) {
          print('❌ Senha incorreta para login offline');
          print('   Esperado: ${savedPassword.substring(0, 2)}***');
          print('   Recebido: ${password.substring(0, 2)}***');
        }
        return false;
      }

      if (kDebugMode) {
        print('✅ Credenciais offline validadas!');
        print('🔄 Carregando dados do usuário...');
      }

      // Carregar dados do usuário salvos
      final userId = prefs.getInt('user_id');
      if (kDebugMode) {
        print('📋 User ID encontrado: $userId');
      }

      if (userId != null) {
        await _loadSavedUserData(prefs, userId);
      }

      if (_user != null) {
        _isAuthenticated = true;

        if (kDebugMode) {
          print('✅ === LOGIN OFFLINE BEM-SUCEDIDO ===');
          print('👤 Usuário: ${_user!.fullName}');
          print('📧 Email: ${_user!.email}');
        }

        notifyListeners();
        return true;
      } else {
        if (kDebugMode) {
          print('❌ Dados do usuário não encontrados para login offline');
        }
        return false;
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Erro durante login offline: $e');
      }
      return false;
    }
  }

  // Método privado para salvar dados de autenticação
  Future<void> _saveAuthData(Map<String, dynamic> response) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Salvar token
      if (response.containsKey('token') && response['token'] != null) {
        await prefs.setString('auth_token', response['token']);
        // Token novo em folha: o alerta de sessão vencida deixa de valer.
        _sessaoRejeitadaPeloServidor = false;
        if (kDebugMode) {
          print('Token saved: ${response['token'].toString().substring(0, 10)}...');
        }
      }

      // Salvar dados do usuário como JSON string para recuperação offline
      if (_user != null) {
        await prefs.setInt('user_id', _user!.id);
        final userJsonString = '${_user!.toJson()}';
        await prefs.setString('user_data', userJsonString);
        await prefs.setString('user_full_name', _user!.fullName);
        await prefs.setString('user_username', _user!.username);
        await prefs.setString('user_email', _user!.email);
        await prefs.setString('user_role', _user!.role);
        await prefs.setBool('user_is_active', _user!.isActive);
        if (kDebugMode) {
          print('User data saved: ${_user!.fullName} (${_user!.username})');
        }
      }

      // Salvar timestamp do login
      await prefs.setInt('login_timestamp', DateTime.now().millisecondsSinceEpoch);

      if (kDebugMode) {
        print('Auth data saved successfully');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error saving auth data: $e');
      }
    }
  }

  void setUser(dynamic userData) {
    if (userData != null) {
      try {
        if (userData is User) {
          _user = userData;
        } else if (userData is Map<String, dynamic>) {
          _user = User.fromJson(userData);
        } else {
          throw Exception('Invalid user data type: ${userData.runtimeType}');
        }
        
        _isAuthenticated = true;
        
        if (kDebugMode) {
          print('User set successfully: ${_user?.id}');
        }
      } catch (e) {
        if (kDebugMode) {
          print('Error setting user: $e');
        }
        _user = null;
        _isAuthenticated = false;
      }
    } else {
      _user = null;
      _isAuthenticated = false;
    }
    
    notifyListeners();
  }

  void clearUser() {
    _user = null;
    _isAuthenticated = false;
    notifyListeners();
    
    if (kDebugMode) {
      print('User cleared');
    }
  }

  Future<void> saveToken(String token) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('auth_token', token);
      
      if (_user != null) {
        await prefs.setInt('user_id', _user!.id);
      }
      
      if (kDebugMode) {
        print('Token saved: ${token.substring(0, 10)}...');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error saving token: $e');
      }
    }
  }

  void updateUserData(Map<String, dynamic> updates) {
    if (_user != null) {
      try {
        final currentData = _user!.toJson();
        currentData.addAll(updates);
        _user = User.fromJson(currentData);
        
        // Atualizar dados salvos
        _saveUpdatedUserData();
        
        notifyListeners();
        
        if (kDebugMode) {
          print('User data updated: $updates');
        }
      } catch (e) {
        if (kDebugMode) {
          print('Error updating user data: $e');
        }
      }
    }
  }

  // Método para salvar dados atualizados do usuário
  Future<void> _saveUpdatedUserData() async {
    if (_user != null) {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('user_data', _user!.toJson().toString());
        await prefs.setInt('user_id', _user!.id);
        await prefs.setString('user_full_name', _user!.fullName);
        await prefs.setString('user_username', _user!.username);
        await prefs.setString('user_email', _user!.email);
        await prefs.setString('user_role', _user!.role);
        await prefs.setBool('user_is_active', _user!.isActive);
      } catch (e) {
        if (kDebugMode) {
          print('Error saving updated user data: $e');
        }
      }
    }
  }

  // Logout manual - remove apenas o token, MAS MANTÉM credenciais e dados do usuário para login offline
  Future<void> logout() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Remove apenas o token de autenticação
      await prefs.remove('auth_token');
      await prefs.remove('login_timestamp');

      // MANTÉM todos os dados do usuário e credenciais offline
      // NÃO remove: user_id, user_data, user_full_name, user_username, user_email, user_role, user_is_active
      // NÃO remove: offline_username, offline_password

      // MAS remove a estratificação em cache: ela agora contém as metas
      // INDIVIDUAIS de quem estava logado. Sem isso, o próximo aplicador a
      // usar este aparelho veria offline as metas do anterior rotuladas
      // como "Suas metas".
      await LocalStorageService.clearStratifications();

      _user = null;
      _isAuthenticated = false;

      if (kDebugMode) {
        print('✅ Logout completo - sessão encerrada');
        print('📝 Credenciais E dados do usuário MANTIDOS para login offline futuro');

        // Debug: verificar o que foi mantido
        final savedUsername = prefs.getString('offline_username');
        final savedPassword = prefs.getString('offline_password');
        final userId = prefs.getInt('user_id');
        final userFullName = prefs.getString('user_full_name');
        final userEmail = prefs.getString('user_email');

        print('   🔐 Credenciais mantidas:');
        print('      Username: $savedUsername');
        print('      Password: ${savedPassword != null ? "${savedPassword.length} chars" : "NULL"}');
        print('   👤 Dados do usuário mantidos:');
        print('      User ID: $userId');
        print('      Nome: $userFullName');
        print('      Email: $userEmail');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error during logout: $e');
      }
    }

    notifyListeners();
  }

  // Verificar status de autenticação - chamado na inicialização do app
  Future<void> checkAuthStatus() async {
    if (kDebugMode) {
      print('Checking authentication status...');
    }

    try {
      // PRIMEIRO: Verificar se o app foi atualizado e forçar logout se necessário
      final bool wasUpdated = await _checkAppVersionAndForceLogoutIfUpdated();

      if (wasUpdated) {
        // App foi atualizado e logout foi forçado
        _isAuthenticated = false;
        _user = null;
        _isInitialized = true;
        notifyListeners();

        if (kDebugMode) {
          print('🆕 App atualizado - usuário deslogado automaticamente');
        }
        return; // Encerra aqui, usuário precisa fazer login novamente
      }

      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');
      final userId = prefs.getInt('user_id');

      if (token != null && userId != null) {
        if (kDebugMode) {
          print('Found saved token and user ID');
        }
        
        // Tentar carregar dados do usuário salvos localmente primeiro
        await _loadSavedUserData(prefs, userId);

        if (_isAuthenticated) {
          // Os dados do aparelho bastam para abrir o app. A verificação no
          // servidor (que renova o token) segue em segundo plano: esperar por
          // ela deixava o app parado na abertura quando havia rede conectada
          // mas sem internet de verdade.
          unawaited(
            _verifyTokenWithServer(token, prefs).then((_) => notifyListeners()),
          );
        } else {
          // Sem dados locais completos, só o servidor pode restaurar o usuário
          await _verifyTokenWithServer(token, prefs);
        }
      } else {
        if (kDebugMode) {
          print('No saved authentication data found');
        }
        _isAuthenticated = false;
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error checking auth status: $e');
      }
      // Em caso de erro, mantém o usuário logado se há dados locais
      // Não faz logout automático por erro de rede
    }
    
    _isInitialized = true;
    notifyListeners();
  }

  // Carregar dados do usuário salvos localmente
  Future<void> _loadSavedUserData(SharedPreferences prefs, int userId) async {
    try {
      // Tentar restaurar o usuário a partir dos dados salvos individualmente
      final fullName = prefs.getString('user_full_name');
      final username = prefs.getString('user_username');
      final email = prefs.getString('user_email');
      final role = prefs.getString('user_role');
      final isActive = prefs.getBool('user_is_active');

      if (fullName != null && username != null && email != null && role != null) {
        // Criar objeto User com os dados salvos
        _user = User(
          id: userId,
          fullName: fullName,
          username: username,
          email: email,
          role: role,
          isActive: isActive ?? true, // Default para true se não encontrado
        );
        _isAuthenticated = true;

        if (kDebugMode) {
          print('✅ User restored from saved data: ${_user!.fullName} (${_user!.username})');
        }
      } else {
        if (kDebugMode) {
          print('⚠️ Incomplete user data in storage');
        }
        _isAuthenticated = false;
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error loading saved user data: $e');
      }
      _isAuthenticated = false;
    }
  }

  // Verificar token com servidor (não obrigatório)
  Future<void> _verifyTokenWithServer(String token, SharedPreferences prefs) async {
    try {
      final response = await ApiService.verifyToken(token);

      if (response.containsKey('success') && response['success'] == true) {
        if (kDebugMode) {
          print('✅ Token verificado com sucesso no servidor');
        }

        // Renovação deslizante: se o servidor devolver um token novo nesta
        // verificação, ele substitui o atual e o prazo recomeça. Assim o
        // aplicador que abre o app de tempos em tempos nunca chega a expirar,
        // em vez de depender só do prazo fixo do backend.
        //
        // Antes esse campo era ignorado — se o servidor já mandasse um token
        // renovado, ele era jogado fora e a expiração vinha do mesmo jeito.
        final novoToken = response['token'];
        if (novoToken is String && novoToken.isNotEmpty) {
          await prefs.setString('auth_token', novoToken);
          if (kDebugMode) {
            print('🔄 Token renovado pelo servidor');
          }
        }

        // Atualizar dados do usuário se disponível
        if (response.containsKey('user') && response['user'] != null) {
          _user = User.fromJson(response['user']);
          await _saveUpdatedUserData();
        }

        _isAuthenticated = true;
        // O servidor aceitou: qualquer alerta anterior de sessão vencida
        // deixa de valer.
        _sessaoRejeitadaPeloServidor = false;
      } else {
        // Token inválido no servidor - NÃO fazer logout automático
        // O usuário só perde a sessão ao clicar em "Sair"
        if (kDebugMode) {
          print('⚠️ Token inválido no servidor, mas mantendo sessão offline');
          print('⚠️ Usuário permanece logado até fazer logout manual');
        }
        // Mantém autenticado com dados locais — derrubar aqui faria o
        // aplicador perder o acesso ao que ainda não sincronizou.
        _isAuthenticated = true;

        // Mas o app para de guardar isso só para si: a interface avisa, e o
        // aplicador refaz o login antes de acumular um dia de trabalho que
        // não vai subir.
        marcarSessaoExpirada();
      }
    } catch (e) {
      if (kDebugMode) {
        print('⚠️ Erro ao verificar token com servidor: $e');
        print('✅ Mantendo usuário logado com dados locais (modo offline)');
      }
      // Em caso de erro de rede, manter usuário logado
      // Não fazer logout automático
      if (_isAuthenticated) {
        if (kDebugMode) {
          print('✅ Sessão mantida mesmo sem conexão com servidor');
        }
      }
    }
  }

  // Método para forçar re-verificação do token (opcional)
  Future<bool> refreshAuthStatus() async {
    if (!_isAuthenticated) return false;

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');

      if (token != null) {
        final response = await ApiService.verifyToken(token);

        if (response.containsKey('success') && response['success'] == true) {
          return true;
        } else {
          await logout();
          return false;
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error refreshing auth status: $e');
      }
      // Manter logado em caso de erro de rede
      return true;
    }

    return false;
  }

  // Método para debug - verificar credenciais salvas
  Future<void> debugOfflineCredentials() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedUsername = prefs.getString('offline_username');
      final savedPassword = prefs.getString('offline_password');

      if (kDebugMode) {
        print('🔍 === DEBUG CREDENCIAIS OFFLINE ===');
        print('📋 Username salvo: $savedUsername');
        print('📋 Password salvo: ${savedPassword != null ? "${savedPassword.length} caracteres" : "NULL"}');
        print('📋 User ID: ${prefs.getInt('user_id')}');
        print('📋 User fullname: ${prefs.getString('user_full_name')}');
        print('📋 User email: ${prefs.getString('user_email')}');

        // Listar todas as chaves
        final allKeys = prefs.getKeys();
        print('📋 Todas as chaves salvas: $allKeys');
        print('🔍 === FIM DEBUG ===');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Erro no debug: $e');
      }
    }
  }
}
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/form_response.dart';
import '../models/stratification.dart';

class ApiService {
  // Producao por padrao. Para apontar outro ambiente, passe no build:
  //   --dart-define=API_BASE_URL=https://painel.sxdata.online/api
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://painel.sxdata.com.br/api',
  );
  //static const String baseUrl = 'http://localhost/painel_sxdata/api';

  static Future<Map<String, String>> _getHeaders() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');

    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  static Future<Map<String, dynamic>> login(
    String username,
    String password,
  ) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/auth/login'),
        headers: await _getHeaders(),
        body: jsonEncode({'username': username, 'password': password}),
      );

      final responseData = jsonDecode(response.body);

      // Verificar o status code da resposta HTTP
      if (response.statusCode == 200) {
        return responseData;
      } else {
        throw Exception(responseData['message'] ?? 'Login failed');
      }
    } catch (e) {
      throw Exception('Connection error: $e');
    }
  }

  static Future<Map<String, dynamic>> verifyToken(String token) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/auth/verify'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      final responseData = jsonDecode(response.body);

      if (response.statusCode == 200) {
        return responseData;
      } else {
        throw Exception(responseData['message'] ?? 'Token verification failed');
      }
    } catch (e) {
      throw Exception('Token verification failed: $e');
    }
  }

  static Future<Map<String, dynamic>> getQuestionnaires() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/questionnaires'),
        headers: await _getHeaders(),
      );

      final responseData = jsonDecode(response.body);

      if (response.statusCode == 200) {
        return responseData;
      } else {
        throw Exception(
          responseData['message'] ?? 'Failed to load questionnaires',
        );
      }
    } catch (e) {
      throw Exception('Failed to load questionnaires: $e');
    }
  }

  static Future<Map<String, dynamic>> submitForm(FormResponse form) async {
    final formJson = form.toJson();

    // IDs locais são timestamps (millisecondsSinceEpoch, ~10^12) gerados
    // pelo app para controle offline — o servidor não os conhece e um
    // INTEGER no banco nem comporta o valor, derrubando a sincronização.
    // Só enviar o id quando for um id real do servidor (modo de edição).
    final dynamic formId = formJson['id'];
    if (formId is int && formId >= 100000000000) {
      formJson.remove('id');
    }

    // Debug: verificar se photo_path_2 está sendo enviado
    print('📤 === ENVIANDO FORMULÁRIO PARA API ===');
    print('📸 photo_path: ${formJson['photo_path']}');
    print('📸 photo_path_2: ${formJson['photo_path_2']}');
    print('📋 JSON completo: ${jsonEncode(formJson)}');

    // Só a chamada de rede fica no try: os erros de resposta são levantados
    // depois, fora dele. Com eles aqui dentro, o catch genérico os embrulhava
    // de novo e a mensagem chegava como "Exception: Failed to submit form:
    // Exception: Invalid token".
    final http.Response response;
    try {
      response = await http
          .post(
            Uri.parse('$baseUrl/forms/submit'),
            headers: await _getHeaders(),
            body: jsonEncode(formJson),
          )
          // 60s: em 3G/4G ruim de campo, desistir cedo faz o app perder a
          // resposta de um envio que o servidor ESTÁ gravando. O id vem só
          // após o commit, então abortar antes disso custa a confirmação.
          .timeout(const Duration(seconds: 60));
    } on TimeoutException {
      throw Exception(
        'O servidor não respondeu em 60 segundos. A resposta continua '
        'salva no aparelho — tente novamente com um sinal melhor.',
      );
    } catch (e) {
      throw Exception('Sem conexão com o servidor: $e');
    }

    // A resposta nem sempre é JSON: erro 500 do PHP, página de manutenção ou
    // um warning impresso antes do payload chegam como HTML. Decodificar
    // direto estourava FormatException, que subia como se fosse falha de
    // rede e escondia o problema real do servidor.
    Map<String, dynamic>? responseData;
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) responseData = decoded;
    } catch (_) {
      // Tratado abaixo, com o status e um trecho do corpo.
    }

    if (response.statusCode == 200 && responseData != null) {
      return responseData;
    }

    // Erros PERMANENTES: reenviar o mesmo corpo daria o mesmo resultado.
    // Sinalizados para a fila não entrar em loop.
    if (responseData != null) {
      final msg = responseData['message']?.toString() ??
          'o servidor recusou o envio';

      // 413: payload acima do post_max_size.
      if (response.statusCode == 413 ||
          responseData['limit_exceeded'] == true) {
        throw PermanentSubmitException(
          'A resposta é grande demais para o servidor aceitar. '
          'Avise o suporte — reenviar não resolve. ($msg)',
          statusCode: response.statusCode,
        );
      }

      // 400: JSON malformado gerado pelo app.
      if (response.statusCode == 400 || responseData['json_error'] != null) {
        throw PermanentSubmitException(
          'O servidor não conseguiu ler esta resposta '
          '(${responseData['json_error'] ?? msg}). Avise o suporte.',
          statusCode: response.statusCode,
        );
      }

      // 500 com fatal: a transação foi revertida, nada gravou. É seguro
      // reenviar, então segue como erro comum (temporário).
      throw Exception('HTTP ${response.statusCode}: $msg');
    }

    final trecho = response.body.trim().replaceAll(RegExp(r'\s+'), ' ');
    throw Exception(
      'HTTP ${response.statusCode} sem JSON válido: '
      '${trecho.length > 160 ? '${trecho.substring(0, 160)}...' : trecho}',
    );
  }

  static Future<Map<String, dynamic>> uploadPhoto(File photo) async {
    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/photos/upload'),
      );

      final headers = await _getHeaders();
      request.headers.addAll(headers);
      request.files.add(await http.MultipartFile.fromPath('photo', photo.path));

      final response = await request.send();
      final responseBody = await response.stream.bytesToString();
      final responseData = jsonDecode(responseBody);

      if (response.statusCode == 200) {
        return responseData;
      } else {
        throw Exception(responseData['message'] ?? 'Failed to upload photo');
      }
    } catch (e) {
      throw Exception('Failed to upload photo: $e');
    }
  }

  /// Upload de foto a partir de bytes (versão web — mídias vêm do
  /// IndexedDB via WebMediaStore, não de arquivos).
  static Future<Map<String, dynamic>> uploadPhotoBytes(
      Uint8List bytes, String filename) async {
    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/photos/upload'),
      );

      final headers = await _getHeaders();
      request.headers.addAll(headers);
      request.files.add(
        http.MultipartFile.fromBytes('photo', bytes, filename: filename),
      );

      final response = await request.send();
      final responseBody = await response.stream.bytesToString();
      final responseData = jsonDecode(responseBody);

      if (response.statusCode == 200) {
        return responseData;
      } else {
        throw Exception(responseData['message'] ?? 'Failed to upload photo');
      }
    } catch (e) {
      throw Exception('Failed to upload photo: $e');
    }
  }

  /// Upload de áudio a partir de bytes (versão web).
  static Future<Map<String, dynamic>> uploadAudioBytes(
      Uint8List bytes, String filename) async {
    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/audios/upload'),
      );

      final headers = await _getHeaders();
      request.headers.addAll(headers);
      request.files.add(
        http.MultipartFile.fromBytes('audio', bytes, filename: filename),
      );

      final response = await request.send();
      final responseBody = await response.stream.bytesToString();
      final responseData = jsonDecode(responseBody);

      if (response.statusCode == 200) {
        return responseData;
      } else {
        throw Exception(responseData['message'] ?? 'Failed to upload audio');
      }
    } catch (e) {
      throw Exception('Failed to upload audio: $e');
    }
  }

  /// Upload de áudio gravado durante aplicação do questionário
  static Future<Map<String, dynamic>> uploadAudio(File audio, {int? formResponseId}) async {
    try {
      print('🎤 Uploading audio: ${audio.path}');
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/audios/upload'),
      );

      final headers = await _getHeaders();
      request.headers.addAll(headers);
      request.files.add(await http.MultipartFile.fromPath('audio', audio.path));
      if (formResponseId != null) {
        request.fields['form_response_id'] = formResponseId.toString();
      }

      final response = await request.send();
      final responseBody = await response.stream.bytesToString();
      final responseData = jsonDecode(responseBody);

      if (response.statusCode == 200) {
        print('✅ Audio uploaded successfully');
        return responseData;
      } else {
        throw Exception(responseData['message'] ?? 'Failed to upload audio');
      }
    } catch (e) {
      print('❌ Failed to upload audio: $e');
      throw Exception('Failed to upload audio: $e');
    }
  }

  /// Obter estatísticas do usuário
  static Future<Map<String, dynamic>> getUserStats(int userId) async {
    print('📊 Chamando API para estatísticas do usuário $userId');

    try {
      final url = Uri.parse('$baseUrl/stats/user/$userId');
      print('🌐 URL: $url');

      final response = await http
          .get(url, headers: await _getHeaders())
          .timeout(const Duration(seconds: 30));

      print('📡 Status da resposta: ${response.statusCode}');
      print('📡 Corpo da resposta: ${response.body}');

      final responseData = jsonDecode(response.body);

      if (response.statusCode == 200) {
        print('✅ Estatísticas obtidas com sucesso');
        return responseData;
      } else if (response.statusCode == 401) {
        throw Exception('Token expirado ou inválido');
      } else if (response.statusCode == 403) {
        throw Exception('Acesso negado às estatísticas');
      } else {
        throw Exception(
          responseData['message'] ?? 'Erro ao obter estatísticas',
        );
      }
    } catch (e) {
      print('❌ Erro ao obter estatísticas: $e');

      if (e.toString().contains('TimeoutException')) {
        throw Exception('Timeout na conexão com o servidor');
      } else if (e.toString().contains('SocketException')) {
        throw Exception('Erro de conexão com a internet');
      } else {
        rethrow;
      }
    }
  }

  /// Obter estatísticas gerais do sistema (apenas para admins)
  static Future<Map<String, dynamic>> getOverviewStats() async {
    print('📊 Chamando API para estatísticas gerais');

    try {
      final url = Uri.parse('$baseUrl/stats/overview');
      print('🌐 URL: $url');

      final response = await http
          .get(url, headers: await _getHeaders())
          .timeout(const Duration(seconds: 30));

      print('📡 Status da resposta: ${response.statusCode}');

      final responseData = jsonDecode(response.body);

      if (response.statusCode == 200) {
        print('✅ Estatísticas gerais obtidas com sucesso');
        return responseData;
      } else if (response.statusCode == 401) {
        throw Exception('Token expirado ou inválido');
      } else if (response.statusCode == 403) {
        throw Exception('Acesso de administrador necessário');
      } else {
        throw Exception(
          responseData['message'] ?? 'Erro ao obter estatísticas gerais',
        );
      }
    } catch (e) {
      print('❌ Erro ao obter estatísticas gerais: $e');

      if (e.toString().contains('TimeoutException')) {
        throw Exception('Timeout na conexão com o servidor');
      } else if (e.toString().contains('SocketException')) {
        throw Exception('Erro de conexão com a internet');
      } else {
        rethrow;
      }
    }
  }

  /// Obter dados de localização para o mapa
  static Future<Map<String, dynamic>> getLocationsData(
    Map<String, String> filters,
  ) async {
    try {
      print('🗺️ Buscando dados de localização');

      final queryParams = filters.entries
          .where((entry) => entry.value.isNotEmpty)
          .map((entry) => '${entry.key}=${Uri.encodeComponent(entry.value)}')
          .join('&');

      final url =
          '$baseUrl/stats/locations${queryParams.isNotEmpty ? '?$queryParams' : ''}';

      final response = await http.get(
        Uri.parse(url),
        headers: await _getHeaders(),
      );

      print('📍 Status da resposta de localizações: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        print('✅ Dados de localização carregados com sucesso');
        return data;
      } else {
        print('❌ Erro ao buscar dados de localização: ${response.statusCode}');
        return {
          'success': false,
          'message':
              'Erro ao carregar dados de localização: ${response.statusCode}',
        };
      }
    } catch (e) {
      print('❌ Erro de conexão ao buscar dados de localização: $e');
      return {'success': false, 'message': 'Erro de conexão: $e'};
    }
  }

  /// Obter estatísticas de aplicadores
  static Future<Map<String, dynamic>> getApplicatorsStats(
    Map<String, String> filters,
  ) async {
    try {
      print('👥 Buscando estatísticas de aplicadores');

      final queryParams = filters.entries
          .where((entry) => entry.value.isNotEmpty)
          .map((entry) => '${entry.key}=${Uri.encodeComponent(entry.value)}')
          .join('&');

      final url =
          '$baseUrl/stats/applicators${queryParams.isNotEmpty ? '?$queryParams' : ''}';

      final response = await http.get(
        Uri.parse(url),
        headers: await _getHeaders(),
      );

      print('📊 Status da resposta de aplicadores: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        print('✅ Estatísticas de aplicadores carregadas com sucesso');
        return data;
      } else {
        print(
          '❌ Erro ao buscar estatísticas de aplicadores: ${response.statusCode}',
        );
        return {
          'success': false,
          'message':
              'Erro ao carregar estatísticas de aplicadores: ${response.statusCode}',
        };
      }
    } catch (e) {
      print('❌ Erro de conexão ao buscar estatísticas de aplicadores: $e');
      return {'success': false, 'message': 'Erro de conexão: $e'};
    }
  }

  /// NOVO: Obter histórico de aplicações do usuário
  static Future<Map<String, dynamic>> getApplicationHistory({
    int? userId,
    String? period,
    String? syncStatus,
    int? questionnaireId,
    int limit = 50,
    int offset = 0,
  }) async {
    try {
      print('📋 Buscando histórico de aplicações');

      // Montar query parameters
      final queryParams = <String, String>{
        'limit': limit.toString(),
        'offset': offset.toString(),
      };

      if (period != null && period != 'all') {
        queryParams['period'] = period;
      }
      if (syncStatus != null) {
        queryParams['sync_status'] = syncStatus;
      }
      if (questionnaireId != null) {
        queryParams['questionnaire_id'] = questionnaireId.toString();
      }

      // Montar URL
      String endpoint = '/stats/history';
      if (userId != null) {
        endpoint += '/$userId';
      }

      final uri = Uri.parse(
        '$baseUrl$endpoint',
      ).replace(queryParameters: queryParams);

      print('🔍 URL do histórico: $uri');

      final response = await http
          .get(uri, headers: await _getHeaders())
          .timeout(const Duration(seconds: 30));

      print('📡 Status resposta histórico: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        print(
          '✅ Histórico carregado com sucesso - ${data['data']?['applications']?.length ?? 0} itens',
        );
        return data;
      } else if (response.statusCode == 401) {
        throw ApiException('Token expirado. Faça login novamente.');
      } else if (response.statusCode == 403) {
        throw ApiException('Acesso negado ao histórico.');
      } else {
        final errorData = json.decode(response.body);
        throw ApiException(
          errorData['message'] ?? 'Erro ao carregar histórico',
        );
      }
    } on SocketException {
      throw ApiException('Sem conexão com a internet');
    } on FormatException {
      throw ApiException('Erro no formato da resposta do servidor');
    } on HttpException {
      throw ApiException('Erro de comunicação com o servidor');
    } catch (e) {
      print('❌ Erro ao buscar histórico: $e');
      if (e is ApiException) {
        rethrow;
      }

      if (e.toString().contains('TimeoutException')) {
        throw ApiException('Timeout na conexão com o servidor');
      }

      throw ApiException('Erro inesperado: $e');
    }
  }

  static Future<Map<String, dynamic>> getQuestionnaireAnalysisList([
    Map<String, dynamic>? filters,
  ]) async {
    try {
      print('🔍 Chamando API: getQuestionnaireAnalysisList');

      // Construir URL com parâmetros de filtro
      var uri = Uri.parse('$baseUrl/stats/questionnaires-analysis');

      if (filters != null && filters.isNotEmpty) {
        // Remover valores null e converter para String
        final cleanFilters = <String, String>{};
        filters.forEach((key, value) {
          if (value != null && value.toString().isNotEmpty) {
            cleanFilters[key] = value.toString();
          }
        });

        if (cleanFilters.isNotEmpty) {
          uri = uri.replace(queryParameters: cleanFilters);
        }
      }

      print('📡 URL: $uri');

      final response = await http.get(uri, headers: await _getHeaders());

      final result = _handleResponse(response);
      print('✅ getQuestionnaireAnalysisList - Resposta recebida');
      return result;
    } catch (e) {
      print('❌ Erro em getQuestionnaireAnalysisList: $e');
      throw Exception(
        'Erro ao carregar lista de questionários para análise: $e',
      );
    }
  }

  static Map<String, dynamic> _handleResponse(http.Response response) {
    print('📡 Status Code: ${response.statusCode}');
    print('📡 Response Body: ${response.body}');

    if (response.statusCode >= 200 && response.statusCode < 300) {
      try {
        final decodedResponse = json.decode(response.body);
        return decodedResponse is Map<String, dynamic>
            ? decodedResponse
            : {'success': true, 'data': decodedResponse};
      } catch (e) {
        print('❌ Erro ao decodificar JSON: $e');
        return {
          'success': false,
          'message': 'Erro ao processar resposta do servidor',
        };
      }
    } else {
      try {
        final errorResponse = json.decode(response.body);
        return {
          'success': false,
          'message': errorResponse['message'] ?? 'Erro desconhecido',
          'status_code': response.statusCode,
        };
      } catch (e) {
        return {
          'success': false,
          'message':
              'Erro de comunicação com o servidor (${response.statusCode})',
          'status_code': response.statusCode,
        };
      }
    }
  }

  /// Obter análise detalhada de um questionário específico
  static Future<Map<String, dynamic>> getQuestionnaireDetailAnalysis(
    int questionnaireId, [
    Map<String, dynamic>? filters,
  ]) async {
    try {
      print(
        '🔍 Chamando API: getQuestionnaireDetailAnalysis para questionário $questionnaireId',
      );

      // Construir URL com parâmetros de filtro
      var uri = Uri.parse(
        '$baseUrl/stats/questionnaire-analysis/$questionnaireId',
      );

      if (filters != null && filters.isNotEmpty) {
        // Remover valores null e converter para String
        final cleanFilters = <String, String>{};
        filters.forEach((key, value) {
          if (value != null && value.toString().isNotEmpty) {
            cleanFilters[key] = value.toString();
          }
        });

        if (cleanFilters.isNotEmpty) {
          uri = uri.replace(queryParameters: cleanFilters);
        }
      }

      print('📡 URL: $uri');

      final response = await http.get(uri, headers: await _getHeaders());

      final result = _handleResponse(response);
      print('✅ getQuestionnaireDetailAnalysis - Resposta recebida');
      return result;
    } catch (e) {
      print('❌ Erro em getQuestionnaireDetailAnalysis: $e');
      throw Exception('Erro ao carregar análise detalhada do questionário: $e');
    }
  }

  static Future<Map<String, dynamic>> getApplicators() async {
    try {
      print('🔍 Chamando API: getApplicators');

      final response = await http.get(
        Uri.parse('$baseUrl/stats/applicators_app'),
        headers: await _getHeaders(),
      );

      final result = _handleResponse(response);
      print('✅ getApplicators - Resposta recebida');
      return result;
    } catch (e) {
      print('❌ Erro em getApplicators: $e');
      throw Exception('Erro ao carregar lista de aplicadores: $e');
    }
  }

  static Future<Map<String, dynamic>> getQuestionnaireQuestions(
    int questionnaireId,
  ) async {
    try {
      print('🔍 Buscando questões do questionário: $questionnaireId');

      final url = '$baseUrl/questionnaires/$questionnaireId/questions';

      final response = await http.get(
        Uri.parse(url),
        // , headers: await _getHeaders(),
      );

      print('📡 Status questões: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        print(
          '✅ Questões carregadas com sucesso - ${data['data']?.length ?? 0} questões',
        );
        return data;
      } else if (response.statusCode == 401) {
        throw ApiException('Token expirado. Faça login novamente.');
      } else if (response.statusCode == 404) {
        throw ApiException('Questionário não encontrado');
      } else {
        final errorData = json.decode(response.body);
        throw ApiException(errorData['message'] ?? 'Erro ao carregar questões');
      }
    } on SocketException {
      throw ApiException('Sem conexão com a internet');
    } on FormatException {
      throw ApiException('Erro no formato da resposta do servidor');
    } catch (e) {
      print('❌ Erro ao buscar questões: $e');
      if (e is ApiException) {
        rethrow;
      }

      if (e.toString().contains('TimeoutException')) {
        throw ApiException('Timeout na conexão com o servidor');
      }

      throw ApiException('Erro inesperado: $e');
    }
  }

  /// NOVO: Obter dados brutos para exportação (compatível com PHP)
  static Future<Map<String, dynamic>> getRawDataForExport(
    Map<String, String> filters,
  ) async {
    try {
      print('📊 Buscando dados brutos para exportação');
      print('🔍 Filtros aplicados: $filters');

      // Construir query parameters
      final queryParams = filters.entries
          .where((entry) => entry.value.isNotEmpty)
          .map((entry) => '${entry.key}=${Uri.encodeComponent(entry.value)}')
          .join('&');

      final url =
          '$baseUrl/responses/raw-data${queryParams.isNotEmpty ? '?$queryParams' : ''}';

      print('🌐 URL: $url');

      final response = await http
          .get(
            Uri.parse(url),
            //, headers: await _getHeaders()
          )
          .timeout(
            const Duration(seconds: 60),
          ); // Timeout maior para dados grandes

      print('📡 Status dados brutos: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        print(
          '✅ Dados brutos carregados com sucesso - ${data['data']?.length ?? 0} registros',
        );
        return data;
      } else if (response.statusCode == 401) {
        throw ApiException('Token expirado. Faça login novamente.');
      } else if (response.statusCode == 403) {
        throw ApiException('Acesso negado aos dados brutos.');
      } else {
        final errorData = json.decode(response.body);
        throw ApiException(
          errorData['message'] ?? 'Erro ao carregar dados brutos',
        );
      }
    } on SocketException {
      throw ApiException('Sem conexão com a internet');
    } on FormatException {
      throw ApiException('Erro no formato da resposta do servidor');
    } catch (e) {
      print('❌ Erro ao buscar dados brutos: $e');
      if (e is ApiException) {
        rethrow;
      }

      if (e.toString().contains('TimeoutException')) {
        throw ApiException('Timeout na conexão - dados muito grandes');
      }

      throw ApiException('Erro inesperado: $e');
    }
  }

  /// NOVO: Contar registros antes da exportação (para validação)
  static Future<Map<String, dynamic>> countExportRecords(
    Map<String, String> filters,
  ) async {
    try {
      print('🔢 Contando registros para exportação');

      // Construir query parameters
      final queryParams = filters.entries
          .where((entry) => entry.value.isNotEmpty)
          .map((entry) => '${entry.key}=${Uri.encodeComponent(entry.value)}')
          .join('&');

      final url =
          '$baseUrl/responses/count${queryParams.isNotEmpty ? '?$queryParams' : ''}';

      final response = await http
          .get(Uri.parse(url), headers: await _getHeaders())
          .timeout(const Duration(seconds: 30));

      print('📡 Status contagem: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        print('✅ Contagem realizada: ${data['data']?['count'] ?? 0} registros');
        return data;
      } else {
        final errorData = json.decode(response.body);
        throw ApiException(errorData['message'] ?? 'Erro ao contar registros');
      }
    } catch (e) {
      print('❌ Erro ao contar registros: $e');
      if (e is ApiException) {
        rethrow;
      }
      throw ApiException('Erro ao contar registros: $e');
    }
  }

  /// NOVO: Validar filtros de exportação
  static Future<Map<String, dynamic>> validateExportFilters(
    Map<String, String> filters,
  ) async {
    try {
      print('✅ Validando filtros de exportação');

      final response = await http
          .post(
            Uri.parse('$baseUrl/responses/validate-export'),
            headers: await _getHeaders(),
            body: json.encode(filters),
          )
          .timeout(const Duration(seconds: 30));

      print('📡 Status validação: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        print('✅ Filtros validados com sucesso');
        return data;
      } else {
        final errorData = json.decode(response.body);
        return {
          'success': false,
          'message': errorData['message'] ?? 'Filtros inválidos',
          'errors': errorData['errors'] ?? [],
        };
      }
    } catch (e) {
      print('❌ Erro na validação de filtros: $e');
      return {'success': false, 'message': 'Erro na validação: $e'};
    }
  }

  /// NOVO: Obter preview dos dados de exportação (primeiros registros)
  static Future<Map<String, dynamic>> getExportPreview(
    Map<String, String> filters, {
    int limit = 5,
  }) async {
    try {
      print('👀 Buscando preview da exportação');

      // Adicionar limite ao filtro
      final previewFilters = Map<String, String>.from(filters);
      previewFilters['limit'] = limit.toString();
      previewFilters['preview'] = 'true';

      // Construir query parameters
      final queryParams = previewFilters.entries
          .where((entry) => entry.value.isNotEmpty)
          .map((entry) => '${entry.key}=${Uri.encodeComponent(entry.value)}')
          .join('&');

      final url =
          '$baseUrl/responses/export-preview${queryParams.isNotEmpty ? '?$queryParams' : ''}';

      final response = await http
          .get(Uri.parse(url), headers: await _getHeaders())
          .timeout(const Duration(seconds: 30));

      print('📡 Status preview: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        print('✅ Preview carregado com sucesso');
        return data;
      } else {
        final errorData = json.decode(response.body);
        throw ApiException(errorData['message'] ?? 'Erro ao carregar preview');
      }
    } catch (e) {
      print('❌ Erro ao buscar preview: $e');
      if (e is ApiException) {
        rethrow;
      }
      throw ApiException('Erro no preview: $e');
    }
  }

  /// NOVO: Obter estatísticas da exportação
  static Future<Map<String, dynamic>> getExportStatistics(
    Map<String, String> filters,
  ) async {
    try {
      print('📊 Buscando estatísticas da exportação');

      // Construir query parameters
      final queryParams = filters.entries
          .where((entry) => entry.value.isNotEmpty)
          .map((entry) => '${entry.key}=${Uri.encodeComponent(entry.value)}')
          .join('&');

      final url =
          '$baseUrl/responses/export-statistics${queryParams.isNotEmpty ? '?$queryParams' : ''}';

      final response = await http
          .get(Uri.parse(url), headers: await _getHeaders())
          .timeout(const Duration(seconds: 30));

      print('📡 Status estatísticas export: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        print('✅ Estatísticas da exportação carregadas');
        return data;
      } else {
        final errorData = json.decode(response.body);
        throw ApiException(
          errorData['message'] ?? 'Erro ao carregar estatísticas',
        );
      }
    } catch (e) {
      print('❌ Erro ao buscar estatísticas da exportação: $e');
      if (e is ApiException) {
        rethrow;
      }
      throw ApiException('Erro nas estatísticas: $e');
    }
  }

  /// NOVO: Log de atividade de exportação
  static Future<Map<String, dynamic>> logExportActivity({
    required String exportType,
    required Map<String, String> filters,
    required int recordCount,
    required String status,
    String? errorMessage,
  }) async {
    try {
      print('📝 Registrando log da exportação');

      final logData = {
        'export_type': exportType,
        'filters': filters,
        'record_count': recordCount,
        'status': status,
        if (errorMessage != null) 'error_message': errorMessage,
        'timestamp': DateTime.now().toIso8601String(),
      };

      final response = await http
          .post(
            Uri.parse('$baseUrl/responses/log-export'),
            headers: await _getHeaders(),
            body: json.encode(logData),
          )
          .timeout(const Duration(seconds: 30));

      print('📡 Status log exportação: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        print('✅ Log da exportação registrado');
        return data;
      } else {
        // Log de erro não deve quebrar o fluxo principal
        print('⚠️ Erro ao registrar log da exportação: ${response.statusCode}');
        return {'success': false};
      }
    } catch (e) {
      // Log de erro não deve quebrar o fluxo principal
      print('⚠️ Erro no log da exportação: $e');
      return {'success': false};
    }
  }

  /// NOVO: Verificar limites de exportação do usuário
  static Future<Map<String, dynamic>> checkExportLimits() async {
    try {
      print('🔒 Verificando limites de exportação');

      final response = await http
          .get(
            Uri.parse('$baseUrl/responses/export-limits'),
            headers: await _getHeaders(),
          )
          .timeout(const Duration(seconds: 30));

      print('📡 Status limites: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        print('✅ Limites verificados');
        return data;
      } else {
        final errorData = json.decode(response.body);
        throw ApiException(errorData['message'] ?? 'Erro ao verificar limites');
      }
    } catch (e) {
      print('❌ Erro ao verificar limites: $e');
      if (e is ApiException) {
        rethrow;
      }
      throw ApiException('Erro nos limites: $e');
    }
  }

  /// NOVO: Obter histórico de exportações do usuário
  static Future<Map<String, dynamic>> getExportHistory({int limit = 10}) async {
    try {
      print('📋 Buscando histórico de exportações');

      final response = await http
          .get(
            Uri.parse('$baseUrl/responses/export-history?limit=$limit'),
            headers: await _getHeaders(),
          )
          .timeout(const Duration(seconds: 30));

      print('📡 Status histórico export: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        print('✅ Histórico de exportações carregado');
        return data;
      } else {
        final errorData = json.decode(response.body);
        throw ApiException(
          errorData['message'] ?? 'Erro ao carregar histórico',
        );
      }
    } catch (e) {
      print('❌ Erro ao buscar histórico de exportações: $e');
      if (e is ApiException) {
        rethrow;
      }
      throw ApiException('Erro no histórico: $e');
    }
  }

  /// Obter análise geral de questões (todas)
  static Future<Map<String, dynamic>> getGeneralQuestionAnalysis([
    Map<String, dynamic>? filters,
  ]) async {
    try {
      print('🔍 Chamando API: getGeneralQuestionAnalysis');

      var uri = Uri.parse('$baseUrl/stats/questions-analysis');

      if (filters != null && filters.isNotEmpty) {
        final cleanFilters = <String, String>{};
        filters.forEach((key, value) {
          if (value != null && value.toString().isNotEmpty) {
            cleanFilters[key] = value.toString();
          }
        });

        if (cleanFilters.isNotEmpty) {
          uri = uri.replace(queryParameters: cleanFilters);
        }
      }

      print('📡 URL: $uri');

      final response = await http.get(uri, headers: await _getHeaders());

      final result = _handleResponse(response);
      print('✅ getGeneralQuestionAnalysis - Resposta recebida');
      return result;
    } catch (e) {
      print('❌ Erro em getGeneralQuestionAnalysis: $e');
      throw Exception('Erro ao carregar análise geral de questões: $e');
    }
  }

  static Future<Map<String, dynamic>> exportQuestionnaireAnalysis(
    int questionnaireId,
    String format, {
    Map<String, dynamic>? filters,
  }) async {
    try {
      print('🔍 Chamando API: exportQuestionnaireAnalysis - formato: $format');

      final body = {
        'questionnaire_id': questionnaireId,
        'format': format, // 'excel', 'pdf', 'csv'
        if (filters != null) ...filters,
      };

      final response = await http.post(
        Uri.parse('$baseUrl/stats/export-questionnaire-analysis'),
        headers: await _getHeaders(),
        body: json.encode(body),
      );

      final result = _handleResponse(response);
      print('✅ exportQuestionnaireAnalysis - Resposta recebida');
      return result;
    } catch (e) {
      print('❌ Erro em exportQuestionnaireAnalysis: $e');
      throw Exception('Erro ao exportar análise do questionário: $e');
    }
  }

  /// NOVO: Obter resumo do histórico
  static Future<Map<String, dynamic>> getHistorySummary({int? userId}) async {
    try {
      print('📊 Buscando resumo do histórico');

      String endpoint = '/stats/history';
      if (userId != null) {
        endpoint += '/$userId';
      }
      endpoint += '/summary';

      final uri = Uri.parse('$baseUrl$endpoint');

      print('🔍 URL resumo histórico: $uri');

      final response = await http
          .get(uri, headers: await _getHeaders())
          .timeout(const Duration(seconds: 30));

      print('📡 Status resposta resumo: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        print('✅ Resumo do histórico carregado com sucesso');
        return data;
      } else if (response.statusCode == 401) {
        throw ApiException('Token expirado. Faça login novamente.');
      } else if (response.statusCode == 403) {
        throw ApiException('Acesso negado ao resumo do histórico.');
      } else {
        final errorData = json.decode(response.body);
        throw ApiException(
          errorData['message'] ?? 'Erro ao carregar resumo do histórico',
        );
      }
    } on SocketException {
      throw ApiException('Sem conexão com a internet');
    } on FormatException {
      throw ApiException('Erro no formato da resposta do servidor');
    } on HttpException {
      throw ApiException('Erro de comunicação com o servidor');
    } catch (e) {
      print('❌ Erro ao buscar resumo do histórico: $e');
      if (e is ApiException) {
        rethrow;
      }

      if (e.toString().contains('TimeoutException')) {
        throw ApiException('Timeout na conexão com o servidor');
      }

      throw ApiException('Erro inesperado: $e');
    }
  }

  /// NOVO: Obter detalhes de uma aplicação específica
  static Future<Map<String, dynamic>> getApplicationDetails(
    int responseId,
  ) async {
    try {
      print('🔍 Buscando detalhes da aplicação: $responseId');

      final uri = Uri.parse('$baseUrl/responses/$responseId');

      final response = await http
          .get(uri, headers: await _getHeaders())
          .timeout(const Duration(seconds: 30));

      print('📡 Status detalhes aplicação: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        print('✅ Detalhes da aplicação carregados com sucesso');
        return data;
      } else if (response.statusCode == 401) {
        throw ApiException('Token expirado. Faça login novamente.');
      } else if (response.statusCode == 404) {
        throw ApiException('Aplicação não encontrada');
      } else if (response.statusCode == 403) {
        throw ApiException('Acesso negado aos detalhes da aplicação.');
      } else {
        final errorData = json.decode(response.body);
        throw ApiException(
          errorData['message'] ?? 'Erro ao carregar detalhes da aplicação',
        );
      }
    } on SocketException {
      throw ApiException('Sem conexão com a internet');
    } on FormatException {
      throw ApiException('Erro no formato da resposta do servidor');
    } on HttpException {
      throw ApiException('Erro de comunicação com o servidor');
    } catch (e) {
      print('❌ Erro ao buscar detalhes da aplicação: $e');
      if (e is ApiException) {
        rethrow;
      }

      if (e.toString().contains('TimeoutException')) {
        throw ApiException('Timeout na conexão com o servidor');
      }

      throw ApiException('Erro inesperado: $e');
    }
  }

  /// NOVO: Sincronizar formulários pendentes
  static Future<Map<String, dynamic>> syncPendingForms() async {
    try {
      print('🔄 Iniciando sincronização de formulários pendentes');

      final response = await http
          .post(Uri.parse('$baseUrl/sync/forms'), headers: await _getHeaders())
          .timeout(const Duration(seconds: 60)); // Timeout maior para sync

      print('📡 Status sincronização: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        print('✅ Sincronização concluída com sucesso');
        return data;
      } else if (response.statusCode == 401) {
        throw ApiException('Token expirado. Faça login novamente.');
      } else {
        final errorData = json.decode(response.body);
        throw ApiException(errorData['message'] ?? 'Erro na sincronização');
      }
    } on SocketException {
      throw ApiException('Sem conexão com a internet');
    } on FormatException {
      throw ApiException('Erro no formato da resposta do servidor');
    } catch (e) {
      print('❌ Erro na sincronização: $e');
      if (e is ApiException) {
        rethrow;
      }

      if (e.toString().contains('TimeoutException')) {
        throw ApiException('Timeout na sincronização - tente novamente');
      }

      throw ApiException('Erro inesperado na sincronização: $e');
    }
  }

  /// Obter token armazenado
  static Future<String?> _getStoredToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');

      if (token != null) {
        // Verificar se o token não expirou (opcional - implementar se necessário)
        // Você pode decodificar o token e verificar a expiração aqui
        return token;
      }

      return null;
    } catch (e) {
      print('❌ Erro ao obter token: $e');
      return null;
    }
  }

  /// Método auxiliar para verificar se o usuário está conectado
  static Future<bool> isLoggedIn() async {
    final token = await _getStoredToken();
    return token != null;
  }

  /// Método auxiliar para fazer logout
  static Future<void> logout() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('auth_token');
      await prefs.remove(
        'user_data',
      ); // Remover outros dados do usuário se existir
      print('✅ Logout realizado com sucesso');
    } catch (e) {
      print('❌ Erro ao fazer logout: $e');
    }
  }

  /// NOVO: Verificar conectividade
  static Future<bool> checkConnectivity() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/health'), headers: await _getHeaders())
          .timeout(const Duration(seconds: 10));

      return response.statusCode == 200;
    } catch (e) {
      print('❌ Erro de conectividade: $e');
      return false;
    }
  }

  /// Busca a estratificação de um questionário.
  ///
  /// [questionnaireId] é o ID DO QUESTIONÁRIO, nunca o stratification_id nem
  /// um id de coleta/resposta. São valores distintos e fáceis de confundir:
  /// a estratificação de id 20 pertence ao questionário 6, e chamar
  /// /api/stratification/20 devolve 200 com "stratifications":[].
  ///
  /// Retorna a LISTA de estratificações do questionário; lista vazia quer
  /// dizer "nenhuma configurada". Erros de rede/HTTP/parse são lançados —
  /// quem chama precisa distinguir os dois casos na tela.
  ///
  /// O token vai no header Authorization (via [_getHeaders]) e é ele que faz
  /// o servidor decidir a visão: token de aplicador recebe SOMENTE as metas
  /// dele (data.view_mode = "individual"); supervisor/admin recebe o geral.
  /// Sem token vem a visão geral, o comportamento antigo.
  ///
  /// O app NUNCA envia ?applied_by: para um aplicador o servidor o ignora
  /// por segurança, e o filtro é coisa das telas de supervisão no painel.
  static Future<List<StratificationData>> getStratification(
      int questionnaireId) async {
    try {
      final url = '$baseUrl/stratification/$questionnaireId';
      final headers = await _getHeaders();
      print('📊 GET $url');
      // Não logar o valor do token; só se ele foi enviado.
      print('📊 Authorization enviado: ${headers.containsKey('Authorization')}');

      final response = await http
          .get(Uri.parse(url), headers: headers)
          .timeout(const Duration(seconds: 15));

      print('📊 Status: ${response.statusCode}');
      print('📊 Body: ${response.body}');

      if (response.statusCode == 200) {
        final responseData =
            jsonDecode(response.body) as Map<String, dynamic>;
        if (responseData['success'] == true) {
          final data = responseData['data'];
          if (data == null) {
            print('📊 Resposta success=true mas data=null');
            return const [];
          }
          // O payload fica em data["stratifications"] (lista), NÃO na raiz.
          final envelope = Map<String, dynamic>.from(data as Map);
          final list = StratificationData.listFromEnvelope(envelope);
          print('📊 Estratificações recebidas: ${list.length} '
              '(view_mode: ${envelope['view_mode'] ?? 'geral'})');
          return list;
        }
        print('📊 Resposta success=${responseData['success']} - message: ${responseData['message']}');
        throw Exception('API retornou success=false: ${responseData['message']}');
      } else if (response.statusCode == 401) {
        print('📊 Token não autorizado (401)');
        throw Exception('Token não autorizado (401)');
      } else {
        print('📊 Erro HTTP ${response.statusCode}');
        throw Exception('Erro HTTP ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Estratificação indisponível: $e');
      rethrow;
    }
  }
}

/// Falha em que reenviar o MESMO corpo não vai adiantar (413 por tamanho,
/// 400 por JSON inválido).
///
/// A coleta continua salva no aparelho — nada é descartado —, mas a fila
/// para de tentar em loop e avisa o aplicador, em vez de repetir a cada
/// sincronização.
class PermanentSubmitException implements Exception {
  final String message;
  final int? statusCode;

  PermanentSubmitException(this.message, {this.statusCode});

  @override
  String toString() => message;
}

/// NOVA: Classe para exceções personalizadas da API
class ApiException implements Exception {
  final String message;
  final int? statusCode;
  final dynamic details;

  ApiException(this.message, {this.statusCode, this.details});

  @override
  String toString() => message;
}

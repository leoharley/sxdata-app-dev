import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';
import '../providers/question_analysis_provider.dart';
import '../widgets/question_analysis_filters.dart';
import '../widgets/question_insights_widget.dart';
import '../utils/web_download_helper.dart';
import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';
import 'package:excel/excel.dart' as excel;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

class QuestionAnalysisScreen extends StatefulWidget {
  const QuestionAnalysisScreen({super.key});

  @override
  State<QuestionAnalysisScreen> createState() => _QuestionAnalysisScreenState();
}

class _QuestionAnalysisScreenState extends State<QuestionAnalysisScreen> {
  AnalysisFilters _currentFilters = AnalysisFilters();
  List<User> _applicators = [];
  bool _loadingApplicators = false;

  @override
  void initState() {
    super.initState();
    _requestPermissions();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadInitialData();
    });
  }

  void _loadInitialData() async {
    // Carregar questionários e aplicadores em paralelo
    await Future.wait<void>([
      _loadData(),
      _loadApplicators(),
    ]);
  }

  Future<void> _loadData() async {
    final provider = Provider.of<QuestionAnalysisProvider>(context, listen: false);
    await provider.loadQuestionnaires(_currentFilters);
  }

  void _loadQuestionnaireDetail(int questionnaireId) {
    final provider = Provider.of<QuestionAnalysisProvider>(context, listen: false);
    provider.loadQuestionnaireDetail(
      questionnaireId,
      filters: _currentFilters,
    );
  }

  Future<void> _loadApplicators() async {
    if (_loadingApplicators) return;
    
    setState(() {
      _loadingApplicators = true;
    });

    try {
      final provider = Provider.of<QuestionAnalysisProvider>(context, listen: false);
      final applicators = await provider.loadApplicators();
      
      setState(() {
        _applicators = applicators;
        _loadingApplicators = false;
      });
    } catch (e) {
      print('❌ Erro ao carregar aplicadores: $e');
      setState(() {
        _loadingApplicators = false;
      });
    }
  }

  Widget _buildActiveFiltersIndicator() {
    final activeFilters = <String>[];
    
    if (_currentFilters.questionnaireId != null) {
      activeFilters.add('Questionário específico');
    }
    if (_currentFilters.appliedBy != null) {
      activeFilters.add('Aplicador específico');
    }
    if (_currentFilters.questionTypes.isNotEmpty) {
      activeFilters.add('${_currentFilters.questionTypes.length} tipo(s)');
    }
    if (_currentFilters.minResponses > 0) {
      activeFilters.add('Min. ${_currentFilters.minResponses} respostas');
    }
    if (_currentFilters.minResponseRate > 0) {
      activeFilters.add('Min. ${_currentFilters.minResponseRate.toStringAsFixed(1)}% taxa');
    }
    if (_currentFilters.periodType != PeriodType.lastMonth) {
      activeFilters.add(_getPeriodLabel(_currentFilters.periodType));
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.filter_alt,
            size: 16,
            color: Color(0xFF8FAE5D),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Filtros: ${activeFilters.join(' • ')}',
              style: const TextStyle(
                fontSize: 12,
                color: Colors.white70,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          GestureDetector(
            onTap: () {
              setState(() {
                _currentFilters = AnalysisFilters();
              });
              _loadData();
            },
            child: const Icon(
              Icons.clear,
              size: 16,
              color: Colors.white70,
            ),
          ),
        ],
      ),
    );
  }

  String _getPeriodLabel(PeriodType period) {
    switch (period) {
      case PeriodType.lastWeek:
        return 'Última semana';
      case PeriodType.lastMonth:
        return 'Último mês';
      case PeriodType.last3Months:
        return 'Últimos 3 meses';
      case PeriodType.lastYear:
        return 'Último ano';
      case PeriodType.custom:
        return 'Período personalizado';
    }
  }

  void _showFilters() {
    final provider = Provider.of<QuestionAnalysisProvider>(context, listen: false);
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => SizedBox(
        height: MediaQuery.of(context).size.height * 0.8,
        child: QuestionAnalysisFilters(
          currentFilters: _currentFilters,
          onFiltersChanged: (newFilters) {
            setState(() {
              _currentFilters = newFilters;
            });
            _loadData();
          },
          questionnaires: provider.questionnaires,
          applicators: _applicators,
        ),
      ),
    );
  }

  Future<void> _exportData(String format) async {
  // Para web, mostrar diálogo de opções ANTES de gerar o arquivo
  if (kIsWeb) {
    await _exportDataWeb(format);
    return;
  }

  try {
    // Mostrar indicador de carregamento
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF8FAE5D)),
        ),
      ),
    );

    final provider = Provider.of<QuestionAnalysisProvider>(context, listen: false);

    String filePath;

    if (provider.selectedQuestionnaireDetail != null) {
      // Exportar dados detalhados do questionário selecionado
      switch (format.toLowerCase()) {
        case 'excel':
          filePath = await _generateExcelDetailedReport(provider.selectedQuestionnaireDetail!);
          break;
        case 'pdf':
          filePath = await _generatePDFDetailedReport(provider.selectedQuestionnaireDetail!);
          break;
        case 'csv':
          filePath = await _generateCSVDetailedReport(provider.selectedQuestionnaireDetail!);
          break;
        default:
          throw Exception('Formato não suportado');
      }
    } else {
      // Exportar dados gerais dos questionários
      switch (format.toLowerCase()) {
        case 'excel':
          filePath = await _generateExcelGeneralReport(provider.questionnaires);
          break;
        case 'pdf':
          filePath = await _generatePDFGeneralReport(provider.questionnaires);
          break;
        case 'csv':
          filePath = await _generateCSVGeneralReport(provider.questionnaires);
          break;
        default:
          throw Exception('Formato não suportado');
      }
    }

    // Fechar indicador de carregamento
    if (!mounted) return;
    Navigator.of(context).pop();

    // Pequeno delay para garantir que o diálogo anterior fechou
    await Future.delayed(const Duration(milliseconds: 100));

    // Compartilhar arquivo
    if (!mounted) return;
    await _shareFile(filePath, format);

  } catch (e) {
    // Fechar indicador de carregamento se ainda estiver aberto
    if (mounted && Navigator.canPop(context)) {
      Navigator.of(context).pop();
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Erro ao exportar dados: $e'),
        backgroundColor: Colors.red,
      ),
    );
  }
}

// Método específico para exportação na web
Future<void> _exportDataWeb(String format) async {
  try {
    if (!mounted) return;

    // Mostrar indicador de carregamento
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF8FAE5D)),
        ),
      ),
    );

    final provider = Provider.of<QuestionAnalysisProvider>(context, listen: false);

    Uint8List bytes;
    String fileName;

    if (provider.selectedQuestionnaireDetail != null) {
      // Exportar dados detalhados do questionário selecionado
      switch (format.toLowerCase()) {
        case 'excel':
          final result = await _generateExcelDetailedReportWeb(provider.selectedQuestionnaireDetail!);
          bytes = result['bytes'] as Uint8List;
          fileName = result['fileName'] as String;
          break;
        default:
          throw Exception('Formato não suportado para web ainda');
      }
    } else {
      // Exportar dados gerais dos questionários
      switch (format.toLowerCase()) {
        case 'excel':
          final result = await _generateExcelGeneralReportWeb(provider.questionnaires);
          bytes = result['bytes'] as Uint8List;
          fileName = result['fileName'] as String;
          break;
        default:
          throw Exception('Formato não suportado para web ainda');
      }
    }

    // Fechar indicador de carregamento
    if (!mounted) return;
    Navigator.of(context).pop();

    // Pequeno delay
    await Future.delayed(const Duration(milliseconds: 100));

    if (!mounted) return;

    // Fazer download direto na web usando o helper
    WebDownloadHelper.downloadFile(bytes, fileName);

    // Mostrar confirmação
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Download iniciado: $fileName\nTamanho: ${(bytes.length / 1024).toStringAsFixed(2)} KB'),
        backgroundColor: const Color(0xFF8FAE5D),
        duration: const Duration(seconds: 3),
        action: SnackBarAction(
          label: 'OK',
          textColor: Colors.white,
          onPressed: () {},
        ),
      ),
    );

  } catch (e) {
    // Fechar indicador de carregamento se ainda estiver aberto
    if (mounted && Navigator.canPop(context)) {
      Navigator.of(context).pop();
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Erro ao exportar dados: $e'),
        backgroundColor: Colors.red,
      ),
    );
  }
}

// Versão Web - Retorna bytes e nome do arquivo
Future<Map<String, dynamic>> _generateExcelDetailedReportWeb(QuestionnaireDetail detail) async {
  // Criar arquivo Excel SEM Sheet1 padrão
  final excelFile = excel.Excel.createExcel();

  // Criar apenas as abas que queremos
  final resultadosSheet = excelFile['Resultados'];
  excelFile.setDefaultSheet('Resultados');

  final allQuestions = await _extractAllQuestionsFromAPI(detail.id);
  final dynamicHeaders = _generateDynamicHeaders(allQuestions);
  final rawData = await _getRawDataForExport({'questionnaire_id': detail.id.toString()});

  for (int i = 0; i < dynamicHeaders.length; i++) {
    final cellRef = _getCellReference(1, i + 1);
    resultadosSheet.cell(excel.CellIndex.indexByString(cellRef)).value = _toCellValue(dynamicHeaders[i]);
  }

  int currentRow = 2;
  for (final responseData in rawData) {
    final mappedData = _mapResponseToDynamicFormatPHP(responseData, allQuestions);
    for (int i = 0; i < mappedData.length && i < dynamicHeaders.length; i++) {
      final cellRef = _getCellReference(currentRow, i + 1);
      resultadosSheet.cell(excel.CellIndex.indexByString(cellRef)).value = _toCellValue(mappedData[i]);
    }
    currentRow++;
  }

  final questionsSheet = excelFile['Perguntas'];
  _generateQuestionsWorksheet(questionsSheet, allQuestions);

  final statisticsSheet = excelFile['Estatísticas'];
  _generateStatisticsWorksheet(statisticsSheet, rawData);

  // SOLUÇÃO DEFINITIVA: Copiar apenas as abas desejadas para um novo arquivo
  final finalExcel = _createCleanExcel(excelFile);

  final fileName = 'dados_brutos_${detail.title.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_')}_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.xlsx';
  final bytes = Uint8List.fromList(finalExcel.encode()!);

  return {
    'bytes': bytes,
    'fileName': fileName,
  };
}

// Método auxiliar para converter valores para CellValue (Excel 4.x)
excel.CellValue? _toCellValue(dynamic value) {
  if (value == null) return null;
  if (value is String) return excel.TextCellValue(value);
  if (value is int) return excel.IntCellValue(value);
  if (value is double) return excel.DoubleCellValue(value);
  if (value is bool) return excel.BoolCellValue(value);
  return excel.TextCellValue(value.toString());
}

// Método auxiliar para criar Excel limpo sem Sheet1
excel.Excel _createCleanExcel(excel.Excel sourceExcel) {
  // Com excel 4.x, podemos deletar Sheet1 corretamente

  // Codificar o arquivo fonte
  final sourceBytes = sourceExcel.encode()!;

  // Decodificar para ter uma cópia
  var workingExcel = excel.Excel.decodeBytes(sourceBytes);

  // Deletar Sheet1 se existir (funciona corretamente na versão 4.x)
  if (workingExcel.tables.containsKey('Sheet1')) {
    workingExcel.delete('Sheet1');
  }

  // Definir Resultados como aba padrão
  if (workingExcel.tables.containsKey('Resultados')) {
    workingExcel.setDefaultSheet('Resultados');
  }

  return workingExcel;
}

Future<Map<String, dynamic>> _generateExcelGeneralReportWeb(List<QuestionnaireAnalysis> questionnaires) async {
  // Criar arquivo Excel
  final excelFile = excel.Excel.createExcel();

  final resultadosSheet = excelFile['Resultados'];
  excelFile.setDefaultSheet('Resultados');

  final allQuestions = await _extractAllQuestionsFromMultipleQuestionnaires(questionnaires);
  final dynamicHeaders = _generateDynamicHeaders(allQuestions);
  final rawData = await _getRawDataForExport({});

  for (int i = 0; i < dynamicHeaders.length; i++) {
    final cellRef = _getCellReference(1, i + 1);
    resultadosSheet.cell(excel.CellIndex.indexByString(cellRef)).value = _toCellValue(dynamicHeaders[i]);
  }

  int currentRow = 2;
  for (final responseData in rawData) {
    final mappedData = _mapResponseToDynamicFormatPHP(responseData, allQuestions);
    for (int i = 0; i < mappedData.length && i < dynamicHeaders.length; i++) {
      final cellRef = _getCellReference(currentRow, i + 1);
      resultadosSheet.cell(excel.CellIndex.indexByString(cellRef)).value = _toCellValue(mappedData[i]);
    }
    currentRow++;
  }

  final questionsSheet = excelFile['Perguntas'];
  _generateQuestionsWorksheet(questionsSheet, allQuestions);

  final statisticsSheet = excelFile['Estatísticas'];
  _generateStatisticsWorksheet(statisticsSheet, rawData);

  // SOLUÇÃO DEFINITIVA: Copiar apenas as abas desejadas para um novo arquivo
  final finalExcel = _createCleanExcel(excelFile);

  final fileName = 'dados_brutos_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.xlsx';
  final bytes = Uint8List.fromList(finalExcel.encode()!);

  return {
    'bytes': bytes,
    'fileName': fileName,
  };
}

// Método para gerar relatório Excel detalhado (questionário específico) com aba de dados brutos
Future<String> _generateExcelDetailedReport(QuestionnaireDetail detail) async {
  // Criar arquivo Excel
  final excelFile = excel.Excel.createExcel();

  final resultadosSheet = excelFile['Resultados'];
  excelFile.setDefaultSheet('Resultados');

  // PASSO 1: Extrair todas as questões únicas
  final allQuestions = await _extractAllQuestionsFromAPI(detail.id);

  // PASSO 2: Gerar headers dinâmicos
  final dynamicHeaders = _generateDynamicHeaders(allQuestions);

  // PASSO 3: Buscar dados brutos da API
  final rawData = await _getRawDataForExport({'questionnaire_id': detail.id.toString()});

  // Escrever headers
  for (int i = 0; i < dynamicHeaders.length; i++) {
    final cellRef = _getCellReference(1, i + 1);
    resultadosSheet.cell(excel.CellIndex.indexByString(cellRef)).value = _toCellValue(dynamicHeaders[i]);
  }

  // Preencher dados
  int currentRow = 2;
  for (final responseData in rawData) {
    final mappedData = _mapResponseToDynamicFormatPHP(responseData, allQuestions);

    for (int i = 0; i < mappedData.length && i < dynamicHeaders.length; i++) {
      final cellRef = _getCellReference(currentRow, i + 1);
      resultadosSheet.cell(excel.CellIndex.indexByString(cellRef)).value = _toCellValue(mappedData[i]);
    }
    currentRow++;
  }

  // === ABA 2: PERGUNTAS ===
  final questionsSheet = excelFile['Perguntas'];
  _generateQuestionsWorksheet(questionsSheet, allQuestions);

  // === ABA 3: ESTATÍSTICAS ===
  final statisticsSheet = excelFile['Estatísticas'];
  _generateStatisticsWorksheet(statisticsSheet, rawData);

  // SOLUÇÃO DEFINITIVA: Copiar apenas as abas desejadas para um novo arquivo
  final finalExcel = _createCleanExcel(excelFile);

  // Salvar arquivo
  final fileName = 'dados_brutos_${detail.title.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_')}_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.xlsx';
  final bytes = finalExcel.encode()!;

  if (kIsWeb) {
    // Em web, retornar apenas o nome do arquivo (bytes serão usados diretamente)
    return fileName;
  } else {
    // Em mobile/desktop, salvar o arquivo normalmente
    final directory = await getApplicationDocumentsDirectory();
    final filePath = '${directory.path}/$fileName';

    final file = File(filePath);
    await file.writeAsBytes(bytes);

    return filePath;
  }
}

List<String> _mapResponseToDynamicFormatPHP(Map<String, dynamic> responseData, Map<int, Map<String, dynamic>> allQuestions) {
  // Dados fixos (EXATAMENTE como no PHP - SEM RESPOSTAS_JSON)
  final fixedData = [
    _getSafeValue(responseData, 'questionnaire_title'),
    _getSafeValue(responseData, 'applied_by_name'),
    _formatDatePHP(responseData['completed_at']),
    _getSafeValue(responseData, 'latitude'),
    _getSafeValue(responseData, 'longitude'),
    _getSafeValue(responseData, 'location_name'),
    responseData['consent_given'] == true ? 'SIM' : 'NÃO',
    (responseData['sync_status'] ?? 'UNKNOWN').toString().toUpperCase(),
    _formatDateTimePHP(responseData['started_at']),
    _formatDateTimePHP(responseData['completed_at']),
    (responseData['photo_path'] != null && responseData['photo_path'].toString().isNotEmpty) ? 'SIM' : 'NÃO',
    '${responseData['id']}-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}'
  ];
  
  // Criar mapa de respostas desta resposta específica (igual ao PHP)
  final answersMap = <int, String>{};
  if (responseData['answers_json'] != null) {
    try {
      final answers = json.decode(responseData['answers_json']);
      if (answers is List) {
        for (final answer in answers) {
          if (answer is Map && answer['question_id'] != null) {
            final questionId = int.tryParse(answer['question_id'].toString()) ?? 0;
            final responseValue = answer['response_value'] ?? '';
            
            // Formatar valor da resposta baseado no tipo (igual _format_answer_value do PHP)
            answersMap[questionId] = _formatAnswerValuePHP(responseValue, answer['question_type'] ?? 'text');
          }
        }
      }
    } catch (e) {
      print('❌ Erro ao decodificar answers_json: $e');
    }
  }
  
  // Dados dinâmicos das perguntas (em ordem - igual ao PHP)
  final questionData = <String>[];
  for (final question in allQuestions.values) {
    final questionId = question['id'] as int;
    
    if (answersMap.containsKey(questionId)) {
      questionData.add(answersMap[questionId]!);
    } else {
      questionData.add(''); // Resposta vazia para esta pergunta
    }
  }
  
  // Combinar dados fixos + dados das perguntas (igual ao PHP)
  return [...fixedData, ...questionData];
}

String _getSafeValue(Map<String, dynamic> object, String property, [String defaultValue = '']) {
  final value = object[property];
  if (value == null) return defaultValue;
  
  if (value is List) {
    return value.join(', ');
  }
  
  return value.toString();
}

String _formatDatePHP(dynamic dateString) {
  if (dateString == null || dateString.toString().isEmpty) return '';
  
  try {
    final date = DateTime.parse(dateString.toString());
    return DateFormat('dd/MM/yyyy').format(date);
  } catch (e) {
    return 'Data inválida';
  }
}

String _formatDateTimePHP(dynamic dateTimeString) {
  if (dateTimeString == null || dateTimeString.toString().isEmpty) return '';
  
  try {
    final dateTime = DateTime.parse(dateTimeString.toString());
    return DateFormat('dd/MM/yyyy HH:mm').format(dateTime);
  } catch (e) {
    return 'Data inválida';
  }
}

// Função para gerar referência de célula (A1, B2, etc.)
String _getCellReference(int row, int column) {
  String columnRef = '';
  int temp = column;
  
  while (temp > 0) {
    temp--;
    columnRef = String.fromCharCode(65 + (temp % 26)) + columnRef;
    temp ~/= 26;
  }
  
  return '$columnRef$row';
}

// FORMATAR VALOR DA RESPOSTA (igual _format_answer_value do PHP)
String _formatAnswerValuePHP(dynamic value, String questionType) {
  if (value == null || value.toString().isEmpty) {
    return '';
  }
  
  switch (questionType) {
    case 'radio':
    case 'checkbox':
      // Se é array de opções selecionadas
      if (value is List) {
        return value.join(', ');
      }
      // Se é JSON string
      if (value is String && (value.startsWith('[') || value.startsWith('{'))) {
        try {
          final decoded = json.decode(value);
          if (decoded is List) {
            return decoded.join(', ');
          }
        } catch (e) {
          // Ignorar erro de JSON
        }
      }
      return value.toString();
      
    case 'date':
      if (value.toString().isNotEmpty) {
        try {
          final date = DateTime.parse(value.toString());
          return DateFormat('dd/MM/yyyy').format(date);
        } catch (e) {
          return value.toString();
        }
      }
      return '';
      
    case 'datetime':
      if (value.toString().isNotEmpty) {
        try {
          final dateTime = DateTime.parse(value.toString());
          return DateFormat('dd/MM/yyyy HH:mm').format(dateTime);
        } catch (e) {
          return value.toString();
        }
      }
      return '';
      
    case 'number':
      return value.toString();
      
    default:
      return value.toString();
  }
}

List<String> _generateDynamicHeaders(Map<int, Map<String, dynamic>> allQuestions) {
  // Headers fixos (EXATAMENTE como no PHP - SEM "RESPOSTAS_JSON")
  final fixedHeaders = [
    'QUESTIONÁRIO',
    'TÉCNICO RESPONSÁVEL PELA APLICAÇÃO',
    'DATA',
    'LATITUDE',
    'LONGITUDE',
    'LOCALIZAÇÃO',
    'CONSENTIMENTO DADO',
    'STATUS SINCRONIZAÇÃO',
    'DATA INÍCIO',
    'DATA CONCLUSÃO',
    'FOTO CAPTURADA',
    'ID DA QUESTÃO'
  ];
  
  // Headers das perguntas (limitado a 60 caracteres como no PHP)
  final questionHeaders = <String>[];
  for (final question in allQuestions.values) {
    String headerText = question['text'];
    
    // Limitar tamanho do header (igual ao PHP)
    if (headerText.length > 60) {
      headerText = headerText.substring(0, 57) + '...';
    }
    
    // Limpar caracteres problemáticos (igual ao PHP)
    headerText = headerText.replaceAll(RegExp(r'[^\p{L}\p{N}\s\-_?!.,:]', unicode: true), '');
    
    questionHeaders.add(headerText);
  }
  
  // Combinar headers (igual ao PHP)
  return [...fixedHeaders, ...questionHeaders];
}

Future<Map<int, Map<String, dynamic>>> _extractAllQuestionsFromAPI(int questionnaireId) async {
  try {
    final response = await ApiService.getQuestionnaireQuestions(questionnaireId);
    
    final allQuestions = <int, Map<String, dynamic>>{};
    
    if (response['success'] == true && response['data'] != null) {
      final questions = response['data'] as List;
      
      for (var question in questions) {
        // Converter string para int com tratamento de erro
        final questionId = int.tryParse(question['id']?.toString() ?? '0') ?? 0;
        
        if (questionId > 0) {
          // Converter order_index para int também
          final orderIndex = int.tryParse(question['order_index']?.toString() ?? '999') ?? 999;
          
          allQuestions[questionId] = {
            'id': questionId,
            'text': question['question_text'] ?? '',
            'type': question['question_type'] ?? 'text',
            'order_index': orderIndex
          };
        }
      }
    }
    
    // Ordenar por order_index (igual ao PHP)
    final sortedQuestions = Map.fromEntries(
      allQuestions.entries.toList()
        ..sort((a, b) => (a.value['order_index'] as int).compareTo(b.value['order_index'] as int))
    );
    
    return sortedQuestions;
  } catch (e) {
    print('❌ Erro ao extrair questões da API: $e');
    return {};
  }
}

String _formatDate(String? dateString) {
  if (dateString == null || dateString.isEmpty) return '';
  try {
    final date = DateTime.parse(dateString);
    return DateFormat('dd/MM/yyyy').format(date);
  } catch (e) {
    return dateString;
  }
}

// Método para gerar relatório Excel geral (todos os questionários) com aba de dados brutos
Future<String> _generateExcelGeneralReport(List<QuestionnaireAnalysis> questionnaires) async {
  // Criar arquivo Excel
  final excelFile = excel.Excel.createExcel();

  final resultadosSheet = excelFile['Resultados'];
  excelFile.setDefaultSheet('Resultados');

  // Para múltiplos questionários, extrair todas as questões de todos
  final allQuestions = await _extractAllQuestionsFromMultipleQuestionnaires(questionnaires);

  // Gerar headers dinâmicos
  final dynamicHeaders = _generateDynamicHeaders(allQuestions);

  // Buscar dados brutos de todos os questionários
  final rawData = await _getRawDataForExport({}); // Sem filtros = todos

  // Escrever headers
  for (int i = 0; i < dynamicHeaders.length; i++) {
    final cellRef = _getCellReference(1, i + 1);
    resultadosSheet.cell(excel.CellIndex.indexByString(cellRef)).value = _toCellValue(dynamicHeaders[i]);
  }

  // Preencher dados
  int currentRow = 2;
  for (final responseData in rawData) {
    final mappedData = _mapResponseToDynamicFormatPHP(responseData, allQuestions);

    for (int i = 0; i < mappedData.length && i < dynamicHeaders.length; i++) {
      final cellRef = _getCellReference(currentRow, i + 1);
      resultadosSheet.cell(excel.CellIndex.indexByString(cellRef)).value = _toCellValue(mappedData[i]);
    }
    currentRow++;
  }

  // === ABA 2: PERGUNTAS ===
  final questionsSheet = excelFile['Perguntas'];
  _generateQuestionsWorksheet(questionsSheet, allQuestions);

  // === ABA 3: ESTATÍSTICAS ===
  final statisticsSheet = excelFile['Estatísticas'];
  _generateStatisticsWorksheet(statisticsSheet, rawData);

  // Salvar arquivo
  final directory = await getApplicationDocumentsDirectory();
  final fileName = 'dados_brutos_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.xlsx';
  final filePath = '${directory.path}/$fileName';

  // SOLUÇÃO DEFINITIVA: Copiar apenas as abas desejadas para um novo arquivo
  final finalExcel = _createCleanExcel(excelFile);

  final file = File(filePath);
  await file.writeAsBytes(finalExcel.encode()!);

  return filePath;
}

void _generateStatisticsWorksheet(excel.Sheet statisticsSheet, List<Map<String, dynamic>> rawData) {
  final totalResponses = rawData.length;
  int totalWithConsent = 0;
  int totalWithLocation = 0;
  int totalWithPhoto = 0;
  final applicators = <String, int>{};
  
  for (final response in rawData) {
    if (response['consent_given'] == true) totalWithConsent++;
    if (response['latitude'] != null && response['longitude'] != null && 
        response['latitude'].toString().isNotEmpty && response['longitude'].toString().isNotEmpty) {
      totalWithLocation++;
    }
    if (response['photo_path'] != null && response['photo_path'].toString().isNotEmpty) {
      totalWithPhoto++;
    }
    
    final applicator = response['applied_by_name']?.toString() ?? 'Não informado';
    applicators[applicator] = (applicators[applicator] ?? 0) + 1;
  }
  
  // Cabeçalho
  statisticsSheet.cell(excel.CellIndex.indexByString('A1')).value = _toCellValue('Estatísticas da Exportação');
  
  // Estatísticas básicas
  final stats = [
    ['Total de Respostas', totalResponses],
    ['Com Consentimento', totalWithConsent],
    ['Com Localização', totalWithLocation],
    ['Com Foto', totalWithPhoto],
    ['Taxa de Consentimento (%)', totalResponses > 0 ? ((totalWithConsent / totalResponses) * 100).toStringAsFixed(1) : '0'],
    ['Taxa de Localização (%)', totalResponses > 0 ? ((totalWithLocation / totalResponses) * 100).toStringAsFixed(1) : '0'],
    ['Taxa de Fotos (%)', totalResponses > 0 ? ((totalWithPhoto / totalResponses) * 100).toStringAsFixed(1) : '0']
  ];
  
  for (int i = 0; i < stats.length; i++) {
    final row = i + 3;
    statisticsSheet.cell(excel.CellIndex.indexByString('A$row')).value = _toCellValue(stats[i][0]);
    statisticsSheet.cell(excel.CellIndex.indexByString('B$row')).value = _toCellValue(stats[i][1]);
  }

  // Respostas por aplicador
  int applicatorRow = stats.length + 5;
  statisticsSheet.cell(excel.CellIndex.indexByString('A$applicatorRow')).value = _toCellValue('Respostas por Aplicador');
  statisticsSheet.cell(excel.CellIndex.indexByString('B$applicatorRow')).value = _toCellValue('Quantidade');
  applicatorRow++;

  for (final entry in applicators.entries) {
    statisticsSheet.cell(excel.CellIndex.indexByString('A$applicatorRow')).value = _toCellValue(entry.key);
    statisticsSheet.cell(excel.CellIndex.indexByString('B$applicatorRow')).value = _toCellValue(entry.value);
    applicatorRow++;
  }
}

// GERAR PLANILHA DE PERGUNTAS (igual _generate_questions_worksheet do PHP)
void _generateQuestionsWorksheet(excel.Sheet questionsSheet, Map<int, Map<String, dynamic>> allQuestions) {
  // Headers
  questionsSheet.cell(excel.CellIndex.indexByString('A1')).value = _toCellValue('ID');
  questionsSheet.cell(excel.CellIndex.indexByString('B1')).value = _toCellValue('Ordem');
  questionsSheet.cell(excel.CellIndex.indexByString('C1')).value = _toCellValue('Tipo');
  questionsSheet.cell(excel.CellIndex.indexByString('D1')).value = _toCellValue('Texto da Pergunta');

  // Dados das perguntas
  int row = 2;
  for (final question in allQuestions.values) {
    questionsSheet.cell(excel.CellIndex.indexByString('A$row')).value = _toCellValue(question['id']);
    questionsSheet.cell(excel.CellIndex.indexByString('B$row')).value = _toCellValue(question['order_index']);
    questionsSheet.cell(excel.CellIndex.indexByString('C$row')).value = _toCellValue(question['type']);
    questionsSheet.cell(excel.CellIndex.indexByString('D$row')).value = _toCellValue(question['text']);
    row++;
  }
}

Future<List<Map<String, dynamic>>> _getRawDataForExport(Map<String, String> filters) async {
  try {
    final response = await ApiService.getRawDataForExport(filters);
    
    if (response['success'] == true && response['data'] != null) {
      final rawData = (response['data'] as List).cast<Map<String, dynamic>>();
      
      print('✅ ${rawData.length} registros carregados da API para exportação');
      return rawData;
    } else {
      print('❌ Erro na resposta da API: ${response['message']}');
      return [];
    }
  } catch (e) {
    print('❌ Erro ao buscar dados brutos da API: $e');
    return [];
  }
}

Future<Map<int, Map<String, dynamic>>> _extractAllQuestionsFromMultipleQuestionnaires(List<QuestionnaireAnalysis> questionnaires) async {
  final allQuestions = <int, Map<String, dynamic>>{};
  
  for (final questionnaire in questionnaires) {
    final questions = await _extractAllQuestionsFromAPI(questionnaire.id);
    allQuestions.addAll(questions);
  }
  
  return allQuestions;
}

Future<String> _generatePDFDetailedReport(QuestionnaireDetail detail) async {
  final pdf = pw.Document();
  
  pdf.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      build: (pw.Context context) {
        return [
          // Título
          pw.Header(
            level: 0,
            child: pw.Text(
              'RELATÓRIO DE ANÁLISE DE QUESTÕES',
              style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
            ),
          ),
          pw.Paragraph(text: detail.title),
          pw.SizedBox(height: 20),
          
          // Resumo
          pw.Header(level: 1, text: 'ESTATÍSTICAS GERAIS'),
          pw.Table.fromTextArray(
            data: [
              ['Métrica', 'Valor'],
              ['Total de Questões', detail.totalQuestions.toString()],
              ['Total de Respostas', detail.totalResponses.toString()],
              ['Tempo Médio', '${detail.avgCompletionTime.toStringAsFixed(2)} min'],
              ['Data do Relatório', DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now())],
            ],
          ),
          pw.SizedBox(height: 20),
          
          // Questões
          pw.Header(level: 1, text: 'ANÁLISE POR QUESTÃO'),
          ...detail.questions.map((question) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Header(
                level: 2, 
                text: 'Questão ${question.id}: ${question.text}'
              ),
              pw.Paragraph(text: 'Tipo: ${_getQuestionTypeLabel(question.type)}'),
              pw.Paragraph(text: 'Respostas: ${question.totalResponses}'),
              pw.Paragraph(text: 'Taxa: ${question.responseRate.toStringAsFixed(2)}%'),
              pw.Table.fromTextArray(
                headers: ['Opção/Categoria', 'Quantidade', 'Percentual'],
                data: question.data.map((data) => [
                  data.label,
                  data.count.toString(),
                  '${data.percentage?.toStringAsFixed(2) ?? '0.00'}%'
                ]).toList(),
              ),
              pw.SizedBox(height: 15),
            ],
          )),
        ];
      },
    ),
  );
  
  final directory = await getApplicationDocumentsDirectory();
  final fileName = 'analise_detalhada_${detail.id}_${DateTime.now().millisecondsSinceEpoch}.pdf';
  final filePath = '${directory.path}/$fileName';
  
  final file = File(filePath);
  await file.writeAsBytes(await pdf.save());
  
  return filePath;
}

Future<String> _generatePDFGeneralReport(List<QuestionnaireAnalysis> questionnaires) async {
  final pdf = pw.Document();
  
  pdf.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      build: (pw.Context context) {
        return pw.Column(
          children: [
            pw.Header(
              level: 0,
              child: pw.Text(
                'RELATÓRIO GERAL DE QUESTIONÁRIOS',
                style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
              ),
            ),
            pw.SizedBox(height: 20),
            pw.Table.fromTextArray(
              headers: ['ID', 'Título', 'Questões', 'Respostas', 'Taxa (%)'],
              data: questionnaires.map((q) => [
                q.id.toString(),
                q.title.length > 30 ? '${q.title.substring(0, 30)}...' : q.title,
                q.totalQuestions.toString(),
                q.totalResponses.toString(),
                q.responseRate.toStringAsFixed(1),
              ]).toList(),
            ),
          ],
        );
      },
    ),
  );
  
  final directory = await getApplicationDocumentsDirectory();
  final fileName = 'relatorio_questionarios_${DateTime.now().millisecondsSinceEpoch}.pdf';
  final filePath = '${directory.path}/$fileName';
  
  final file = File(filePath);
  await file.writeAsBytes(await pdf.save());
  
  return filePath;
}

// 6. Métodos para gerar CSV:

Future<String> _generateCSVDetailedReport(QuestionnaireDetail detail) async {
  final StringBuffer csv = StringBuffer();
  
  // Cabeçalho do relatório
  csv.writeln('"RELATÓRIO DE ANÁLISE DETALHADA"');
  csv.writeln('"Questionário:","${detail.title}"');
  csv.writeln('"Data:","${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now())}"');
  csv.writeln('');
  
  // Estatísticas gerais
  csv.writeln('"ESTATÍSTICAS GERAIS"');
  csv.writeln('"Total de Questões","${detail.totalQuestions}"');
  csv.writeln('"Total de Respostas","${detail.totalResponses}"');
  csv.writeln('"Tempo Médio (min)","${detail.avgCompletionTime.toStringAsFixed(2)}"');
  csv.writeln('');
  
  // Dados detalhados
  csv.writeln('"ANÁLISE DETALHADA"');
  csv.writeln('"Questão ID","Questão","Tipo","Total Respostas","Taxa (%)","Opção/Categoria","Quantidade","Percentual (%)"');
  
  for (final question in detail.questions) {
    if (question.data.isEmpty) {
      csv.writeln('"${question.id}","${_escapeCsvField(question.text)}","${_getQuestionTypeLabel(question.type)}","${question.totalResponses}","${question.responseRate.toStringAsFixed(2)}","Sem dados","0","0.00"');
    } else {
      for (int i = 0; i < question.data.length; i++) {
        final data = question.data[i];
        final isFirstRow = i == 0;
        csv.writeln('"${isFirstRow ? question.id : ''}","${isFirstRow ? _escapeCsvField(question.text) : ''}","${isFirstRow ? _getQuestionTypeLabel(question.type) : ''}","${isFirstRow ? question.totalResponses : ''}","${isFirstRow ? question.responseRate.toStringAsFixed(2) : ''}","${_escapeCsvField(data.label)}","${data.count}","${data.percentage?.toStringAsFixed(2) ?? '0.00'}"');
      }
    }
  }
  
  final directory = await getApplicationDocumentsDirectory();
  final fileName = 'analise_detalhada_${detail.id}_${DateTime.now().millisecondsSinceEpoch}.csv';
  final filePath = '${directory.path}/$fileName';
  
  final file = File(filePath);
  await file.writeAsString(csv.toString(), encoding: utf8); // CORRIGIDO: usar utf8
  
  return filePath;
}

Future<String> _generateCSVGeneralReport(List<QuestionnaireAnalysis> questionnaires) async {
  final StringBuffer csv = StringBuffer();
  
  // Cabeçalhos
  csv.writeln('"ID","Título","Descrição","Total Questões","Total Respostas","Taxa de Resposta (%)","Última Resposta"');
  
  // Dados
  for (final q in questionnaires) {
    csv.writeln('"${q.id}","${_escapeCsvField(q.title)}","${_escapeCsvField(q.description)}","${q.totalQuestions}","${q.totalResponses}","${q.responseRate.toStringAsFixed(2)}","${q.lastResponse?.toString() ?? 'N/A'}"');
  }
  
  final directory = await getApplicationDocumentsDirectory();
  final fileName = 'relatorio_questionarios_${DateTime.now().millisecondsSinceEpoch}.csv';
  final filePath = '${directory.path}/$fileName';
  
  final file = File(filePath);
  await file.writeAsString(csv.toString(), encoding: utf8); // CORRIGIDO: usar utf8
  
  return filePath;
}

// 7. Método para compartilhar arquivos:

Future<void> _shareFile(String filePath, String format) async {
  print('🔍 DEBUG: _shareFile chamado com filePath=$filePath, format=$format');

  try {
    final file = File(filePath);
    print('🔍 DEBUG: Verificando se arquivo existe: ${await file.exists()}');

    if (await file.exists()) {
      if (!mounted) {
        print('❌ DEBUG: Widget não está montado (mounted=false)');
        return;
      }

      print('✅ DEBUG: Mostrando diálogo de opções...');

      // Mostrar diálogo de opções
      final action = await showDialog<String>(
        context: context,
        barrierDismissible: true,
        builder: (context) => AlertDialog(
          title: const Text('Como deseja exportar?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.share, color: Color(0xFF8FAE5D)),
                title: const Text('Compartilhar arquivo'),
                subtitle: const Text('Via apps instalados'),
                onTap: () {
                  print('🔍 DEBUG: Opção SHARE selecionada');
                  Navigator.pop(context, 'share');
                },
              ),
            /*  ListTile(
                leading: const Icon(Icons.download, color: Colors.blue),
                title: const Text('Download direto'),
                subtitle: const Text('Para teste no Chrome/navegador'),
                onTap: () {
                  print('🔍 DEBUG: Opção DOWNLOAD selecionada');
                  Navigator.pop(context, 'download');
                },
              ), */
              ListTile(
                leading: const Icon(Icons.copy, color: Colors.orange),
                title: const Text('Copiar caminho'),
                subtitle: const Text('Ver localização do arquivo'),
                onTap: () {
                  print('🔍 DEBUG: Opção COPY selecionada');
                  Navigator.pop(context, 'copy');
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
          ],
        ),
      );

      print('🔍 DEBUG: Ação selecionada: $action');

      if (action == null) {
        print('⚠️ DEBUG: Nenhuma ação selecionada (cancelado)');
        return;
      }

      switch (action) {
        case 'share':
          print('▶️ DEBUG: Executando _shareFileMobile...');
          await _shareFileMobile(filePath);
          break;
        case 'download':
          print('▶️ DEBUG: Executando _downloadFile...');
          await _downloadFile(filePath, format);
          break;
        case 'copy':
          print('▶️ DEBUG: Executando _copyPathToClipboard...');
          await _copyPathToClipboard(filePath);
          break;
      }
    } else {
      print('❌ DEBUG: Arquivo não encontrado em: $filePath');
      throw Exception('Arquivo não encontrado');
    }
  } catch (e) {
    print('❌ DEBUG: Erro em _shareFile: $e');
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Erro ao processar arquivo: $e'),
        backgroundColor: Colors.red,
      ),
    );
  }
}

Future<void> _shareFileMobile(String filePath) async {
  try {
    final result = await Share.shareXFiles([XFile(filePath)]);

    if (!mounted) return;
    if (result.status == ShareResultStatus.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Arquivo compartilhado com sucesso!'),
          backgroundColor: Color(0xFF8FAE5D),
        ),
      );
    }
  } catch (e) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Erro ao compartilhar arquivo: $e'),
        backgroundColor: Colors.red,
      ),
    );
  }
}

Future<void> _downloadFile(String filePath, String format) async {
  try {
    final file = File(filePath);
    final bytes = await file.readAsBytes();
    final fileName = filePath.split(Platform.pathSeparator).last;

    if (!mounted) return;

    // Para teste em Chrome/Web, mostrar informações e tentar download automático
    if (kIsWeb) {
      // Em web, usar download nativo do navegador
      // (requer package web ao invés de dart:html deprecated)
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Download iniciado: $fileName'),
          backgroundColor: const Color(0xFF8FAE5D),
          duration: const Duration(seconds: 5),
        ),
      );
    } else {
      // Em desktop/mobile, mostrar diálogo com informações
      await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Download do Arquivo'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Arquivo gerado: $fileName'),
              const SizedBox(height: 8),
              Text('Tamanho: ${(bytes.length / 1024).toStringAsFixed(2)} KB'),
              const SizedBox(height: 8),
              Text('Localização:\n$filePath', style: const TextStyle(fontSize: 12)),
              const SizedBox(height: 16),
              const Text(
                'Para testar no Chrome:\n'
                '1. Copie o caminho acima\n'
                '2. Abra o arquivo diretamente\n'
                '3. Ou use a opção "Compartilhar"',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Fechar'),
            ),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(context);
                _shareFileMobile(filePath);
              },
              icon: const Icon(Icons.share),
              label: const Text('Compartilhar'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF8FAE5D),
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      );
    }
  } catch (e) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Erro ao processar download: $e'),
        backgroundColor: Colors.red,
      ),
    );
  }
}

Future<void> _copyPathToClipboard(String filePath) async {
  try {
    if (!mounted) return;
    // Copiar para clipboard (requer package flutter/services)
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Caminho do arquivo:\n$filePath'),
        backgroundColor: const Color(0xFF8FAE5D),
        duration: const Duration(seconds: 10),
        action: SnackBarAction(
          label: 'OK',
          textColor: Colors.white,
          onPressed: () {},
        ),
      ),
    );
  } catch (e) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Erro ao copiar caminho: $e'),
        backgroundColor: Colors.red,
      ),
    );
  }
}

// 8. Método auxiliar para escapar campos CSV:

String _escapeCsvField(String field) {
  return field.replaceAll('"', '""');
}

// 9. Adicione este método para solicitar permissões (adicione no initState):

/// Não pede permissão de armazenamento: a exportação grava em
/// getApplicationDocumentsDirectory() (área interna do app, que nunca exigiu
/// permissão) e entrega o arquivo por Share.shareXFiles.
///
/// O pedido anterior incluía MANAGE_EXTERNAL_STORAGE ("acesso a todos os
/// arquivos"), que o Google restringe e que contribui para alertas do Play
/// Protect — sem que o app precisasse dele.
Future<void> _requestPermissions() async {
  // Intencionalmente vazio.
}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Header customizado
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                color: Color(0xFFF5F5F5),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(
                          Icons.arrow_back,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                      Image.asset(
                        'assets/images/logo_socialx.png',
                        width: 120,
                        fit: BoxFit.contain,
                      ),
                      Row(
                        children: [
                          // Botão de filtros
                          Stack(
                            children: [
                              IconButton(
                                onPressed: _loadingApplicators ? null : _showFilters,
                                icon: _loadingApplicators 
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                        ),
                                      )
                                    : const Icon(
                                        Icons.filter_list,
                                        color: Colors.white,
                                        size: 24,
                                      ),
                              ),
                              if (_currentFilters.hasActiveFilters)
                                Positioned(
                                  right: 8,
                                  top: 8,
                                  child: Container(
                                    width: 8,
                                    height: 8,
                                    decoration: const BoxDecoration(
                                      color: Color(0xFF8FAE5D),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          // Botão de exportação
                          PopupMenuButton<String>(
                            icon: const Icon(
                              Icons.download,
                              color: Colors.white,
                              size: 24,
                            ),
                            onSelected: _exportData,
                            itemBuilder: (context) => [
                              const PopupMenuItem(
                                value: 'excel',
                                child: Row(
                                  children: [
                                    Icon(Icons.table_chart, size: 16),
                                    SizedBox(width: 8),
                                    Text('Excel (.xlsx)'),
                                  ],
                                ),
                              ),
                              const PopupMenuItem(
                                value: 'pdf',
                                child: Row(
                                  children: [
                                    Icon(Icons.picture_as_pdf, size: 16),
                                    SizedBox(width: 8),
                                    Text('PDF'),
                                  ],
                                ),
                              ),
                             /* const PopupMenuItem(
                                value: 'csv',
                                child: Row(
                                  children: [
                                    Icon(Icons.description, size: 16),
                                    SizedBox(width: 8),
                                    Text('CSV'),
                                  ],
                                ),
                              ),*/
                            ],
                          ),
                          // Botão de refresh
                          Consumer<QuestionAnalysisProvider>(
                            builder: (context, provider, child) {
                              return IconButton(
                                onPressed: provider.isLoading ? null : _loadData,
                                icon: provider.isLoading
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                        ),
                                      )
                                    : const Icon(
                                        Icons.refresh,
                                        color: Color(0xFF8FAE5D),
                                        size: 24,
                                      ),
                              );
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                  
                  // Indicadores de filtros ativos
                  if (_currentFilters.hasActiveFilters) ...[
                    const SizedBox(height: 12),
                    _buildActiveFiltersIndicator(),
                  ],
                ],
              ),
            ),
            
            // Conteúdo principal
            Expanded(
              child: _buildContent(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    return Consumer<QuestionAnalysisProvider>(
      builder: (context, provider, child) {
        if (provider.isLoading) {
          return const Center(
            child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF8FAE5D)),
            ),
          );
        }

        if (provider.error != null) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.error_outline,
                  size: 64,
                  color: Colors.red[300],
                ),
                const SizedBox(height: 16),
                Text(
                  'Erro ao carregar dados',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Colors.red[700],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  provider.error!,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Colors.grey,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: _loadData,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Tentar Novamente'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF8FAE5D),
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Análise de Questões',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF23345F),
                    ),
                  ),
                  SizedBox(height: 5),
                  Text(
                    'Estatísticas detalhadas das respostas por questão',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 30),
              
              Expanded(
                child: provider.selectedQuestionnaireDetail != null 
                    ? _buildQuestionnaireDetail(provider)
                    : _buildQuestionnairesList(provider),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildQuestionnairesList(QuestionAnalysisProvider provider) {
    if (provider.questionnaires.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.quiz_outlined,
              size: 64,
              color: Colors.grey[300],
            ),
            const SizedBox(height: 16),
            const Text(
              'Nenhum questionário encontrado',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _currentFilters.hasActiveFilters 
                  ? 'Tente ajustar os filtros para ver mais resultados'
                  : 'Não há questionários disponíveis para análise',
              style: const TextStyle(
                fontSize: 14,
                color: Colors.grey,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            if (_currentFilters.hasActiveFilters) ...[
              ElevatedButton.icon(
                onPressed: () {
                  setState(() {
                    _currentFilters = AnalysisFilters();
                  });
                  _loadData();
                },
                icon: const Icon(Icons.clear_all),
                label: const Text('Limpar Filtros'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF8FAE5D),
                  foregroundColor: Colors.white,
                ),
              ),
            ] else ...[
              OutlinedButton.icon(
                onPressed: _loadInitialData,
                icon: const Icon(Icons.refresh),
                label: const Text('Recarregar'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF8FAE5D),
                ),
              ),
            ],
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: provider.questionnaires.length,
      itemBuilder: (context, index) {
        final questionnaire = provider.questionnaires[index];
        return _buildQuestionnaireCard(questionnaire);
      },
    );
  }

  Widget _buildQuestionnaireCard(QuestionnaireAnalysis questionnaire) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: InkWell(
        onTap: () => _loadQuestionnaireDetail(questionnaire.id),
        borderRadius: BorderRadius.circular(12),
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
                      color: const Color(0xFF8FAE5D).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.quiz,
                      color: Color(0xFF8FAE5D),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          questionnaire.title,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF23345F),
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (questionnaire.description.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            questionnaire.description,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.grey,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.arrow_forward_ios,
                    size: 16,
                    color: Colors.grey,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              
              // Estatísticas básicas
              Row(
                children: [
                  Expanded(
                    child: _buildStatItem(
                      'Questões',
                      '${questionnaire.totalQuestions}',
                      Icons.help_outline,
                      Colors.blue,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildStatItem(
                      'Respostas',
                      '${questionnaire.totalResponses}',
                      Icons.people_outline,
                      const Color(0xFF8FAE5D),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildStatItem(
                      'Taxa',
                      '${questionnaire.responseRate.toStringAsFixed(1)}%',
                      Icons.analytics_outlined,
                      Colors.orange,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatItem(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        children: [
          Icon(
            icon,
            size: 16,
            color: color,
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              fontSize: 9,
              color: Colors.grey,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildQuestionnaireDetail(QuestionAnalysisProvider provider) {
    final detail = provider.selectedQuestionnaireDetail!;
    
    // CORREÇÃO: Calcular valores efetivos se vierem zerados
    int effectiveTotalQuestions = detail.totalQuestions > 0 
        ? detail.totalQuestions 
        : detail.questions.length;
    
    int effectiveTotalResponses = detail.totalResponses;
    if (effectiveTotalResponses == 0 && detail.questions.isNotEmpty) {
      // Pegar o maior número de respostas entre as questões
      effectiveTotalResponses = detail.questions
          .map((q) => q.totalResponses)
          .reduce((a, b) => a > b ? a : b);
    }
    
    double effectiveAvgTime = detail.avgCompletionTime;
    
    print('🔍 DEBUG - Valores efetivos: Questions=$effectiveTotalQuestions, Responses=$effectiveTotalResponses, Time=$effectiveAvgTime');
    
    return Column(
      children: [
        // Header do questionário selecionado
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF8FAE5D).withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF8FAE5D).withOpacity(0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      detail.title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF23345F),
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () {
                      provider.clearSelection();
                    },
                    icon: const Icon(Icons.close, color: Colors.grey),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              
              // Resumo do questionário (CORRIGIDO)
              Row(
                children: [
                  Expanded(
                    child: _buildSummaryItem(
                      'Questões',
                      '$effectiveTotalQuestions',
                      Icons.quiz_outlined,
                      Colors.blue,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildSummaryItem(
                      'Respostas',
                      '$effectiveTotalResponses',
                      Icons.people_outlined,
                      const Color(0xFF8FAE5D),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildSummaryItem(
                      'Tempo Médio',
                      '${effectiveAvgTime.toStringAsFixed(1)}min',
                      Icons.timer_outlined,
                      Colors.orange,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        
        const SizedBox(height: 20),
        
        // Lista de questões e insights
        Expanded(
          child: provider.isLoadingDetail
              ? const Center(
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF8FAE5D)),
                  ),
                )
              : ListView(
                  children: [
                    // Widget de insights
                    QuestionInsightsWidget(
                      questionnaireDetail: detail,
                    ),
                    
                    // Lista de questões
                    ...detail.questions.asMap().entries.map((entry) {
                      final index = entry.key;
                      final question = entry.value;
                      return _buildQuestionCard(question, index + 1);
                    }),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _buildSummaryItem(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              fontSize: 9,
              color: Colors.grey,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildQuestionCard(QuestionAnalysis question, int questionNumber) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header da questão
            Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: _getQuestionTypeColor(question.type).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: Text(
                      '$questionNumber',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: _getQuestionTypeColor(question.type),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        question.text,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF23345F),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: _getQuestionTypeColor(question.type).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              _getQuestionTypeLabel(question.type),
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w500,
                                color: _getQuestionTypeColor(question.type),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${question.totalResponses} respostas • ${question.responseRate.toStringAsFixed(1)}%',
                            style: const TextStyle(
                              fontSize: 10,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 16),
            
            // Dados da análise
            _buildQuestionAnalysisData(question),
          ],
        ),
      ),
    );
  }

  Widget _buildQuestionAnalysisData(QuestionAnalysis question) {
    if (question.type == 'radio' || question.type == 'checkbox') {
      return _buildOptionAnalysis(question);
    } else {
      return _buildGenericAnalysis(question);
    }
  }

  Widget _buildOptionAnalysis(QuestionAnalysis question) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          question.type == 'radio' ? 'Distribuição das Opções:' : 'Seleções por Opção:',
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Color(0xFF23345F),
          ),
        ),
        const SizedBox(height: 8),
        
        ...question.data.map((data) => Container(
          margin: const EdgeInsets.only(bottom: 8),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      data.label,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF23345F),
                      ),
                    ),
                  ),
                  Text(
                    '${data.count}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF23345F),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${data.percentage?.toStringAsFixed(1) ?? '0.0'}%',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              LinearProgressIndicator(
                value: (data.percentage ?? 0) / 100,
                backgroundColor: Colors.grey.shade200,
                valueColor: AlwaysStoppedAnimation<Color>(_getQuestionTypeColor(question.type)),
                minHeight: 4,
              ),
            ],
          ),
        )),
      ],
    );
  }

  Widget _buildGenericAnalysis(QuestionAnalysis question) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Estatísticas:',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Color(0xFF23345F),
          ),
        ),
        const SizedBox(height: 8),
        
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: question.data.map((data) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: _getQuestionTypeColor(question.type).withOpacity(0.1),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: _getQuestionTypeColor(question.type).withOpacity(0.3),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  data.isDate 
                      ? _formatDate(data.dateValue ?? '')
                      : '${data.count}${data.unit != null ? ' ${data.unit}' : ''}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: _getQuestionTypeColor(question.type),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  data.label,
                  style: const TextStyle(
                    fontSize: 9,
                    color: Colors.grey,
                  ),
                  textAlign: TextAlign.center,
                ),
                if (data.percentage != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    '${data.percentage!.toStringAsFixed(1)}%',
                    style: const TextStyle(
                      fontSize: 8,
                      color: Colors.grey,
                    ),
                  ),
                ],
              ],
            ),
          )).toList(),
        ),
      ],
    );
  }

  Color _getQuestionTypeColor(String type) {
    switch (type) {
      case 'radio':
        return Colors.blue;
      case 'checkbox':
        return const Color(0xFF8FAE5D);
      case 'text':
      case 'textarea':
      case 'phone':
        return Colors.orange;
      case 'number':
        return Colors.purple;
      case 'date':
      case 'datetime':
        return Colors.teal;
      default:
        return Colors.grey;
    }
  }

  String _getQuestionTypeLabel(String type) {
    switch (type) {
      case 'radio':
        return 'Escolha Única';
      case 'checkbox':
        return 'Múltipla Escolha';
      case 'text':
        return 'Texto Curto';
      case 'textarea':
        return 'Texto Longo';
      case 'number':
        return 'Número';
      case 'date':
        return 'Data';
      case 'datetime':
        return 'Data/Hora';
      case 'phone':
        return 'Telefone';
      default:
        return type.toUpperCase();
    }
  }

}
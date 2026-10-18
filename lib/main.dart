// main.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/foundation.dart';
import 'providers/auth_provider.dart';
import 'providers/questionnaire_provider.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'providers/stats_provider.dart';
import 'providers/form_provider.dart';
import 'providers/history_provider.dart';
import 'screens/login_screen.dart';
import 'screens/splash_screen.dart';
import 'utils/theme.dart';
import '../providers/question_analysis_provider.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Teto do cache de imagens. O padrão do Flutter (1000 imagens / 100 MB)
  // é pensado para aparelho com folga de memória; em celular de 2 GB
  // rodando no navegador, guardar 100 MB de bitmaps decodificados é o que
  // derruba a aba depois da foto de evidência.
  PaintingBinding.instance.imageCache.maximumSize = 50;
  PaintingBinding.instance.imageCache.maximumSizeBytes = 20 << 20; // 20 MB

  // Inicializar configurações conforme a plataforma
  _initializePlatform();

  runApp(const SXDataApp());
}

void _initializePlatform() {
  try {
    // Configurações específicas da plataforma
    if (!kIsWeb) {
      print('✅ Aplicativo móvel inicializado');
    } else {
      print('✅ Aplicativo web inicializado');
    }
  } catch (e) {
    print('⚠️ Erro ao inicializar plataforma: $e');
  }
}

class SXDataApp extends StatelessWidget {
  const SXDataApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => QuestionnaireProvider()),
        ChangeNotifierProvider(create: (_) => FormProvider()),
        ChangeNotifierProvider(create: (_) => StatsProvider()),
        ChangeNotifierProvider(create: (_) => HistoryProvider()),
        ChangeNotifierProvider(create: (_) => QuestionAnalysisProvider()),
      ],
      child: MaterialApp(
        title: 'SXData',
        theme: AppTheme.lightTheme,
        locale: const Locale('pt', 'BR'),
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [
          Locale('pt', 'BR'), // Português do Brasil
          Locale('en', 'US'), // Inglês (fallback)
        ],
        home: const SplashScreen(),
        // A rota nomeada '/login' já era usada pelo dashboard (ação do aviso
        // de sessão expirada), mas nunca esteve registrada — tocar no botão
        // lançava exceção de rota desconhecida em vez de levar ao login.
        routes: {
          '/login': (_) => const LoginScreen(),
        },
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}
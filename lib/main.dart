import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'pages/home_page.dart';
import 'services/vlm_service.dart';
import 'services/app_config.dart';
import 'services/model_manager.dart';

void main() async {
  // Preserve the splash screen until we're ready
  WidgetsBinding widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

  // Set preferred orientations
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Set system UI overlay style
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ),
  );

  // Pre-initialize VLM service listener
  VlmService.instance.initStreamListener();

  // Start initialization (including model loading) and ensure minimum splash time
  _initializeApp();

  runApp(const MyApp());
}

/// Initialize app components during splash screen
/// Starts model loading early to minimize user wait time
Future<void> _initializeApp() async {
  final stopwatch = Stopwatch()..start();
  const minSplashDuration = Duration(milliseconds: 2500);

  try {
    // Check if SDK is ready
    final sdkReady = await VlmService.instance.isSdkReady();
    debugPrint('Splash: SDK ready: $sdkReady');

    // Check if model is already loaded
    final modelLoaded = await VlmService.instance.isModelLoaded();
    debugPrint('Splash: Model already loaded: $modelLoaded');

    // Start model loading in background if not already loaded
    // VlmService now prevents duplicate loads, so this is safe
    if (!modelLoaded && sdkReady) {
      debugPrint('Splash: Starting model loading...');
      _startModelLoading(); // Fire and forget - continues after splash
    }
  } catch (e) {
    debugPrint('Error during initialization: $e');
  }

  // Ensure minimum splash duration for smooth UX
  final elapsed = stopwatch.elapsed;
  if (elapsed < minSplashDuration) {
    await Future.delayed(minSplashDuration - elapsed);
  }

  debugPrint(
    'Splash: Removing splash screen after ${stopwatch.elapsedMilliseconds}ms',
  );
  FlutterNativeSplash.remove();
}

/// Start model loading in background
/// This doesn't block - model continues loading after splash is removed
/// HomePage will detect the in-progress load and wait for it
Future<void> _startModelLoading() async {
  try {
    // Get the selected model configuration
    final selectedModel = await AppConfig.instance.getSelectedModel();
    debugPrint('Splash: Selected model: ${selectedModel.id}');

    // Check if model is downloaded
    final modelManager = ModelManager.instance;
    final isDownloaded = await modelManager.isModelDownloaded(selectedModel);

    if (!isDownloaded) {
      debugPrint('Splash: Model not downloaded, skipping preload');
      return;
    }

    // Get model paths
    final modelPath = await modelManager.getMainModelPath(selectedModel);
    final mmprojPath = await modelManager.getMmprojPath(selectedModel);

    debugPrint('Splash: Loading model from $modelPath');

    // Start loading - VlmService will prevent duplicate loads
    // This continues in background after splash is removed
    VlmService.instance
        .loadModel(
          modelPath: modelPath,
          mmprojPath: mmprojPath,
          pluginId: selectedModel.pluginId,
          deviceId: selectedModel.deviceId,
        )
        .then((result) {
          debugPrint(
            'Splash: Model load completed - ${result.success}: ${result.message}',
          );
        })
        .catchError((e) {
          debugPrint('Splash: Model load error - $e');
        });
  } catch (e) {
    debugPrint('Splash: Error starting model load - $e');
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Live Cam Learn',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFFFD54F),
          primary: const Color(0xFFFFD54F),
          secondary: const Color(0xFFFF5722),
        ),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFFFD54F),
          foregroundColor: Colors.black87,
          elevation: 0,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFFFD54F),
            foregroundColor: Colors.black87,
          ),
        ),
      ),
      home: const HomePage(),
    );
  }
}

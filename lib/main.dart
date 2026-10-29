import 'services/iphone_duo_service.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';
import 'app_theme.dart';
import 'screens/splash_screen.dart';
import 'services/plex_auth_service.dart';
import 'services/plex_server_service.dart';
import 'services/plix_device_helper.dart';
import 'services/plix_image_cache.dart';
import 'services/tv_sound_service.dart';
import 'services/update_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  PlixImageCache.configure();
  await UpdateService.initVersion();

  await PlixDeviceHelper.initDeviceName();
  if (Platform.isIOS) {
    await IPhoneDuoService.init();
  }
  TvSoundService.instance.init();

  if (Platform.isWindows || Platform.isIOS || Platform.isLinux || Platform.isMacOS) {
    MediaKit.ensureInitialized();
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      await windowManager.ensureInitialized();
      windowManager.setTitle('Plix');
    }
  }

  await PlixTheme.loadSavedTheme();

  // Set system UI overlay style for immersive dark experience
  SystemChrome.setSystemUIOverlayStyle(
    SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: PlixTheme.background,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  final authService = PlexAuthService();
  final serverService = PlexServerService(authService: authService);

  runApp(PlixApp(
    authService: authService,
    serverService: serverService,
  ));
}

class PlixApp extends StatelessWidget {
  final PlexAuthService authService;
  final PlexServerService serverService;

  const PlixApp({
    super.key,
    required this.authService,
    required this.serverService,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: PlixTheme.themeRevision,
      builder: (context, _, __) {
        return MaterialApp(
          title: 'Plix',
          debugShowCheckedModeBanner: false,
          theme: PlixTheme.themeData,
          home: SplashScreen(
            authService: authService,
            serverService: serverService,
          ),
        );
      },
    );
  }
}

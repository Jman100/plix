import 'services/guest_mode_service.dart';
import 'services/custom_avatar_service.dart';
import 'services/iphone_duo_service.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';
import 'app_theme.dart';
import 'screens/splash_screen.dart';
import 'screens/profiles_screen.dart';
import 'services/theme_music_service.dart';
import 'services/native_player_service.dart';
import 'services/plex_auth_service.dart';
import 'services/plex_server_service.dart';
import 'services/plix_device_helper.dart';
import 'services/plix_image_cache.dart';
import 'services/profile_service.dart';
import 'services/tv_sound_service.dart';
import 'services/update_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  PlixImageCache.configure();
  await UpdateService.initVersion();
  if (Platform.isAndroid) {
    UpdateService.cleanUpDownloadedUpdate();
  }

  await PlixDeviceHelper.initDeviceName();
  if (Platform.isIOS) {
    await IPhoneDuoService.init();
  }
  TvSoundService.instance.init();

  if (Platform.isWindows || Platform.isIOS || Platform.isLinux || Platform.isMacOS) {
    await NativePlayerService.loadSavedHwdecMode();
    MediaKit.ensureInitialized();
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      await windowManager.ensureInitialized();
      windowManager.setTitle('Plix');
    }
  }

  await ProfileService.instance.init();
  await CustomAvatarService.init();
  await PlixTheme.loadSavedTheme();
  await GuestModeService.instance.init();

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
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
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
          navigatorKey: PlixApp.navigatorKey,
          title: 'Plix',
          debugShowCheckedModeBanner: false,
          theme: PlixTheme.themeData,
          builder: (context, child) {
            return _SystemUiOrientationWatcher(
              authService: authService,
              serverService: serverService,
              child: child ?? const SizedBox.shrink(),
            );
          },
          home: SplashScreen(
            authService: authService,
            serverService: serverService,
          ),
        );
      },
    );
  }
}

class _SystemUiOrientationWatcher extends StatefulWidget {
  final Widget child;
  final PlexAuthService authService;
  final PlexServerService serverService;

  const _SystemUiOrientationWatcher({
    required this.child,
    required this.authService,
    required this.serverService,
  });

  @override
  State<_SystemUiOrientationWatcher> createState() => _SystemUiOrientationWatcherState();
}

class _SystemUiOrientationWatcherState extends State<_SystemUiOrientationWatcher> with WidgetsBindingObserver {
  Orientation? _lastOrientation;
  bool _wasBackgrounded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached || state == AppLifecycleState.hidden) {
      if (GuestModeService.instance.isGuestMode) {
        GuestModeService.instance.exitGuestMode();
      }
    }
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      _wasBackgrounded = true;
    } else if (state == AppLifecycleState.resumed && mounted) {
      _applySystemUi(MediaQuery.of(context).orientation);
      if (_wasBackgrounded) {
        _wasBackgrounded = false;
        final activeProf = ProfileService.instance.activeProfile;
        if (activeProf != null && activeProf.hasPin && !ProfilesScreen.isVisible) {
          NativePlayerService().stop();
          ThemeMusicService.instance.stopImmediate();
          PlixApp.navigatorKey.currentState?.pushAndRemoveUntil(
            MaterialPageRoute(
              builder: (_) => ProfilesScreen(
                authService: widget.authService,
                serverService: widget.serverService,
              ),
            ),
            (route) => false,
          );
        }
      }
    }
  }

  void _applySystemUi(Orientation orientation) {
    if (!PlixDeviceHelper.isTelevision && (Platform.isAndroid || Platform.isIOS)) {
      if (orientation == Orientation.landscape) {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      } else {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final orientation = MediaQuery.of(context).orientation;
    if (_lastOrientation != orientation) {
      _lastOrientation = orientation;
      _applySystemUi(orientation);
    }
    return widget.child;
  }
}

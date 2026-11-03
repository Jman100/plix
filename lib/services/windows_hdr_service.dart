import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';

// CCD (Configuring Connected Displays) API constants for Windows Display Configuration
const int _qdcOnlyActivePaths = 0x00000002;
const int _displayConfigModeInfoTypeTarget = 2;
const int _displayConfigDeviceInfoGetAdvancedColorInfo = 9;
const int _displayConfigDeviceInfoSetAdvancedColorState = 10;

final class _Luid extends Struct {
  @Uint32()
  external int lowPart;
  @Int32()
  external int highPart;
}

final class _DisplayConfigDeviceInfoHeader extends Struct {
  @Uint32()
  external int type;
  @Uint32()
  external int size;
  external _Luid adapterId;
  @Uint32()
  external int id;
}

final class _DisplayConfigPathInfo extends Struct {
  @Array(20)
  external Array<Uint8> sourceInfo;
  @Array(48)
  external Array<Uint8> targetInfo;
  @Uint32()
  external int flags;
}

final class _DisplayConfigModeInfo extends Struct {
  @Uint32()
  external int infoType;
  @Uint32()
  external int id;
  external _Luid adapterId;
  @Array(48)
  external Array<Uint8> modeInfo;
}

final class _DisplayConfigGetAdvancedColorInfo extends Struct {
  external _DisplayConfigDeviceInfoHeader header;
  @Uint32()
  external int value;
  @Uint32()
  external int colorEncoding;
  @Uint32()
  external int bitsPerColorChannel;
}

final class _DisplayConfigSetAdvancedColorState extends Struct {
  external _DisplayConfigDeviceInfoHeader header;
  @Uint32()
  external int value;
}

typedef _GetDisplayConfigBufferSizesC = Int32 Function(
  Uint32 flags,
  Pointer<Uint32> numPathArrayElements,
  Pointer<Uint32> numModeInfoArrayElements,
);
typedef _GetDisplayConfigBufferSizesDart = int Function(
  int flags,
  Pointer<Uint32> numPathArrayElements,
  Pointer<Uint32> numModeInfoArrayElements,
);

typedef _QueryDisplayConfigC = Int32 Function(
  Uint32 flags,
  Pointer<Uint32> numPathArrayElements,
  Pointer<_DisplayConfigPathInfo> pathArray,
  Pointer<Uint32> numModeInfoArrayElements,
  Pointer<_DisplayConfigModeInfo> modeInfoArray,
  Pointer<Uint32> currentTopologyId,
);
typedef _QueryDisplayConfigDart = int Function(
  int flags,
  Pointer<Uint32> numPathArrayElements,
  Pointer<_DisplayConfigPathInfo> pathArray,
  Pointer<Uint32> numModeInfoArrayElements,
  Pointer<_DisplayConfigModeInfo> modeInfoArray,
  Pointer<Uint32> currentTopologyId,
);

typedef _DisplayConfigGetDeviceInfoC = Int32 Function(
  Pointer<_DisplayConfigDeviceInfoHeader> requestPacket,
);
typedef _DisplayConfigGetDeviceInfoDart = int Function(
  Pointer<_DisplayConfigDeviceInfoHeader> requestPacket,
);

typedef _DisplayConfigSetDeviceInfoC = Int32 Function(
  Pointer<_DisplayConfigDeviceInfoHeader> setPacket,
);
typedef _DisplayConfigSetDeviceInfoDart = int Function(
  Pointer<_DisplayConfigDeviceInfoHeader> setPacket,
);

/// Manages per-app HDR enablement on Windows desktop.
///
/// When HDR content is played, if the user keeps Windows HDR globally disabled,
/// this service activates Advanced Color (HDR) for the display target, and automatically
/// restores the display back to SDR when playback finishes.
class WindowsHdrService {
  static final WindowsHdrService _instance = WindowsHdrService._internal();
  factory WindowsHdrService() => _instance;
  WindowsHdrService._internal();

  bool _plixEnabledHdr = false;
  final List<({int adapterLow, int adapterHigh, int targetId})> _switchedTargets = [];

  bool get wasHdrEnabledByPlix => _plixEnabledHdr;

  /// Activates HDR on Windows for connected displays that support it if currently disabled.
  Future<bool> enableHdrForContent() async {
    if (!Platform.isWindows) return false;
    try {
      final user32 = DynamicLibrary.open('user32.dll');
      final getSizes = user32.lookupFunction<_GetDisplayConfigBufferSizesC, _GetDisplayConfigBufferSizesDart>(
        'GetDisplayConfigBufferSizes',
      );
      final queryConfig = user32.lookupFunction<_QueryDisplayConfigC, _QueryDisplayConfigDart>(
        'QueryDisplayConfig',
      );
      final getDeviceInfo = user32.lookupFunction<_DisplayConfigGetDeviceInfoC, _DisplayConfigGetDeviceInfoDart>(
        'DisplayConfigGetDeviceInfo',
      );
      final setDeviceInfo = user32.lookupFunction<_DisplayConfigSetDeviceInfoC, _DisplayConfigSetDeviceInfoDart>(
        'DisplayConfigSetDeviceInfo',
      );

      return using((arena) {
        final pathCountPtr = arena<Uint32>();
        final modeCountPtr = arena<Uint32>();
        final sizeRes = getSizes(_qdcOnlyActivePaths, pathCountPtr, modeCountPtr);
        if (sizeRes != 0) return false;

        final pathCount = pathCountPtr.value;
        final modeCount = modeCountPtr.value;
        if (pathCount == 0 || modeCount == 0) return false;

        final paths = arena<_DisplayConfigPathInfo>(pathCount);
        final modes = arena<_DisplayConfigModeInfo>(modeCount);
        final queryRes = queryConfig(_qdcOnlyActivePaths, pathCountPtr, paths, modeCountPtr, modes, nullptr);
        if (queryRes != 0) return false;

        bool anyEnabled = false;
        for (int i = 0; i < modeCountPtr.value; i++) {
          final mode = modes[i];
          if (mode.infoType == _displayConfigModeInfoTypeTarget) {
            final getPacket = arena<_DisplayConfigGetAdvancedColorInfo>();
            getPacket.ref.header.type = _displayConfigDeviceInfoGetAdvancedColorInfo;
            getPacket.ref.header.size = sizeOf<_DisplayConfigGetAdvancedColorInfo>();
            getPacket.ref.header.adapterId.lowPart = mode.adapterId.lowPart;
            getPacket.ref.header.adapterId.highPart = mode.adapterId.highPart;
            getPacket.ref.header.id = mode.id;

            final getRes = getDeviceInfo(getPacket.cast());
            if (getRes == 0) {
              final val = getPacket.ref.value;
              final supported = (val & 0x1) != 0;
              final enabled = (val & 0x2) != 0;

              // If display supports HDR but user keeps it disabled in Windows:
              if (supported && !enabled) {
                final setPacket = arena<_DisplayConfigSetAdvancedColorState>();
                setPacket.ref.header.type = _displayConfigDeviceInfoSetAdvancedColorState;
                setPacket.ref.header.size = sizeOf<_DisplayConfigSetAdvancedColorState>();
                setPacket.ref.header.adapterId.lowPart = mode.adapterId.lowPart;
                setPacket.ref.header.adapterId.highPart = mode.adapterId.highPart;
                setPacket.ref.header.id = mode.id;
                setPacket.ref.value = 1; // Enable Advanced Color

                final setRes = setDeviceInfo(setPacket.cast());
                if (setRes == 0) {
                  _switchedTargets.add((
                    adapterLow: mode.adapterId.lowPart,
                    adapterHigh: mode.adapterId.highPart,
                    targetId: mode.id,
                  ));
                  _plixEnabledHdr = true;
                  anyEnabled = true;
                }
              }
            }
          }
        }
        return anyEnabled;
      });
    } catch (_) {
      return false;
    }
  }

  /// Restores display targets back to SDR if they were enabled by Plix during playback.
  Future<void> restoreHdrState() async {
    if (!Platform.isWindows || !_plixEnabledHdr || _switchedTargets.isEmpty) return;
    try {
      final user32 = DynamicLibrary.open('user32.dll');
      final setDeviceInfo = user32.lookupFunction<_DisplayConfigSetDeviceInfoC, _DisplayConfigSetDeviceInfoDart>(
        'DisplayConfigSetDeviceInfo',
      );

      using((arena) {
        for (final target in _switchedTargets) {
          final setPacket = arena<_DisplayConfigSetAdvancedColorState>();
          setPacket.ref.header.type = _displayConfigDeviceInfoSetAdvancedColorState;
          setPacket.ref.header.size = sizeOf<_DisplayConfigSetAdvancedColorState>();
          setPacket.ref.header.adapterId.lowPart = target.adapterLow;
          setPacket.ref.header.adapterId.highPart = target.adapterHigh;
          setPacket.ref.header.id = target.targetId;
          setPacket.ref.value = 0; // Disable Advanced Color (restore SDR)

          setDeviceInfo(setPacket.cast());
        }
      });
    } catch (_) {
    } finally {
      _switchedTargets.clear();
      _plixEnabledHdr = false;
    }
  }
}

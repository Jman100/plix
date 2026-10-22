// Dev helper: runs `flutter run --machine` on a device and triggers hot
// reload automatically when Dart files under lib/ change.
//
// Usage:
//   dart tools/flutter_hot_runner.dart [device-id]
//
// The device defaults to the Android TV at 192.168.0.81:5555.
//
// Manual commands can be written to %TEMP%\plix_flutter_command.txt:
//   {"method":"hotReload"}
//   {"method":"hotRestart"}
//   {"method":"stop"}
//   {"method":"quit"}
//
// Log: %TEMP%\plix_flutter_run.log

import 'dart:async';
import 'dart:convert';
import 'dart:io';

const String _flutterBat =
    r'C:\Users\joshc\Documents\AISTUFF\tools\flutter\bin\flutter.bat';
const String _defaultDevice = '192.168.0.81:5555';

late final File _logFile;
late final File _commandFile;
late final Process _process;
String? _appId;
bool _ready = false;
bool _stopping = false;
Timer? _reloadDebounce;
int _requestId = 0;
String _lastCommand = '';

Future<void> main(List<String> args) async {
  final device = args.isNotEmpty ? args[0] : _defaultDevice;
  final tempDir = Directory.systemTemp.path;
  _logFile = File('$tempDir\\plix_flutter_run.log')..writeAsStringSync('');
  _commandFile = File('$tempDir\\plix_flutter_command.txt')
    ..writeAsStringSync('');

  _log('Starting flutter run --machine for $device');

  _process = await Process.start(
    _flutterBat,
    <String>['run', '--machine', '-d', device, '--debug'],
    workingDirectory: Directory.current.path,
    runInShell: true,
  );

  _process.stdout
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen(_handleLine);
  _process.stderr
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen((line) => _log('ERR $line'));

  _watchLibDirectory();
  _watchCommandFile();

  final exitCode = await _process.exitCode;
  _log('flutter run exited with code $exitCode');
  exit(exitCode);
}

void _handleLine(String line) {
  _log(line);
  final trimmed = line.trim();
  if (!trimmed.startsWith('[') && !trimmed.startsWith('{')) return;

  try {
    final data = jsonDecode(trimmed);
    final items = data is List ? data : <Object?>[data];
    for (final item in items) {
      if (item is! Map) continue;
      final event = item['event'];
      final params = item['params'];
      if (event == 'app.start' && params is Map) {
        _appId = params['appId']?.toString();
        _log('APP ID: $_appId');
      } else if (event == 'app.started') {
        _log('APP STARTED');
        Timer(const Duration(seconds: 2), () {
          _ready = true;
          _log('Auto hot reload enabled');
        });
      } else if (event == 'app.stop') {
        _log('APP STOPPED');
        _ready = false;
      }
    }
  } catch (_) {
    // Non-JSON output is already in the log.
  }
}

void _watchLibDirectory() {
  final lib = Directory('lib');
  if (!lib.existsSync()) {
    _log('WARNING: lib directory not found; auto reload disabled');
    return;
  }

  lib.watch(recursive: true).listen((event) {
    if (!_ready || _stopping || !event.path.endsWith('.dart')) return;
    _reloadDebounce?.cancel();
    _reloadDebounce = Timer(const Duration(milliseconds: 600), () {
      _sendRestart(fullRestart: false);
    });
  });
}

void _watchCommandFile() {
  Timer.periodic(const Duration(milliseconds: 300), (_) {
    if (!_commandFile.existsSync()) return;
    final content = _commandFile.readAsStringSync().trim();
    if (content.isEmpty || content == _lastCommand) return;
    _lastCommand = content;

    try {
      final command = jsonDecode(content);
      if (command is Map && command['method'] is String) {
        final method = command['method'] as String;
        if (method == 'hotReload') {
          _sendRestart(fullRestart: false);
        } else if (method == 'hotRestart') {
          _sendRestart(fullRestart: true);
        } else if (method == 'stop') {
          _sendCommand('app.stop', <String, Object?>{'appId': _appId});
        } else if (method == 'quit') {
          _stopping = true;
          _log('Stopping flutter run');
          _process.kill();
          exit(0);
        } else {
          _process.stdin.writeln(content);
          _process.stdin.flush();
          _log('>> $content');
        }
      } else {
        _process.stdin.writeln(content);
        _process.stdin.flush();
        _log('>> $content');
      }
    } catch (error) {
      _log('COMMAND ERROR: $error');
    }

    _commandFile.writeAsStringSync('');
    _lastCommand = '';
  });
}

void _sendRestart({required bool fullRestart}) {
  if (_appId == null) {
    _log('Cannot restart: app id not available yet');
    return;
  }
  _log(fullRestart ? 'Requesting hot restart' : 'Requesting hot reload');
  _sendCommand('app.restart', <String, Object?>{
    'appId': _appId,
    'fullRestart': fullRestart,
    'debounce': true,
  });
}

void _sendCommand(String method, Map<String, Object?> params) {
  final id = (++_requestId).toString();
  final payload = jsonEncode(<String, Object?>{
    'id': id,
    'method': method,
    'params': params,
  });
  _process.stdin.writeln(payload);
  _process.stdin.flush();
  _log('>> $payload');
}

void _log(String message) {
  final line = '${DateTime.now().toIso8601String()} $message';
  _logFile.writeAsStringSync('$line\n', mode: FileMode.append, flush: true);
  stdout.writeln(line);
}

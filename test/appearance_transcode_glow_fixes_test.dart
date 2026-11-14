import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plix/app_theme.dart';
import 'package:plix/models/plex_media_item.dart';
import 'package:plix/models/plex_server.dart';
import 'package:plix/services/plex_timeline_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Appearance, Transcode Reporting, and Focus Glow Fixes Tests', () {
    test('PlixTheme.themeData has transparent focusColor, highlightColor, and splashColor', () {
      final theme = PlixTheme.themeData;
      expect(theme.focusColor, equals(Colors.transparent));
      expect(theme.highlightColor, equals(Colors.transparent));
      expect(theme.splashColor, equals(Colors.transparent));
    });

    test('PlexTimelineService Jellyfin reports PlayMethod and PlaySessionId on start and progress', () async {
      final recordedRequests = <http.Request>[];
      final mockClient = MockClient((request) async {
        recordedRequests.add(request);
        return http.Response('', 204);
      });

      final jfServer = PlexServer(
        name: 'JF Test',
        clientIdentifier: 'jf_test_1',
        accessToken: 'token_abc',
        connections: [
          PlexConnection(
            uri: 'http://127.0.0.1:8096',
            protocol: 'http',
            address: '127.0.0.1',
            port: 8096,
            local: true,
            relay: false,
          ),
        ],
        owned: true,
        serverType: 'jellyfin',
      );

      final timelineService = PlexTimelineService(
        server: jfServer,
        clientId: 'client_123',
        client: mockClient,
      );

      const item = PlexMediaItem(
        key: '/item_999',
        ratingKey: 'item_999',
        title: 'Hellboy',
        type: 'movie',
        duration: 7200000,
      );

      // Start playback as Transcode
      timelineService.startPlayback(
        item,
        10000,
        playMethod: 'Transcode',
        playSessionId: 'sess_123',
      );

      await Future.delayed(const Duration(milliseconds: 50));

      expect(recordedRequests.isNotEmpty, isTrue);
      final startReq = recordedRequests.first;
      expect(startReq.url.path, endsWith('/Sessions/Playing'));
      final startBody = jsonDecode(startReq.body) as Map<String, dynamic>;
      expect(startBody['ItemId'], equals('item_999'));
      expect(startBody['PlayMethod'], equals('Transcode'));
      expect(startBody['PlaySessionId'], equals('sess_123'));
      expect(startBody['CanSeek'], equals(true));

      // Initial progress report
      final initialProgReq = recordedRequests[1];
      expect(initialProgReq.url.path, endsWith('/Sessions/Playing/Progress'));
      final initialProgBody = jsonDecode(initialProgReq.body) as Map<String, dynamic>;
      expect(initialProgBody['PlayMethod'], equals('Transcode'));
      expect(initialProgBody['PlaySessionId'], equals('sess_123'));

      // Update play method to DirectPlay
      timelineService.updatePlayMethod(
        playMethod: 'DirectPlay',
        playSessionId: 'sess_456',
      );

      await Future.delayed(const Duration(milliseconds: 50));
      expect(recordedRequests.length, greaterThanOrEqualTo(3));
      final updateReq = recordedRequests[2];
      expect(updateReq.url.path, endsWith('/Sessions/Playing'));
      final updateBody = jsonDecode(updateReq.body) as Map<String, dynamic>;
      expect(updateBody['PlayMethod'], equals('DirectPlay'));
      expect(updateBody['PlaySessionId'], equals('sess_456'));

      // Progress reporting via pause
      timelineService.pause(15000);
      await Future.delayed(const Duration(milliseconds: 50));
      final progReq = recordedRequests.last;
      expect(progReq.url.path, endsWith('/Sessions/Playing/Progress'));
      final progBody = jsonDecode(progReq.body) as Map<String, dynamic>;
      expect(progBody['PlayMethod'], equals('DirectPlay'));
      expect(progBody['PlaySessionId'], equals('sess_456'));

      timelineService.stop(15000);
      timelineService.dispose();
    });

    test('Theme preset and color change increments themeRevision', () async {
      final initialRevision = PlixTheme.themeRevision.value;
      await PlixTheme.setPreset(PlixTheme.presetOptions[1]); // Liquid Glass
      expect(PlixTheme.themeRevision.value, greaterThan(initialRevision));

      final nextRevision = PlixTheme.themeRevision.value;
      await PlixTheme.setTheme(PlixTheme.colorOptions[2]); // Cyber Cyan
      expect(PlixTheme.themeRevision.value, greaterThan(nextRevision));
    });
  });
}

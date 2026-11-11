import 'package:flutter_test/flutter_test.dart';
import 'package:plix/models/plex_server.dart';
import 'package:plix/services/plex_media_service.dart';

void main() {
  group('Plex and Jellyfin Transcode & Direct Stream URL Tests', () {
    final plexServer = PlexServer(
      name: 'Plex Server',
      clientIdentifier: 'plex_123',
      accessToken: 'token_abc',
      connections: [
        PlexConnection(
          uri: 'http://192.168.1.50:32400',
          protocol: 'http',
          address: '192.168.1.50',
          port: 32400,
          local: true,
          relay: false,
        ),
      ],
      owned: true,
      serverType: 'plex',
    );

    final jfServer = PlexServer(
      name: 'Jellyfin Server',
      clientIdentifier: 'jf_123',
      accessToken: 'token_xyz',
      connections: [
        PlexConnection(
          uri: 'http://192.168.1.60:8096',
          protocol: 'http',
          address: '192.168.1.60',
          port: 8096,
          local: true,
          relay: false,
        ),
      ],
      owned: true,
      serverType: 'jellyfin',
    );

    test('Plex: directStreamVideo=true with forceAudioTranscode=true preserves video as directStream and only converts audio', () {
      final service = PlexMediaService(server: plexServer);
      final url = service.buildTranscodeUrl(
        ratingKey: '1001',
        maxBitrateKbps: 0,
        resolution: '',
        offsetSeconds: 0,
        clientId: 'client_tv',
        directStreamVideo: true,
        forceAudioTranscode: true,
      );

      final uri = Uri.parse(url);
      final params = uri.queryParameters;

      // directStream must be 1 so video is not re-encoded
      expect(params['directStream'], equals('1'));
      // directStreamAudio must be 0 so audio is converted
      expect(params['directStreamAudio'], equals('0'));
      expect(params['audioCodec'], equals('aac'));
      // videoCodec must NOT be set to h264 so 4K video is not converted
      expect(params.containsKey('videoCodec'), isFalse);
      expect(params.containsKey('videoResolution'), isFalse);
      // X-Plex-Client-Profile-Extra must be present to allow 4K HEVC Direct Stream
      expect(params.containsKey('X-Plex-Client-Profile-Extra'), isTrue);
      expect(params['X-Plex-Client-Profile-Extra'], contains('videoCodec=hevc'));
      expect(params['X-Plex-Client-Profile-Extra'], contains('replace=true'));
    });

    test('Plex: directStreamVideo=false forces videoCodec=h264 and directStream=0', () {
      final service = PlexMediaService(server: plexServer);
      final url = service.buildTranscodeUrl(
        ratingKey: '1001',
        maxBitrateKbps: 8000,
        resolution: '1920x1080',
        offsetSeconds: 0,
        clientId: 'client_tv',
        directStreamVideo: false,
        forceAudioTranscode: true,
      );

      final uri = Uri.parse(url);
      final params = uri.queryParameters;

      expect(params['directStream'], equals('0'));
      expect(params['videoCodec'], equals('h264'));
      expect(params['videoResolution'], equals('1920x1080'));
    });

    test('Jellyfin: directStreamVideo=true with forceAudioTranscode=true sets videoCodec=copy and AllowVideoStreamCopy=true', () {
      final service = PlexMediaService(server: jfServer);
      final url = service.buildTranscodeUrl(
        ratingKey: 'jf_item_1',
        maxBitrateKbps: 0,
        resolution: '',
        offsetSeconds: 0,
        clientId: 'client_tv',
        directStreamVideo: true,
        forceAudioTranscode: true,
      );

      final uri = Uri.parse(url);
      final params = uri.queryParameters;

      expect(params['videoCodec'], equals('copy'));
      expect(params['AllowVideoStreamCopy'], equals('true'));
      expect(params['audioCodec'], equals('aac'));
      expect(params['AllowAudioStreamCopy'], equals('false'));
    });
  });
}

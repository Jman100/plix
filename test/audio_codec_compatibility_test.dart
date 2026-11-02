import 'package:flutter_test/flutter_test.dart';

bool isStandardAudioCodec(String codec) {
  final audioCodec = codec.toLowerCase().trim();
  return audioCodec == 'aac' ||
      audioCodec == 'mp4a' ||
      audioCodec == 'mp3' ||
      audioCodec == 'flac' ||
      audioCodec == 'opus' ||
      audioCodec == 'vorbis' ||
      audioCodec == 'pcm' ||
      audioCodec == 'wav' ||
      audioCodec == 'alac' ||
      audioCodec.startsWith('pcm_');
}

void main() {
  group('Audio Codec Compatibility', () {
    test('aac, mp3, flac, opus, pcm are standard universally supported without passthrough check', () {
      expect(isStandardAudioCodec('aac'), isTrue);
      expect(isStandardAudioCodec('mp3'), isTrue);
      expect(isStandardAudioCodec('flac'), isTrue);
      expect(isStandardAudioCodec('opus'), isTrue);
      expect(isStandardAudioCodec('pcm'), isTrue);
      expect(isStandardAudioCodec('pcm_s16le'), isTrue);
      expect(isStandardAudioCodec('pcm_s24le'), isTrue);
    });

    test('ac3, eac3, dts, and truehd require hardware / receiver capability checks', () {
      expect(isStandardAudioCodec('ac3'), isFalse);
      expect(isStandardAudioCodec('eac3'), isFalse);
      expect(isStandardAudioCodec('e-ac3'), isFalse);
      expect(isStandardAudioCodec('dts'), isFalse);
      expect(isStandardAudioCodec('truehd'), isFalse);
      expect(isStandardAudioCodec('dca'), isFalse);
    });
  });
}

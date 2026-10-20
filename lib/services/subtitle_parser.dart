class SubtitleCue {
  final Duration start;
  final Duration end;
  final String text;

  const SubtitleCue({
    required this.start,
    required this.end,
    required this.text,
  });
}

class SubtitleParser {
  static List<SubtitleCue> parse(String content) {
    if (content.isEmpty) return [];

    // Strip BOM if present
    String cleaned = content;
    if (cleaned.startsWith('\uFEFF')) {
      cleaned = cleaned.substring(1);
    }
    cleaned = cleaned.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

    // Check if this is an ASS/SSA subtitle file
    if (cleaned.contains('[Events]') || cleaned.contains('Dialogue:')) {
      final assCues = _parseAssSubtitles(cleaned);
      if (assCues.isNotEmpty) {
        return assCues;
      }
    }

    // Otherwise, parse as SRT or WebVTT
    return _parseSrtOrVtt(cleaned);
  }

  static List<SubtitleCue> _parseSrtOrVtt(String content) {
    final List<SubtitleCue> cues = [];
    final blocks = content.split(RegExp(r'\n{2,}'));

    for (final block in blocks) {
      final lines = block.trim().split('\n');
      if (lines.isEmpty) continue;

      int timeIndex = -1;
      for (int i = 0; i < lines.length; i++) {
        if (lines[i].contains('-->')) {
          timeIndex = i;
          break;
        }
      }

      if (timeIndex == -1) continue;

      final timeParts = lines[timeIndex].split('-->');
      if (timeParts.length < 2) continue;

      final start = _parseTimestamp(timeParts[0].trim());
      final end = _parseTimestamp(timeParts[1].trim().split(' ').first);

      if (start == null || end == null) continue;

      final textLines = lines.sublist(timeIndex + 1);
      final rawText = textLines.join('\n').trim();
      // Strip simple HTML tags like <i>, </i>, <b>, <font...>, <c...>
      final cleanText = _cleanSubtitleText(rawText);

      if (cleanText.isNotEmpty) {
        cues.add(SubtitleCue(start: start, end: end, text: cleanText));
      }
    }

    cues.sort((a, b) => a.start.compareTo(b.start));
    return cues;
  }

  static List<SubtitleCue> _parseAssSubtitles(String content) {
    final List<SubtitleCue> cues = [];
    final lines = content.split('\n');

    for (final line in lines) {
      final trimmed = line.trim();
      if (!trimmed.toLowerCase().startsWith('dialogue:')) continue;

      // Dialogue format: Dialogue: Marked, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
      // Note: First 9 commas separate metadata, everything after the 9th comma is Text
      final colonIndex = trimmed.indexOf(':');
      if (colonIndex == -1) continue;

      final paramsStr = trimmed.substring(colonIndex + 1).trim();
      final parts = _splitAssDialogue(paramsStr);
      if (parts.length < 10) continue;

      final start = _parseAssTimestamp(parts[1].trim());
      final end = _parseAssTimestamp(parts[2].trim());

      if (start == null || end == null) continue;

      final rawText = parts[9].trim();
      final cleanText = _cleanSubtitleText(rawText);

      if (cleanText.isNotEmpty) {
        cues.add(SubtitleCue(start: start, end: end, text: cleanText));
      }
    }

    cues.sort((a, b) => a.start.compareTo(b.start));
    return cues;
  }

  static List<String> _splitAssDialogue(String line) {
    final List<String> parts = [];
    int start = 0;
    for (int i = 0; i < 9; i++) {
      final comma = line.indexOf(',', start);
      if (comma == -1) {
        parts.add(line.substring(start));
        return parts;
      }
      parts.add(line.substring(start, comma));
      start = comma + 1;
    }
    // Remainder is Text (can contain commas)
    parts.add(line.substring(start));
    return parts;
  }

  static Duration? _parseAssTimestamp(String timestamp) {
    // Format: H:MM:SS.cs (centiseconds) e.g. 0:01:23.45
    try {
      final parts = timestamp.split(':');
      if (parts.length == 3) {
        final hours = int.parse(parts[0]);
        final minutes = int.parse(parts[1]);
        final secParts = parts[2].split('.');
        final seconds = int.parse(secParts[0]);
        final cs = secParts.length > 1 ? int.parse(secParts[1].padRight(2, '0').substring(0, 2)) : 0;
        return Duration(hours: hours, minutes: minutes, seconds: seconds, milliseconds: cs * 10);
      }
    } catch (_) {}
    return null;
  }

  static String _cleanSubtitleText(String text) {
    var s = text;
    // Replace ASS newline markers \N and \n
    s = s.replaceAll(r'\N', '\n').replaceAll(r'\n', '\n');
    // Remove ASS styling tags: {\an8}, {\b1}, {\c&H...&}, {\pos(x,y)}, etc.
    s = s.replaceAll(RegExp(r'\{[^}]*\}'), '');
    // Remove HTML tags: <i>, </b>, <font color="...">, <c.yellow>
    s = s.replaceAll(RegExp(r'<[^>]*>'), '');
    return s.trim();
  }

  static Duration? _parseTimestamp(String timestamp) {
    try {
      final normalized = timestamp.replaceAll(',', '.');
      final parts = normalized.split(':');
      if (parts.length == 3) {
        final hours = int.parse(parts[0]);
        final minutes = int.parse(parts[1]);
        final secParts = parts[2].split('.');
        final seconds = int.parse(secParts[0]);
        final ms = secParts.length > 1 ? int.parse(secParts[1].padRight(3, '0').substring(0, 3)) : 0;
        return Duration(hours: hours, minutes: minutes, seconds: seconds, milliseconds: ms);
      } else if (parts.length == 2) {
        final minutes = int.parse(parts[0]);
        final secParts = parts[1].split('.');
        final seconds = int.parse(secParts[0]);
        final ms = secParts.length > 1 ? int.parse(secParts[1].padRight(3, '0').substring(0, 3)) : 0;
        return Duration(minutes: minutes, seconds: seconds, milliseconds: ms);
      }
    } catch (_) {}
    return null;
  }

  static SubtitleCue? findActiveCue(List<SubtitleCue> cues, Duration position) {
    for (final cue in cues) {
      if (position >= cue.start && position <= cue.end) {
        return cue;
      }
      if (cue.start > position) {
        break; // Sorted, so no need to search further
      }
    }
    return null;
  }
}

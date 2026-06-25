import 'dart:math';

/// Generates and normalizes readable room codes made of two German nouns, for
/// example `adler-insel`. Readable codes are easy to read aloud to a group.
abstract final class RoomCodeGenerator {
  static final Random _random = Random();

  /// Curated, group-friendly German nouns (no spaces, no umlauts to keep codes
  /// easy to type on any keyboard).
  static const List<String> _words = [
    'adler', 'insel', 'wolke', 'hafen', 'sturm', 'anker', 'kompass', 'segel',
    'leuchtturm', 'welle', 'duene', 'fels', 'moewe', 'delfin', 'koralle',
    'lagune', 'palme', 'strand', 'horizont', 'kapitaen', 'matrose', 'kabine',
    'cockpit', 'turbine', 'rotor', 'flosse', 'kiel', 'bug', 'heck', 'mast',
    'boje', 'riff', 'ebbe', 'flut', 'nebel', 'blitz', 'donner', 'orkan',
    'brise', 'passat', 'kompassrose', 'seestern', 'krabbe', 'muschel',
    'gischt', 'brandung', 'klippe', 'bucht', 'fjord', 'archipel', 'atoll',
    'vulkan', 'krater', 'oase', 'wueste', 'tundra', 'gletscher', 'lawine',
    'komet', 'planet', 'orbit', 'rakete', 'pilot', 'funke', 'radar',
    'propeller', 'tragflaeche', 'fahrwerk', 'schub', 'auftrieb', 'landung',
  ];

  /// Returns a new code like `adler-insel` using two distinct words.
  static String generate() {
    final first = _words[_random.nextInt(_words.length)];
    String second;
    do {
      second = _words[_random.nextInt(_words.length)];
    } while (second == first);
    return '$first-$second';
  }

  /// Normalizes user-entered codes: trims, lowercases and collapses spaces to a
  /// single hyphen so `Adler Insel` and `adler-insel` resolve to the same room.
  static String normalize(String input) {
    return input
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[\s_]+'), '-')
        .replaceAll(RegExp(r'-+'), '-');
  }

  /// Whether [input] looks like a usable room code.
  static bool isValid(String input) {
    final normalized = normalize(input);
    return RegExp(r'^[a-z]+-[a-z]+$').hasMatch(normalized);
  }
}

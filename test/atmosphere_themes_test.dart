import 'package:flutter_test/flutter_test.dart';
import 'package:plix/app_theme.dart';

void main() {
  group('Atmosphere Themes', () {
    test('Total preset options is 16 and custom is the last option', () {
      expect(PlixTheme.presetOptions.length, 16);
      expect(PlixTheme.presetOptions.last.id, 'custom');
      expect(PlixTheme.presetOptions.last.name, 'Custom Theme');
    });

    test('Includes all four new creative atmosphere themes', () {
      final ids = PlixTheme.presetOptions.map((p) => p.id).toList();
      expect(ids.contains('abyss'), isTrue);
      expect(ids.contains('aurora'), isTrue);
      expect(ids.contains('dune'), isTrue);
      expect(ids.contains('royal'), isTrue);

      final abyss = PlixTheme.presetOptions.firstWhere((p) => p.id == 'abyss');
      expect(abyss.name, 'Abyssal Depth');
      expect(abyss.defaultAccentId, 'cyan');

      final aurora = PlixTheme.presetOptions.firstWhere((p) => p.id == 'aurora');
      expect(aurora.name, 'Borealis Aurora');
      expect(aurora.defaultAccentId, 'mint');

      final dune = PlixTheme.presetOptions.firstWhere((p) => p.id == 'dune');
      expect(dune.name, 'Desert Mirage');
      expect(dune.defaultAccentId, 'gold');

      final royal = PlixTheme.presetOptions.firstWhere((p) => p.id == 'royal');
      expect(royal.name, 'Imperial Amethyst');
      expect(royal.defaultAccentId, 'amethyst');
    });

    test('Liquid Glass theme properties are crystal clear without muddy gray', () {
      final glass = PlixTheme.presetOptions.firstWhere((p) => p.id == 'glass');
      expect(glass.isGlass, isTrue);
      expect(glass.surface.alpha, lessThan(40));
      expect(glass.card.alpha, lessThan(40));
    });
  });
}

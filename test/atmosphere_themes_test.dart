import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plix/app_theme.dart';

void main() {
  group('Atmosphere Themes', () {
    test('Total preset options is 20 and custom is the last option', () {
      expect(PlixTheme.presetOptions.length, 20);
      expect(PlixTheme.presetOptions.last.id, 'custom');
      expect(PlixTheme.presetOptions.last.name, 'Custom Theme');
    });

    test('Includes all new creative atmosphere themes', () {
      final ids = PlixTheme.presetOptions.map((p) => p.id).toList();
      expect(ids.contains('abyss'), isTrue);
      expect(ids.contains('aurora'), isTrue);
      expect(ids.contains('dune'), isTrue);
      expect(ids.contains('rainbow'), isTrue);
      expect(ids.contains('sakura'), isTrue);
      expect(ids.contains('glacier'), isTrue);
      expect(ids.contains('eclipse'), isTrue);
      expect(ids.contains('horizon'), isTrue);

      final sakura = PlixTheme.presetOptions.firstWhere((p) => p.id == 'sakura');
      expect(sakura.name, 'Sakura Blossom');

      final glacier = PlixTheme.presetOptions.firstWhere((p) => p.id == 'glacier');
      expect(glacier.name, 'Glacier Titanium');

      final eclipse = PlixTheme.presetOptions.firstWhere((p) => p.id == 'eclipse');
      expect(eclipse.name, 'Crimson Eclipse');

      final horizon = PlixTheme.presetOptions.firstWhere((p) => p.id == 'horizon');
      expect(horizon.name, 'Golden Horizon');

      final abyss = PlixTheme.presetOptions.firstWhere((p) => p.id == 'abyss');
      expect(abyss.name, 'Abyssal Depth');
      expect(abyss.defaultAccentId, 'cyan');

      final aurora = PlixTheme.presetOptions.firstWhere((p) => p.id == 'aurora');
      expect(aurora.name, 'Borealis Aurora');
      expect(aurora.defaultAccentId, 'mint');

      final dune = PlixTheme.presetOptions.firstWhere((p) => p.id == 'dune');
      expect(dune.name, 'Desert Mirage');
      expect(dune.defaultAccentId, 'gold');

      final rainbow = PlixTheme.presetOptions.firstWhere((p) => p.id == 'rainbow');
      expect(rainbow.name, 'Prism Rainbow');
      expect(rainbow.isRainbow, isTrue);
    });

    test('Liquid Glass theme properties are crystal clear without muddy gray', () {
      final glass = PlixTheme.presetOptions.firstWhere((p) => p.id == 'glass');
      expect(glass.isGlass, isTrue);
      expect(glass.surface.alpha, lessThan(40));
      expect(glass.card.alpha, lessThan(40));
    });

    test('Glass sidebar transparency slider levels (1 to 5) and gradient', () async {
      expect(PlixTheme.isGlassSidebarLevel, inInclusiveRange(1, 5));

      await PlixTheme.setGlassSidebarLevel(1);
      expect(PlixTheme.isGlassSidebarLevel, 1);
      final grad1 = PlixTheme.glassSidebarGradient();
      expect(grad1.colors.first.alpha, 0xF4);

      await PlixTheme.setGlassSidebarLevel(5);
      expect(PlixTheme.isGlassSidebarLevel, 5);
      final grad5 = PlixTheme.glassSidebarGradient();
      expect(grad5.colors.first.alpha, 0x20);

      // Clamping test
      await PlixTheme.setGlassSidebarLevel(0);
      expect(PlixTheme.isGlassSidebarLevel, 1);
      await PlixTheme.setGlassSidebarLevel(10);
      expect(PlixTheme.isGlassSidebarLevel, 5);

      // Restore default 3
      await PlixTheme.setGlassSidebarLevel(3);
      expect(PlixTheme.isGlassSidebarLevel, 3);
    });

    test('Glass sidebar blur option can be toggled', () async {
      final initial = PlixTheme.isGlassSidebarBlur;
      await PlixTheme.setGlassSidebarBlur(!initial);
      expect(PlixTheme.isGlassSidebarBlur, !initial);
      await PlixTheme.setGlassSidebarBlur(initial);
      expect(PlixTheme.isGlassSidebarBlur, initial);
    });

    test('Glass sidebar retains active theme preset colors', () async {
      final solar = PlixTheme.presetOptions.firstWhere((p) => p.id == 'solar');
      final matrix = PlixTheme.presetOptions.firstWhere((p) => p.id == 'matrix');
      final cinema = PlixTheme.presetOptions.firstWhere((p) => p.id == 'cinema');

      final solarGrad = PlixTheme.glassSidebarGradient(3, solar);
      expect(solarGrad.colors[1].red, solar.surface.red);
      expect(solarGrad.colors[1].green, solar.surface.green);
      expect(solarGrad.colors[1].blue, solar.surface.blue);

      final matrixGrad = PlixTheme.glassSidebarGradient(3, matrix);
      expect(matrixGrad.colors[1].red, matrix.surface.red);
      expect(matrixGrad.colors[1].green, matrix.surface.green);
      expect(matrixGrad.colors[1].blue, matrix.surface.blue);

      final cinemaGrad = PlixTheme.glassSidebarGradient(3, cinema);
      expect(cinemaGrad.colors[1].red, cinema.surface.red);
      expect(cinemaGrad.colors[1].green, cinema.surface.green);
      expect(cinemaGrad.colors[1].blue, cinema.surface.blue);
    });

    test('Accent color names are clean single words without descriptive adjectives and includes Rainbow without Violet', () {
      final names = PlixTheme.colorOptions.map((c) => c.name).toList();
      expect(names, [
        'Orange',
        'Gold',
        'Crimson',
        'Ruby',
        'Fuchsia',
        'Amethyst',
        'Indigo',
        'Blue',
        'Cyan',
        'Frost',
        'Teal',
        'Mint',
        'Green',
        'Platinum',
        'Rainbow',
      ]);
      expect(names.contains('Violet'), isFalse);
      expect(names.contains('Rainbow'), isTrue);
    });

    test('Glass sidebar blur level has 5 positions mapping internally to 5, 10, 20, 30, 40 percent', () async {
      await PlixTheme.setGlassSidebarBlurLevel(1);
      expect(PlixTheme.isGlassSidebarBlurLevel, 1);
      expect(PlixTheme.glassSidebarBlurPercent, 5);
      expect(PlixTheme.glassSidebarBlurSigma, 1.25);

      await PlixTheme.setGlassSidebarBlurLevel(2);
      expect(PlixTheme.isGlassSidebarBlurLevel, 2);
      expect(PlixTheme.glassSidebarBlurPercent, 10);
      expect(PlixTheme.glassSidebarBlurSigma, 2.5);

      await PlixTheme.setGlassSidebarBlurLevel(3);
      expect(PlixTheme.isGlassSidebarBlurLevel, 3);
      expect(PlixTheme.glassSidebarBlurPercent, 20);
      expect(PlixTheme.glassSidebarBlurSigma, 5.0);

      await PlixTheme.setGlassSidebarBlurLevel(4);
      expect(PlixTheme.isGlassSidebarBlurLevel, 4);
      expect(PlixTheme.glassSidebarBlurPercent, 30);
      expect(PlixTheme.glassSidebarBlurSigma, 7.5);

      await PlixTheme.setGlassSidebarBlurLevel(5);
      expect(PlixTheme.isGlassSidebarBlurLevel, 5);
      expect(PlixTheme.glassSidebarBlurPercent, 40);
      expect(PlixTheme.glassSidebarBlurSigma, 10.0);

      // Clamping test
      await PlixTheme.setGlassSidebarBlurLevel(0);
      expect(PlixTheme.isGlassSidebarBlurLevel, 1);
      await PlixTheme.setGlassSidebarBlurLevel(10);
      expect(PlixTheme.isGlassSidebarBlurLevel, 5);

      // Restore default 2 (10%)
      await PlixTheme.setGlassSidebarBlurLevel(2);
      expect(PlixTheme.isGlassSidebarBlurLevel, 2);
    });

    test('Green accent color is full on #00FF00', () {
      final green = PlixTheme.colorOptions.firstWhere((c) => c.id == 'green');
      expect(green.primary, const Color(0xFF00FF00));
    });

    test('Rainbow theme has deep purple background matching Cosmic Nebula and provides darker subtle rainbowButtonGradient', () {
      final rainbow = PlixTheme.presetOptions.firstWhere((p) => p.id == 'rainbow');
      final nebula = PlixTheme.presetOptions.firstWhere((p) => p.id == 'nebula');
      expect(rainbow.background, nebula.background);
      expect(rainbow.surface, nebula.surface);
      expect(rainbow.card, nebula.card);
      expect(rainbow.defaultAccentId, 'rainbow');
      expect(PlixTheme.rainbowButtonGradient.colors.length, 5);

      PlixTheme.currentPreset.value = rainbow;
      expect(PlixTheme.isRainbow, isTrue);
      expect(PlixTheme.isRainbowBorder, isTrue);
      final deco = PlixTheme.backgroundDecoration;
      expect(deco.color, nebula.background);

      // Reset
      PlixTheme.resetToDefaultModern();
    });

    test('glassButtonAlpha maps level 1-5 correctly', () async {
      await PlixTheme.setGlassSidebarLevel(1);
      expect(PlixTheme.glassButtonAlpha, 0xF0);
      await PlixTheme.setGlassSidebarLevel(4);
      expect(PlixTheme.glassButtonAlpha, 0x50);
      await PlixTheme.setGlassSidebarLevel(5);
      expect(PlixTheme.glassButtonAlpha, 0x22);
      await PlixTheme.setGlassSidebarLevel(4);
    });

    test('Vaporwave defaults to crimson accent and Solar Flare defaults to gold accent', () {
      final vaporwave = PlixTheme.presetOptions.firstWhere((p) => p.id == 'vaporwave');
      expect(vaporwave.defaultAccentId, 'crimson');

      final solar = PlixTheme.presetOptions.firstWhere((p) => p.id == 'solar');
      expect(solar.defaultAccentId, 'gold');
    });

    test('Color options length is 15 yielding exactly 16 tiles (2 rows of 8) with Custom tile', () {
      expect(PlixTheme.colorOptions.length, 15);
      final totalTiles = PlixTheme.colorOptions.length + 1;
      expect(totalTiles, 16);
      expect(totalTiles % 8, 0);
    });

    test('GradientBoxBorder can safely interpolate with BoxBorder.lerp and BoxDecoration.lerp', () {
      const gradient = PlixTheme.vividRainbowGradient;
      final rainbowBorder = GradientBoxBorder(gradient: gradient, width: 2.2);
      final normalBorder = Border.all(color: Colors.white, width: 1.2);

      // Must not throw ArgumentError
      final lerpedBorder = BoxBorder.lerp(normalBorder, rainbowBorder, 0.5);
      expect(lerpedBorder, isNotNull);

      final lerpedBorderRev = BoxBorder.lerp(rainbowBorder, normalBorder, 0.5);
      expect(lerpedBorderRev, isNotNull);

      final decoNormal = BoxDecoration(border: normalBorder);
      final decoRainbow = BoxDecoration(border: rainbowBorder);

      final lerpedDeco = BoxDecoration.lerp(decoNormal, decoRainbow, 0.5);
      expect(lerpedDeco, isNotNull);

      final decoEnd = BoxDecoration.lerp(decoNormal, decoRainbow, 1.0);
      expect(decoEnd?.border, isA<GradientBoxBorder>());

      // Both must be uniform so BoxPainter paints rounded rectangles at all t
      expect(rainbowBorder.isUniform, isTrue);
      final lerped = lerpedBorder as Border;
      expect(lerped.isUniform, isTrue);
      expect(lerped.top.color, lerped.right.color);
      expect(lerped.top.color, lerped.bottom.color);
      expect(lerped.top.color, lerped.left.color);
    });
  });
}

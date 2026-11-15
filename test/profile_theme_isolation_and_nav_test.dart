import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:plix/app_theme.dart';
import 'package:plix/services/profile_service.dart';
import 'package:plix/screens/appearance_screen.dart';
import 'package:plix/widgets/appearance_hero_tile.dart';
import 'package:plix/widgets/plix_button.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    ProfileService.targetProfileIdOverride = null;
    PlixTheme.resetToDefaultModern();
  });

  group('Profile Theme Isolation Tests', () {
    test('targetProfileIdOverride overrides active profile id for theme keys', () async {
      // With no active profile and no override:
      expect(ProfileService.key('theme_preset'), equals('theme_preset'));

      // Set targetProfileIdOverride to an editing profile ID:
      ProfileService.targetProfileIdOverride = 'profile_123';
      expect(ProfileService.key('theme_preset'), equals('prof_profile_123_theme_preset'));

      // Save a preset under this overridden profile:
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(ProfileService.key('app_theme_preset_id'), 'cyberpunk');

      // Verify the value was stored under the overridden profile key:
      expect(prefs.getString('prof_profile_123_app_theme_preset_id'), equals('cyberpunk'));

      // Clear override:
      ProfileService.targetProfileIdOverride = null;
      expect(ProfileService.key('theme_preset'), equals('theme_preset'));
    });

    test('PlixTheme.resetToDefaultModern restores neutral Plix theme', () async {
      // Set to a custom non-default theme preset
      PlixTheme.currentPreset.value = PlixTheme.presetOptions.firstWhere((p) => p.id == 'cyberpunk');
      PlixTheme.currentThemeOption.value = PlixTheme.colorOptions.firstWhere((c) => c.id == 'crimson');
      expect(PlixTheme.currentPreset.value.id, equals('cyberpunk'));

      // Reset to default modern (as Who's Watching requires)
      PlixTheme.resetToDefaultModern();
      expect(PlixTheme.currentPreset.value.id, equals('modern'));
      expect(PlixTheme.currentThemeOption.value.id, equals('gold'));
    });
  });

  group('PlixButton Icon-Only Tests', () {
    testWidgets('PlixButton with empty label renders as icon-only button without text widget', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: PlixButton(
                onPressed: () {},
                label: '',
                icon: const Icon(Icons.refresh_rounded),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.refresh_rounded), findsOneWidget);
      expect(find.byType(Text), findsNothing);
    });
  });

  group('AppearanceHeroTile Widget Tests', () {
    testWidgets('AppearanceHeroTile renders preset name, accent chip, and action button', (tester) async {
      final focusNode = FocusNode();
      bool selected = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: AppearanceHeroTile(
                focusNode: focusNode,
                onSelect: () => selected = true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Edit Appearance & Themes'), findsOneWidget);
      expect(find.text(PlixTheme.currentPreset.value.name), findsOneWidget);

      await tester.tap(find.byType(AppearanceHeroTile));
      await tester.pumpAndSettle();
      expect(selected, isTrue);

      focusNode.dispose();
    });

    testWidgets('AppearanceHeroTile absorbs arrowLeft and arrowRight to keep cursor stationary', (tester) async {
      final heroNode = FocusNode();
      final otherNode = FocusNode();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                Focus(focusNode: otherNode, child: const SizedBox(height: 10)),
                AppearanceHeroTile(
                  focusNode: heroNode,
                  onSelect: () {},
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      heroNode.requestFocus();
      await tester.pumpAndSettle();
      expect(heroNode.hasFocus, isTrue);

      // Send arrowLeft
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(heroNode.hasFocus, isTrue);

      // Send arrowRight
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(heroNode.hasFocus, isTrue);

      heroNode.dispose();
      otherNode.dispose();
    });
  });

  group('AppearanceScreen Scroll & Header Tests', () {
    testWidgets('AppearanceScreen uses BouncingScrollPhysics and does not contain PlixHomeButton', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: AppearanceScreen(),
        ),
      );
      await tester.pumpAndSettle();

      final scrollFinder = find.byType(SingleChildScrollView);
      expect(scrollFinder, findsWidgets);
      final scrollView = tester.widget<SingleChildScrollView>(scrollFinder.first);
      expect(scrollView.physics, isA<BouncingScrollPhysics>());

      // Verify PlixHomeButton is completely absent
      expect(find.byIcon(Icons.home_rounded), findsNothing);
    });
  });
}

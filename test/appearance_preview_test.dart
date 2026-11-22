import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plix/app_theme.dart';
import 'package:plix/screens/appearance_screen.dart';
import 'package:plix/widgets/brand_logo.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Appearance Live Theme Preview Bar', () {
    setUp(() {
      PlixTheme.glassSidebar.value = false;
      PlixTheme.glassSidebarBlur.value = false;
      PlixTheme.glassSidebarLevel.value = 3;
    });

    testWidgets('LiveThemePreviewBar renders with PlixWordmark repeated pattern', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AppearanceScreen(),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));

      // Verify PlixWordmarks are present in the preview bar background
      expect(find.byType(PlixWordmark), findsWidgets);
      expect(find.text('Live Preview'), findsOneWidget);
      expect(find.text('Accent'), findsOneWidget);
      expect(find.text('Watch'), findsOneWidget);
      expect(find.text('Details'), findsOneWidget);
    });

    testWidgets('LiveThemePreviewBar reflects glassSidebar toggle and blur', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AppearanceScreen(),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));

      // Enable glass sidebar and blur
      PlixTheme.glassSidebar.value = true;
      PlixTheme.glassSidebarBlur.value = true;
      await tester.pump(const Duration(milliseconds: 200));

      expect(PlixTheme.isGlassSidebar, isTrue);
      expect(PlixTheme.isGlassSidebarBlur, isTrue);
      expect(find.byType(BackdropFilter), findsWidgets);
    });
  });
}

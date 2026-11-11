import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plix/models/plex_library.dart';
import 'package:plix/models/plex_server.dart';
import 'package:plix/screens/library_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LibraryScreen Top Buttons Navigation', () {
    testWidgets('Pressing UP on any top button does nothing and stays on button', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final testServer = PlexServer(
        name: 'Test Server',
        clientIdentifier: 'test_srv',
        accessToken: 'test_tok',
        owned: true,
        connections: [],
      );

      final testLibrary = PlexLibrary(
        key: '1',
        title: 'Movies',
        type: 'movie',
        serverId: 'test_srv',
        server: testServer,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: LibraryScreen(
            library: testLibrary,
            server: testServer,
            clientId: 'client_123',
          ),
        ),
      );

      await tester.pump();

      // Verify top icon buttons exist: Back, Categories, Sort, Refresh
      final iconButtons = tester.widgetList<IconButton>(find.byType(IconButton)).toList();
      expect(iconButtons.length, equals(4));

      for (final iconButton in iconButtons) {
        final focusNode = iconButton.focusNode!;
        focusNode.requestFocus();
        await tester.pump();
        expect(focusNode.hasFocus, isTrue);

        // Send Arrow Up
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
        await tester.pump();

        // Focus must remain on the button!
        expect(focusNode.hasFocus, isTrue, reason: 'Button with label ${focusNode.debugLabel} should retain focus on ArrowUp');
      }
    });

    testWidgets('Horizontal and downward navigation between top buttons remains smooth', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final testServer = PlexServer(
        name: 'Test Server',
        clientIdentifier: 'test_srv',
        accessToken: 'test_tok',
        owned: true,
        connections: [],
      );

      final testLibrary = PlexLibrary(
        key: '1',
        title: 'Movies',
        type: 'movie',
        serverId: 'test_srv',
        server: testServer,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: LibraryScreen(
            library: testLibrary,
            server: testServer,
            clientId: 'client_123',
          ),
        ),
      );

      await tester.pump();

      final iconButtons = tester.widgetList<IconButton>(find.byType(IconButton)).toList();
      final backNode = iconButtons[0].focusNode!;
      final catNode = iconButtons[1].focusNode!;
      final sortNode = iconButtons[2].focusNode!;
      final refreshNode = iconButtons[3].focusNode!;

      // Start on Sort button
      sortNode.requestFocus();
      await tester.pump();
      expect(sortNode.hasFocus, isTrue);

      // Move Left to Categories
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      expect(catNode.hasFocus, isTrue);

      // Move Left to Back
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      expect(backNode.hasFocus, isTrue);

      // Press UP on Back: stays on Back
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      expect(backNode.hasFocus, isTrue);

      // Move Right back to Categories
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(catNode.hasFocus, isTrue);

      // Move Right to Sort
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(sortNode.hasFocus, isTrue);

      // Move Right to Refresh
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(refreshNode.hasFocus, isTrue);

      // Press UP on Refresh: stays on Refresh
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      expect(refreshNode.hasFocus, isTrue);
    });
  });
}

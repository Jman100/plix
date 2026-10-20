import 'package:flutter_test/flutter_test.dart';
import 'package:plix/main.dart';
import 'package:plix/services/plex_auth_service.dart';
import 'package:plix/services/plex_server_service.dart';

void main() {
  testWidgets('PlixApp smoke test', (WidgetTester tester) async {
    final authService = PlexAuthService();
    final serverService = PlexServerService(authService: authService);

    await tester.pumpWidget(PlixApp(
      authService: authService,
      serverService: serverService,
    ));

    expect(find.byType(PlixApp), findsOneWidget);
  });
}

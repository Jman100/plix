import 'package:flutter_test/flutter_test.dart';
import 'package:plix/main.dart';
import 'package:plix/services/iphone_duo_service.dart';
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
    await tester.pump(const Duration(seconds: 2));
  });

  test('IPhoneDuoInfo parsing and posture resolution', () {
    // Non-Duo device map
    final nonDuo = IPhoneDuoInfo.fromMap({
      'isDuo': false,
      'posture': 'none',
      'angle': 0.0,
      'foldY': 0.0,
      'foldBand': 0.0,
    });
    expect(nonDuo.isDuo, isFalse);
    expect(nonDuo.posture, DuoPosture.none);

    // iPhone Duo tabletop posture
    final duoTabletop = IPhoneDuoInfo.fromMap({
      'isDuo': true,
      'posture': 'tabletop',
      'angle': 1.57,
      'foldY': 475.5,
      'foldBand': 40.0,
    });
    expect(duoTabletop.isDuo, isTrue);
    expect(duoTabletop.posture, DuoPosture.tabletop);
    expect(duoTabletop.foldCoord, 475.5);
    expect(duoTabletop.foldBand, 40.0);

    // iPhone Duo closed posture
    final duoClosed = IPhoneDuoInfo.fromMap({
      'isDuo': true,
      'posture': 'closed',
      'angle': 0.0,
      'foldY': 475.5,
      'foldBand': 40.0,
    });
    expect(duoClosed.isDuo, isTrue);
    expect(duoClosed.posture, DuoPosture.closed);

    // iPhone Duo book posture
    final duoBook = IPhoneDuoInfo.fromMap({
      'isDuo': true,
      'posture': 'book',
      'angle': 1.57,
      'foldY': 475.5,
      'foldBand': 40.0,
    });
    expect(duoBook.isDuo, isTrue);
    expect(duoBook.posture, DuoPosture.book);
  });
}

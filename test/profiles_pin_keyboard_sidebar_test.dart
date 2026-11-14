import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:plix/services/profile_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ProfileService shouldForceAlwaysAsk tests', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
    });

    test('Single profile with PIN forces always ask', () async {
      SharedPreferences.setMockInitialValues({
        'plix_profiles_list': '[{"id":"p1","name":"Home","avatarId":"avatar_default","avatarColorId":"gradient_gold","pin":"1234","hasPin":true,"createdAt":1700000000000}]',
        'plix_active_profile_id': 'p1',
      });
      await ProfileService.instance.init();
      expect(ProfileService.instance.shouldForceAlwaysAsk, isTrue);
    });

    test('Single profile without PIN does not force always ask', () async {
      SharedPreferences.setMockInitialValues({
        'plix_profiles_list': '[{"id":"p1","name":"Home","avatarId":"avatar_default","avatarColorId":"gradient_gold","pin":"","hasPin":false,"createdAt":1700000000000}]',
        'plix_active_profile_id': 'p1',
      });
      await ProfileService.instance.init();
      expect(ProfileService.instance.shouldForceAlwaysAsk, isFalse);
    });

    test('Multiple profiles all with PIN force always ask', () async {
      SharedPreferences.setMockInitialValues({
        'plix_profiles_list': '[{"id":"p1","name":"User 1","avatarId":"avatar_default","avatarColorId":"gradient_gold","pin":"1111","hasPin":true,"createdAt":1700000000000},{"id":"p2","name":"User 2","avatarId":"avatar_cat","avatarColorId":"gradient_blue","pin":"2222","hasPin":true,"createdAt":1700000000000}]',
        'plix_active_profile_id': 'p1',
      });
      await ProfileService.instance.init();
      expect(ProfileService.instance.shouldForceAlwaysAsk, isTrue);
    });

    test('Multiple profiles where at least one has no PIN do NOT force always ask', () async {
      SharedPreferences.setMockInitialValues({
        'plix_profiles_list': '[{"id":"p1","name":"User 1","avatarId":"avatar_default","avatarColorId":"gradient_gold","pin":"1111","hasPin":true,"createdAt":1700000000000},{"id":"p2","name":"User 2","avatarId":"avatar_cat","avatarColorId":"gradient_blue","pin":"","hasPin":false,"createdAt":1700000000000}]',
        'plix_active_profile_id': 'p1',
      });
      await ProfileService.instance.init();
      expect(ProfileService.instance.shouldForceAlwaysAsk, isFalse);
    });
  });
}

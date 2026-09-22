import 'package:edupro_flutter_web/core/constants/establishment_types.dart';
import 'package:edupro_flutter_web/data/models/user_model.dart';
import 'package:edupro_flutter_web/navigation/nav_items.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('la session admin conserve sa direction et ses cycles', () {
    final user = UserModel.fromJson({
      'id': 'admin-1',
      'name': 'BOUAKO Leader',
      'email': 'admin@ecole.test',
      'role': 'admin',
      'schoolId': 'school-1',
      'mustChangePassword': false,
      'directionId': 'direction-lycee',
      'direction': {
        'id': 'direction-lycee',
        'name': 'Direction Lycée',
        'cycles': [
          {'id': 'cycle-lycee', 'name': 'Lycée'}
        ],
      },
    });

    expect(user.directionId, 'direction-lycee');
    expect(user.directionName, 'Direction Lycée');
    expect(user.directionCycleIds, ['cycle-lycee']);
    expect(user.legacyDirectionScope, isFalse);
    expect(user.toJson().containsKey('password'), isFalse);
    expect(user.toJson().containsKey('passwordHash'), isFalse);
  });

  test('la compatibilité des administrateurs existants reste explicite', () {
    final user = UserModel.fromJson({
      'id': 'admin-legacy',
      'name': 'Administrateur existant',
      'email': 'legacy@ecole.test',
      'role': 'admin',
      'schoolId': 'school-1',
      'legacyDirectionScope': true,
    });

    expect(user.directionId, isNull);
    expect(user.directionCycleIds, isEmpty);
    expect(user.legacyDirectionScope, isTrue);
  });

  test('la gestion des directions reste réservée au Super Admin', () {
    final superAdminItems = NavItems.getNavItemsForRole(UserRole.superadmin);
    final adminItems = NavItems.getNavItemsForRole(UserRole.admin);

    expect(superAdminItems.map((item) => item.id), contains('directions'));
    expect(adminItems.map((item) => item.id), isNot(contains('directions')));
  });
}

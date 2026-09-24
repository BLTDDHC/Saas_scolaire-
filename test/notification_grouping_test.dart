import 'package:edupro_flutter_web/core/utils/notification_grouping.dart';
import 'package:edupro_flutter_web/data/models/other_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('notifications are grouped by real month and sorted newest first', () {
    final groups = groupNotificationsByMonth([
      NotificationModel(
        id: 'august',
        title: 'Août',
        time: '2026-08-31T10:00:00Z',
      ),
      NotificationModel(
        id: 'september-old',
        title: 'Septembre ancien',
        time: '2026-09-01T08:00:00Z',
      ),
      NotificationModel(
        id: 'september-new',
        title: 'Septembre récent',
        time: '2026-09-24T12:00:00Z',
      ),
    ]);

    expect(groups.map((group) => group.label).toList(),
        ['Septembre 2026', 'Août 2026']);
    expect(groups.first.items.map((item) => item.id).toList(),
        ['september-new', 'september-old']);
    expect(notificationDisplayTime(groups.first.items.first),
        contains('24/09/2026'));
  });
}

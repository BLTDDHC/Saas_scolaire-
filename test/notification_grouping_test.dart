import 'package:edupro_flutter_web/core/utils/notification_grouping.dart';
import 'package:edupro_flutter_web/data/models/other_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('notifications are grouped by persisted month and newest first', () {
    final groups = groupNotificationsByMonth([
      NotificationModel(
        id: 'aug',
        title: 'Août',
        time: '2026-08-31T23:00:00Z',
      ),
      NotificationModel(
        id: 'sep-old',
        title: 'Septembre ancien',
        time: '2026-09-01T08:00:00Z',
      ),
      NotificationModel(
        id: 'sep-new',
        title: 'Septembre récent',
        time: '2026-09-24T09:30:00Z',
      ),
    ]);

    expect(groups.keys.toList(), ['Septembre 2026', 'Août 2026']);
    expect(
      groups['Septembre 2026']!.map((item) => item.id).toList(),
      ['sep-new', 'sep-old'],
    );
    expect(groups['Août 2026']!.single.id, 'aug');
  });

  test('monthly grouping preserves read state and real timestamp', () {
    final unread = NotificationModel(
      id: 'unread',
      title: 'Résultats',
      time: '2026-09-23T18:45:00+01:00',
      read: false,
    );
    final groups = groupNotificationsByMonth([unread]);
    expect(groups['Septembre 2026']!.single.read, isFalse);
    expect(notificationDate(unread).year, 2026);
    expect(notificationDate(unread).month, 9);
  });
}

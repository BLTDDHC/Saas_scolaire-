import 'package:edupro_flutter_web/core/utils/notification_grouping.dart';
import 'package:edupro_flutter_web/data/models/other_models.dart';
import 'package:flutter_test/flutter_test.dart';

NotificationModel notification(String id, String time) => NotificationModel(
      id: id,
      title: id,
      time: time,
    );

void main() {
  test('notifications are grouped by persisted month and newest first', () {
    final groups = groupNotificationsByMonth([
      notification('aug-old', '2026-08-01T08:00:00Z'),
      notification('sep-old', '2026-09-03T08:00:00Z'),
      notification('sep-new', '2026-09-20T09:00:00Z'),
      notification('jul', '2026-07-30T08:00:00Z'),
    ]);

    expect(groups.keys.toList(), [
      'Septembre 2026',
      'Août 2026',
      'Juillet 2026',
    ]);
    expect(groups['Septembre 2026']!.map((item) => item.id).toList(),
        ['sep-new', 'sep-old']);
  });
}

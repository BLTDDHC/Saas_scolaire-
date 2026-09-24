import '../../data/models/other_models.dart';

const _notificationMonths = [
  'janvier', 'février', 'mars', 'avril', 'mai', 'juin',
  'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre',
];

DateTime notificationDate(NotificationModel item) =>
    DateTime.tryParse(item.time)?.toLocal() ??
    DateTime.fromMillisecondsSinceEpoch(0);

String notificationMonthLabel(DateTime value) {
  final name = _notificationMonths[value.month - 1];
  return '${name[0].toUpperCase()}${name.substring(1)} ${value.year}';
}

Map<String, List<NotificationModel>> groupNotificationsByMonth(
    Iterable<NotificationModel> source) {
  final items = source.toList()
    ..sort((a, b) {
      final byDate = notificationDate(b).compareTo(notificationDate(a));
      return byDate != 0 ? byDate : b.id.compareTo(a.id);
    });
  final result = <String, List<NotificationModel>>{};
  for (final item in items) {
    final date = notificationDate(item);
    final label = notificationMonthLabel(date);
    result.putIfAbsent(label, () => <NotificationModel>[]).add(item);
  }
  return result;
}

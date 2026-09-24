import '../../data/models/other_models.dart';

class NotificationMonthGroup {
  const NotificationMonthGroup({
    required this.label,
    required this.items,
  });

  final String label;
  final List<NotificationModel> items;
}

const _notificationMonths = <String>[
  'Janvier',
  'Février',
  'Mars',
  'Avril',
  'Mai',
  'Juin',
  'Juillet',
  'Août',
  'Septembre',
  'Octobre',
  'Novembre',
  'Décembre',
];

DateTime? notificationDate(NotificationModel item) =>
    DateTime.tryParse(item.time)?.toLocal();

String notificationMonthLabel(DateTime date) =>
    '${_notificationMonths[date.month - 1]} ${date.year}';

String notificationDisplayTime(NotificationModel item) {
  final date = notificationDate(item);
  if (date == null) return item.time;
  final day = date.day.toString().padLeft(2, '0');
  final month = date.month.toString().padLeft(2, '0');
  final hour = date.hour.toString().padLeft(2, '0');
  final minute = date.minute.toString().padLeft(2, '0');
  return '$day/$month/${date.year} · $hour:$minute';
}

List<NotificationMonthGroup> groupNotificationsByMonth(
    Iterable<NotificationModel> source) {
  final items = source.toList()
    ..sort((left, right) {
      final leftDate = notificationDate(left);
      final rightDate = notificationDate(right);
      if (leftDate == null && rightDate == null) {
        return right.time.compareTo(left.time);
      }
      if (leftDate == null) return 1;
      if (rightDate == null) return -1;
      final byDate = rightDate.compareTo(leftDate);
      return byDate != 0 ? byDate : right.id.compareTo(left.id);
    });
  final groups = <String, List<NotificationModel>>{};
  final order = <String>[];
  for (final item in items) {
    final date = notificationDate(item);
    final label =
        date == null ? 'Date non disponible' : notificationMonthLabel(date);
    if (!groups.containsKey(label)) order.add(label);
    groups.putIfAbsent(label, () => <NotificationModel>[]).add(item);
  }
  return [
    for (final label in order)
      NotificationMonthGroup(label: label, items: groups[label]!)
  ];
}

import '../../data/models/other_models.dart';

DateTime notificationDate(NotificationModel item) =>
    DateTime.tryParse(item.time)?.toLocal() ??
    DateTime.fromMillisecondsSinceEpoch(0);

String notificationMonthLabel(DateTime value) {
  const months = [
    'Janvier', 'Février', 'Mars', 'Avril', 'Mai', 'Juin',
    'Juillet', 'Août', 'Septembre', 'Octobre', 'Novembre', 'Décembre',
  ];
  return '${months[value.month - 1]} ${value.year}';
}

Map<String, List<NotificationModel>> groupNotificationsByMonth(
    Iterable<NotificationModel> source) {
  final items = source.toList()
    ..sort((a, b) => notificationDate(b).compareTo(notificationDate(a)));
  final result = <String, List<NotificationModel>>{};
  for (final item in items) {
    final date = notificationDate(item);
    final label = date.millisecondsSinceEpoch == 0
        ? 'Date non renseignée'
        : notificationMonthLabel(date);
    result.putIfAbsent(label, () => <NotificationModel>[]).add(item);
  }
  return result;
}

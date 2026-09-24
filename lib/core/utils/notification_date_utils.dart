DateTime notificationDate(String value) =>
    DateTime.tryParse(value)?.toLocal() ??
    DateTime.fromMillisecondsSinceEpoch(0);

String notificationMonthLabel(String value) {
  final date = notificationDate(value);
  const months = [
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
  return '${months[date.month - 1]} ${date.year}';
}

String notificationMonthKey(String value) {
  final date = notificationDate(value);
  return '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}';
}

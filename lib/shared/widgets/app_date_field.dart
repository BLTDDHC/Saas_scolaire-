import 'package:flutter/material.dart';

import '../../core/utils/date_utils.dart';

/// Sélecteur de date commun : aucune saisie au clavier et affichage JJ-MM-AAAA.
class AppDateField extends StatelessWidget {
  const AppDateField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.firstDate,
    this.lastDate,
    this.enabled = true,
  });

  final String label;
  final DateTime? value;
  final ValueChanged<DateTime> onChanged;
  final DateTime? firstDate;
  final DateTime? lastDate;
  final bool enabled;

  Future<void> _pick(BuildContext context) async {
    final now = DateTime.now();
    final lowerBound = firstDate ?? DateTime(now.year - 10);
    final upperBound = lastDate ?? DateTime(now.year + 20, 12, 31);
    final initial = value == null
        ? now.isBefore(lowerBound)
            ? lowerBound
            : now.isAfter(upperBound)
                ? upperBound
                : now
        : value!;
    final selected = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: lowerBound,
      lastDate: upperBound,
      helpText: label,
      cancelText: 'Annuler',
      confirmText: 'Choisir',
      fieldLabelText: 'Date',
      fieldHintText: 'JJ-MM-AAAA',
    );
    if (selected != null) onChanged(selected);
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: InkWell(
        onTap: enabled ? () => _pick(context) : null,
        borderRadius: BorderRadius.circular(8),
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: label,
            enabled: enabled,
            suffixIcon: const Icon(Icons.calendar_month_outlined),
          ),
          child: Text(AppDateUtils.formatDate(value)),
        ),
      ),
    );
  }
}

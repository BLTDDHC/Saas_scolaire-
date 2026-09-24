import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/workspace_header.dart';
import '../../../shared/widgets/app_toast.dart';
import '../../../data/datasources/api_client.dart';
import '../../../data/services/store_service.dart';
import '../../../core/utils/date_utils.dart';
import '../documents/receipt_pdf.dart';

const financeKinds = {
  'tuition': 'Frais mensuels',
  'registration': 'Inscription',
  'reenrollment': 'Réinscription',
  'td': 'TD',
  'other': 'Autres frais'
};
const financeMonths = [
  'janvier',
  'février',
  'mars',
  'avril',
  'mai',
  'juin',
  'juillet',
  'août',
  'septembre',
  'octobre',
  'novembre',
  'décembre'
];
String money(dynamic value) => value is num
    ? '${NumberFormat('#,##0', 'fr_FR').format(value)} FCFA'
    : 'Indisponible';
String financeStatus(dynamic value) =>
    const {
      'paid': 'PAYÉ',
      'partial': 'AVANCE',
      'unpaid': 'IMPAYÉ',
      'no_tariff': 'Tarif à configurer',
      'not_applicable': 'Non concerné'
    }[value] ??
    '$value';

class FinancePage extends StatefulWidget {
  const FinancePage({super.key, this.initialStudentId});
  final String? initialStudentId;
  @override
  State<FinancePage> createState() => _FinancePageState();
}

class _FinancePageState extends State<FinancePage> {
  String? _year, _school, _classId, _selectedStudent;
  String _kind = 'tuition';
  String _month = '';
  String _search = '';
  int _tab = 4, _request = 0;
  String _catalogSearch = '';
  bool _busy = false;
  String? _error;
  Map<String, dynamic>? _data;
  List<String> _months = [];
  Timer? _debounce;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final store = context.watch<StoreService>();
    final id =
        store.getSelectedAcademicYearId() ?? store.getActiveAcademicYear()?.id;
    if (_year == id) return;
    _year = id;
    _classId = null;
    _selectedStudent = widget.initialStudentId;
    final years = store.getAcademicYears().where((y) => y.id == id).toList();
    _school =
        years.isNotEmpty ? years.first.schoolId : store.getCurrentSchool()?.id;
    _months = [];
    if (years.isNotEmpty) {
      final start = DateTime.tryParse(years.first.start);
      final end = DateTime.tryParse(years.first.end);
      if (start != null && end != null) {
        for (var date = DateTime(start.year, start.month);
            !date.isAfter(end);
            date = DateTime(date.year, date.month + 1)) {
          _months.add('${date.year}-${date.month.toString().padLeft(2, '0')}');
        }
      }
    }
    final now = DateTime.now();
    final current = '${now.year}-${now.month.toString().padLeft(2, '0')}';
    _month = _months.contains(current)
        ? current
        : (_months.isEmpty ? '' : _months.first);
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  List<Map<String, dynamic>> items(String key) => ((_data?[key] as List?) ?? [])
      .map((r) => Map<String, dynamic>.from(r as Map))
      .toList();

  Future<void> _load() async {
    final token = ++_request;
    _busy = true;
    _error = null;
    _data = null;
    if (_year == null ||
        _school == null ||
        (_kind == 'tuition' && _month.isEmpty)) {
      _busy = false;
      _error =
          'Sélectionnez une année scolaire valide dans le contexte principal.';
      return;
    }
    try {
      final value = await context.read<StoreService>().loadSchoolFinance({
        'academic_year_id': _year!,
        'school_id': _school!,
        'kind': _kind,
        if (_kind == 'tuition') 'month': _month,
        if (_classId != null) 'class_id': _classId!,
        if (_search.isNotEmpty) 'search': _search,
      });
      if (mounted && token == _request) {
        setState(() {
          _data = value;
          _busy = false;
          final periods = (value['budget'] as Map?)?['months'] as List?;
          if (periods != null) {
            _months = periods.cast<String>();
            if (!_months.contains(_month)) {
              _month = _months.isEmpty ? '' : _months.first;
              if (_kind == 'tuition' && _month.isNotEmpty) {
                scheduleMicrotask(reload);
              }
            }
          }
        });
      }
    } catch (error) {
      if (mounted && token == _request) {
        setState(() {
          _error = error is ApiException
              ? AppToast.humanErrorMessage(
                  error.message,
                  fallback: 'Finance est indisponible. Réessayez.',
                )
              : 'Finance est indisponible. Réessayez.';
          _busy = false;
        });
      }
    }
  }

  void reload() {
    setState(() {});
    _load();
  }

  Future<void> _showPaymentSaved(
      int amount, Map<String, dynamic>? receipt) async {
    if (!mounted) return;
    final route = DialogRoute<void>(
      context: context,
      barrierDismissible: true,
      builder: (_) => AlertDialog(
        content: SizedBox(
          width: 330,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.check_circle_rounded,
                color: Colors.green, size: 52),
            const SizedBox(height: 14),
            const Text('Paiement enregistré avec succès',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(money(amount), textAlign: TextAlign.center),
            if (receipt?['receiptNumber'] != null) ...[
              const SizedBox(height: 6),
              Text('Reçu ${receipt!['receiptNumber']}',
                  textAlign: TextAlign.center),
            ],
          ]),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Fermer'),
          ),
        ],
      ),
    );
    Navigator.of(context).push(route);
    await Future<void>.delayed(const Duration(seconds: 2));
    if (mounted && route.isActive) Navigator.of(context).pop();
  }

  Future<void> _pay(Map<String, dynamic> row) async {
    final store = context.read<StoreService>();
    Map<String, dynamic> situation = row;
    var monthRows = <Map<String, dynamic>>[];
    final selectedMonths = <String>{};
    if (row['type'] == 'tuition') {
      try {
        situation = await store.loadFinanceMonthlySituation(
          row['registrationId'].toString(),
          {
            'academic_year_id': _year!,
            if (_school != null) 'school_id': _school!,
          },
        );
        monthRows = ((situation['months'] as List?) ?? const [])
            .map((item) => Map<String, dynamic>.from(item as Map))
            .where((item) => ['unpaid', 'partial'].contains(item['status']))
            .toList();
        final current = monthRows.where((item) => item['month'] == _month);
        if (current.isNotEmpty) {
          selectedMonths.add(_month);
        } else if (monthRows.isNotEmpty) {
          selectedMonths.add(monthRows.first['month'].toString());
        }
      } catch (error) {
        if (mounted) {
          AppToast.error(
            context,
            error is ApiException
                ? error.message
                : 'La situation mensuelle est indisponible.',
          );
        }
        return;
      }
      if (monthRows.isEmpty) {
        if (mounted) {
          AppToast.warning(context, 'Tous les mois sont déjà payés.');
        }
        return;
      }
    }
    int selectedTotal() => monthRows
        .where((item) => selectedMonths.contains(item['month']))
        .fold(0, (total, item) => total + (item['remaining'] as num).toInt());
    final amount = TextEditingController(
        text: (row['type'] == 'tuition'
                ? selectedTotal()
                : (row['remaining'] as num).toInt())
            .toString());
    var method = 'cash', sending = false;
    String? error;
    final route = DialogRoute<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialog) => StatefulBuilder(
            builder: (dialog, refresh) => AlertDialog(
                    title: Text('${situation['lastName'] ?? row['lastName'] ?? ''} '
                        '${situation['firstName'] ?? row['firstName'] ?? row['studentName']}'.trim()),
                    content: SizedBox(
                        width: 430,
                        child: SingleChildScrollView(
                            child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                              Text('${situation['className'] ?? row['className']} - ${row['label']}'),
                              Text('Matricule : ${situation['matricule'] ?? row['matricule'] ?? 'Non attribué'}'),
                              if (row['type'] != 'tuition' && row['month'] != null)
                                Text('Mois : ${row['month']}'),
                              if (row['type'] == 'tuition') ...[
                                const SizedBox(height: 12),
                                const Text('Mois non entièrement payés',
                                    style: TextStyle(fontWeight: FontWeight.w700)),
                                ...monthRows.map((monthRow) => CheckboxListTile(
                                      key: ValueKey('payment-month-${monthRow['month']}'),
                                      contentPadding: EdgeInsets.zero,
                                      dense: true,
                                      value: selectedMonths.contains(monthRow['month']),
                                      title: Text(
                                          '${financeMonths[int.parse(monthRow['month'].substring(5)) - 1]} ${monthRow['month'].substring(0, 4)}'),
                                      subtitle: Text(
                                          'Attendu ${money(monthRow['expected'])} · Payé ${money(monthRow['paid'])} · Reste ${money(monthRow['remaining'])} · ${financeStatus(monthRow['status'])}'),
                                      onChanged: sending
                                          ? null
                                          : (checked) => refresh(() {
                                                if (checked == true) {
                                                  selectedMonths.add(monthRow['month']);
                                                } else {
                                                  selectedMonths.remove(monthRow['month']);
                                                }
                                                amount.text = selectedTotal().toString();
                                              }),
                                    )),
                                Text('Montant attendu total : ${money(selectedTotal())}',
                                    style: const TextStyle(fontWeight: FontWeight.w700)),
                              ] else ...[
                                Text('Tarif : ${money(row['expected'])}'),
                                Text(
                                    'Déjà payé : ${money(row['paid'])} - Reste : ${money(row['remaining'])}'),
                              ],
                              TextField(
                                  controller: amount,
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(
                                      labelText: 'Montant payé (FCFA)')),
                              DropdownButtonFormField<String>(
                                  isExpanded: true,
                                  initialValue: method,
                                  items: const [
                                    DropdownMenuItem(
                                        value: 'cash', child: Text('Espèces')),
                                    DropdownMenuItem(
                                        value: 'mobile',
                                        child: Text('Mobile money')),
                                    DropdownMenuItem(
                                        value: 'transfer',
                                        child: Text('Virement')),
                                    DropdownMenuItem(
                                        value: 'card', child: Text('Carte')),
                                  ],
                                  onChanged:
                                      sending ? null : (v) => method = v!,
                                  decoration: const InputDecoration(
                                      labelText: 'Moyen de paiement')),
                              if (error != null)
                                Text(error!,
                                    style: const TextStyle(color: Colors.red)),
                            ]))),
                    actions: [
                      TextButton(
                          onPressed:
                              sending ? null : () => Navigator.pop(dialog),
                          child: const Text('Annuler')),
                      FilledButton(
                          onPressed: sending
                              ? null
                              : () async {
                                  final value =
                                      int.tryParse(amount.text.trim());
                                  if (value == null || value <= 0) {
                                    refresh(() => error =
                                        'Saisissez un montant entier positif.');
                                    return;
                                  }
                                  if (row['type'] == 'tuition' &&
                                      selectedMonths.isEmpty) {
                                    refresh(() => error =
                                        'Sélectionnez au moins un mois.');
                                    return;
                                  }
                                  if (row['type'] == 'tuition' &&
                                      value > selectedTotal()) {
                                    refresh(() => error =
                                        'Le montant dépasse le reste des mois sélectionnés.');
                                    return;
                                  }
                                  refresh(() => sending = true);
                                  try {
                                    final result =
                                        await store.paySchoolFinance({
                                      'registrationId': row['registrationId'],
                                      'type': row['type'],
                                      if (row['type'] == 'other')
                                        'feeId': row['feeId'],
                                      if (row['type'] == 'tuition')
                                        'months': selectedMonths.toList()
                                      else
                                        'month': row['month'],
                                      'amount': value,
                                      'paymentMethod': method,
                                      'schoolId': _school
                                    });
                                    if (dialog.mounted) Navigator.pop(dialog);
                                    if (mounted) {
                                      final receipt = result['receipt'] is Map
                                          ? Map<String, dynamic>.from(
                                              result['receipt'] as Map)
                                          : null;
                                      await _showPaymentSaved(value, receipt);
                                      reload();
                                    }
                                  } catch (e) {
                                    if (dialog.mounted)
                                      refresh(() {
                                        sending = false;
                                        error = e is ApiException
                                            ? e.message
                                            : 'Paiement non enregistré.';
                                      });
                                  }
                                },
                          child: Text(sending
                              ? 'Enregistrement…'
                              : 'Encaisser')),
                    ])));
    await Navigator.of(context).push(route);
    await route.completed;
    amount.dispose();
  }

  Future<void> _tariff([Map<String, dynamic>? existing]) async {
    final classes = items('classes');
    if (classes.isEmpty) return;
    final name = TextEditingController(text: existing?['name'] ?? '');
    final amount = TextEditingController(
        text: existing == null ? '' : '${existing['amount']}');
    var kind = existing?['type']?.toString() ?? 'tuition';
    var scope = existing?['scope']?.toString() ?? 'class';
    String? tariffMonth = existing?['month']?.toString();
    String? tariffRegime = existing?['regime']?.toString();
    String? target = existing?['classId']?.toString() ?? classes.first['id'];
    String? levelId = existing?['levelId']?.toString();
    String? cycleId = existing?['cycle']?.toString();
    var sending = false;
    String? error;
    final levels = <String, String>{
      for (final cl in classes)
        if (cl['levelId'] != null)
          cl['levelId'].toString():
              cl['levelName']?.toString() ?? cl['name'].toString()
    };
    final cycles = <String, String>{
      for (final cl in classes)
        if (cl['cycleId'] != null)
          cl['cycleId'].toString():
              cl['cycleName']?.toString() ?? 'Cycle scolaire'
    };
    bool regimeAppliesToTarget() {
      String? cycleName;
      if (scope == 'class') {
        final match = classes.where((item) => item['id']?.toString() == target);
        if (match.isNotEmpty) cycleName = match.first['cycleName']?.toString();
      } else if (scope == 'level') {
        final match = classes.where((item) => item['levelId']?.toString() == levelId);
        if (match.isNotEmpty) cycleName = match.first['cycleName']?.toString();
      } else if (scope == 'cycle') {
        cycleName = cycles[cycleId];
      }
      final normalized = (cycleName ?? '').trim().toUpperCase();
      return normalized.contains('MATERNELLE') || normalized.contains('PRIMAIRE');
    }

    final store = context.read<StoreService>();
    final route = DialogRoute<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialog) => StatefulBuilder(
            builder: (dialog, refresh) => AlertDialog(
                    title: Text(existing == null
                        ? 'Ajouter un tarif'
                        : 'Modifier le tarif'),
                    content: SizedBox(
                        width: 440,
                        child: SingleChildScrollView(
                            child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                              DropdownButtonFormField<String>(
                                  isExpanded: true,
                                  initialValue: kind,
                                  decoration: const InputDecoration(
                                      labelText: 'Nature'),
                                  items: financeKinds.entries
                                      .map((e) => DropdownMenuItem(
                                          value: e.key, child: Text(e.value)))
                                      .toList(),
                                  onChanged: existing != null || sending
                                      ? null
                                      : (v) => refresh(() => kind = v!)),
                              if (existing == null)
                                DropdownButtonFormField<String>(
                                    isExpanded: true,
                                    initialValue: scope,
                                    decoration: const InputDecoration(
                                        labelText: 'Portée du tarif'),
                                    items: const [
                                      DropdownMenuItem(
                                          value: 'cycle', child: Text('Cycle')),
                                      DropdownMenuItem(
                                          value: 'class',
                                          child: Text('Classe')),
                                      DropdownMenuItem(
                                          value: 'level', child: Text('Niveau'))
                                    ],
                                    onChanged: sending
                                        ? null
                                        : (v) => refresh(() {
                                              scope = v!;
                                              tariffRegime = null;
                                            })),
                              if (existing == null && scope == 'class')
                                DropdownButtonFormField<String>(
                                    isExpanded: true,
                                    key: const ValueKey('tariff-class'),
                                    initialValue: target,
                                    decoration: const InputDecoration(
                                        labelText: 'Classe'),
                                    items: classes
                                        .map((cl) => DropdownMenuItem<String>(
                                            value: cl['id'],
                                            child: Text(cl['name'])))
                                        .toList(),
                                    onChanged: sending
                                        ? null
                                        : (v) => refresh(() {
                                              target = v;
                                              if (!regimeAppliesToTarget()) tariffRegime = null;
                                            })),
                              if (existing == null && scope == 'level')
                                DropdownButtonFormField<String>(
                                    isExpanded: true,
                                    key: const ValueKey('tariff-level'),
                                    initialValue: levelId,
                                    decoration: const InputDecoration(
                                        labelText: 'Niveau'),
                                    items: levels.entries
                                        .map((e) => DropdownMenuItem(
                                            value: e.key, child: Text(e.value)))
                                        .toList(),
                                    onChanged: sending
                                        ? null
                                        : (v) => refresh(() {
                                              levelId = v;
                                              if (!regimeAppliesToTarget()) tariffRegime = null;
                                            })),
                              if (existing == null && scope == 'cycle')
                                DropdownButtonFormField<String>(
                                    isExpanded: true,
                                    key: const ValueKey('tariff-cycle'),
                                    initialValue: cycleId,
                                    decoration: const InputDecoration(
                                        labelText: 'Cycle'),
                                    items: cycles.entries
                                        .map((e) => DropdownMenuItem(
                                            value: e.key, child: Text(e.value)))
                                        .toList(),
                                    onChanged: sending
                                        ? null
                                        : (v) => refresh(() {
                                              cycleId = v;
                                              if (!regimeAppliesToTarget()) tariffRegime = null;
                                            })),
                              TextField(
                                  controller: name,
                                  decoration: const InputDecoration(
                                      labelText: 'Libellé du tarif')),
                              if (kind == 'tuition' &&
                                  regimeAppliesToTarget())
                                DropdownButtonFormField<String?>(
                                  key: const ValueKey('tariff-regime'),
                                  isExpanded: true,
                                  initialValue: tariffRegime,
                                  decoration: const InputDecoration(
                                    labelText: 'Régime',
                                    helperText:
                                        'Créez un tarif Mi-temps et un tarif Plein temps.',
                                  ),
                                  items: const [
                                    DropdownMenuItem<String?>(
                                      value: null,
                                      child: Text('Tarif général (secours)'),
                                    ),
                                    DropdownMenuItem<String?>(
                                      value: 'part_time',
                                      child: Text('Mi-temps'),
                                    ),
                                    DropdownMenuItem<String?>(
                                      value: 'full_time',
                                      child: Text('Plein temps'),
                                    ),
                                  ],
                                  onChanged: existing != null || sending
                                      ? null
                                      : (value) =>
                                          refresh(() => tariffRegime = value),
                                ),
                              if (kind == 'tuition')
                                DropdownButtonFormField<String>(
                                    isExpanded: true,
                                    initialValue: tariffMonth,
                                    decoration: const InputDecoration(
                                        labelText: 'Mois du tarif'),
                                    items: [
                                      const DropdownMenuItem<String>(
                                          value: null,
                                          child:
                                              Text('Tous les mois scolaires')),
                                      ..._months.map((m) => DropdownMenuItem(
                                          value: m,
                                          child: Text(
                                              '${financeMonths[int.parse(m.substring(5)) - 1]} ${m.substring(0, 4)}')))
                                    ],
                                    onChanged: existing != null || sending
                                        ? null
                                        : (v) =>
                                            refresh(() => tariffMonth = v)),
                              TextField(
                                  controller: amount,
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(
                                      labelText: 'Montant officiel (FCFA)')),
                              if (error != null)
                                Text(error!,
                                    style: const TextStyle(color: Colors.red)),
                            ]))),
                    actions: [
                      TextButton(
                          onPressed:
                              sending ? null : () => Navigator.pop(dialog),
                          child: const Text('Annuler')),
                      FilledButton(
                          onPressed: sending
                              ? null
                              : () async {
                                  final value =
                                      int.tryParse(amount.text.trim());
                                  if (value == null ||
                                      value <= 0 ||
                                      name.text.trim().length < 2 ||
                                      (scope == 'level' && levelId == null) ||
                                      (scope == 'cycle' && cycleId == null)) {
                                    refresh(() => error =
                                        'Renseignez le contexte, un libellé et un montant positif.');
                                    return;
                                  }
                                  refresh(() => sending = true);
                                  try {
                                    await store.saveFinanceTariff({
                                      'name': name.text.trim(),
                                      'amount': value,
                                      'scope': scope,
                                      'classId':
                                          scope == 'class' ? target : null,
                                      'levelId':
                                          scope == 'level' ? levelId : null,
                                      'cycle': scope == 'cycle'
                                          ? cycleId
                                          : existing?['cycle'],
                                      'academicYearId': _year,
                                      'schoolId': _school,
                                      'type': kind,
                                      'regime': kind == 'tuition' && regimeAppliesToTarget()
                                          ? tariffRegime
                                          : null,
                                      'month': kind == 'tuition'
                                          ? tariffMonth
                                          : null,
                                      'frequency': kind == 'tuition'
                                          ? 'monthly'
                                          : 'once',
                                      'description':
                                          existing?['description'] ?? ''
                                    }, id: existing?['id']);
                                    if (dialog.mounted) Navigator.pop(dialog);
                                    if (mounted) reload();
                                  } catch (e) {
                                    if (dialog.mounted)
                                      refresh(() {
                                        sending = false;
                                        error = e is ApiException
                                            ? e.message
                                            : 'Tarif non enregistré.';
                                      });
                                  }
                                },
                          child:
                              Text(sending ? 'Enregistrement…' : 'Enregistrer'))
                    ])));
    await Navigator.of(context).push(route);
    await route.completed;
    name.dispose();
    amount.dispose();
  }

  Future<void> _receipt(Map<String, dynamic> row, {bool print = false}) async {
    try {
      final value = await context
          .read<StoreService>()
          .fetchFinanceReceipt(row['id'], _school);
      if (print) {
        final pdf = await buildFinanceReceiptPdf(value);
        await Printing.layoutPdf(
            name: 'Reçu - ${value['receiptNumber']}',
            onLayout: (_) => pdf.save());
      } else if (mounted) {
        await showDialog<void>(
            context: context,
            builder: (dialog) => AlertDialog(
                    title: Text('Reçu ${value['receiptNumber']}'),
                    content: SingleChildScrollView(
                        child: Text(financeReceiptText(value))),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(dialog),
                          child: const Text('Fermer'))
                    ]));
      }
    } catch (e) {
      if (mounted) {
        AppToast.error(
          context,
          e is ApiException
              ? e.message
              : 'Impossible de consulter ou imprimer ce reçu.',
        );
      }
    }
  }

  Future<void> _cancel(Map<String, dynamic> row) async {
    final reason = TextEditingController();
    final route = DialogRoute<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
                title: const Text('Annuler le paiement'),
                content: TextField(
                    controller: reason,
                    decoration:
                        const InputDecoration(labelText: 'Motif obligatoire')),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(dialog, false),
                      child: const Text('Retour')),
                  TextButton(
                      onPressed: () => Navigator.pop(dialog, true),
                      child: const Text('Confirmer l’annulation'))
                ]));
    final confirmed = await Navigator.of(context).push(route);
    await route.completed;
    final text = reason.text.trim();
    reason.dispose();
    if (confirmed != true || !mounted) return;
    if (text.length < 3) {
      AppToast.warning(
          context, 'Le motif doit contenir au moins trois caractères.');
      return;
    }
    try {
      await context
          .read<StoreService>()
          .cancelSchoolPayment(row['paymentId'], text, _school);
      if (mounted) reload();
    } catch (e) {
      if (mounted) {
        AppToast.error(
          context,
          e is ApiException ? e.message : 'Annulation impossible.',
        );
      }
    }
  }

  Widget table(List<String> headers, List<DataRow> rows) => AppCard(
      padding: EdgeInsets.zero,
      child: LayoutBuilder(
          builder: (context, box) => SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                  constraints: BoxConstraints(minWidth: box.maxWidth),
                  child: DataTable(
                      showCheckboxColumn: false,
                      headingRowHeight: 52,
                      dataRowMinHeight: 56,
                      dataRowMaxHeight: 76,
                      headingRowColor: WidgetStatePropertyAll(Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest),
                      columns: headers
                          .map((s) => DataColumn(
                              label: Text(s,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600))))
                          .toList(),
                      rows: rows)))));

  Widget metric(String label, String value, IconData icon) => SizedBox(
      width: 250,
      child: AppCard(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(child: Text(label))
        ]),
        const SizedBox(height: 12),
        Text(value,
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.w700)),
      ])));

  Widget stateBadge(dynamic status) => Chip(
      avatar: Icon(
          status == 'paid'
              ? Icons.check_circle_outline
              : status == 'partial'
                  ? Icons.timelapse
                  : Icons.info_outline,
          size: 18),
      label: Text(financeStatus(status)));

  void changeTab(int tab) {
    setState(() {
      _tab = tab;
      _catalogSearch = '';
      if (tab == 0) {
        _kind = 'tuition';
      }
      if (tab == 8) {
        _kind = 'registration';
      }
    });
    if (tab == 0 || tab == 2 || tab == 8) {
      reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    final students = items('students')
        .where((s) =>
            _tab == 2 ||
            _tab == 8 ||
            s['status'] == 'unpaid' ||
            s['status'] == 'partial')
        .toList();
    final selectedRows = students
        .where((item) => item['studentId'] == _selectedStudent)
        .toList();
    final classes = items('classes');
    final summary = _data?['summary'] as Map?;
    final budget = _data?['budget'] as Map?;
    final annual = budget?['summary'] as Map?;
    final counts = budget?['counts'] as Map?;
    final missingTariffs = (annual?['unconfiguredCount'] as num?)?.toInt() ?? 0;
    final budgetCannotBeCalculated =
        missingTariffs > 0 && (annual?['expected'] as num? ?? 0) == 0;
    final receiptRows = items('receipts')
        .reversed
        .where((r) =>
            '${r['receiptNumber']} ${r['studentName']} ${r['className']} ${r['label']}'
                .toLowerCase()
                .contains(_catalogSearch.toLowerCase()))
        .toList();
    final feeRows = items('fees')
        .where((r) => '${r['name']} ${financeKinds[r['type']]}'
            .toLowerCase()
            .contains(_catalogSearch.toLowerCase()))
        .toList();
    return SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          WorkspaceHeader(
              title: 'Gestion financière',
              subtitle:
                  '${context.read<StoreService>().getSelectedAcademicYear()?.name ?? 'Année scolaire'} · Le budget suit automatiquement les inscriptions des élèves.',
              actions: [
                OutlinedButton.icon(
                    onPressed: _busy ? null : reload,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Actualiser'))
              ]),
          Wrap(spacing: 8, children: [
            for (final entry in const {
              4: 'Vue d’ensemble',
              1: 'Tarifs',
              8: 'Inscription / Réinscription',
              0: 'Paiement mensuel',
              2: 'Suivi',
              3: 'Reçus',
            }.entries)
              ChoiceChip(
                  label: Text(entry.value),
                  selected: _tab == entry.key,
                  onSelected: (_) => changeTab(entry.key)),
          ]),
          const SizedBox(height: 16),
          if (_tab == 0 || _tab == 2 || _tab == 8) ...[
            if (_tab == 0)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: FilledButton.icon(
                  key: const ValueKey('pay-month-button'),
                  onPressed: selectedRows.isEmpty
                      ? () => AppToast.warning(context,
                          'Choisissez une classe puis sélectionnez un élève à encaisser.')
                      : () => _pay(selectedRows.first),
                  icon: const Icon(Icons.payments_outlined),
                  label: const Text('Payer le mois'),
                ),
              ),
            Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(_tab == 0
                    ? '1. Choisissez une classe  ·  2. Recherchez et sélectionnez l’élève  ·  3. Cliquez sur Payer le mois'
                    : _tab == 8
                        ? 'Les frais validés à l’inscription ou à la réinscription sont considérés comme réglés, sans double encaissement.'
                        : 'Suivi des impayés et avances pour la période sélectionnée.')),
            Wrap(spacing: 16, runSpacing: 12, children: [
              if (_tab == 2 || _tab == 8)
                SizedBox(
                  width: 230,
                  child: DropdownButtonFormField<String>(
                    isExpanded: true,
                    key: ValueKey('kind:$_kind'),
                    initialValue: _kind,
                    decoration:
                        const InputDecoration(labelText: 'Nature du paiement'),
                    items: financeKinds.entries
                        .where((entry) => _tab != 8 ||
                            {'registration', 'reenrollment'}
                                .contains(entry.key))
                        .map((entry) => DropdownMenuItem(
                            value: entry.key, child: Text(entry.value)))
                        .toList(),
                    onChanged: _busy
                        ? null
                        : (value) {
                            setState(() => _kind = value!);
                            reload();
                          },
                  ),
                ),
              if (_kind == 'tuition')
                SizedBox(
                    width: 210,
                    child: DropdownButtonFormField<String>(
                        isExpanded: true,
                        key: ValueKey('month:$_month'),
                        initialValue: _month.isEmpty ? null : _month,
                        decoration: const InputDecoration(labelText: 'Mois'),
                        items: _months
                            .map((m) => DropdownMenuItem(
                                value: m,
                                child: Text(
                                    '${financeMonths[int.parse(m.substring(5)) - 1]} ${m.substring(0, 4)}')))
                            .toList(),
                        onChanged: _busy
                            ? null
                            : (v) {
                                setState(() => _month = v!);
                                reload();
                              })),
              if (_data != null)
                SizedBox(
                    width: 220,
                    child: DropdownButtonFormField<String>(
                        isExpanded: true,
                        key: ValueKey('class:$_classId'),
                        initialValue: _classId,
                        decoration: const InputDecoration(labelText: 'Classe'),
                        items: [
                          const DropdownMenuItem<String>(
                              value: null, child: Text('Toutes les classes')),
                          ...classes.map((cl) => DropdownMenuItem<String>(
                              value: cl['id'], child: Text(cl['name'])))
                        ],
                        onChanged: _busy
                            ? null
                            : (v) {
                                setState(() => _classId = v);
                                reload();
                              })),
              SizedBox(
                  width: 250,
                  child: TextField(
                      decoration: const InputDecoration(
                          labelText: 'Rechercher un élève'),
                      onChanged: (v) {
                        _search = v;
                        _debounce?.cancel();
                        _debounce =
                            Timer(const Duration(milliseconds: 300), reload);
                      })),
            ]),
          ],
          if (_tab == 1 || _tab == 3 || _tab == 5)
            Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: TextField(
                        key: ValueKey('catalog:$_tab'),
                        decoration: InputDecoration(
                            prefixIcon: const Icon(Icons.search),
                            labelText: _tab == 1
                                ? 'Rechercher un tarif'
                                : 'Rechercher un reçu ou un élève'),
                        onChanged: (v) => setState(() => _catalogSearch = v)))),
          if (_busy) const LinearProgressIndicator(),
          if (_error != null)
            WorkspaceNotice(message: _error!, error: true, onRetry: reload),
          if (_tab == 4 && _data != null) ...[
            const Text('Situation financière · Budget annuel',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 16),
            if (annual == null)
              const Text(
                  'Budget annuel indisponible. Vérifiez la version du serveur.'),
            if (annual != null) ...[
              if (missingTariffs > 0)
                AppCard(
                    child: Row(children: [
                  Icon(Icons.warning_amber_rounded,
                      color: Theme.of(context).colorScheme.error),
                  const SizedBox(width: 12),
                  Expanded(
                      child: Text(budgetCannotBeCalculated
                          ? 'Budget non calculable : aucun tarif applicable n’est configuré pour ces élèves. Les montants à 0 FCFA ne représentent pas une gratuité.'
                          : 'Budget incomplet : $missingTariffs obligation(s) financière(s) n’ont pas encore de tarif applicable.')),
                  TextButton(
                      onPressed: () => changeTab(1),
                      child: const Text('Configurer les tarifs'))
                ])),
              if (missingTariffs > 0) const SizedBox(height: 16),
              Wrap(spacing: 16, runSpacing: 16, children: [
                metric(
                    'ATTENDU',
                    budgetCannotBeCalculated
                        ? 'À CONFIGURER'
                        : money(annual['expected']),
                    Icons.account_balance_wallet_outlined),
                metric('ENCAISSÉ', money(annual['paid']),
                    Icons.check_circle_outline),
                metric(
                    'RESTE',
                    budgetCannotBeCalculated
                        ? 'À CONFIGURER'
                        : money(annual['remaining']),
                    Icons.pending_actions),
                metric(
                    'Élèves inscrits',
                    '${budget!['registrationCount'] ?? 'Indisponible'}',
                    Icons.groups_outlined),
              ]),
              const SizedBox(height: 16),
              if (counts != null)
                Wrap(spacing: 12, runSpacing: 8, children: [
                  Chip(label: Text('PAYÉS : ${counts['paid']}')),
                  Chip(label: Text('AVANCES : ${counts['partial']}')),
                  Chip(label: Text('IMPAYÉS : ${counts['unpaid']}')),
                  Chip(label: Text('À configurer : ${counts['unconfigured']}')),
                ])
              else
                const WorkspaceNotice(
                    message:
                        'Le serveur ne fournit pas encore les compteurs de statuts. Actualisez sa version.'),
              const Text(
                  'Statuts des élèves sur l’ensemble de l’année ; les dossiers sans tarif complet sont à configurer.'),
              const SizedBox(height: 16),
              if ((annual['credit'] as num? ?? 0) > 0)
                Text('Excédent conservé : ${money(annual['credit'])}'),
              if ((annual['unconfiguredCount'] as num? ?? 0) > 0)
                const Text(
                    'Budget incomplet : certains tarifs applicables restent à configurer.'),
              table(
                  [
                    'Type de frais',
                    'Attendu',
                    'Encaissé',
                    'Reste',
                    'Configuration'
                  ],
                  (budget['breakdown'] as List)
                      .map((r) => DataRow(cells: [
                            DataCell(Text(r['label'])),
                            DataCell(Text(money(r['expected']))),
                            DataCell(Text(money(r['paid']))),
                            DataCell(Text(money(r['remaining']))),
                            DataCell(Text((r['unconfiguredCount'] as num? ??
                                        0) >
                                    0
                                ? '${r['unconfiguredCount']} tarif(s) manquant(s)'
                                : 'Complète')),
                          ]))
                      .toList()),
            ],
          ],
          if (summary != null &&
              (_tab == 0 || _tab == 2 || _tab == 8))
            Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Wrap(spacing: 24, children: [
                  Text('Tarifs dus : ${money(summary['expected'])}'),
                  Text('Encaissé : ${money(summary['paid'])}'),
                  Text('Reste : ${money(summary['remaining'])}'),
                  if ((summary['credit'] as num? ?? 0) > 0)
                    Text('Excédent conservé : ${money(summary['credit'])}'),
                ])),
          if ((_data?['unconfiguredCount'] as int? ?? 0) > 0)
            const Text(
                'Certains élèves n’ont pas de tarif applicable. Configurez-le dans Tarifs.'),
          if (_data != null &&
              (_tab == 0 || _tab == 2 || _tab == 8)) ...[
            if (_tab != 2 && _classId == null)
              const Padding(
                  padding: EdgeInsets.all(20),
                  child: Text(
                      'Sélectionnez une classe pour rechercher un élève et encaisser.')),
            if (_tab == 2 || _classId != null) ...[
              if (students.isEmpty)
                const Padding(
                    padding: EdgeInsets.all(20),
                    child: Text('Aucun élève correspondant à ces critères.')),
              table(
                  [
                    'Élève',
                    'Classe',
                    'Frais',
                    'Prévu',
                    'Payé',
                    'Reste',
                    'Statut',
                    'Action'
                  ],
                  students
                      .map((s) => DataRow(
                              selected: _selectedStudent == s['studentId'],
                              onSelectChanged: (_) {
                                setState(
                                    () => _selectedStudent = s['studentId']);
                              },
                              cells: [
                                DataCell(Text(s['studentName'])),
                                DataCell(Text(s['className'])),
                                DataCell(Text(s['label'])),
                                DataCell(Text(s['status'] == 'no_tariff'
                                    ? 'Non configuré'
                                    : money(s['expected']))),
                                DataCell(Text(money(s['paid']))),
                                DataCell(Text(money(s['remaining']))),
                                DataCell(stateBadge(s['status'])),
                                DataCell(TextButton(
                                    onPressed: _tab == 8 ||
                                            !['unpaid', 'partial']
                                            .contains(s['status'])
                                        ? null
                                        : () {
                                            setState(() => _selectedStudent =
                                                s['studentId']);
                                            _pay(s);
                                          },
                                    child: Text(_tab == 0
                                        ? 'Payer le mois'
                                        : _tab == 8
                                            ? 'Réglé à l’inscription'
                                            : 'Encaisser')))
                              ]))
                      .toList()),
            ],
          ],
          if (_data != null && _tab == 1) ...[
            FilledButton.icon(
                onPressed: () => _tariff(),
                icon: const Icon(Icons.add),
                label: const Text('Ajouter un tarif')),
            const SizedBox(height: 16),
            if (feeRows.isEmpty)
              const WorkspaceNotice(
                  message:
                      'Aucun tarif trouvé. Ajoutez vos tarifs pour alimenter le budget automatiquement.'),
            table(
                ['Libellé', 'Nature', 'Contexte', 'Montant', 'Action'],
                feeRows
                    .map((f) => DataRow(cells: [
                          DataCell(Text(f['name'] ?? '')),
                          DataCell(
                              Text(financeKinds[f['type']] ?? 'Autres frais')),
                          DataCell(Text(f['scope'] == 'class'
                              ? classes
                                  .where((c) => c['id'] == f['classId'])
                                  .map((c) => c['name'])
                                  .join()
                              : f['scope'] == 'level'
                                  ? classes
                                      .where(
                                          (c) => c['levelId'] == f['levelId'])
                                      .map((c) => c['levelName'] ?? 'Niveau')
                                      .toSet()
                                      .join()
                                  : f['scope'] == 'cycle'
                                      ? classes
                                          .where(
                                              (c) => c['cycleId'] == f['cycle'])
                                          .map((c) => c['cycleName'] ?? 'Cycle')
                                          .toSet()
                                          .join()
                                      : 'Établissement')),
                          DataCell(Text(money(f['amount']))),
                          DataCell(TextButton(
                              onPressed: () => _tariff(f),
                              child: const Text('Modifier')))
                        ]))
                    .toList()),
          ],
          if (_data != null && (_tab == 3 || _tab == 5)) ...[
            if (_tab == 5)
              const WorkspaceNotice(
                  message:
                      'Historique des transactions officielles, y compris les paiements annulés. Aucun reçu annulé n’est effacé.'),
            if (receiptRows.isEmpty)
              const WorkspaceNotice(
                  message:
                      'Aucun reçu correspondant. Les reçus apparaissent après un paiement enregistré.'),
            table(
                [
                  'Reçu',
                  'Élève',
                  'Classe',
                  'Nature',
                  'Montant',
                  'Date',
                  'Statut',
                  'Actions'
                ],
                receiptRows
                    .map((r) => DataRow(cells: [
                          DataCell(Text(r['receiptNumber'] ?? '')),
                          DataCell(Text(r['studentName'] ?? '')),
                          DataCell(Text(r['className'] ?? 'Non renseignée')),
                          DataCell(Text(r['label'] ?? 'Paiement historique')),
                          DataCell(Text(money(r['amount']))),
                          DataCell(Text(AppDateUtils.formatNumeric(
                              r['date']?.toString(),
                              fallback: 'Non renseignée'))),
                          DataCell(Text(
                              r['status'] == 'cancelled' ? 'ANNULÉ' : 'Actif')),
                          DataCell(Row(children: [
                            Tooltip(
                                message: 'Consulter',
                                child: TextButton.icon(
                                    onPressed: () => _receipt(r),
                                    icon: const Icon(Icons.visibility),
                                    label: const Text('Voir'))),
                            Tooltip(
                                message: 'Générer le PDF',
                                child: TextButton.icon(
                                    onPressed: () => _receipt(r, print: true),
                                    icon: const Icon(Icons.picture_as_pdf),
                                    label: const Text('PDF'))),
                            if (_tab == 5)
                              IconButton(
                                  onPressed: r['status'] == 'cancelled'
                                      ? null
                                      : () => _cancel(r),
                                  icon: const Icon(Icons.cancel_outlined),
                                  tooltip: 'Annuler le paiement'),
                          ]))
                        ]))
                    .toList()),
          ],
        ]));
  }
}

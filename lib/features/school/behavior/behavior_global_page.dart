import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../data/services/store_service.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_card.dart';

/// Explicit school context for the global administrator; never impersonates an admin.
class BehaviorGlobalPage extends StatefulWidget {
  const BehaviorGlobalPage({super.key});
  @override
  State<BehaviorGlobalPage> createState() => _BehaviorGlobalPageState();
}

class _BehaviorGlobalPageState extends State<BehaviorGlobalPage> {
  List<Map<String, dynamic>> _contexts = [];
  String? _school, _class, _period;
  Map<String, dynamic>? _result;
  bool _busy = false;
  String? _error;

  Future<void> _load() async {
    setState(() { _busy = true; _error = null; });
    try {
      final rows = await context.read<StoreService>().behaviorContextsRemote();
      if (mounted) setState(() => _contexts = rows);
    } catch (_) {
      if (mounted) setState(() => _error = 'Impossible de charger les classes. Réessayez.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _fetch({bool calculate = false}) async {
    if (_class == null || _period == null) return;
    final classId = _class!, periodId = _period!;
    setState(() { _busy = true; _error = null; });
    try {
      final store = context.read<StoreService>();
      final result = calculate
          ? await store.calculateBehaviorRemote(classId, periodId)
          : await store.behaviorResultsRemote(classId, periodId);
      if (mounted && classId == _class && periodId == _period) setState(() => _result = result);
    } catch (_) {
      if (mounted) setState(() => _error = 'Impossible de terminer. Vérifiez le contexte et les relevés reçus.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final schools = {for (final row in _contexts) row['schoolId'] as String: row['school'] as String};
    final classes = _contexts.where((row) => row['schoolId'] == _school).toList();
    final selected = classes.where((row) => row['classId'] == _class).firstOrNull;
    final periods = selected?['periods'] as List? ?? const [];
    return SingleChildScrollView(padding: const EdgeInsets.all(24), child: Column(
      crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Comportement — consultation globale', style: TextStyle(fontSize: 24)),
        AppButton(label: 'Charger les établissements et classes', onPressed: _busy ? null : _load),
        if (_busy) const LinearProgressIndicator(),
        if (_error != null) Text(_error!),
        DropdownButtonFormField<String>(initialValue: _school,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Établissement'),
          items: schools.entries.map((s) => DropdownMenuItem(value: s.key, child: Text(s.value))).toList(),
          onChanged: _busy ? null : (value) => setState(() { _school = value; _class = null; _period = null; _result = null; })),
        DropdownButtonFormField<String>(key: ValueKey('class-$_school'), initialValue: _class,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Année · Cycle · Niveau · Classe'),
          items: classes.map((c) => DropdownMenuItem(value: c['classId'] as String,
            child: Text('${c['year']} · ${c['cycle']} · ${c['level']} · ${c['class']}'))).toList(),
          onChanged: _busy ? null : (value) => setState(() { _class = value; _period = null; _result = null; })),
        DropdownButtonFormField<String>(key: ValueKey('period-$_class'), initialValue: _period,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Trimestre'),
          items: periods.map((p) => DropdownMenuItem(value: p['id'] as String, child: Text(p['name'] as String))).toList(),
          onChanged: _busy ? null : (value) => setState(() { _period = value; _result = null; })),
        Wrap(spacing: 12, children: [
          AppButton(label: 'Consulter le suivi', onPressed: _busy || _period == null ? null : () => _fetch()),
          AppButton(label: 'Calculer les moyennes', onPressed: _busy || _result?['readyForCalculation'] != true ? null : () => _fetch(calculate: true)),
        ]),
        if (_result != null) AppCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${_result!['receivedCount']} reçus / ${_result!['expectedCount']} attendus'),
          Text(switch (_result!['calculationStatus']) {
            'official' => 'Résultat officiel disponible', 'ready' => 'Prêt pour le calcul',
            'stale' => 'Résultat obsolète : recalcul nécessaire', _ => 'En attente des relevés',
          }),
          for (final row in _result!['teacherSubmissions'] as List)
            Text('${row['teacher']} — ${row['status'] == 'submitted' ? 'Soumis' : 'En attente'}'),
          for (final row in _result!['students'] as List)
            Text('${row['student']} : ${(row['average'] as num).toStringAsFixed(2)} / 5'),
        ])),
      ],
    ));
  }
}

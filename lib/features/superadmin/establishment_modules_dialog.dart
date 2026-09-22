import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_spacing.dart';
import '../../data/services/store_service.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/confirm_dialog.dart';

typedef ModulesLoader = Future<Map<String, dynamic>> Function(String id);
typedef ModulesSaver = Future<Map<String, dynamic>> Function(
    String id, List<String> enabledModules);

class EstablishmentModulesDialog extends StatefulWidget {
  const EstablishmentModulesDialog({
    super.key,
    required this.establishmentId,
    required this.establishmentName,
    this.loader,
    this.saver,
  });

  final String establishmentId;
  final String establishmentName;
  final ModulesLoader? loader;
  final ModulesSaver? saver;

  @override
  State<EstablishmentModulesDialog> createState() =>
      _EstablishmentModulesDialogState();
}

class _EstablishmentModulesDialogState
    extends State<EstablishmentModulesDialog> {
  bool _loading = true;
  bool _saving = false;
  String? _error;
  String? _success;
  List<Map<String, dynamic>> _available = const [];
  Set<String> _enabled = {};
  Set<String> _persisted = {};
  String? _planName;
  Set<String> _planFeatures = {};

  String _label(String id) {
    for (final module in _available) {
      if (module['id'] == id) return module['label']?.toString() ?? id;
    }
    return id;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _success = null;
    });
    try {
      final loader = widget.loader ??
          context.read<StoreService>().getSuperAdminEstablishmentModules;
      final response = await loader(widget.establishmentId);
      if (!mounted) return;
      final available = (response['availableModules'] as List? ?? const [])
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();
      final enabled = Set<String>.from(
          response['enabledModules'] as List? ?? const <String>[]);
      final plan = response['currentPlan'];
      final planFeatures = Set<String>.from(
          response['planFeatures'] as List? ?? const <String>[]);
      setState(() {
        _available = available;
        _enabled = enabled;
        _persisted = Set<String>.from(enabled);
        _planName = plan is Map ? plan['name']?.toString() : null;
        _planFeatures = planFeatures;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Impossible de charger les modules de l\'établissement.';
      });
    }
  }

  Future<void> _save() async {
    final removed = _persisted.difference(_enabled);
    if (removed.isNotEmpty) {
      final confirmed = await ConfirmDialog.show(
        context: context,
        title: 'Désactiver des modules',
        message:
            'La désactivation peut retirer l’accès aux fonctionnalités concernées. Continuer ?',
        confirmLabel: 'Désactiver',
        isDanger: true,
      );
      if (!confirmed || !mounted) return;
    }
    setState(() {
      _saving = true;
      _error = null;
      _success = null;
    });
    try {
      final saver = widget.saver ??
          context.read<StoreService>().updateSuperAdminEstablishmentModules;
      final ordered = _available
          .map((item) => item['id'].toString())
          .where(_enabled.contains)
          .toList();
      final response = await saver(widget.establishmentId, ordered);
      if (!mounted) return;
      final saved = Set<String>.from(
          response['enabledModules'] as List? ?? const <String>[]);
      setState(() {
        _enabled = saved;
        _persisted = Set<String>.from(saved);
        _saving = false;
        _success = 'Modules enregistrés dans PostgreSQL.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Les modules n\'ont pas pu être enregistrés.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 580,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.establishmentName,
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.s3),
          if (_loading)
            const Center(
              key: Key('modules-loading'),
              child: Padding(
                padding: EdgeInsets.all(AppSpacing.s6),
                child: CircularProgressIndicator(),
              ),
            )
          else if (_error != null && _available.isEmpty)
            Column(
              key: const Key('modules-error'),
              children: [
                Text(_error!),
                const SizedBox(height: AppSpacing.s3),
                AppButton(label: 'Réessayer', onPressed: _load),
              ],
            )
          else if (_available.isEmpty)
            const Text('Aucun module configurable disponible.',
                key: Key('modules-empty'))
          else ...[
            const Text(
                'Fonctionnalités actuellement disponibles pour cet établissement.'),
            const SizedBox(height: AppSpacing.s3),
            Text('Plan actuel : ${_planName ?? "Non renseigné"}',
                key: const Key('modules-current-plan'),
                style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: AppSpacing.s2),
            const Text('Fonctionnalités incluses dans le plan :'),
            Text(
              _planFeatures.isEmpty
                  ? 'Aucune fonctionnalité incluse'
                  : _planFeatures.map(_label).join(', '),
              key: const Key('modules-plan-features'),
            ),
            const SizedBox(height: AppSpacing.s3),
            Text('${_enabled.length} module(s) actuellement disponible(s)',
                key: const Key('modules-enabled-count')),
            const SizedBox(height: AppSpacing.s2),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  children: _available.map((module) {
                    final id = module['id'].toString();
                    final label = module['label']?.toString() ?? id;
                    return CheckboxListTile(
                      key: Key('module-$id'),
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(label),
                      subtitle: Text(id),
                      value: _enabled.contains(id),
                      onChanged: _saving
                          ? null
                          : (selected) => setState(() {
                                _success = null;
                                if (selected ?? false) {
                                  _enabled.add(id);
                                } else {
                                  _enabled.remove(id);
                                }
                              }),
                    );
                  }).toList(),
                ),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.s2),
              Text(_error!,
                  key: const Key('modules-save-error'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            if (_success != null) ...[
              const SizedBox(height: AppSpacing.s2),
              Text(_success!,
                  key: const Key('modules-save-success'),
                  style: const TextStyle(color: Colors.green)),
            ],
            const SizedBox(height: AppSpacing.s4),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                AppButton(
                  label: 'Fermer',
                  variant: AppButtonVariant.secondary,
                  onPressed: _saving ? null : () => Navigator.of(context).pop(),
                ),
                const SizedBox(width: AppSpacing.s3),
                AppButton(
                  key: const Key('modules-save'),
                  label: _saving ? 'Enregistrement...' : 'Enregistrer',
                  onPressed: _saving ? null : _save,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

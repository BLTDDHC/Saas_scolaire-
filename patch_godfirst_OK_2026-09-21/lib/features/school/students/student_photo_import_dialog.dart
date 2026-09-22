import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/student_photo_picker.dart';
import '../../../data/datasources/api_client.dart';
import '../../../data/services/store_service.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/app_toast.dart';

Future<void> showStudentPhotoImportDialog(BuildContext context) => showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ChangeNotifierProvider.value(
        value: context.read<StoreService>(),
        child: const _StudentPhotoImportDialog(),
      ),
    );

class _StudentPhotoImportDialog extends StatefulWidget {
  const _StudentPhotoImportDialog();

  @override
  State<_StudentPhotoImportDialog> createState() =>
      _StudentPhotoImportDialogState();
}

class _StudentPhotoImportDialogState extends State<_StudentPhotoImportDialog> {
  String? _yearId;
  String? _cycleId;
  List<PickedStudentPhoto> _files = const [];
  bool _busy = false;
  int _processed = 0;
  int _associated = 0;
  int _existing = 0;
  int _notFound = 0;
  int _errors = 0;
  final List<Map<String, dynamic>> _results = [];

  Future<void> _pick() async {
    final files = await pickStudentPhotos();
    if (!mounted || files.isEmpty) return;
    setState(() {
      _files = files;
      _processed = 0;
      _associated = _existing = _notFound = 0;
      _errors = files.where((file) => file.isRejected).length;
      _results
        ..clear()
        ..addAll(files.where((file) => file.isRejected).map((file) => {
              'name': file.name,
              'status': 'error',
              'message': file.rejectionReason ?? 'Image refusée',
            }));
    });
  }

  Future<void> _start() async {
    final validFiles = _files.where((file) => file.isValid).toList();
    if (_busy || _yearId == null || _cycleId == null || validFiles.isEmpty) return;
    setState(() {
      _busy = true;
      _processed = 0;
      _associated = _existing = _notFound = 0;
      _errors = _files.where((file) => file.isRejected).length;
      _results
        ..clear()
        ..addAll(_files.where((file) => file.isRejected).map((file) => {
              'name': file.name,
              'status': 'error',
              'message': file.rejectionReason ?? 'Image refusée',
            }));
    });
    final store = context.read<StoreService>();
    try {
      for (var offset = 0; offset < validFiles.length; offset += 10) {
        final end = offset + 10 < validFiles.length ? offset + 10 : validFiles.length;
        final batch = validFiles.sublist(offset, end);
        final response = await store.importStudentPhotosRemote(
          academicYearId: _yearId!,
          cycleId: _cycleId!,
          files: batch.map((file) => file.toJson()).toList(),
        );
        final items = (response['items'] as List? ?? const [])
            .map((item) => Map<String, dynamic>.from(item as Map));
        if (!mounted) return;
        setState(() {
          for (final item in items) {
            _results.add(item);
            switch (item['status']) {
              case 'associated':
                _associated++;
              case 'already_present':
                _existing++;
              case 'not_found':
                _notFound++;
              default:
                _errors++;
            }
            _processed++;
          }
        });
      }
      if (mounted) AppToast.success(context, 'Importation terminée.');
    } on ApiException catch (error) {
      if (mounted) AppToast.error(context, error.message);
    } catch (_) {
      if (mounted) AppToast.error(context, 'L’importation des photos a échoué.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<StoreService>();
    _yearId ??= store.getSelectedAcademicYearId();
    final years = store.getAcademicYears();
    final cycles = store.getSchoolCycles().where((cycle) => cycle.isActive).toList();
    final total = _files.length;
    final validTotal = _files.where((file) => file.isValid).length;
    final progress = validTotal == 0 ? 0.0 : _processed / validTotal;
    return AlertDialog(
      title: const Text('Importer les photos des élèves'),
      content: SizedBox(
        width: 680,
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            AppCard(
              title: store.getCurrentSchool()?.name ?? 'Établissement',
              subtitle: store.currentUser?.directionName ??
                  'Périmètre de l’administration scolaire',
              child: const Text(
                  'La correspondance utilise uniquement le suffixe numérique exact du matricule.'),
            ),
            const SizedBox(height: AppSpacing.s4),
            Wrap(spacing: AppSpacing.s3, runSpacing: AppSpacing.s3, children: [
              SizedBox(
                width: 280,
                child: DropdownButtonFormField<String>(
                  value: _yearId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Année scolaire'),
                  items: years
                      .map((year) => DropdownMenuItem(
                          value: year.id, child: Text(year.name)))
                      .toList(),
                  onChanged: _busy ? null : (value) => setState(() => _yearId = value),
                ),
              ),
              SizedBox(
                width: 280,
                child: DropdownButtonFormField<String>(
                  value: _cycleId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Cycle'),
                  items: cycles
                      .map((cycle) => DropdownMenuItem(
                          value: cycle.id, child: Text(cycle.name)))
                      .toList(),
                  onChanged: _busy ? null : (value) => setState(() => _cycleId = value),
                ),
              ),
            ]),
            const SizedBox(height: AppSpacing.s4),
            OutlinedButton.icon(
              onPressed: _busy ? null : _pick,
              icon: const Icon(Icons.add_photo_alternate_outlined),
              label: Text(total == 0
                  ? 'Sélectionner les photos'
                  : '$validTotal photo(s) prête(s) / $total sélectionnée(s)'),
            ),
            if (_files.isNotEmpty && _processed == 0) ...[
              const SizedBox(height: AppSpacing.s3),
              Wrap(
                spacing: AppSpacing.s2,
                runSpacing: AppSpacing.s2,
                children: _files
                    .map((file) => Chip(
                          avatar: const Icon(Icons.image_outlined, size: 16),
                          label: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 170),
                            child: Text(file.name,
                                overflow: TextOverflow.ellipsis),
                          ),
                        ))
                    .toList(),
              ),
            ],
            if (_busy || _processed > 0) ...[
              const SizedBox(height: AppSpacing.s5),
              Text('$_processed / $validTotal photo(s) valide(s) traitée(s)'),
              const SizedBox(height: AppSpacing.s2),
              LinearProgressIndicator(value: progress),
              const SizedBox(height: AppSpacing.s3),
              Wrap(spacing: AppSpacing.s4, runSpacing: AppSpacing.s2, children: [
                Text('$_associated associées'),
                Text('$_existing déjà présentes'),
                Text('$_notFound non trouvées'),
                Text('$_errors erreurs'),
              ]),
              if (_results.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.s4),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 220),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: _results.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final item = _results[index];
                      final status = '${item['status']}';
                      final label = switch (status) {
                        'associated' => 'Associée',
                        'already_present' => 'Déjà présente',
                        'not_found' => 'Matricule introuvable',
                        _ => item['message']?.toString() ?? 'Erreur',
                      };
                      final color = switch (status) {
                        'associated' => Colors.green,
                        'already_present' => Colors.blueGrey,
                        'not_found' => Colors.orange,
                        _ => Colors.red,
                      };
                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.circle, size: 10, color: color),
                        title: Text('${item['name']}',
                            overflow: TextOverflow.ellipsis),
                        subtitle: Text(
                          item['studentName'] == null
                              ? label
                              : '$label · ${item['studentName']}',
                        ),
                      );
                    },
                  ),
                ),
              ],
            ],
          ]),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Fermer'),
        ),
        FilledButton.icon(
          onPressed: !_busy && _yearId != null && _cycleId != null && validTotal > 0
              ? _start
              : null,
          icon: _busy
              ? const SizedBox.square(
                  dimension: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.cloud_upload_outlined),
          label: Text(_busy ? 'Importation…' : 'Importer'),
        ),
      ],
    );
  }
}

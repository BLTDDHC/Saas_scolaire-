import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/services/store_service.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/app_toast.dart';

class MigrationPage extends StatefulWidget {
  const MigrationPage({super.key});

  @override
  State<MigrationPage> createState() => _MigrationPageState();
}

class _MigrationPageState extends State<MigrationPage> {
  bool _running = false;
  String _result = '';

  @override
  Widget build(BuildContext context) {
    final store = context.read<StoreService>();
    return AppCard(
      title: 'Migration: frais legacy → scope',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Cette action convertit les frais configurés en mode legacy (className/level) en enregistrements explicites avec scope.'),
          const SizedBox(height: 12),
          Row(
            children: [
              AppButton(
                label: _running ? 'En cours...' : 'Lancer la migration',
                variant: AppButtonVariant.primary,
                onPressed: _running
                    ? null
                    : () async {
                        setState(() {
                          _running = true;
                          _result = '';
                        });
                        try {
                          final migrated = store.migrateLegacyFeesToScope();
                          setState(() {
                            _result = 'Frais migrés: $migrated';
                          });
                          AppToast.success(context, 'Migration effectuée. $migrated frais mis à jour.');
                        } catch (e) {
                          setState(() {
                            _result = 'Erreur: $e';
                          });
                          AppToast.error(context, 'Erreur lors de la migration: $e');
                        } finally {
                          setState(() {
                            _running = false;
                          });
                        }
                      },
              ),
              const SizedBox(width: 12),
              AppButton(
                label: 'Prévisualiser (non destructive)',
                variant: AppButtonVariant.secondary,
                onPressed: () {
                  // si la méthode preview existe, utiliser sinon informer
                  try {
                    final preview = store.previewLegacyFeeMigration();
                    AppToast.success(context, 'Prévisualisation: ${preview.length} frais seraient modifiés.');
                  } catch (e) {
                    AppToast.warning(context, 'Prévisualisation non disponible : $e');
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_result.isNotEmpty) Text(_result),
        ],
      ),
    );
  }
}

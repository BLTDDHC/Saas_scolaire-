import 'package:flutter/material.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../shared/widgets/workspace_header.dart';
import '../settings/pedagogical_settings_card.dart';

/// Point d'entrée métier dédié aux périodes académiques.
///
/// La logique de lecture/écriture reste centralisée dans
/// [PedagogicalSettingsCard] afin de ne pas dupliquer le référentiel
/// `academic_periods` ni les appels API existants.
class PeriodsPage extends StatelessWidget {
  const PeriodsPage({super.key});

  @override
  Widget build(BuildContext context) => const WorkspacePage(
        title: 'Périodes',
        subtitle:
            'Configurez les 1er, 2e et 3e trimestres de l’année scolaire sélectionnée.',
        children: [
          PedagogicalSettingsCard(),
          SizedBox(height: AppSpacing.s6),
        ],
      );
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../data/models/establishment_model.dart';
import '../../data/services/store_service.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/app_page_header.dart';
import '../../shared/widgets/app_toast.dart';

class DirectionsPage extends StatefulWidget {
  const DirectionsPage({super.key});

  @override
  State<DirectionsPage> createState() => _DirectionsPageState();
}

class _DirectionsPageState extends State<DirectionsPage> {
  List<EstablishmentModel> _schools = const [];
  EstablishmentModel? _selectedSchool;
  List<Map<String, dynamic>> _directions = const [];
  List<Map<String, dynamic>> _unassignedAdmins = const [];
  List<Map<String, dynamic>> _administrators = const [];
  Map<String, dynamic> _establishmentStatistics = const {};
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadSchools();
  }

  Future<void> _loadSchools() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final schools =
          await context.read<StoreService>().searchSuperAdminEstablishments();
      if (!mounted) return;
      setState(() {
        _schools = schools;
        _selectedSchool = schools.isEmpty ? null : schools.first;
      });
      await _loadDirections();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Impossible de charger les directions scolaires.';
      });
    }
  }

  Future<void> _loadDirections() async {
    final school = _selectedSchool;
    if (school == null) {
      setState(() => _loading = false);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response =
          await context.read<StoreService>().getSuperAdminDirections(school.id);
      if (!mounted) return;
      setState(() {
        _directions = List<Map<String, dynamic>>.from(
            (response['directions'] as List? ?? const [])
                .map((item) => Map<String, dynamic>.from(item as Map)));
        _unassignedAdmins = List<Map<String, dynamic>>.from(
            (response['unassignedAdministrators'] as List? ?? const [])
                .map((item) => Map<String, dynamic>.from(item as Map)));
        _administrators = List<Map<String, dynamic>>.from(
            (response['administrators'] as List? ??
                    response['unassignedAdministrators'] as List? ??
                    const [])
                .map((item) => Map<String, dynamic>.from(item as Map)));
        final establishment = Map<String, dynamic>.from(
            response['establishment'] as Map? ?? const {});
        _establishmentStatistics = Map<String, dynamic>.from(
            establishment['statistics'] as Map? ?? const {});
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Impossible de charger les directions de cet établissement.';
      });
    }
  }

  Future<void> _assignAdministrator(Map<String, dynamic> direction) async {
    final current = direction['administrator'] as Map?;
    String? selectedId = current?['id']?.toString();
    final choices = _administrators;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Administrateur — ${direction['name']}'),
          content: DropdownButtonFormField<String?>(
            isExpanded: true,
            initialValue: selectedId,
            decoration: const InputDecoration(labelText: 'Administrateur'),
            items: [
              ...choices.map((admin) => DropdownMenuItem<String?>(
                    value: admin['id']?.toString(),
                    child: Text(admin['name']?.toString() ?? ''),
                  )),
            ],
            onChanged: (value) => setDialogState(() => selectedId = value),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Annuler')),
            FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Enregistrer l’attribution')),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await context
          .read<StoreService>()
          .assignDirectionAdministrator(direction['id'].toString(), selectedId);
      if (!mounted) return;
      AppToast.success(context, 'Administrateur attribué à la direction.');
      await _loadDirections();
    } catch (_) {
      if (mounted) {
        AppToast.error(context, 'Impossible d’attribuer cet administrateur.');
      }
    }
  }

  Future<void> _createAdministrator(Map<String, dynamic> direction) async {
    final school = _selectedSchool;
    if (school == null) return;
    final nameController = TextEditingController();
    final emailController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Créer l’administrateur — ${direction['name']}'),
          content: SizedBox(
            width: 460,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                controller: nameController,
                onChanged: (_) => setDialogState(() {}),
                decoration: const InputDecoration(labelText: 'Nom complet'),
              ),
              const SizedBox(height: AppSpacing.s3),
              TextField(
                controller: emailController,
                keyboardType: TextInputType.emailAddress,
                onChanged: (_) => setDialogState(() {}),
                decoration: const InputDecoration(labelText: 'Adresse e-mail'),
              ),
            ]),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: nameController.text.trim().length >= 2 &&
                      emailController.text.contains('@')
                  ? () => Navigator.pop(dialogContext, true)
                  : null,
              child: const Text('Créer'),
            ),
          ],
        ),
      ),
    );
    final name = nameController.text.trim();
    final email = emailController.text.trim();
    nameController.dispose();
    emailController.dispose();
    if (confirmed != true || !mounted) return;
    final password = await context.read<StoreService>().createAccount(
          name: name,
          email: email,
          role: UserRole.admin,
          schoolId: school.id,
          directionId: direction['id'].toString(),
        );
    if (!mounted) return;
    if (password == null) {
      AppToast.error(context, 'Impossible de créer cet administrateur.');
      return;
    }
    await _loadDirections();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Compte administrateur créé'),
        content: SelectableText(
          'Mot de passe temporaire : $password\n\n'
          'Copiez-le maintenant. Il ne sera plus affiché et devra être changé à la première connexion.',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('J’ai copié le mot de passe'),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleDirection(Map<String, dynamic> direction) async {
    final active = direction['status'] == 'active';
    try {
      await context.read<StoreService>().updateSuperAdminDirection(
          direction['id'].toString(),
          {'status': active ? 'inactive' : 'active'});
      if (!mounted) return;
      AppToast.success(
          context, active ? 'Direction désactivée.' : 'Direction activée.');
      await _loadDirections();
    } catch (_) {
      if (mounted) {
        AppToast.error(context, 'Impossible de modifier cette direction.');
      }
    }
  }

  Future<void> _createDirection() async {
    final school = _selectedSchool;
    if (school == null) return;
    final occupied = _directions
        .expand((direction) => direction['cycles'] as List? ?? const [])
        .map((cycle) => (cycle as Map)['id']?.toString())
        .whereType<String>()
        .toSet();
    final available =
        school.cycles.where((cycle) => !occupied.contains(cycle.id)).toList();
    if (available.isEmpty) {
      AppToast.info(
          context, 'Tous les cycles appartiennent déjà à une direction.');
      return;
    }
    final nameController = TextEditingController();
    final selected = <String>{};
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Créer une direction'),
          content: SizedBox(
            width: 460,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                controller: nameController,
                onChanged: (_) => setDialogState(() {}),
                decoration:
                    const InputDecoration(labelText: 'Nom de la direction'),
              ),
              const SizedBox(height: AppSpacing.s3),
              ...available.map((cycle) => CheckboxListTile(
                    value: selected.contains(cycle.id),
                    title: Text(cycle.name),
                    contentPadding: EdgeInsets.zero,
                    onChanged: (checked) => setDialogState(() {
                      checked == true
                          ? selected.add(cycle.id)
                          : selected.remove(cycle.id);
                    }),
                  )),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Annuler')),
            FilledButton(
              onPressed:
                  nameController.text.trim().length < 2 || selected.isEmpty
                      ? null
                      : () => Navigator.pop(dialogContext, true),
              child: const Text('Créer'),
            ),
          ],
        ),
      ),
    );
    final name = nameController.text.trim();
    nameController.dispose();
    if (confirmed != true || !mounted) return;
    try {
      await context.read<StoreService>().createSuperAdminDirection(
          school.id, {'name': name, 'cycleIds': selected.toList()});
      if (!mounted) return;
      AppToast.success(context, 'Direction créée.');
      await _loadDirections();
    } catch (_) {
      if (mounted) {
        AppToast.error(context, 'Impossible de créer cette direction.');
      }
    }
  }

  Future<void> _renameDirection(Map<String, dynamic> direction) async {
    final controller =
        TextEditingController(text: direction['name']?.toString() ?? '');
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Modifier la direction'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Nom'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Annuler')),
          FilledButton(
              onPressed: () =>
                  Navigator.pop(dialogContext, controller.text.trim()),
              child: const Text('Enregistrer')),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.length < 2 || !mounted) return;
    try {
      await context.read<StoreService>().updateSuperAdminDirection(
          direction['id'].toString(), {'name': name});
      if (!mounted) return;
      AppToast.success(context, 'Direction mise à jour.');
      await _loadDirections();
    } catch (_) {
      if (mounted) {
        AppToast.error(context, 'Impossible de modifier cette direction.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        AppPageHeader(
          title: 'Directions scolaires',
          subtitle:
              'Attribuez chaque administrateur au périmètre qu’il doit gérer.',
          actions: [
            FilledButton.icon(
              onPressed: _createDirection,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Créer une direction'),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.s6, AppSpacing.s2, AppSpacing.s6, AppSpacing.s4),
          child: DropdownButtonFormField<String>(
            isExpanded: true,
            initialValue: _selectedSchool?.id,
            decoration: const InputDecoration(labelText: 'Établissement'),
            items: _schools
                .map((school) => DropdownMenuItem(
                    value: school.id, child: Text(school.name)))
                .toList(),
            onChanged: (id) {
              setState(() {
                _selectedSchool =
                    _schools.where((school) => school.id == id).firstOrNull;
              });
              _loadDirections();
            },
          ),
        ),
        Expanded(child: _buildBody()),
      ],
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(_error!),
          const SizedBox(height: AppSpacing.s3),
          FilledButton(
              onPressed: _loadDirections, child: const Text('Réessayer')),
        ]),
      );
    }
    if (_selectedSchool == null) {
      return const Center(child: Text('Aucun établissement disponible.'));
    }
    if (_directions.isEmpty) {
      return const Center(
          child: Text('Aucune direction configurée pour cet établissement.'));
    }
    return RefreshIndicator(
      onRefresh: _loadDirections,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.s6, 0, AppSpacing.s6, AppSpacing.s6),
        children: [
          AppCard(
            title: 'Vue consolidée de l’établissement',
            child: Wrap(
              spacing: AppSpacing.s5,
              runSpacing: AppSpacing.s2,
              children: [
                Text('${_establishmentStatistics['students'] ?? 0} élèves'),
                Text('${_establishmentStatistics['classes'] ?? 0} classes'),
                Text(
                    '${_establishmentStatistics['teachers'] ?? 0} enseignants'),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.s4),
          if (_unassignedAdmins.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(bottom: AppSpacing.s4),
              padding: const EdgeInsets.all(AppSpacing.s3),
              decoration: BoxDecoration(
                color: AppColors.warning500.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '${_unassignedAdmins.length} administrateur(s) attendent une attribution.',
              ),
            ),
          ..._directions.map(_directionCard),
        ],
      ),
    );
  }

  Widget _directionCard(Map<String, dynamic> direction) {
    final cycles = (direction['cycles'] as List? ?? const [])
        .map((cycle) => (cycle as Map)['name']?.toString() ?? '')
        .where((name) => name.isNotEmpty)
        .join(', ');
    final administrator = direction['administrator'] as Map?;
    final statistics =
        Map<String, dynamic>.from(direction['statistics'] as Map? ?? const {});
    final active = direction['status'] == 'active';
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.s4),
      child: AppCard(
        title: direction['name']?.toString() ?? 'Direction',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Cycles : ${cycles.isEmpty ? 'Aucun' : cycles}'),
            const SizedBox(height: AppSpacing.s2),
            Text(
                'Administrateur : ${administrator?['name'] ?? 'Non attribué'}'),
            const SizedBox(height: AppSpacing.s2),
            Text('Statut : ${active ? 'Actif' : 'Inactif'}'),
            const SizedBox(height: AppSpacing.s3),
            Wrap(
              spacing: AppSpacing.s4,
              runSpacing: AppSpacing.s2,
              children: [
                Text('${statistics['students'] ?? 0} élèves'),
                Text('${statistics['classes'] ?? 0} classes'),
                Text('${statistics['teachers'] ?? 0} enseignants'),
              ],
            ),
            const SizedBox(height: AppSpacing.s3),
            Wrap(spacing: AppSpacing.s2, runSpacing: AppSpacing.s2, children: [
              OutlinedButton.icon(
                onPressed: () => _assignAdministrator(direction),
                icon: const Icon(Icons.admin_panel_settings_rounded),
                label: const Text('Attribuer un administrateur'),
              ),
              if (administrator == null)
                FilledButton.icon(
                  onPressed: () => _createAdministrator(direction),
                  icon: const Icon(Icons.person_add_alt_1_rounded),
                  label: const Text('Créer un administrateur'),
                ),
              TextButton.icon(
                onPressed: () => _renameDirection(direction),
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Modifier'),
              ),
              TextButton.icon(
                onPressed: () => _toggleDirection(direction),
                icon: Icon(active
                    ? Icons.pause_circle_outline_rounded
                    : Icons.play_circle_outline_rounded),
                label: Text(active ? 'Désactiver' : 'Activer'),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}

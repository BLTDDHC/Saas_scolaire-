import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/date_utils.dart';
import '../../data/datasources/api_client.dart';
import '../../data/models/user_model.dart';
import '../../data/services/store_service.dart';
import '../../shared/widgets/app_badge.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/app_toast.dart';
import '../../shared/widgets/workspace_header.dart';

typedef AdminLoader = Future<List<UserModel>> Function({
  String? search,
  String? status,
  String? establishmentId,
});

class AdministratorsPage extends StatefulWidget {
  const AdministratorsPage({
    super.key,
    this.loader,
    this.detailLoader,
    this.passwordResetter,
    this.statusUpdater,
  });

  final AdminLoader? loader;
  final Future<UserModel> Function(String userId)? detailLoader;
  final Future<String> Function(String userId)? passwordResetter;
  final Future<UserModel> Function(String userId, AccountStatus status)?
      statusUpdater;

  @override
  State<AdministratorsPage> createState() => _AdministratorsPageState();
}

class _AdministratorsPageState extends State<AdministratorsPage> {
  final _searchController = TextEditingController();
  List<UserModel>? _admins;
  Map<String, String> _establishments = {};
  bool _loading = true;
  String? _error;
  String? _status;
  String? _establishmentId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_admins == null && _loading) _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<List<UserModel>> _fetch() =>
      widget.loader?.call(
        search: _searchController.text.trim(),
        status: _status,
        establishmentId: _establishmentId,
      ) ??
      context.read<StoreService>().getSuperAdminUsers(
            role: 'admin',
            search: _searchController.text.trim(),
            status: _status,
            establishmentId: _establishmentId,
          );

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _admins = null;
    });
    try {
      final admins = await _fetch();
      if (!mounted) return;
      final establishments = <String, String>{..._establishments};
      for (final admin in admins) {
        if (admin.schoolId != null && admin.establishment != null) {
          establishments[admin.schoolId!] = admin.establishment!;
        }
      }
      setState(() {
        _admins = admins;
        _establishments = establishments;
        _loading = false;
      });
    } on Exception {
      if (!mounted) return;
      setState(() {
        _error = 'Impossible de charger les administrateurs.';
        _loading = false;
      });
    }
  }

  Future<void> _showDetail(UserModel summary) async {
    setState(() => _loading = true);
    try {
      final admin = await (widget.detailLoader?.call(summary.id) ??
          context.read<StoreService>().getSuperAdminUser(summary.id));
      if (!mounted) return;
      setState(() => _loading = false);
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Détail administrateur'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(admin.name,
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              Text(admin.email),
              if (admin.phone?.isNotEmpty ?? false) Text(admin.phone!),
              const SizedBox(height: AppSpacing.s3),
              Text('Établissement : ${admin.establishment ?? "Non rattaché"}'),
              Text('Compte : ${admin.status.label}'),
              Text(
                  'Statut de l’établissement : ${admin.establishmentStatus == "active" ? "Actif" : "Suspendu"}'),
              Text(admin.mustChangePassword
                  ? 'Changement de mot de passe obligatoire'
                  : 'Mot de passe configuré'),
              Text('Créé le : ${_formatDate(admin.createdAt)}'),
              Text(admin.lastLoginAt == null
                  ? 'Dernière connexion : non disponible'
                  : 'Dernière connexion : ${_formatDate(admin.lastLoginAt)}'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Fermer'),
            ),
          ],
        ),
      );
    } on Exception {
      if (!mounted) return;
      setState(() => _loading = false);
      AppToast.error(context, 'Impossible de charger le détail.');
    }
  }

  Future<void> _resetPassword(UserModel admin) async {
    try {
      final password = await (widget.passwordResetter?.call(admin.id) ??
          context.read<StoreService>().resetAdminPassword(admin.id));
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Mot de passe temporaire généré'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                  'Copiez-le maintenant. Il ne sera affiché qu’une seule fois, expire après 24 heures et ne permet qu’une connexion avant son remplacement.'),
              const SizedBox(height: AppSpacing.s3),
              SelectableText(password,
                  key: const Key('temporary-admin-password'),
                  style: const TextStyle(
                      fontFamily: 'monospace', fontWeight: FontWeight.bold)),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Fermer'),
            ),
          ],
        ),
      );
      await _load();
    } on ApiException catch (error) {
      if (!mounted) return;
      AppToast.error(context, error.message);
    }
  }

  Future<void> _toggleStatus(UserModel admin) async {
    final next = admin.status == AccountStatus.active
        ? AccountStatus.suspended
        : AccountStatus.active;
    try {
      await (widget.statusUpdater?.call(admin.id, next) ??
          context
              .read<StoreService>()
              .updateAdminAccountStatus(admin.id, next));
      if (mounted) await _load();
    } on ApiException catch (error) {
      if (!mounted) return;
      AppToast.error(context, error.message);
    }
  }

  String _formatDate(String? value) {
    return AppDateUtils.formatNumeric(value, fallback: 'Non disponible');
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.s6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const WorkspaceHeader(
            title: 'Administrateurs scolaires',
            subtitle: 'Comptes de direction associés aux établissements',
          ),
          Wrap(
            spacing: AppSpacing.s3,
            runSpacing: AppSpacing.s3,
            children: [
              SizedBox(
                width: 300,
                child: TextField(
                  key: const Key('admin-search'),
                  controller: _searchController,
                  decoration: const InputDecoration(
                    labelText: 'Rechercher',
                    prefixIcon: Icon(Icons.search_rounded),
                  ),
                  onSubmitted: (_) => _load(),
                ),
              ),
              SizedBox(
                width: 190,
                child: DropdownButtonFormField<String?>(
                  key: const Key('admin-status-filter'),
                  isExpanded: true,
                  initialValue: _status,
                  decoration: const InputDecoration(labelText: 'Statut compte'),
                  items: const [
                    DropdownMenuItem(value: null, child: Text('Tous')),
                    DropdownMenuItem(value: 'active', child: Text('Actif')),
                    DropdownMenuItem(
                        value: 'suspended', child: Text('Suspendu')),
                  ],
                  onChanged: (value) {
                    _status = value;
                    _load();
                  },
                ),
              ),
              SizedBox(
                width: 250,
                child: DropdownButtonFormField<String?>(
                  key: const Key('admin-establishment-filter'),
                  isExpanded: true,
                  initialValue: _establishmentId,
                  decoration: const InputDecoration(labelText: 'Établissement'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Tous')),
                    ..._establishments.entries.map((entry) => DropdownMenuItem(
                        value: entry.key, child: Text(entry.value))),
                  ],
                  onChanged: (value) {
                    _establishmentId = value;
                    _load();
                  },
                ),
              ),
              AppButton(
                key: const Key('admin-search-button'),
                label: 'Rechercher',
                icon: Icons.search_rounded,
                onPressed: _load,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s5),
          if (_loading)
            const Center(
              child: CircularProgressIndicator(key: Key('admins-loading')),
            )
          else if (_error != null)
            AppCard(
              key: const Key('admins-error'),
              child: Column(
                children: [
                  Text(_error!,
                      style: const TextStyle(color: AppColors.danger500)),
                  const SizedBox(height: AppSpacing.s3),
                  AppButton(label: 'Réessayer', onPressed: _load),
                ],
              ),
            )
          else if (_admins!.isEmpty)
            const AppCard(
              key: Key('admins-empty'),
              child: Text('Aucun administrateur trouvé.'),
            )
          else
            AppCard(
              padding: EdgeInsets.zero,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  headingRowColor: WidgetStatePropertyAll(
                      isDark ? AppColors.darkBgTableStripe : AppColors.gray100),
                  columns: const [
                    DataColumn(label: Text('Administrateur')),
                    DataColumn(label: Text('Téléphone')),
                    DataColumn(label: Text('Établissement')),
                    DataColumn(label: Text('Compte')),
                    DataColumn(label: Text('Établissement')),
                    DataColumn(label: Text('Mot de passe')),
                    DataColumn(label: Text('Création')),
                    DataColumn(label: Text('Actions')),
                  ],
                  rows: _admins!
                      .map((admin) => DataRow(cells: [
                            DataCell(Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(admin.name,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold)),
                                Text(admin.email,
                                    style: const TextStyle(fontSize: 11)),
                              ],
                            )),
                            DataCell(Text(admin.phone ?? 'Non renseigné')),
                            DataCell(
                                Text(admin.establishment ?? 'Non rattaché')),
                            DataCell(AppBadge(
                              label: admin.status.label,
                              variant: admin.status == AccountStatus.active
                                  ? AppBadgeVariant.success
                                  : AppBadgeVariant.danger,
                            )),
                            DataCell(AppBadge(
                              label: admin.establishmentStatus == 'active'
                                  ? 'Actif'
                                  : 'Suspendu',
                              variant: admin.establishmentStatus == 'active'
                                  ? AppBadgeVariant.success
                                  : AppBadgeVariant.warning,
                            )),
                            DataCell(AppBadge(
                              label: admin.mustChangePassword
                                  ? 'À changer'
                                  : 'Configuré',
                              variant: admin.mustChangePassword
                                  ? AppBadgeVariant.warning
                                  : AppBadgeVariant.success,
                            )),
                            DataCell(Text(_formatDate(admin.createdAt))),
                            DataCell(Row(children: [
                              IconButton(
                                tooltip: 'Consulter',
                                onPressed: () => _showDetail(admin),
                                icon: const Icon(Icons.visibility_outlined),
                              ),
                              IconButton(
                                tooltip: 'Réinitialiser le mot de passe',
                                onPressed: () => _resetPassword(admin),
                                icon: const Icon(Icons.password_rounded),
                              ),
                              IconButton(
                                tooltip: admin.status == AccountStatus.active
                                    ? 'Suspendre le compte'
                                    : 'Réactiver le compte',
                                onPressed: () => _toggleStatus(admin),
                                icon: Icon(admin.status == AccountStatus.active
                                    ? Icons.person_off_outlined
                                    : Icons.person_outline),
                              ),
                            ])),
                          ]))
                      .toList(),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import '../datasources/local_storage_source.dart';
import '../datasources/api_client.dart';
import '../repositories/school_repository.dart';
import '../datasources/seed_data.dart';
import '../models/user_model.dart';
import '../models/plan_model.dart';
import '../models/establishment_model.dart';
import '../models/academic_year_model.dart';
import '../models/class_model.dart';
import '../models/subject_model.dart';
import '../models/teacher_model.dart';
import '../models/student_model.dart';
import '../models/attendance_sheet_model.dart';
import '../models/registration_model.dart';
import '../models/affectation_model.dart';
import '../models/grade_model.dart';
import '../models/behavior_assessment_model.dart';
import '../models/evaluation_model.dart';
import '../models/grade_modification_request_model.dart';
import '../models/grade_change_log_model.dart';
import '../models/evaluation_period_config_model.dart';
import '../models/annual_bulletin_model.dart';
import '../models/annual_decision_model.dart';
import '../models/other_models.dart';
import 'result_service.dart';
import '../models/finance/finance_models.dart';
import '../../core/constants/establishment_types.dart';
import '../../core/utils/date_utils.dart';
import '../../core/utils/id_generator.dart';
import '../models/education/school_level_model.dart';
import '../models/education/school_cycle_model.dart';
import '../models/education/series_model.dart';
export '../../core/constants/establishment_types.dart';

/// StoreService centralisé — Portage Dart exact du `Store` JS (store.js)
/// Gère le multi-tenant, les permissions par rôle, les filtres par année et le thème.
class StoreService extends ChangeNotifier {
  StoreService({ApiClient? api}) : _api = api ?? ApiClient() {
    _api.onUnauthorized = _handleUnauthorized;
  }

  final LocalStorageSource _storage = LocalStorageSource();
  final ApiClient _api;
  late final SchoolRepository _repository = SchoolRepository(_api);

  UserModel? _currentUser;
  ThemeMode _themeMode = ThemeMode.light;
  String? _selectedAcademicYearId;

  // Collections en mémoire
  List<UserModel> _users = [];
  List<EstablishmentModel> _establishments = [];
  List<SubscriptionModel> _subscriptions = [];
  List<AcademicYearModel> _academicYears = [];
  List<ClassModel> _classes = [];
  List<SubjectModel> _subjects = [];
  List<TeacherModel> _teachers = [];
  List<StudentModel> _students = [];
  List<AffectationModel> _affectations = [];
  List<GradeModel> _grades = [];
  List<BehaviorAssessmentModel> _behaviorAssessments = [];
  List<EvaluationModel> _evaluations = [];
  List<EvaluationPeriodConfigModel> _evaluationPeriodConfigs = [];
  List<dynamic> _gradeModificationRequests = [];
  List<dynamic> _gradeChangeLogs = [];
  List<AbsenceModel> _absences = [];
  List<AssignmentModel> _assignments = [];
  List<NotificationModel> _notifications = [];
  List<AuditLogModel> _auditLogs = [];
  List<AnnouncementModel> _announcements = [];
  List<ConversationModel> _conversations = [];
  List<DocumentModel> _documents = [];
  List<StudentRegistrationModel> _studentRegistrations = [];
  List<FeeModel> _financeFees = [];
  List<FinanceRegistrationModel> _financeRegistrations = [];
  List<FinanceFeeAssignmentModel> _financeFeeAssignments = [];
  List<FinancePaymentModel> _financePayments = [];
  List<FinanceReceiptModel> _financeReceipts = [];
  // New FinancialAccount / FinancialLine / FinancialPayment storage
  List<FinancialAccountModel> _financialAccounts = [];
  List<FinancialLineModel> _financialLines = [];
  List<FinancialPaymentRecord> _financialPaymentsRecords = [];
  // Annual bulletins stored (typed)
  List<AnnualBulletinModel> _annualBulletins = [];
  List<AnnualDecisionModel> _annualDecisions = [];
  List<DecisionChangeLogModel> _decisionChangeLogs = [];
  List<ReEnrollmentRequestModel> _reEnrollmentRequests = [];

  // School-levels and series for primary/college/highschool
  List<SchoolCycleModel> _schoolCycles = [];
  List<SchoolLevelModel> _schoolLevels = [];
  List<SeriesModel> _series = [];

  bool _isLoaded = false;
  String? _passwordChangeError;
  String? _loginError;
  String? _sessionWarning;
  final Map<String, Set<String>> _remoteIds = {};
  bool _remoteSyncScheduled = false;
  bool _remoteSyncInFlight = false;
  bool _remoteSyncPending = false;
  final Map<String, int> _studentPhotoRevisions = {};

  // Annual bulletin lock map: key = '<studentId>_<academicYearId>' => true
  Map<String, bool> _lockedAnnualBulletins = {};

  // Getters
  bool get isLoaded => _isLoaded;
  UserModel? get currentUser => _currentUser;
  bool get isAuthenticated => _currentUser != null;
  ThemeMode get themeMode => _themeMode;
  bool get isDarkMode => _themeMode == ThemeMode.dark;
  String? get passwordChangeError => _passwordChangeError;
  String? get loginError => _loginError;
  String? get sessionWarning => _sessionWarning;

  int studentPhotoRevision(String studentId) =>
      _studentPhotoRevisions[studentId] ?? 0;

  int _ownProfilePhotoRevision = 0;
  int get ownProfilePhotoRevision => _ownProfilePhotoRevision;

  Future<Uint8List?> ownProfilePhotoRemote() async {
    try {
      return await _repository.ownProfilePhoto();
    } on ApiException catch (error) {
      if (error.statusCode == 404) return null;
      rethrow;
    }
  }

  Future<void> updateOwnProfilePhotoRemote(Map<String, dynamic> file) async {
    await _repository.updateOwnProfilePhoto(file);
    _ownProfilePhotoRevision++;
    notifyListeners();
  }

  Future<UserModel> updateOwnProfileRemote({
    required String name,
    required String email,
  }) async {
    final updated = UserModel.fromJson(await _repository.updateOwnProfile({
      'name': name.trim(),
      'email': email.trim(),
    }));
    _currentUser = updated;
    await _storage.set('currentUser', updated.toJson());
    notifyListeners();
    return updated;
  }

  void _clearBusinessMemory() {
    _selectedAcademicYearId = null;
    _lockedAnnualBulletins = {};
    _users.clear();
    _establishments.clear();
    _subscriptions.clear();
    _academicYears.clear();
    _classes.clear();
    _subjects.clear();
    _teachers.clear();
    _students.clear();
    _affectations.clear();
    _grades.clear();
    _behaviorAssessments.clear();
    _evaluations.clear();
    _evaluationPeriodConfigs.clear();
    _gradeModificationRequests.clear();
    _gradeChangeLogs.clear();
    _absences.clear();
    _assignments.clear();
    _notifications.clear();
    _auditLogs.clear();
    _announcements.clear();
    _conversations.clear();
    _documents.clear();
    _studentRegistrations.clear();
    _financeFees.clear();
    _financeRegistrations.clear();
    _financeFeeAssignments.clear();
    _financePayments.clear();
    _financeReceipts.clear();
    _financialAccounts.clear();
    _financialLines.clear();
    _financialPaymentsRecords.clear();
    _annualBulletins.clear();
    _annualDecisions.clear();
    _decisionChangeLogs.clear();
    _reEnrollmentRequests.clear();
    _schoolCycles.clear();
    _schoolLevels.clear();
    _series.clear();
    _remoteIds.clear();
  }

  Future<void> _purgePersistedSessionData() async {
    final preservedTheme = _themeMode == ThemeMode.dark ? 'dark' : 'light';
    await _storage.clearAll();
    await _storage.set('initialized', true);
    await _storage.set('theme', preservedTheme);
  }

  void _handleUnauthorized() {
    if (_currentUser == null) return;
    _currentUser = null;
    _loginError = null;
    _sessionWarning = 'Votre session a expiré. Veuillez vous reconnecter.';
    _api.setToken(null);
    _clearBusinessMemory();
    unawaited(_purgePersistedSessionData());
    notifyListeners();
  }

  /// Initialisation asynchrone du store
  Future<void> init() async {
    await _storage.init();

    // Thème
    final savedTheme = _storage.get('theme');
    if (savedTheme == 'dark') {
      _themeMode = ThemeMode.dark;
    } else {
      _themeMode = ThemeMode.light;
    }

    if (!_storage.isInitialized()) {
      // The local store is only a cache. Business data is loaded from the API
      // after authentication; no demo dataset is used during normal startup.
      await _saveAllAsync();
      await _storage.set('initialized', true);
    } else {
      _loadAll();
    }

    // Utilisateur actuellement connecté
    final savedUserJson = _storage.get('currentUser');
    if (savedUserJson != null && savedUserJson is Map<String, dynamic>) {
      _currentUser = UserModel.fromJson(savedUserJson);
      final token = _storage.get('accessToken');
      if (token is String && token.isNotEmpty) {
        if (_jwtIsExpired(token)) {
          _currentUser = null;
          await _storage.remove('currentUser');
          await _storage.remove('accessToken');
          _sessionWarning =
              'Votre session a expiré. Veuillez vous reconnecter.';
          _isLoaded = true;
          notifyListeners();
          return;
        }
        _api.setToken(token);
        try {
          final remoteUser = UserModel.fromJson(await _repository.me());
          _currentUser = remoteUser;
          await _storage.set('currentUser', remoteUser.toJson());
          if (!remoteUser.mustChangePassword) {
            try {
              await _loadRemoteData();
              _sessionWarning = null;
            } on Exception {
              // /auth/me has already validated this token. A secondary data
              // endpoint must not invalidate an otherwise healthy session.
              _sessionWarning =
                  'Session restaurée, mais certaines données n’ont pas encore pu être actualisées.';
            }
          }
        } on ApiException catch (error) {
          if (error.statusCode == 401 || error.statusCode == 403) {
            _currentUser = null;
            _api.setToken(null);
            await _storage.remove('currentUser');
            await _storage.remove('accessToken');
          } else {
            // A 5xx/business failure does not prove that the persisted JWT is
            // invalid. Keep the cached identity and retry server validation.
            _sessionWarning =
                'Session conservée, mais le serveur est temporairement indisponible.';
          }
        } on Exception {
          // Keep the persisted token so a temporary server/network outage does
          // not destroy the session. Protected calls remain server-controlled.
          _sessionWarning =
              'Session conservée, mais sa vérification est temporairement indisponible.';
        }
      } else {
        _currentUser = null;
      }
    }

    _isLoaded = true;
    notifyListeners();
  }

  Future<void> _saveAllAsync() async {
    final writes = <Future<bool>>[
      _storage.set('usersList', _users.map((u) => u.toJson()).toList()),
      _storage.set(
          'establishments', _establishments.map((e) => e.toJson()).toList()),
      _storage.set(
          'subscriptions', _subscriptions.map((s) => s.toJson()).toList()),
      _storage.set(
          'academicYears', _academicYears.map((a) => a.toJson()).toList()),
      _storage.set('classes', _classes.map((c) => c.toJson()).toList()),
      _storage.set('subjects', _subjects.map((s) => s.toJson()).toList()),
      _storage.set('teachers', _teachers.map((t) => t.toJson()).toList()),
      _storage.set('students', _students.map((s) => s.toJson()).toList()),
      _storage.set(
          'affectations', _affectations.map((a) => a.toJson()).toList()),
      _storage.set('grades', _grades.map((g) => g.toJson()).toList()),
      _storage.set('behaviorAssessments',
          _behaviorAssessments.map((b) => b.toJson()).toList()),
      _storage.set('evaluations', _evaluations.map((e) => e.toJson()).toList()),
      _storage.set('evaluationPeriodConfigs',
          _evaluationPeriodConfigs.map((c) => c.toJson()).toList()),
      _storage.set('gradeModificationRequests',
          _gradeModificationRequests.map((r) => r.toJson()).toList()),
      _storage.set(
          'gradeChangeLogs', _gradeChangeLogs.map((r) => r.toJson()).toList()),
      _storage.set('absences', _absences.map((a) => a.toJson()).toList()),
      _storage.set('assignments', _assignments.map((a) => a.toJson()).toList()),
      _storage.set(
          'notifications', _notifications.map((n) => n.toJson()).toList()),
      _storage.set('auditLogs', _auditLogs.map((a) => a.toJson()).toList()),
      _storage.set(
          'announcements', _announcements.map((a) => a.toJson()).toList()),
      _storage.set(
          'conversations', _conversations.map((c) => c.toJson()).toList()),
      _storage.set('documents', _documents.map((d) => d.toJson()).toList()),
      _storage.set('studentRegistrations',
          _studentRegistrations.map((r) => r.toJson()).toList()),
      _storage.set('financeFees', _financeFees.map((f) => f.toJson()).toList()),
      _storage.set('financeRegistrations',
          _financeRegistrations.map((r) => r.toJson()).toList()),
      _storage.set('financeFeeAssignments',
          _financeFeeAssignments.map((a) => a.toJson()).toList()),
      _storage.set(
          'financePayments', _financePayments.map((p) => p.toJson()).toList()),
      _storage.set(
          'financeReceipts', _financeReceipts.map((r) => r.toJson()).toList()),
      // New financial account storage
      _storage.set('financialAccounts',
          _financialAccounts.map((a) => a.toJson()).toList()),
      _storage.set(
          'financialLines', _financialLines.map((l) => l.toJson()).toList()),
      _storage.set('financialPayments',
          _financialPaymentsRecords.map((p) => p.toJson()).toList()),
      _storage.set(
          'schoolCycles', _schoolCycles.map((s) => s.toJson()).toList()),
      _storage.set(
          'schoolLevels', _schoolLevels.map((s) => s.toJson()).toList()),
      _storage.set('series', _series.map((s) => s.toJson()).toList()),
      _storage.set('lockedAnnualBulletins', _lockedAnnualBulletins),
      _storage.set(
          'annualBulletins', _annualBulletins.map((b) => b.toJson()).toList()),
      _storage.set(
          'annualDecisions', _annualDecisions.map((d) => d.toJson()).toList()),
      _storage.set('decisionChangeLogs',
          _decisionChangeLogs.map((d) => d.toJson()).toList()),
      _storage.set('reEnrollmentRequests',
          _reEnrollmentRequests.map((r) => r.toJson()).toList()),
    ];

    await Future.wait(writes);
  }

  void _saveAll() {
    unawaited(_saveAllAsync());
    if (_currentUser != null) _scheduleRemoteSync();
  }

  /// Regroupe les mutations rapprochées et interdit les synchronisations
  /// complètes concurrentes. Les écrans métier écrivent déjà immédiatement
  /// via leurs routes dédiées ; ce passage reste uniquement un filet de
  /// compatibilité pour les anciennes mutations locales.
  void _scheduleRemoteSync() {
    _remoteSyncPending = true;
    if (_remoteSyncScheduled || _remoteSyncInFlight) return;
    _remoteSyncScheduled = true;
    scheduleMicrotask(() {
      _remoteSyncScheduled = false;
      unawaited(_flushRemoteSync());
    });
  }

  Future<void> _flushRemoteSync() async {
    if (_remoteSyncInFlight || !_remoteSyncPending || _currentUser == null) {
      return;
    }
    _remoteSyncPending = false;
    _remoteSyncInFlight = true;
    try {
      await _syncRemoteState();
    } finally {
      _remoteSyncInFlight = false;
      if (_remoteSyncPending && _currentUser != null) _scheduleRemoteSync();
    }
  }

  void _loadAll() {
    _users =
        _loadList('usersList', (j) => UserModel.fromJson(j), SeedData.users);
    _establishments = _loadList('establishments',
        (j) => EstablishmentModel.fromJson(j), SeedData.establishments);
    _subscriptions = _loadList('subscriptions',
        (j) => SubscriptionModel.fromJson(j), SeedData.subscriptions);
    _academicYears = _loadList('academicYears',
        (j) => AcademicYearModel.fromJson(j), SeedData.academicYears);
    _classes = _loadList('classes', (j) => ClassModel.fromJson(j), []);
    _subjects = _loadList('subjects', (j) => SubjectModel.fromJson(j), []);
    _teachers = _loadList('teachers', (j) => TeacherModel.fromJson(j), []);
    _students = _loadList(
        'students', (j) => StudentModel.fromJson(j), SeedData.students);
    _affectations =
        _loadList('affectations', (j) => AffectationModel.fromJson(j), []);
    _grades = _loadList('grades', (j) => GradeModel.fromJson(j), []);
    _behaviorAssessments = _loadList(
        'behaviorAssessments', (j) => BehaviorAssessmentModel.fromJson(j), []);
    _evaluations =
        _loadList('evaluations', (j) => EvaluationModel.fromJson(j), []);
    _evaluationPeriodConfigs = _loadList('evaluationPeriodConfigs',
        (j) => EvaluationPeriodConfigModel.fromJson(j), []);
    _gradeModificationRequests = _loadList('gradeModificationRequests',
        (j) => GradeModificationRequestModel.fromJson(j), []);
    _gradeChangeLogs = _loadList(
        'gradeChangeLogs', (j) => GradeChangeLogModel.fromJson(j), []);
    _absences = _loadList('absences', (j) => AbsenceModel.fromJson(j), []);
    // annual bulletins
    _annualBulletins = _loadList(
        'annualBulletins', (j) => AnnualBulletinModel.fromJson(j), []);
    _annualDecisions = _loadList(
        'annualDecisions', (j) => AnnualDecisionModel.fromJson(j), []);
    _decisionChangeLogs = _loadList(
        'decisionChangeLogs', (j) => DecisionChangeLogModel.fromJson(j), []);
    _reEnrollmentRequests = _loadList('reEnrollmentRequests',
        (j) => ReEnrollmentRequestModel.fromJson(j), []);
    _assignments =
        _loadList('assignments', (j) => AssignmentModel.fromJson(j), []);
    _notifications =
        _loadList('notifications', (j) => NotificationModel.fromJson(j), []);
    _announcements =
        _loadList('announcements', (j) => AnnouncementModel.fromJson(j), []);
    _conversations =
        _loadList('conversations', (j) => ConversationModel.fromJson(j), []);
    _documents = _loadList('documents', (j) => DocumentModel.fromJson(j), []);
    _financeFees = _loadList('financeFees', (j) => FeeModel.fromJson(j), []);
    _financeRegistrations = _loadList('financeRegistrations',
        (j) => FinanceRegistrationModel.fromJson(j), []);
    _studentRegistrations = _loadList('studentRegistrations',
        (j) => StudentRegistrationModel.fromJson(j), []);
    _financeFeeAssignments = _loadList('financeFeeAssignments',
        (j) => FinanceFeeAssignmentModel.fromJson(j), []);
    _financePayments = _loadList(
        'financePayments', (j) => FinancePaymentModel.fromJson(j), []);
    _financeReceipts = _loadList(
        'financeReceipts', (j) => FinanceReceiptModel.fromJson(j), []);
    // Load new financial account structures (if present)
    _financialAccounts = _loadList(
        'financialAccounts', (j) => FinancialAccountModel.fromJson(j), []);
    _financialLines =
        _loadList('financialLines', (j) => FinancialLineModel.fromJson(j), []);
    _financialPaymentsRecords = _loadList(
        'financialPayments', (j) => FinancialPaymentRecord.fromJson(j), []);
    _schoolCycles =
        _loadList('schoolCycles', (j) => SchoolCycleModel.fromJson(j), []);
    _schoolLevels = _loadList(
        'schoolLevels',
        (j) => SchoolLevelModel.fromJson(j),
        SeedData.schoolLevels.cast<SchoolLevelModel>());
    _series = _loadList('series', (j) => SeriesModel.fromJson(j),
        SeedData.series.cast<SeriesModel>());

    // load locked annual bulletins map (saved as Map<String,bool>)
    final lockedMap = _storage.get('lockedAnnualBulletins');
    if (lockedMap != null && lockedMap is Map<String, dynamic>) {
      _lockedAnnualBulletins = lockedMap.map((k, v) => MapEntry(k, v == true));
    }

    // load notifications and audit logs
    _notifications =
        _loadList('notifications', (j) => NotificationModel.fromJson(j), []);
    _auditLogs = _loadList('auditLogs', (j) => AuditLogModel.fromJson(j), []);
  }

  List<T> _loadList<T>(
      String key, T Function(Map<String, dynamic>) fromJson, List<T> fallback) {
    final raw = _storage.get(key);
    if (raw == null || raw is! List) return fallback;
    try {
      return raw
          .map((item) => fromJson(Map<String, dynamic>.from(item)))
          .toList();
    } catch (_) {
      return fallback;
    }
  }

  // ---- Authentification ----
  bool _jwtIsExpired(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return true;
      final payload = jsonDecode(
          utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))));
      final expiration = payload is Map ? payload['exp'] : null;
      if (expiration is! num) return true;
      return DateTime.now().millisecondsSinceEpoch >= expiration * 1000;
    } on Exception {
      return true;
    }
  }

  Future<bool> login(String identifier, String password) async {
    final cleanIdentifier = identifier.toLowerCase().trim();
    _loginError = null;
    _sessionWarning = null;
    try {
      final response = await _repository.login(cleanIdentifier, password);
      final token = response['accessToken'] as String?;
      final rawUser = response['user'];
      if (token == null || token.isEmpty || rawUser is! Map) {
        _loginError = 'Réponse de connexion invalide.';
        return false;
      }
      _api.setToken(token);
      final user = UserModel.fromJson(Map<String, dynamic>.from(rawUser));
      _currentUser = user;
      await _storage.set('currentUser', user.toJson());
      await _storage.set('accessToken', token);
      if (!user.mustChangePassword) {
        try {
          await _loadRemoteData();
        } on Exception {
          // Authentication succeeded and the token is valid. Do not report a
          // false password error because a secondary module failed to load.
          _sessionWarning =
              'Connexion réussie, mais certaines données n’ont pas encore pu être actualisées.';
        }
      }
      notifyListeners();
      return true;
    } on ApiException catch (error) {
      _loginError = error.message;
      _api.setToken(null);
      _currentUser = null;
      await _storage.remove('currentUser');
      await _storage.remove('accessToken');
      return false;
    } on TimeoutException {
      _loginError = 'Le serveur met trop de temps à répondre.';
      _api.setToken(null);
      _currentUser = null;
      await _storage.remove('currentUser');
      await _storage.remove('accessToken');
      return false;
    } on Exception {
      _loginError =
          'Serveur indisponible. Vérifiez la connexion puis réessayez.';
      _api.setToken(null);
      _currentUser = null;
      await _storage.remove('currentUser');
      await _storage.remove('accessToken');
      return false;
    }
  }

  Future<bool> changeRequiredPassword(String newPassword) async {
    _passwordChangeError = null;
    try {
      final response = await _repository.changeRequiredPassword(newPassword);
      final refreshed = await _applyPasswordChangeResponse(response);
      if (refreshed.mustChangePassword) {
        _passwordChangeError =
            'Le serveur exige encore le changement du mot de passe.';
        return false;
      }
      try {
        await _loadRemoteData();
      } on Exception {
        _sessionWarning =
            'Mot de passe modifié, mais certaines données n’ont pas encore pu être actualisées.';
      }
      await _saveAllAsync();
      notifyListeners();
      return true;
    } on ApiException catch (error) {
      _passwordChangeError = error.message;
      return false;
    } on Exception {
      _passwordChangeError = 'Serveur indisponible. Veuillez réessayer.';
      return false;
    }
  }

  Future<bool> changePassword(
      String currentPassword, String newPassword, String confirmation) async {
    _passwordChangeError = null;
    try {
      final response = await _repository.changePassword(
          currentPassword, newPassword, confirmation);
      await _applyPasswordChangeResponse(response);
      notifyListeners();
      return true;
    } on ApiException catch (error) {
      _passwordChangeError = error.message;
      return false;
    } on TimeoutException {
      _passwordChangeError = 'Le serveur met trop de temps à répondre.';
      return false;
    } on Exception {
      _passwordChangeError = 'Le serveur est temporairement indisponible.';
      return false;
    }
  }

  Future<UserModel> _applyPasswordChangeResponse(
      Map<String, dynamic> response) async {
    final token = response['accessToken'];
    final rawUser = response['user'];
    if (token is! String || token.isEmpty || rawUser is! Map) {
      throw ApiException(
          'Réponse de changement de mot de passe invalide.', 500);
    }
    final user = UserModel.fromJson(Map<String, dynamic>.from(rawUser));
    _api.setToken(token);
    _currentUser = user;
    await _storage.set('accessToken', token);
    await _storage.set('currentUser', user.toJson());
    return user;
  }

  Future<void> _loadRemoteData() async {
    final data = await _repository.bootstrap();
    Map<String, dynamic>? teacherWorkspace;
    Map<String, dynamic>? studentWorkspace;
    Map<String, dynamic>? parentWorkspace;
    if (_currentUser?.role == UserRole.teacher) {
      try {
        teacherWorkspace = await _repository.teacherWorkspace();
      } on TypeError {
        // Compatibilité avec les anciens adaptateurs de tests/local-first qui
        // répondent [] aux routes qu'ils ne connaissent pas encore.
        teacherWorkspace = null;
      }
    }
    if (_currentUser?.role == UserRole.student) {
      studentWorkspace = await _repository.studentWorkspace();
    }
    if (_currentUser?.role == UserRole.parent) {
      parentWorkspace = await _repository.parentWorkspace();
    }
    List<Map<String, dynamic>> teacherWorkspaceList(String key) =>
        List<Map<String, dynamic>>.from(
          ((teacherWorkspace?[key] as List?) ?? const [])
              .map((item) => Map<String, dynamic>.from(item as Map)),
        );
    List<Map<String, dynamic>> studentWorkspaceList(String key) =>
        List<Map<String, dynamic>>.from(
          ((studentWorkspace?[key] as List?) ?? const [])
              .map((item) => Map<String, dynamic>.from(item as Map)),
        );
    List<Map<String, dynamic>> parentWorkspaceList(String key) =>
        List<Map<String, dynamic>>.from(
          ((parentWorkspace?[key] as List?) ?? const [])
              .map((item) => Map<String, dynamic>.from(item as Map)),
        );
    _establishments = (data['establishments'] ?? [])
        .map(EstablishmentModel.fromJson)
        .toList();
    _subscriptions =
        (data['subscriptions'] ?? []).map(SubscriptionModel.fromJson).toList();
    // Le bootstrap historique ne contient pas toujours la configuration
    // relationnelle actuelle de l'établissement (notamment enabledModules).
    // Pour un ADMIN, cette projection PostgreSQL doit être chargée avant de
    // décider quelles collections relationnelles récupérer.
    if (_currentUser?.role == UserRole.admin) {
      try {
        final establishment =
            EstablishmentModel.fromJson(await _repository.adminEstablishment());
        final index =
            _establishments.indexWhere((item) => item.id == establishment.id);
        if (index >= 0) {
          _establishments[index] = establishment;
        } else {
          _establishments.add(establishment);
        }
      } on ApiException catch (error) {
        // Compatibilité limitée avec les anciens backends et mocks. Les
        // autres erreurs restent bloquantes afin d'éviter un faux état vide.
        if (error.statusCode != 404) rethrow;
      } on TypeError {
        // Même compatibilité legacy : le backend réel retourne toujours un
        // objet, tandis que certains anciens mocks retournent une liste vide.
      }
    }
    if (teacherWorkspace?['establishment'] is Map) {
      final establishment = EstablishmentModel.fromJson(
          Map<String, dynamic>.from(teacherWorkspace!['establishment'] as Map));
      final index =
          _establishments.indexWhere((item) => item.id == establishment.id);
      if (index >= 0) {
        _establishments[index] = establishment;
      } else {
        _establishments.add(establishment);
      }
    }
    if (studentWorkspace?['establishment'] is Map) {
      final establishment = EstablishmentModel.fromJson(
          Map<String, dynamic>.from(studentWorkspace!['establishment'] as Map));
      final index =
          _establishments.indexWhere((item) => item.id == establishment.id);
      if (index >= 0) {
        _establishments[index] = establishment;
      } else {
        _establishments.add(establishment);
      }
    }
    if (parentWorkspace?['establishment'] is Map) {
      final establishment = EstablishmentModel.fromJson(
          Map<String, dynamic>.from(parentWorkspace!['establishment'] as Map));
      final index =
          _establishments.indexWhere((item) => item.id == establishment.id);
      if (index >= 0) {
        _establishments[index] = establishment;
      } else {
        _establishments.add(establishment);
      }
    }
    // PostgreSQL relational endpoints are canonical for the tenant Admin.
    // Super Admin keeps its global bootstrap projection and has no tenant scope.
    _academicYears = _currentUser?.role == UserRole.admin
        ? (await _repository.academicYears())
            .map(AcademicYearModel.fromJson)
            .toList()
        : _currentUser?.role == UserRole.teacher && teacherWorkspace != null
            ? teacherWorkspaceList('academicYears')
                .map(AcademicYearModel.fromJson)
                .toList()
            : _currentUser?.role == UserRole.student && studentWorkspace != null
                ? studentWorkspaceList('academicYears')
                    .map(AcademicYearModel.fromJson)
                    .toList()
                : _currentUser?.role == UserRole.parent &&
                        parentWorkspace != null
                    ? parentWorkspaceList('academicYears')
                        .map(AcademicYearModel.fromJson)
                        .toList()
                    : (data['academic-years'] ?? [])
                        .map(AcademicYearModel.fromJson)
                        .toList();
    _students = _currentUser?.role == UserRole.student &&
            studentWorkspace?['student'] is Map
        ? [
            StudentModel.fromJson(
                Map<String, dynamic>.from(studentWorkspace!['student'] as Map))
          ]
        : _currentUser?.role == UserRole.teacher && teacherWorkspace != null
            ? teacherWorkspaceList('students')
                .map(StudentModel.fromJson)
                .toList()
            : _currentUser?.role == UserRole.parent && parentWorkspace != null
                ? parentWorkspaceList('students')
                    .map(StudentModel.fromJson)
                    .toList()
                : (data['students'] ?? []).map(StudentModel.fromJson).toList();
    _teachers = _currentUser?.role == UserRole.teacher &&
            teacherWorkspace?['teacher'] is Map
        ? [
            TeacherModel.fromJson(
                Map<String, dynamic>.from(teacherWorkspace!['teacher'] as Map))
          ]
        : (data['teachers'] ?? []).map(TeacherModel.fromJson).toList();
    _classes = _currentUser?.role == UserRole.admin
        ? (await _repository.schoolClasses()).map(ClassModel.fromJson).toList()
        : _currentUser?.role == UserRole.teacher && teacherWorkspace != null
            ? teacherWorkspaceList('classes').map(ClassModel.fromJson).toList()
            : _currentUser?.role == UserRole.student && studentWorkspace != null
                ? studentWorkspaceList('classes')
                    .map(ClassModel.fromJson)
                    .toList()
                : _currentUser?.role == UserRole.parent &&
                        parentWorkspace != null
                    ? parentWorkspaceList('classes')
                        .map(ClassModel.fromJson)
                        .toList()
                    : (data['classes'] ?? []).map(ClassModel.fromJson).toList();
    _schoolCycles = _currentUser?.role == UserRole.student &&
            studentWorkspace != null
        ? studentWorkspaceList('cycles').map(SchoolCycleModel.fromJson).toList()
        : _currentUser?.role == UserRole.parent && parentWorkspace != null
            ? parentWorkspaceList('cycles')
                .map(SchoolCycleModel.fromJson)
                .toList()
            : _currentUser?.role == UserRole.teacher && teacherWorkspace != null
                ? teacherWorkspaceList('cycles')
                    .map(SchoolCycleModel.fromJson)
                    .toList()
                : (data['cycles'] ?? [])
                    .map(SchoolCycleModel.fromJson)
                    .toList();
    _schoolLevels = _currentUser?.role == UserRole.student &&
            studentWorkspace != null
        ? studentWorkspaceList('schoolLevels')
            .map(SchoolLevelModel.fromJson)
            .toList()
        : _currentUser?.role == UserRole.parent && parentWorkspace != null
            ? parentWorkspaceList('schoolLevels')
                .map(SchoolLevelModel.fromJson)
                .toList()
            : _currentUser?.role == UserRole.teacher && teacherWorkspace != null
                ? teacherWorkspaceList('schoolLevels')
                    .map(SchoolLevelModel.fromJson)
                    .toList()
                : (data['school-levels'] ?? [])
                    .map(SchoolLevelModel.fromJson)
                    .toList();
    _subjects = _currentUser?.role == UserRole.teacher &&
            teacherWorkspace != null
        ? teacherWorkspaceList('subjects').map(SubjectModel.fromJson).toList()
        : (data['subjects'] ?? []).map(SubjectModel.fromJson).toList();
    _evaluations =
        (data['evaluations'] ?? []).map(EvaluationModel.fromJson).toList();
    _grades = (data['grades'] ?? []).map(GradeModel.fromJson).toList();
    _behaviorAssessments = (data['behavior-assessments'] ?? [])
        .map(BehaviorAssessmentModel.fromJson)
        .toList();
    _affectations = _currentUser?.role == UserRole.teacher &&
            teacherWorkspace != null
        ? teacherWorkspaceList('affectations')
            .map(AffectationModel.fromJson)
            .toList()
        : (data['affectations'] ?? []).map(AffectationModel.fromJson).toList();
    _absences = (data['absences'] ?? []).map(AbsenceModel.fromJson).toList();
    _assignments =
        (data['assignments'] ?? []).map(AssignmentModel.fromJson).toList();
    _notifications =
        (data['notifications'] ?? []).map(NotificationModel.fromJson).toList();
    _documents = (data['documents'] ?? []).map(DocumentModel.fromJson).toList();
    _financeFees = (data['finance-fees'] ?? []).map(FeeModel.fromJson).toList();
    _financeRegistrations = (data['finance-registrations'] ?? [])
        .map(FinanceRegistrationModel.fromJson)
        .toList();
    _financeFeeAssignments = (data['finance-fee-assignments'] ?? [])
        .map(FinanceFeeAssignmentModel.fromJson)
        .toList();
    _financePayments = (data['finance-payments'] ?? [])
        .map(FinancePaymentModel.fromJson)
        .toList();
    _financeReceipts = (data['finance-receipts'] ?? [])
        .map(FinanceReceiptModel.fromJson)
        .toList();
    _studentRegistrations =
        _currentUser?.role == UserRole.parent && parentWorkspace != null
            ? parentWorkspaceList('registrations')
                .map(StudentRegistrationModel.fromJson)
                .toList()
            : (data['student-registrations'] ?? [])
                .map(StudentRegistrationModel.fromJson)
                .toList();
    _announcements =
        (data['announcements'] ?? []).map(AnnouncementModel.fromJson).toList();
    _annualBulletins = (data['annual-bulletins'] ?? [])
        .map(AnnualBulletinModel.fromJson)
        .toList();
    _annualDecisions = (data['annual-decisions'] ?? [])
        .map(AnnualDecisionModel.fromJson)
        .toList();
    _reEnrollmentRequests = (data['re-enrollment-requests'] ?? [])
        .map(ReEnrollmentRequestModel.fromJson)
        .toList();
    _remoteIds
      ..clear()
      ..addAll(data.map((kind, items) =>
          MapEntry(kind, items.map((item) => item['id'].toString()).toSet())));
    final savedSelection = _storage.get('selectedAcademicYearId');
    final candidate = _selectedAcademicYearId ??
        (savedSelection is String ? savedSelection : null);
    if (candidate != null &&
        _academicYears.any((year) => year.id == candidate)) {
      _selectedAcademicYearId = candidate;
    } else {
      _selectedAcademicYearId = getActiveAcademicYear()?.id;
    }
    if (_selectedAcademicYearId != null) {
      await _storage.set('selectedAcademicYearId', _selectedAcademicYearId!);
    }
    final schoolModules =
        getCurrentSchool()?.enabledModules ?? const <String>[];
    final isAdmin = _currentUser?.role == UserRole.admin;
    final canLoadGrades = (isAdmin || _currentUser?.role == UserRole.teacher) &&
        schoolModules.contains('grades');
    // Start independent requests together. Awaiting each result below keeps
    // model updates deterministic while removing the network waterfall.
    final studentsRequest = isAdmin && schoolModules.contains('students')
        ? _repository.students(academicYearId: _selectedAcademicYearId)
        : null;
    final teachersRequest = isAdmin && schoolModules.contains('teachers')
        ? _repository.teachers()
        : null;
    final subjectsRequest = isAdmin && schoolModules.contains('subjects')
        ? _repository.subjects()
        : null;
    final affectationsRequest =
        isAdmin && schoolModules.contains('affectations')
            ? _repository.affectations(academicYearId: _selectedAcademicYearId)
            : null;
    final evaluationsRequest = canLoadGrades
        ? _repository.evaluations(academicYearId: _selectedAcademicYearId)
        : null;
    final gradesRequest = canLoadGrades
        ? _repository.grades(academicYearId: _selectedAcademicYearId)
        : null;
    final attendanceRequest = isAdmin && schoolModules.contains('attendance')
        ? _repository.attendanceReport({
            if (_selectedAcademicYearId != null)
              'academic_year_id': _selectedAcademicYearId!,
          })
        : null;
    final assignmentsRequest =
        (isAdmin || _currentUser?.role == UserRole.teacher) &&
                schoolModules.contains('assignments')
            ? _repository.assignments(academicYearId: _selectedAcademicYearId)
            : null;
    if (_currentUser?.role == UserRole.admin &&
        (getCurrentSchool()?.enabledModules.contains('students') ?? false)) {
      _students = (await studentsRequest!).map(StudentModel.fromJson).toList();
    }
    if (_currentUser?.role == UserRole.admin &&
        (getCurrentSchool()?.enabledModules.contains('teachers') ?? false)) {
      _teachers = (await teachersRequest!).map(TeacherModel.fromJson).toList();
    }
    if (_currentUser?.role == UserRole.admin &&
        (getCurrentSchool()?.enabledModules.contains('subjects') ?? false)) {
      _subjects = (await subjectsRequest!).map(SubjectModel.fromJson).toList();
    }
    if (_currentUser?.role == UserRole.admin &&
        (getCurrentSchool()?.enabledModules.contains('affectations') ??
            false)) {
      _affectations =
          (await affectationsRequest!).map(AffectationModel.fromJson).toList();
    }
    if ((_currentUser?.role == UserRole.admin ||
            _currentUser?.role == UserRole.teacher) &&
        (getCurrentSchool()?.enabledModules.contains('grades') ?? false)) {
      _evaluations =
          (await evaluationsRequest!).map(EvaluationModel.fromJson).toList();
      try {
        _grades = (await gradesRequest!).map(GradeModel.fromJson).toList();
      } on ApiException catch (error) {
        // Compatibility during a rolling backend deployment. The current
        // server exposes the batch route, so normal operation remains one call.
        if (error.statusCode != 404) rethrow;
        _grades = [];
        for (final evaluation in _evaluations) {
          _grades.addAll((await _repository.evaluationGrades(evaluation.id))
              .map(GradeModel.fromJson));
        }
      }
    }
    // L'ADMIN peut précharger la consultation journalière globale. Pour un
    // ENSEIGNANT, chaque appel doit être chargé depuis son créneau sélectionné
    // (scheduleId) dans AttendancePage ; une lecture globale serait à la fois
    // ambiguë et refusée par le backend.
    if (_currentUser?.role == UserRole.admin &&
        (getCurrentSchool()?.enabledModules.contains('attendance') ?? false)) {
      final report = await attendanceRequest!;
      _absences = List<Map<String, dynamic>>.from(
        ((report['records'] as List?) ?? const [])
            .map((item) => Map<String, dynamic>.from(item as Map)),
      ).map(AbsenceModel.fromJson).toList();
    }
    // Une consultation Comportement exige impérativement une classe et un
    // trimestre. Ces paramètres n'existent pas encore au moment du login :
    // ne surtout pas appeler cette route ici, sinon son refus normal (422)
    // ferait annuler une authentification pourtant réussie. BehaviorPage
    // charge les événements avec son contexte utilisateur explicite.
    _behaviorAssessments = [];
    if ((_currentUser?.role == UserRole.admin ||
            _currentUser?.role == UserRole.teacher) &&
        (getCurrentSchool()?.enabledModules.contains('assignments') ?? false)) {
      _assignments =
          (await assignmentsRequest!).map(AssignmentModel.fromJson).toList();
    }
  }

  Future<void> _syncRemoteState() async {
    final collections = <String, List<dynamic>>{
      'establishments': List.of(_establishments),
      'subscriptions': List.of(_subscriptions),
      'students': List.of(_students),
      'teachers': List.of(_teachers),
      'subjects': List.of(_subjects),
      'evaluations': List.of(_evaluations),
      'grades': List.of(_grades),
      'behavior-assessments': List.of(_behaviorAssessments),
      'affectations': List.of(_affectations),
      'absences': List.of(_absences),
      'assignments': List.of(_assignments),
      'documents': List.of(_documents),
      'student-registrations': List.of(_studentRegistrations),
      'finance-fees': List.of(_financeFees),
      'finance-registrations': List.of(_financeRegistrations),
      'finance-fee-assignments': List.of(_financeFeeAssignments),
      'finance-payments': List.of(_financePayments),
      'finance-receipts': List.of(_financeReceipts),
      'announcements': List.of(_announcements),
      'annual-bulletins': List.of(_annualBulletins),
      'annual-decisions': List.of(_annualDecisions),
      're-enrollment-requests': List.of(_reEnrollmentRequests),
    };
    for (final entry in collections.entries) {
      final current = <String>{};
      for (final item in entry.value) {
        final payload = Map<String, dynamic>.from(item.toJson());
        if (entry.key != 'establishments' &&
            (payload['schoolId'] == null ||
                payload['schoolId'].toString().isEmpty)) {
          payload['schoolId'] = _currentUser?.schoolId;
        }
        final id = payload['id']?.toString();
        if (id == null || id.isEmpty) continue;
        current.add(id);
        try {
          await _repository.create(entry.key, payload);
        } on ApiException {/* retried on next mutation */}
      }
      for (final id in (_remoteIds[entry.key] ?? {}).difference(current)) {
        try {
          await _repository.delete(entry.key, id);
        } on ApiException {/* access or network failure */}
      }
      _remoteIds[entry.key] = current;
    }
  }

  void _createRemote(String kind, Map<String, dynamic> payload) =>
      unawaited(_ignoreRemoteFailure(_repository.create(kind, payload)));
  void _updateRemote(String kind, String id, Map<String, dynamic> payload) =>
      unawaited(_ignoreRemoteFailure(_repository.update(kind, id, payload)));
  void _deleteRemote(String kind, String id) =>
      unawaited(_ignoreRemoteFailure(_repository.delete(kind, id)));

  Future<void> _ignoreRemoteFailure(Future<Object?> operation) async {
    try {
      await operation;
    } on Exception {
      // Local mutations remain cached and the next authenticated sync retries.
    }
  }

  Future<String?> createAccount(
      {required String name,
      required String email,
      required UserRole role,
      required String schoolId,
      String? directionId}) async {
    try {
      final data = await _repository.createUser({
        'name': name,
        'email': email,
        'role': role.value,
        'establishment_id': schoolId,
        if (directionId != null) 'direction_id': directionId,
      });
      _users.add(UserModel.fromJson(data));
      await _saveAllAsync();
      notifyListeners();
      return data['initialPassword'] as String?;
    } on ApiException {
      return null;
    }
  }

  Future<Map<String, dynamic>> getSuperAdminDashboard() =>
      _repository.superAdminDashboard();

  Future<Map<String, dynamic>> getSuperAdminSubscriptions() =>
      _repository.superAdminSubscriptions();

  Future<Map<String, dynamic>> renewSuperAdminSubscription(
          String id, String plan, DateTime startDate) =>
      _repository.renewSuperAdminSubscription(id, {
        'plan': plan,
        'startDate': startDate.toIso8601String().substring(0, 10),
      });

  Future<List<Map<String, dynamic>>> getSuperAdminModuleCatalog() =>
      _repository.superAdminModuleCatalog();

  Future<List<PlanModel>> getSuperAdminPlans() async =>
      (await _repository.superAdminPlans()).map(PlanModel.fromJson).toList();

  Future<PlanModel> getSuperAdminPlan(String id) async =>
      PlanModel.fromJson(await _repository.superAdminPlan(id));

  Future<PlanModel> createSuperAdminPlan(PlanModel plan) async =>
      PlanModel.fromJson(await _repository.createSuperAdminPlan(plan.toJson()));

  Future<PlanModel> updateSuperAdminPlan(PlanModel plan) async =>
      PlanModel.fromJson(
          await _repository.updateSuperAdminPlan(plan.id, plan.toJson()));

  Future<List<EstablishmentModel>> searchSuperAdminEstablishments(
      {String? search, String? status}) async {
    final data = await _repository.superAdminEstablishments(
      search: search,
      status: status,
    );
    return data.map(EstablishmentModel.fromJson).toList();
  }

  Future<EstablishmentModel> getSuperAdminEstablishment(String id) async =>
      EstablishmentModel.fromJson(
          await _repository.superAdminEstablishment(id));

  Future<Map<String, dynamic>> getSuperAdminDirections(
          String establishmentId) =>
      _repository.superAdminDirections(establishmentId);

  Future<Map<String, dynamic>> createSuperAdminDirection(
          String establishmentId, Map<String, dynamic> payload) =>
      _repository.createSuperAdminDirection(establishmentId, payload);

  Future<Map<String, dynamic>> updateSuperAdminDirection(
          String directionId, Map<String, dynamic> payload) =>
      _repository.updateSuperAdminDirection(directionId, payload);

  Future<Map<String, dynamic>> assignDirectionAdministrator(
          String directionId, String? userId) =>
      _repository.assignDirectionAdministrator(directionId, userId);

  Future<Map<String, dynamic>> getSuperAdminEstablishmentModules(String id) =>
      _repository.superAdminEstablishmentModules(id);

  Future<Map<String, dynamic>> updateSuperAdminEstablishmentModules(
          String id, List<String> enabledModules) async =>
      _repository.updateSuperAdminEstablishmentModules(id, enabledModules);

  Future<String> resetAdminPassword(String userId) =>
      _repository.resetAdminPassword(userId);

  Future<List<UserModel>> getSuperAdminUsers({
    String? role,
    String? search,
    String? status,
    String? establishmentId,
  }) async =>
      (await _repository.superAdminUsers(
        role: role,
        search: search,
        status: status,
        establishmentId: establishmentId,
      ))
          .map(UserModel.fromJson)
          .toList();

  Future<UserModel> getSuperAdminUser(String userId) async =>
      UserModel.fromJson(await _repository.superAdminUser(userId));

  Future<UserModel> updateAdminAccountStatus(
          String userId, AccountStatus status) async =>
      UserModel.fromJson(
          await _repository.updateAdminAccountStatus(userId, status.value));

  Future<String> createManagedEstablishment({
    required EstablishmentModel establishment,
    required String adminName,
    required String adminEmail,
    String? adminPhone,
    String? adminDirectionCode,
    bool useBaseConfiguration = true,
    String? initialAcademicYear,
  }) async {
    final response = await _repository.createSuperAdminEstablishment({
      if (establishment.id.isNotEmpty) 'id': establishment.id,
      'name': establishment.name,
      'code': establishment.code,
      'city': establishment.city,
      'country': establishment.country,
      'phone': establishment.phone,
      'email': establishment.email,
      'plan': establishment.plan,
      'admin_name': adminName,
      'admin_email': adminEmail,
      'admin_phone': adminPhone,
      if (adminDirectionCode != null)
        'admin_direction_code': adminDirectionCode,
      'use_base_configuration': useBaseConfiguration,
      if (initialAcademicYear != null)
        'initial_academic_year': initialAcademicYear,
      'cycles': establishment.cycles.map((cycle) => cycle.code).toList(),
    });
    final created = EstablishmentModel.fromJson(
        Map<String, dynamic>.from(response['establishment'] as Map));
    _establishments.insert(0, created);
    final admin = Map<String, dynamic>.from(response['administrator'] as Map);
    _users.add(UserModel.fromJson(admin));
    await _loadRemoteData();
    await _saveAllAsync();
    notifyListeners();
    final password = response['initialPassword'];
    if (password is! String || password.isEmpty) {
      throw ApiException('Réponse de création invalide', 500);
    }
    return password;
  }

  Future<bool> updateManagedEstablishment(
    EstablishmentModel establishment, {
    List<String>? cycleCodes,
    bool rethrowErrors = false,
  }) async {
    try {
      final data =
          await _repository.updateSuperAdminEstablishment(establishment.id, {
        'name': establishment.name,
        if (establishment.code != null && establishment.code!.isNotEmpty)
          'code': establishment.code,
        'city': establishment.city,
        'address': establishment.address,
        'country': establishment.country,
        'phone': establishment.phone,
        'email': establishment.email,
        'status': establishment.status,
        if (cycleCodes != null) 'cycles': cycleCodes,
      });
      final updated = EstablishmentModel.fromJson(data);
      final index =
          _establishments.indexWhere((item) => item.id == establishment.id);
      if (index >= 0) _establishments[index] = updated;
      await _saveAllAsync();
      notifyListeners();
      return true;
    } on Exception {
      if (rethrowErrors) rethrow;
      return false;
    }
  }

  Future<Map<String, dynamic>> getRemoteStatistics(
          {String? schoolId,
          String? academicYearId,
          String? cycle,
          String? levelId,
          String? classId,
          String? periodId,
          String? subjectId}) =>
      _repository.statistics(
          schoolId: schoolId,
          academicYearId: academicYearId,
          cycle: cycle,
          levelId: levelId,
          classId: classId,
          periodId: periodId,
          subjectId: subjectId);

  Future<EstablishmentModel> loadCurrentEstablishment() async {
    final establishment =
        EstablishmentModel.fromJson(await _repository.adminEstablishment());
    final index =
        _establishments.indexWhere((item) => item.id == establishment.id);
    if (index >= 0) {
      _establishments[index] = establishment;
    } else {
      _establishments.add(establishment);
    }
    await _saveAllAsync();
    notifyListeners();
    return establishment;
  }

  Future<EstablishmentModel> updateCurrentEstablishment(
      Map<String, dynamic> changes) async {
    final establishment = EstablishmentModel.fromJson(
        await _repository.updateAdminEstablishment(changes));
    final index =
        _establishments.indexWhere((item) => item.id == establishment.id);
    if (index >= 0) {
      _establishments[index] = establishment;
    } else {
      _establishments.add(establishment);
    }
    await _saveAllAsync();
    notifyListeners();
    return establishment;
  }

  Future<bool> addAssignment(AssignmentModel assignment) async {
    try {
      await _repository.create('assignments', assignment.toJson());
    } on ApiException {
      return false;
    }
    _assignments.add(assignment);
    _saveAll();
    notifyListeners();
    return true;
  }

  Future<void> clearDemoData() async {
    final preservedTheme = _themeMode == ThemeMode.dark ? 'dark' : 'light';
    await _storage.clearAll();

    _currentUser = null;
    _selectedAcademicYearId = null;
    _lockedAnnualBulletins = {};
    _users = [];
    _establishments = [];
    _subscriptions = [];
    _academicYears = [];
    _classes = [];
    _subjects = [];
    _teachers = [];
    _students = [];
    _affectations = [];
    _grades = [];
    _evaluations = [];
    _gradeModificationRequests = [];
    _gradeChangeLogs = [];
    _absences = [];
    _assignments = [];
    _notifications = [];
    _auditLogs = [];
    _announcements = [];
    _conversations = [];
    _documents = [];
    _financeFees = [];
    _financeRegistrations = [];
    _financeFeeAssignments = [];
    _financePayments = [];
    _financeReceipts = [];
    _annualBulletins = [];
    _annualDecisions = [];
    _decisionChangeLogs = [];
    _reEnrollmentRequests = [];
    _schoolCycles = [];
    _schoolLevels = [];
    _series = [];

    await _saveAllAsync();
    await _storage.set('initialized', true);
    await _storage.set('theme', preservedTheme);
    _isLoaded = true;
    notifyListeners();
  }

  Future<void> resetDemoData() async {
    final preservedTheme = _themeMode == ThemeMode.dark ? 'dark' : 'light';
    await _storage.clearAll();

    _currentUser = null;
    _selectedAcademicYearId = null;
    _lockedAnnualBulletins = {};

    _users = List.from(SeedData.users);
    _establishments = List.from(SeedData.establishments);
    _subscriptions = List.from(SeedData.subscriptions);
    _academicYears = List.from(SeedData.academicYears);
    _classes = [];
    _subjects = [];
    _teachers = [];
    _students = List.from(SeedData.students);
    _affectations = [];
    _grades = [];
    _evaluations = [];
    _gradeModificationRequests = [];
    _gradeChangeLogs = [];
    _absences = [];
    _assignments = [];
    _notifications = [];
    _auditLogs = [];
    _announcements = [];
    _conversations = [];
    _documents = [];
    _financeFees = [];
    _financeRegistrations = [];
    _financeFeeAssignments = [];
    _financePayments = [];
    _financeReceipts = [];
    _annualBulletins = [];
    _annualDecisions = [];
    _decisionChangeLogs = [];
    _reEnrollmentRequests = [];
    _schoolCycles = [];
    _schoolLevels = List<SchoolLevelModel>.from(SeedData.schoolLevels);
    _series = List<SeriesModel>.from(SeedData.series);

    await _saveAllAsync();
    await _storage.set('initialized', true);
    await _storage.set('theme', preservedTheme);
    ensureDefaultInstitutionSetup();
    _isLoaded = true;
    notifyListeners();
  }

  void logout() {
    _currentUser = null;
    _loginError = null;
    _sessionWarning = null;
    _api.setToken(null);
    _clearBusinessMemory();
    unawaited(_purgePersistedSessionData());
    notifyListeners();
  }

  void toggleTheme() {
    _themeMode =
        _themeMode == ThemeMode.light ? ThemeMode.dark : ThemeMode.light;
    _storage.set('theme', _themeMode == ThemeMode.dark ? 'dark' : 'light');
    notifyListeners();
  }

  // ---- Multi-tenant & Role Checks ----
  bool isSuperAdmin() => _currentUser?.role == UserRole.superadmin;

  EstablishmentModel? getCurrentSchool() {
    if (_currentUser == null || _currentUser!.schoolId == null) return null;
    return getEstablishmentById(_currentUser!.schoolId!);
  }

  bool isCurrentSchoolSuspended() => getCurrentSchool()?.status == 'suspended';

  SubscriptionModel? getCurrentSchoolSubscription() {
    final school = getCurrentSchool();
    if (school == null) return null;
    final matchIndex =
        _subscriptions.indexWhere((s) => s.client == school.name);
    if (matchIndex == -1) return null;
    final match = _subscriptions[matchIndex];
    return match.copyWith(status: _computeSubscriptionStatus(match));
  }

  EstablishmentModel? getEstablishmentById(String schoolId) {
    return _establishments.firstWhere(
      (e) => e.id == schoolId,
      orElse: () => EstablishmentModel(
        id: schoolId,
        name: 'Établissement Inconnu',
        type: 'École',
        institutionType: InstitutionType.school,
      ),
    );
  }

  bool canModify(dynamic resource) {
    if (_currentUser == null) return false;
    if (isSuperAdmin()) return true;
    final resSchoolId = resource is Map
        ? (resource['schoolId'] ?? resource['institutionId'])
        : (resource?.schoolId ?? resource?.institutionId);
    return resSchoolId != null && _currentUser!.schoolId == resSchoolId;
  }

  // ---- Filtering Getters by Tenant ----
  List<EstablishmentModel> getEstablishments() =>
      List.unmodifiable(_establishments);

  List<AcademicYearModel> getAcademicYears() {
    if (isSuperAdmin() ||
        _currentUser == null ||
        _currentUser?.schoolId == null ||
        _currentUser!.schoolId!.isEmpty)
      return List.unmodifiable(_academicYears);
    final schoolId = _currentUser?.schoolId;
    return _academicYears
        .where((y) => y.schoolId.isEmpty || y.schoolId == schoolId)
        .toList();
  }

  AcademicYearModel? getActiveAcademicYear() {
    final years = getAcademicYears();
    final active = years.where((year) => year.isActive).toList();
    return active.isEmpty ? null : active.first;
  }

  String? getSelectedAcademicYearId() {
    if (_selectedAcademicYearId != null) return _selectedAcademicYearId;
    final active = getActiveAcademicYear();
    return active?.id;
  }

  void setSelectedAcademicYearId(String yearId) {
    if (!getAcademicYears().any((year) => year.id == yearId)) {
      throw ArgumentError.value(yearId, 'yearId', 'Année scolaire inconnue');
    }
    _selectedAcademicYearId = yearId;
    unawaited(_storage.set('selectedAcademicYearId', yearId));
    notifyListeners();
  }

  AcademicYearModel? getSelectedAcademicYear() {
    final selectedId = getSelectedAcademicYearId();
    if (selectedId == null) return null;
    final matches = getAcademicYears().where((year) => year.id == selectedId);
    return matches.isEmpty ? null : matches.first;
  }

  Future<void> refreshAcademicOrganization() async {
    _academicYears = (await _repository.academicYears())
        .map(AcademicYearModel.fromJson)
        .toList();
    _classes =
        (await _repository.schoolClasses()).map(ClassModel.fromJson).toList();
    if (_selectedAcademicYearId == null ||
        !_academicYears.any((year) => year.id == _selectedAcademicYearId)) {
      _selectedAcademicYearId = getActiveAcademicYear()?.id;
    }
    if (_selectedAcademicYearId != null) {
      await _storage.set('selectedAcademicYearId', _selectedAcademicYearId!);
    }
    await _saveAllAsync();
    notifyListeners();
  }

  Future<AcademicYearModel> createAcademicYearRemote({
    required String name,
    required String start,
    required String end,
  }) async {
    final created =
        AcademicYearModel.fromJson(await _repository.createAcademicYear({
      'name': name,
      'start': start,
      'end': end,
    }));
    _academicYears.insert(0, created);
    _selectedAcademicYearId ??= created.id;
    await _storage.set('selectedAcademicYearId', _selectedAcademicYearId!);
    await _saveAllAsync();
    notifyListeners();
    return created;
  }

  Future<AcademicYearModel> updateAcademicYearRemote({
    required String id,
    required String name,
    required String start,
    required String end,
  }) async {
    final updated = AcademicYearModel.fromJson(
      await _repository
          .updateAcademicYear(id, {'name': name, 'start': start, 'end': end}),
    );
    final index = _academicYears.indexWhere((year) => year.id == id);
    if (index >= 0) _academicYears[index] = updated;
    await _saveAllAsync();
    notifyListeners();
    return updated;
  }

  Future<AcademicYearModel> activateAcademicYearRemote(String yearId) async {
    final activated = AcademicYearModel.fromJson(
        await _repository.activateAcademicYear(yearId));
    _academicYears = (await _repository.academicYears())
        .map(AcademicYearModel.fromJson)
        .toList();
    await _saveAllAsync();
    notifyListeners();
    return activated;
  }

  Future<Map<String, dynamic>> copyAcademicYearConfigurationRemote({
    required String targetYearId,
    required String sourceYearId,
  }) async {
    final result = await _repository.copyAcademicYearConfiguration(
        targetYearId, sourceYearId);
    await refreshAcademicOrganization();
    return result;
  }

  Future<void> deleteAcademicYearRemote(String yearId) async {
    await _repository.deleteAcademicYear(yearId);
    _academicYears.removeWhere((year) => year.id == yearId);
    if (_selectedAcademicYearId == yearId) {
      _selectedAcademicYearId = getActiveAcademicYear()?.id;
      if (_selectedAcademicYearId == null) {
        await _storage.remove('selectedAcademicYearId');
      } else {
        await _storage.set('selectedAcademicYearId', _selectedAcademicYearId!);
      }
    }
    await _saveAllAsync();
    notifyListeners();
  }

  List<ClassModel> getClasses() {
    if (isSuperAdmin() ||
        _currentUser == null ||
        _currentUser?.schoolId == null ||
        _currentUser!.schoolId!.isEmpty) return List.unmodifiable(_classes);
    final schoolId = _currentUser?.schoolId;
    return _classes
        .where((c) => c.schoolId.isEmpty || c.schoolId == schoolId)
        .toList();
  }

  List<SchoolCycleModel> getSchoolCycles() {
    if (isSuperAdmin()) return List.unmodifiable(_schoolCycles);
    final schoolId = _currentUser?.schoolId ?? '';
    return _schoolCycles.where((cycle) => cycle.schoolId == schoolId).toList();
  }

  Future<List<Map<String, dynamic>>> getSchoolCycleCatalog() =>
      _repository.schoolCycleCatalog();

  Future<List<SchoolCycleModel>> loadSchoolCycles({String? schoolId}) async {
    final cycles = (await _repository.schoolCycles(schoolId: schoolId))
        .map(SchoolCycleModel.fromJson)
        .toList();
    if (schoolId == null || schoolId == _currentUser?.schoolId) {
      _schoolCycles = cycles;
      await _saveAllAsync();
      notifyListeners();
    }
    return cycles;
  }

  Future<SchoolCycleModel> createSchoolCycle(
      {required String code, String? schoolId}) async {
    final cycle =
        SchoolCycleModel.fromJson(await _repository.createSchoolCycle({
      if (schoolId != null) 'schoolId': schoolId,
      'code': code,
    }));
    _schoolCycles.add(cycle);
    await _saveAllAsync();
    notifyListeners();
    return cycle;
  }

  Future<SchoolCycleModel> updateSchoolCycle(
      String cycleId, Map<String, dynamic> changes) async {
    final cycle = SchoolCycleModel.fromJson(
        await _repository.updateSchoolCycle(cycleId, changes));
    final index = _schoolCycles.indexWhere((item) => item.id == cycle.id);
    if (index >= 0) _schoolCycles[index] = cycle;
    await _saveAllAsync();
    notifyListeners();
    return cycle;
  }

  List<SchoolLevelModel> getSchoolLevels() {
    if (isSuperAdmin())
      return List.unmodifiable(_schoolLevels.cast<SchoolLevelModel>());
    final schoolId = _currentUser?.schoolId ?? '';
    // return levels that are global (schoolId empty) or specific to this school
    return _schoolLevels
        .cast<SchoolLevelModel>()
        .where((l) => l.schoolId.isEmpty || l.schoolId == schoolId)
        .toList();
  }

  List<SchoolLevelModel> getSchoolLevelsByCycle(String cycle) {
    return getSchoolLevels()
        .where((l) => l.cycle.toLowerCase() == cycle.toLowerCase())
        .toList();
  }

  List<SchoolLevelModel> getSchoolLevelsByCycleId(String cycleId) =>
      getSchoolLevels().where((level) => level.cycleId == cycleId).toList();

  Future<List<SchoolLevelModel>> loadStructuredSchoolLevels(
      String cycleId) async {
    final levels = (await _repository.schoolLevels(cycleId))
        .map(SchoolLevelModel.fromJson)
        .toList();
    _schoolLevels.removeWhere((level) => level.cycleId == cycleId);
    _schoolLevels.addAll(levels);
    await _saveAllAsync();
    notifyListeners();
    return levels;
  }

  Future<SchoolLevelModel> createStructuredSchoolLevel(
      String cycleId, Map<String, dynamic> payload) async {
    final level = SchoolLevelModel.fromJson(
        await _repository.createSchoolLevel(cycleId, payload));
    _schoolLevels.add(level);
    await _saveAllAsync();
    notifyListeners();
    return level;
  }

  Future<SchoolLevelModel> updateStructuredSchoolLevel(
      String levelId, Map<String, dynamic> changes) async {
    final level = SchoolLevelModel.fromJson(
        await _repository.updateSchoolLevel(levelId, changes));
    final index = _schoolLevels.indexWhere((item) => item.id == level.id);
    if (index >= 0) _schoolLevels[index] = level;
    await _saveAllAsync();
    notifyListeners();
    return level;
  }

  List<SeriesModel> getSeries() {
    if (isSuperAdmin()) return List.unmodifiable(_series.cast<SeriesModel>());
    final schoolId = _currentUser?.schoolId ?? '';
    return _series
        .cast<SeriesModel>()
        .where((s) => s.schoolId.isEmpty || s.schoolId == schoolId)
        .toList();
  }

  void addSchoolLevel(SchoolLevelModel level) {
    _schoolLevels.add(level);
    _saveAll();
    notifyListeners();
  }

  void addSeries(SeriesModel series) {
    _series.add(series);
    _saveAll();
    notifyListeners();
  }

  List<ClassModel> getClassesByYear(String? yearId) {
    final classes = getClasses();
    if (yearId == null || yearId.isEmpty) return classes;

    return classes.where((c) {
      final classYear = c.academicYearId ?? c.schoolYearId;
      return classYear == yearId;
    }).toList();
  }

  Future<ClassModel> createStructuredClass(ClassModel value) async {
    final created = ClassModel.fromJson(await _repository.createSchoolClass({
      'schoolId': value.schoolId,
      'academicYearId': value.academicYearId,
      'cycleId': value.cycleId,
      'schoolLevelId': value.structuredLevelId ?? value.levelId,
      if (value.seriesId != null) 'seriesId': value.seriesId,
      'name': value.name,
    }));
    _classes.add(created);
    await _saveAllAsync();
    notifyListeners();
    return created;
  }

  Future<ClassModel> updateStructuredClass(ClassModel value) async {
    final updated =
        ClassModel.fromJson(await _repository.updateSchoolClass(value.id, {
      'schoolId': value.schoolId,
      'academicYearId': value.academicYearId,
      'cycleId': value.cycleId,
      'schoolLevelId': value.structuredLevelId ?? value.levelId,
      if (value.seriesId != null) 'seriesId': value.seriesId,
      'name': value.name,
    }));
    final index = _classes.indexWhere((item) => item.id == updated.id);
    if (index >= 0) _classes[index] = updated;
    await _saveAllAsync();
    notifyListeners();
    return updated;
  }

  Future<void> deleteStructuredClass(String classId) async {
    await _repository.deleteSchoolClass(classId);
    _classes.removeWhere((item) => item.id == classId);
    await _saveAllAsync();
    notifyListeners();
  }

  Future<ClassModel> setClassMainTeacherRemote(
      String classId, String teacherId) async {
    final updated = ClassModel.fromJson(
        await _repository.setClassMainTeacher(classId, teacherId));
    final index = _classes.indexWhere((item) => item.id == updated.id);
    if (index >= 0) _classes[index] = updated;
    await _saveAllAsync();
    notifyListeners();
    return updated;
  }

  Future<void> clearClassMainTeacherRemote(String classId) async {
    await _repository.clearClassMainTeacher(classId);
    final index = _classes.indexWhere((item) => item.id == classId);
    if (index >= 0) {
      final current = _classes[index];
      _classes[index] = ClassModel.fromJson({
        ...current.toJson(),
        'mainTeacher': null,
        'mainTeacherId': null,
      });
    }
    await _saveAllAsync();
    notifyListeners();
  }

  Future<Map<String, dynamic>> getSchoolOrganizationSummary() => _repository
      .schoolOrganizationSummary(academicYearId: getSelectedAcademicYearId());

  ClassModel? getClassById(String? classId) {
    if (classId == null || classId.isEmpty) return null;
    final cls = getClasses().firstWhere(
      (c) => c.id == classId,
      orElse: () => ClassModel(id: '', name: '', schoolId: ''),
    );
    return cls.id.isNotEmpty ? cls : null;
  }

  ClassModel? getClassByName(String? className, {String? schoolId}) {
    if (className == null || className.isEmpty) return null;
    final classes = getClasses().where((c) => c.name == className).toList();
    if (schoolId != null && schoolId.isNotEmpty) {
      final bySchool = classes.where((c) => c.schoolId == schoolId).toList();
      if (bySchool.isNotEmpty) return bySchool.last;
    }
    final currentSchool = _currentUser?.schoolId;
    if (currentSchool != null && currentSchool.isNotEmpty) {
      final byCurrentSchool =
          classes.where((c) => c.schoolId == currentSchool).toList();
      if (byCurrentSchool.isNotEmpty) return byCurrentSchool.last;
    }
    if (classes.isNotEmpty) return classes.last;
    return null;
  }

  List<SubjectModel> getSubjects() {
    if (isSuperAdmin() ||
        _currentUser == null ||
        _currentUser?.schoolId == null ||
        _currentUser!.schoolId!.isEmpty) return List.unmodifiable(_subjects);
    final schoolId = _currentUser?.schoolId;
    return _subjects
        .where((s) => s.schoolId.isEmpty || s.schoolId == schoolId)
        .toList();
  }

  List<SubjectModel> getSubjectsByYear(String? yearId) {
    final subjects = getSubjects();
    if (yearId == null || yearId.isEmpty) return subjects;

    final matches = subjects.where((s) => s.academicYearId == yearId).toList();

    if (matches.isNotEmpty) return matches;

    final legacy = subjects.where((s) => s.academicYearId == null).toList();
    if (legacy.isNotEmpty) return legacy;

    return subjects;
  }

  List<StudentModel> getStudents() {
    if (isSuperAdmin() ||
        _currentUser == null ||
        _currentUser?.schoolId == null ||
        _currentUser!.schoolId!.isEmpty) return List.unmodifiable(_students);
    final schoolId = _currentUser?.schoolId;
    return _students
        .where((s) => s.schoolId.isEmpty || s.schoolId == schoolId)
        .toList();
  }

  List<StudentModel> getStudentsByYear(String? yearId) {
    final students = getStudents();
    if (yearId == null) return students;
    return students.where((s) => s.academicYearId == yearId).toList();
  }

  Future<void> refreshStudentsRemote({
    String? academicYearId,
    String? cycleId,
    String? levelId,
    String? classId,
    String? search,
  }) async {
    _students = (await _repository.students(
            academicYearId: academicYearId ?? getSelectedAcademicYearId(),
            cycleId: cycleId,
            levelId: levelId,
            classId: classId,
            search: search))
        .map(StudentModel.fromJson)
        .toList();
    await _saveAllAsync();
    notifyListeners();
  }

  Future<Map<String, dynamic>> reEnrollmentCandidatesRemote({
    required String targetAcademicYearId,
    String? classId,
    String? lastName,
    String? firstName,
    String? matricule,
  }) =>
      _repository.reEnrollmentCandidates(
        targetAcademicYearId: targetAcademicYearId,
        classId: classId,
        lastName: lastName,
        firstName: firstName,
        matricule: matricule,
      );

  Future<StudentModel> studentDetailsRemote(String studentId,
          {String? academicYearId}) async =>
      StudentModel.fromJson(await _repository.studentDetails(studentId,
          academicYearId: academicYearId));

  Future<StudentModel> createStudentRemote(Map<String, dynamic> identity,
      {String? classId,
      String schoolRegime = 'normal',
      bool hasTd = false,
      Map<String, dynamic> registrationOptions = const {}}) async {
    final created =
        StudentModel.fromJson(await _repository.createStudent(identity));
    StudentModel result = created;
    if (classId != null && classId.isNotEmpty) {
      await _repository.createStudentRegistration(created.id, classId,
          schoolRegime: schoolRegime,
          hasTd: hasTd,
          options: registrationOptions);
      final refreshed = await _repository.students(
          academicYearId: getSelectedAcademicYearId());
      _students = refreshed.map(StudentModel.fromJson).toList();
      result = _students.firstWhere((item) => item.id == created.id);
    } else {
      _students.add(created);
    }
    await _saveAllAsync();
    notifyListeners();
    return result;
  }

  Future<StudentModel> updateStudentRemote(
      String studentId, Map<String, dynamic> identity) async {
    final updated = StudentModel.fromJson(
        await _repository.updateStudent(studentId, identity));
    final index = _students.indexWhere((item) => item.id == studentId);
    if (index >= 0) _students[index] = updated;
    await _saveAllAsync();
    notifyListeners();
    return updated;
  }

  Future<Map<String, dynamic>> importStudentPhotosRemote({
    required String academicYearId,
    required String cycleId,
    required List<Map<String, dynamic>> files,
  }) =>
      _repository.importStudentPhotos({
        'academicYearId': academicYearId,
        'cycleId': cycleId,
        'files': files,
      });

  Future<void> updateStudentPhotoRemote(
        String studentId, Map<String, dynamic> file) async {
      await _repository.updateStudentPhoto(studentId, file);
      _studentPhotoRevisions[studentId] = studentPhotoRevision(studentId) + 1;
      notifyListeners();
    }

  Future<Uint8List?> studentPhotoRemote(String studentId) async {
    try {
      return await _repository.studentPhoto(studentId);
    } on ApiException catch (error) {
      if (error.statusCode == 404) return null;
      rethrow;
    }
  }

  Future<Map<String, String>> provisionStudentAccess(String studentId) async {
    final response = await _repository.provisionStudentAccess(studentId);
    final rawStudent = response['student'];
    final temporaryPassword = response['temporaryPassword'];
    final matricule = response['matricule'];
    if (rawStudent is! Map ||
        temporaryPassword is! String ||
        temporaryPassword.isEmpty ||
        matricule is! String ||
        matricule.isEmpty) {
      throw ApiException('Réponse de création d’accès invalide.', 500);
    }
    final updated =
        StudentModel.fromJson(Map<String, dynamic>.from(rawStudent));
    final index = _students.indexWhere((item) => item.id == studentId);
    if (index >= 0) _students[index] = updated;
    await _saveAllAsync();
    notifyListeners();
    return {'matricule': matricule, 'temporaryPassword': temporaryPassword};
  }

  Future<void> archiveStudentRemote(String studentId) async {
    await _repository.archiveStudent(studentId);
    _students.removeWhere((item) => item.id == studentId);
    await _saveAllAsync();
    notifyListeners();
  }

  Future<List<StudentRegistrationModel>> studentRegistrationHistoryRemote(
          String studentId) async =>
      (await _repository.studentRegistrations(studentId))
          .map(StudentRegistrationModel.fromJson)
          .toList();

  Future<void> changeStudentClassRemote(String studentId, String classId,
      {String schoolRegime = 'normal',
      bool hasTd = false,
      Map<String, dynamic> registrationOptions = const {}}) async {
    final history = await _repository.studentRegistrations(studentId);
    final selectedYearId = getSelectedAcademicYearId();
    final current = history
        .where((item) => item['academicYearId']?.toString() == selectedYearId);
    if (current.isEmpty) {
      await _repository.createStudentRegistration(studentId, classId,
          schoolRegime: schoolRegime,
          hasTd: hasTd,
          options: registrationOptions);
    } else {
      await _repository.updateStudentRegistration(
          current.first['id'].toString(), classId);
    }
    await refreshStudentsRemote(academicYearId: selectedYearId);
  }

  Future<void> createGuardianAndLinkRemote({
    required String studentId,
    required String firstName,
    required String lastName,
    String? phone,
    String? secondPhone,
    String? email,
    required String address,
    required String profession,
    required String relationship,
    bool isPrimary = true,
  }) async {
    String normalizePhone(String value) =>
        value.replaceAll(RegExp(r'[^0-9+]'), '');
    Map<String, dynamic>? guardian;
    if (phone != null && phone.isNotEmpty) {
      final normalizedPhone = normalizePhone(phone);
      final matches = await _repository.guardians(search: phone);
      final exact = matches.where((item) {
        final candidate = item['phone']?.toString() ?? '';
        return candidate.isNotEmpty &&
            normalizePhone(candidate) == normalizedPhone;
      }).toList();
      if (exact.isNotEmpty) guardian = exact.first;
    }
    guardian ??= await _repository.createGuardian({
      'firstName': firstName,
      'lastName': lastName,
      if (phone != null && phone.isNotEmpty) 'phone': phone,
      if (secondPhone != null && secondPhone.isNotEmpty)
        'secondPhone': secondPhone,
      if (email != null && email.isNotEmpty) 'email': email,
      'address': address,
      'profession': profession,
    });
    await _repository.linkStudentGuardian(
        studentId, guardian['id'].toString(), relationship, isPrimary);
    await refreshStudentsRemote();
  }

  Future<void> updateGuardianRemote(
      String guardianId, Map<String, dynamic> payload) async {
    await _repository.updateGuardian(guardianId, payload);
    await refreshStudentsRemote(academicYearId: getSelectedAcademicYearId());
  }

  Future<Map<String, String>> provisionParentAccess(String guardianId) async {
    final response = await _repository.provisionParentAccess(guardianId);
    final email = response['email'];
    final temporaryPassword = response['temporaryPassword'];
    if (email is! String ||
        email.isEmpty ||
        temporaryPassword is! String ||
        temporaryPassword.isEmpty) {
      throw ApiException('Réponse de création d’accès parent invalide.', 500);
    }
    await refreshStudentsRemote(academicYearId: getSelectedAcademicYearId());
    return {'email': email, 'temporaryPassword': temporaryPassword};
  }

  Future<void> refreshTeachersRemote({String? search, String? status}) async {
    _teachers = (await _repository.teachers(search: search, status: status))
        .map(TeacherModel.fromJson)
        .toList();
    await _saveAllAsync();
    notifyListeners();
  }

  Future<String> provisionTeacherAccess(String teacherId) async {
    final response = await _repository.provisionTeacherAccess(teacherId);
    final rawTeacher = response['teacher'];
    final temporaryPassword = response['temporaryPassword'];
    if (rawTeacher is! Map ||
        temporaryPassword is! String ||
        temporaryPassword.isEmpty) {
      throw ApiException('Réponse de création d’accès invalide', 500);
    }
    final updated =
        TeacherModel.fromJson(Map<String, dynamic>.from(rawTeacher));
    final index = _teachers.indexWhere((item) => item.id == updated.id);
    if (index >= 0) _teachers[index] = updated;
    await _saveAllAsync();
    notifyListeners();
    return temporaryPassword;
  }

  Future<TeacherModel> updateTeacherEmailRemote(
      String teacherId, String email) async {
    final updated = TeacherModel.fromJson(
        await _repository.updateTeacher(teacherId, {'email': email.trim()}));
    final index = _teachers.indexWhere((item) => item.id == teacherId);
    if (index >= 0) _teachers[index] = updated;
    await _saveAllAsync();
    notifyListeners();
    return updated;
  }

  Future<TeacherModel> createTeacherRemote(TeacherModel teacher) async {
    final created = TeacherModel.fromJson(await _repository.createTeacher({
      'firstName': teacher.firstName,
      'lastName': teacher.lastName,
      if (teacher.email != null && teacher.email!.isNotEmpty)
        'email': teacher.email,
      if (teacher.phone != null && teacher.phone!.isNotEmpty)
        'phone': teacher.phone,
      if (teacher.subject != null && teacher.subject!.isNotEmpty)
        'specialization': teacher.subject,
      if (teacher.sex != null && teacher.sex!.isNotEmpty) 'gender': teacher.sex,
      if (teacher.birthDate != null && teacher.birthDate!.isNotEmpty)
        'birthDate': teacher.birthDate,
      if (teacher.address != null && teacher.address!.isNotEmpty)
        'address': teacher.address,
      if (teacher.diploma != null && teacher.diploma!.isNotEmpty)
        'diploma': teacher.diploma,
      if (teacher.hireDate != null && teacher.hireDate!.isNotEmpty)
        'hireDate': teacher.hireDate,
    }));
    _teachers.add(created);
    await _saveAllAsync();
    notifyListeners();
    return created;
  }

  Future<TeacherModel> updateTeacherRemote(TeacherModel teacher) async {
    final updated =
        TeacherModel.fromJson(await _repository.updateTeacher(teacher.id, {
      'firstName': teacher.firstName,
      'lastName': teacher.lastName,
      'email': teacher.email,
      'phone': teacher.phone,
      'specialization': teacher.subject,
      'gender': teacher.sex,
      'birthDate': teacher.birthDate,
      'address': teacher.address,
      'diploma': teacher.diploma,
      'hireDate': teacher.hireDate,
      'status': teacher.status,
      if (teacher.employeeNumber != null)
        'employeeNumber': teacher.employeeNumber,
    }));
    final index = _teachers.indexWhere((item) => item.id == teacher.id);
    if (index >= 0) _teachers[index] = updated;
    await _saveAllAsync();
    notifyListeners();
    return updated;
  }

  Future<void> archiveTeacherRemote(String teacherId) async {
    await _repository.archiveTeacher(teacherId);
    _teachers.removeWhere((item) => item.id == teacherId);
    await _saveAllAsync();
    notifyListeners();
  }

  Future<void> refreshSubjectsRemote() async {
    _subjects =
        (await _repository.subjects()).map(SubjectModel.fromJson).toList();
    await _saveAllAsync();
    notifyListeners();
  }

  Future<SubjectModel> createSubjectRemote(SubjectModel subject) async {
    final created = SubjectModel.fromJson(await _repository.createSubject({
      'name': subject.name,
    }));
    _subjects.add(created);
    await _saveAllAsync();
    notifyListeners();
    return created;
  }

  Future<SubjectModel> updateSubjectRemote(SubjectModel subject) async {
    final updated =
        SubjectModel.fromJson(await _repository.updateSubject(subject.id, {
      'name': subject.name,
      'status': subject.status,
    }));
    final index = _subjects.indexWhere((item) => item.id == subject.id);
    if (index >= 0) _subjects[index] = updated;
    await _saveAllAsync();
    notifyListeners();
    return updated;
  }

  Future<SubjectModel> updateSubjectStatusRemote(
      String subjectId, String status) async {
    final updated = SubjectModel.fromJson(
        await _repository.updateSubject(subjectId, {'status': status}));
    final index = _subjects.indexWhere((item) => item.id == subjectId);
    if (index >= 0) _subjects[index] = updated;
    await _saveAllAsync();
    notifyListeners();
    return updated;
  }

  Future<void> archiveSubjectRemote(String subjectId) async {
    await _repository.archiveSubject(subjectId);
    _subjects.removeWhere((item) => item.id == subjectId);
    await _saveAllAsync();
    notifyListeners();
  }

  Future<SubjectModel> saveSubjectLevelSettingRemote(
      String subjectId, Map<String, dynamic> payload) async {
    final updated = SubjectModel.fromJson(
        await _repository.updateSubjectLevelSetting(subjectId, payload));
    final index = _subjects.indexWhere((item) => item.id == subjectId);
    if (index >= 0) {
      _subjects[index] = updated;
    } else {
      _subjects.add(updated);
    }
    await _saveAllAsync();
    notifyListeners();
    return updated;
  }

  Future<void> refreshAffectationsRemote({String? academicYearId}) async {
    _affectations =
        (await _repository.affectations(academicYearId: academicYearId))
            .map(AffectationModel.fromJson)
            .toList();
    await _saveAllAsync();
    notifyListeners();
  }

  Future<AffectationModel> createAffectationRemote(
      AffectationModel affectation) async {
    final created =
        AffectationModel.fromJson(await _repository.createAffectation({
      'teacherId': affectation.teacherId,
      'classId': affectation.classId,
      'subjectId': affectation.subjectId,
    }));
    _affectations.add(created);
    await _saveAllAsync();
    notifyListeners();
    return created;
  }

  Future<AffectationModel> updateAffectationRemote(
      AffectationModel affectation) async {
    final updated = AffectationModel.fromJson(
        await _repository.updateAffectation(affectation.id, {
      'teacherId': affectation.teacherId,
      'classId': affectation.classId,
      'subjectId': affectation.subjectId,
    }));
    final index = _affectations.indexWhere((item) => item.id == affectation.id);
    if (index >= 0) _affectations[index] = updated;
    await _saveAllAsync();
    notifyListeners();
    return updated;
  }

  Future<void> archiveAffectationRemote(String affectationId) async {
    await _repository.archiveAffectation(affectationId);
    _affectations.removeWhere((item) => item.id == affectationId);
    await _saveAllAsync();
    notifyListeners();
  }

  Future<List<Map<String, dynamic>>> academicPeriodsRemote(
          String academicYearId) =>
      _repository.academicPeriods(academicYearId);

  Future<Map<String, dynamic>> createAcademicPeriodRemote(
          Map<String, dynamic> payload) =>
      _repository.createAcademicPeriod(payload);

  Future<Map<String, dynamic>> updateAcademicPeriodRemote(
          String id, Map<String, dynamic> payload) =>
      _repository.updateAcademicPeriod(id, payload);

  Future<void> archiveAcademicPeriodRemote(String id) =>
      _repository.archiveAcademicPeriod(id);

  Future<void> refreshEvaluationsRemote({
    String? academicYearId,
    String? classId,
    String? subjectId,
    String? periodId,
  }) async {
    _evaluations = (await _repository.evaluations(
      academicYearId: academicYearId,
      classId: classId,
      subjectId: subjectId,
      periodId: periodId,
    ))
        .map(EvaluationModel.fromJson)
        .toList();
    final evaluationIds = _evaluations.map((item) => item.id).toSet();
    try {
      _grades = (await _repository.grades(
        academicYearId: academicYearId,
        classId: classId,
      ))
          .map(GradeModel.fromJson)
          .where((item) => evaluationIds.contains(item.evaluationId))
          .toList();
    } on ApiException catch (error) {
      if (error.statusCode != 404) rethrow;
      _grades = [];
      for (final evaluation in _evaluations) {
        _grades.addAll((await _repository.evaluationGrades(evaluation.id))
            .map(GradeModel.fromJson));
      }
    }
    await _saveAllAsync();
    notifyListeners();
  }

  Future<EvaluationModel> createEvaluationRemote(
      EvaluationModel evaluation) async {
    final created =
        EvaluationModel.fromJson(await _repository.createEvaluation({
      'title': evaluation.title,
      'type': evaluation.type,
      if (evaluation.examCode != null) 'examCode': evaluation.examCode,
      'classId': evaluation.classId,
      'subjectId': evaluation.subjectId,
      'periodId': evaluation.periodId,
      'date': evaluation.date,
      'maxScore': evaluation.maxScore,
    }));
    _evaluations.add(created);
    await _saveAllAsync();
    notifyListeners();
    return created;
  }

  Future<List<EvaluationModel>> createEvaluationProgramRemote(
      Map<String, dynamic> payload) async {
    final response = await _repository.createEvaluationProgram(payload);
    final created = List<Map<String, dynamic>>.from(
            (response['evaluations'] as List? ?? const [])
                .map((item) => Map<String, dynamic>.from(item)))
        .map(EvaluationModel.fromJson)
        .toList();
    _evaluations.addAll(created);
    await _saveAllAsync();
    notifyListeners();
    return created;
  }

  Future<EvaluationModel> changeEvaluationStatusRemote(
      String evaluationId, String status,
      {String? reason}) async {
    final updated = EvaluationModel.fromJson(await _repository
        .updateEvaluationStatus(evaluationId, status, reason: reason));
    final index = _evaluations.indexWhere((item) => item.id == evaluationId);
    if (index >= 0) _evaluations[index] = updated;
    await _saveAllAsync();
    notifyListeners();
    return updated;
  }

  Future<List<GradeModel>> saveEvaluationGradesRemote(
      String evaluationId, List<GradeModel> grades,
      {String? correctionReason}) async {
    final saved = (await _repository.saveEvaluationGrades(
            evaluationId,
            grades
                .map((grade) => {
                      'studentId': grade.studentId,
                      'value': grade.grade,
                      'presence': grade.presence ??
                          (grade.grade == null ? 'not_recorded' : 'present'),
                      if (grade.comment != null) 'comment': grade.comment,
                    })
                .toList(),
            correctionReason: correctionReason))
        .map(GradeModel.fromJson)
        .toList();
    _grades.removeWhere((item) => item.evaluationId == evaluationId);
    _grades.addAll(saved);
    await _saveAllAsync();
    notifyListeners();
    return saved;
  }

  Future<Map<String, dynamic>> schoolResultsRemote(
          String classId, String periodId,
          {String? eventCode}) =>
      _repository.schoolResults(classId, periodId, eventCode: eventCode);

  Future<Map<String, dynamic>> calculateSchoolResultsRemote(
          String classId, String periodId, {String? eventCode}) =>
      _repository.calculateSchoolResults(classId, periodId,
          eventCode: eventCode);

  Future<Map<String, dynamic>> submissionStatusRemote(
          String classId, String periodId,
          {String? eventCode}) =>
      _repository.submissionStatus(classId, periodId, eventCode: eventCode);

  Future<Map<String, dynamic>> studentBulletinRemote(
          String studentId, String academicYearId) =>
      _repository.studentBulletin(studentId, academicYearId);

  Future<List<AbsenceModel>> attendanceRemote(String classId,
      {String? date, String? scheduleId}) async {
    final records = (await _repository.attendance(classId,
            date: date, scheduleId: scheduleId))
        .map(AbsenceModel.fromJson)
        .toList();
    if (scheduleId == null) {
      _absences.removeWhere((item) =>
          item.classId == classId && (date == null || item.date == date));
    } else {
      _absences.removeWhere((item) =>
          item.classId == classId &&
          item.date == date &&
          item.scheduleId == scheduleId);
    }
    _absences.addAll(records);
    await _saveAllAsync();
    notifyListeners();
    return records;
  }

  Future<List<AbsenceModel>> saveAttendanceRemote({
    required String classId,
    required String scheduleId,
    required String date,
    required List<Map<String, dynamic>> entries,
    String action = 'draft',
  }) async {
    final records = (await _repository.saveAttendance({
      'classId': classId,
      'scheduleId': scheduleId,
      'date': date,
      'entries': entries,
      'action': action,
    }))
        .map(AbsenceModel.fromJson)
        .toList();
    _absences.removeWhere((item) =>
        item.classId == classId &&
        item.date == date &&
        item.scheduleId == scheduleId);
    _absences.addAll(records);
    await _saveAllAsync();
    notifyListeners();
    return records;
  }

  Future<AttendanceSheetModel> attendanceSheetRemote(
          String classId, String scheduleId, String date) async =>
      AttendanceSheetModel(
          await _repository.attendanceSheet(classId, scheduleId, date));

  Future<Map<String, dynamic>> attendanceReportRemote(
          Map<String, String> filters) =>
      _repository.attendanceReport(filters);

  Future<List<Map<String, dynamic>>> attendanceContextsRemote() =>
      _repository.attendanceContexts();

  Future<List<BehaviorAssessmentModel>> behaviorEventsRemote({
    String? classId,
    String? studentId,
    String? academicYearId,
    String? periodId,
  }) async {
    final items = (await _repository.behaviorEvents(
      classId: classId,
      studentId: studentId,
      academicYearId: academicYearId,
      periodId: periodId,
    ))
        .map(BehaviorAssessmentModel.fromJson)
        .toList();
    _behaviorAssessments.removeWhere((item) =>
        (currentUser?.role != UserRole.teacher ||
            item.teacherId == getCurrentTeacherId()) &&
        (classId == null || item.classId == classId) &&
        (studentId == null || item.studentId == studentId) &&
        (academicYearId == null || item.academicYearId == academicYearId) &&
        (periodId == null || item.periodId == periodId));
    _behaviorAssessments.addAll(items);
    await _saveAllAsync();
    notifyListeners();
    return items;
  }

  Future<BehaviorAssessmentModel> createBehaviorEventRemote(
      Map<String, dynamic> payload) async {
    final event = BehaviorAssessmentModel.fromJson(
        await _repository.createBehaviorEvent(payload));
    _behaviorAssessments.add(event);
    await _saveAllAsync();
    notifyListeners();
    return event;
  }

  Future<List<BehaviorAssessmentModel>> submitBehaviorRemote({
    required String classId,
    required String periodId,
    required List<Map<String, dynamic>> entries,
    String action = 'submit',
  }) async {
    final saved = (await _repository.submitBehavior({
      'classId': classId,
      'periodId': periodId,
      'entries': entries,
      'action': action,
    }))
        .map(BehaviorAssessmentModel.fromJson)
        .toList();
    final savedKeys = saved.map((item) => item.contextKey).toSet();
    _behaviorAssessments
        .removeWhere((item) => savedKeys.contains(item.contextKey));
    _behaviorAssessments.addAll(saved);
    await _saveAllAsync();
    notifyListeners();
    return saved;
  }

  Future<Map<String, dynamic>> behaviorResultsRemote(
          String classId, String periodId) =>
      _repository.behaviorResults(classId, periodId);

  Future<List<Map<String, dynamic>>> behaviorContextsRemote() =>
      _repository.behaviorContexts();

  Future<Map<String, dynamic>> calculateBehaviorRemote(
          String classId, String periodId) =>
      _repository.calculateBehavior(classId, periodId);

  Future<List<AssignmentModel>> assignmentsRemote({
    String? academicYearId,
    String? classId,
  }) async {
    final items = (await _repository.assignments(
      academicYearId: academicYearId,
      classId: classId,
    ))
        .map(AssignmentModel.fromJson)
        .toList();
    _assignments = items;
    await _saveAllAsync();
    notifyListeners();
    return items;
  }

  Future<AssignmentModel> createAssignmentRemote(
      Map<String, dynamic> payload) async {
    final item =
        AssignmentModel.fromJson(await _repository.createAssignment(payload));
    _assignments.add(item);
    await _saveAllAsync();
    notifyListeners();
    return item;
  }

  Future<void> archiveAssignmentRemote(String assignmentId) async {
    await _repository.archiveAssignment(assignmentId);
    _assignments.removeWhere((item) => item.id == assignmentId);
    await _saveAllAsync();
    notifyListeners();
  }

  Future<List<Map<String, dynamic>>> scheduleRemote(String academicYearId,
          {String? classId}) =>
      _repository.schedule(academicYearId, classId: classId);

  Future<Map<String, dynamic>> createScheduleEntryRemote(
          Map<String, dynamic> payload) =>
      _repository.createScheduleEntry(payload);

  Future<Map<String, dynamic>> updateScheduleEntryRemote(
          String id, Map<String, dynamic> payload) =>
      _repository.updateScheduleEntry(id, payload);

  Future<void> archiveScheduleEntryRemote(String id) =>
      _repository.archiveScheduleEntry(id);

  Future<List<Map<String, dynamic>>> schoolSeriesRemote({String? cycleId}) =>
      _repository.schoolSeries(cycleId: cycleId);

  Future<Map<String, dynamic>> createSchoolSeriesRemote(
          Map<String, dynamic> payload) =>
      _repository.createSchoolSeries(payload);

  Future<Map<String, dynamic>?> calendarSettingsRemote(String academicYearId) =>
      _repository.calendarSettings(academicYearId);

  Future<Map<String, dynamic>> saveCalendarSettingsRemote(
          Map<String, dynamic> payload) =>
      _repository.saveCalendarSettings(payload);

  Future<List<Map<String, dynamic>>> calendarEventsRemote(
          String academicYearId) =>
      _repository.calendarEvents(academicYearId);

  Future<Map<String, dynamic>> createCalendarEventRemote(
          Map<String, dynamic> payload) =>
      _repository.createCalendarEvent(payload);

  Future<Map<String, dynamic>> updateCalendarEventRemote(
          String id, Map<String, dynamic> payload) =>
      _repository.updateCalendarEvent(id, payload);

  Future<void> archiveCalendarEventRemote(String id) =>
      _repository.archiveCalendarEvent(id);

  Future<List<Map<String, dynamic>>> evaluationRulesRemote(
          String academicYearId) =>
      _repository.evaluationRules(academicYearId);

  Future<Map<String, dynamic>> createEvaluationRuleRemote(
          Map<String, dynamic> payload) =>
      _repository.createEvaluationRule(payload);

  Future<Map<String, dynamic>> updateEvaluationRuleRemote(
          String id, Map<String, dynamic> payload) =>
      _repository.updateEvaluationRule(id, payload);

  Future<void> archiveEvaluationRuleRemote(String id) =>
      _repository.archiveEvaluationRule(id);

  Future<Map<String, dynamic>> saveAnnualDecisionRemote(
          String studentId, Map<String, dynamic> payload) =>
      _repository.saveAnnualDecision(studentId, payload);

  Future<List<Map<String, dynamic>>> annualDecisionsRemote(
          String academicYearId) =>
      _repository.annualDecisions(academicYearId);

  Future<Map<String, dynamic>> attendanceStatisticsRemote(String classId,
          {String? periodId, int? month}) =>
      _repository.attendanceStatistics(classId,
          periodId: periodId, month: month);

  Future<Map<String, dynamic>> studentResultsRemote(
          String studentId, String academicYearId) =>
      _repository.studentResults(studentId, academicYearId);

  Future<Map<String, dynamic>> myStudentResultsRemote() =>
      _repository.myStudentResults();

  Future<Map<String, dynamic>> documentOverviewRemote(
          {String? academicYearId}) =>
      _repository.documentOverview(academicYearId: academicYearId);

  Future<Map<String, dynamic>> documentHistoryPageRemote(
          Map<String, String> query) =>
      _repository.documentHistoryPage(query);

  Future<List<Map<String, dynamic>>> myChildrenForResultsRemote() =>
      _repository.myChildrenForResults();

  Future<List<Map<String, dynamic>>> parentDashboardChildrenRemote() async {
    final workspace = await _repository.parentWorkspace();
    final students = (workspace['students'] as List? ?? const [])
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
    final registrations = (workspace['registrations'] as List? ?? const [])
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
    final years = {
      for (final item in (workspace['academicYears'] as List? ?? const []))
        '${(item as Map)['id']}': Map<String, dynamic>.from(item),
    };
    return students.map((student) {
      final studentYears = registrations
          .where((registration) =>
              '${registration['studentId']}' == '${student['id']}')
          .map((registration) {
        final year = years['${registration['academicYearId']}'];
        return <String, dynamic>{
          'id': registration['academicYearId'],
          'name': year?['name'],
          'className': registration['className'],
        };
      }).toList();
      return <String, dynamic>{
        'id': student['id'],
        'fullName': student['fullName'] ??
            '${student['lastName'] ?? ''} ${student['firstName'] ?? ''}'.trim(),
        'years': studentYears,
      };
    }).toList();
  }

  Future<Map<String, dynamic>> myStudentTrackingRemote(String academicYearId) =>
      _repository.myStudentTracking(academicYearId);

  Future<Map<String, dynamic>> myChildTrackingRemote(
          String studentId, String academicYearId) =>
      _repository.myChildTracking(studentId, academicYearId);

  Future<List<Map<String, dynamic>>> studentRegimeHistoryRemote(
          String studentId, String academicYearId) =>
      _repository.studentRegimeHistory(studentId, academicYearId);

  Future<Map<String, dynamic>> changeStudentRegimeRemote({
    required String studentId,
    required String academicYearId,
    required String schoolRegime,
    required String effectiveFrom,
  }) =>
      _repository.changeStudentRegime(
        studentId,
        {
          'academicYearId': academicYearId,
          'schoolRegime': schoolRegime,
          'effectiveFrom': effectiveFrom,
        },
      );

  Future<Map<String, dynamic>> parentFinancialSituationRemote(
          String studentId, String academicYearId) =>
      _repository.parentFinancialSituation(studentId, academicYearId);

  Future<List<Map<String, dynamic>>> preEnrollmentsRemote(
          {String? academicYearId, String? status}) =>
      _repository.preEnrollments(
          academicYearId: academicYearId ?? getSelectedAcademicYearId(),
          status: status);

  Future<Map<String, dynamic>> createPreEnrollmentRemote({
    String? studentId,
    String? firstName,
    String? lastName,
    required String academicYearId,
    required String desiredClassId,
    String registrationKind = 'registration',
    String? schoolRegime,
    bool submit = true,
  }) =>
      _repository.createPreEnrollment({
        if (studentId != null) 'studentId': studentId,
        if (firstName != null) 'firstName': firstName,
        if (lastName != null) 'lastName': lastName,
        'academicYearId': academicYearId,
        'desiredClassId': desiredClassId,
        'registrationKind': registrationKind,
        if (schoolRegime != null) 'schoolRegime': schoolRegime,
        'status': submit ? 'submitted' : 'draft',
      });

  Future<Map<String, dynamic>> updatePreEnrollmentRemote(
          String id, Map<String, dynamic> payload) =>
      _repository.updatePreEnrollment(id, payload);

  Future<Map<String, dynamic>> approvePreEnrollmentRemote(String id,
          {String? classId,
          String schoolRegime = 'normal',
          bool hasTd = false,
          Map<String, dynamic> options = const {}}) =>
      _repository.approvePreEnrollment(
        id,
        classId: classId,
        schoolRegime: schoolRegime,
        hasTd: hasTd,
        options: options,
      );

  Future<Map<String, dynamic>> rejectPreEnrollmentRemote(
          String id, String note) =>
      _repository.updatePreEnrollmentStatus(id, 'rejected', decisionNote: note);

  List<TeacherModel> getTeachers() {
    if (isSuperAdmin()) return List.unmodifiable(_teachers);
    final schoolId = _currentUser?.schoolId;
    return _teachers.where((t) => t.schoolId == schoolId).toList();
  }

  List<AffectationModel> getAffectations() {
    if (isSuperAdmin()) return List.unmodifiable(_affectations);
    final schoolId = _currentUser?.schoolId;
    return _affectations.where((a) => a.schoolId == schoolId).toList();
  }

  /// Vérifie si un enseignant est affecté à la classe et/ou à la matière.
  /// Si subjectId est null on vérifie seulement la classe. Si classId est null on vérifie seulement la matière.
  bool isTeacherAssignedTo(
      {required String teacherId,
      String? classId,
      String? subjectId,
      String? academicYearId}) {
    if (teacherId.isEmpty) return false;
    final affects =
        _affectations.where((a) => a.teacherId == teacherId).toList();
    if (academicYearId != null && academicYearId.isNotEmpty) {
      // filter by academic year when provided
      final filtered = affects
          .where((a) =>
              a.academicYearId == null || a.academicYearId == academicYearId)
          .toList();
      if (filtered.isEmpty) return false;
      if (classId != null && subjectId != null) {
        return filtered.any((a) =>
            (a.classId != null && a.classId == classId) &&
            (a.subjectId != null && a.subjectId == subjectId));
      }
      if (classId != null)
        return filtered.any((a) => a.classId != null && a.classId == classId);
      if (subjectId != null)
        return filtered
            .any((a) => a.subjectId != null && a.subjectId == subjectId);
      return filtered.isNotEmpty;
    }
    if (classId != null && subjectId != null) {
      return affects.any((a) =>
          (a.classId != null && a.classId == classId) &&
          (a.subjectId != null && a.subjectId == subjectId));
    }
    if (classId != null)
      return affects.any((a) => a.classId != null && a.classId == classId);
    if (subjectId != null)
      return affects
          .any((a) => a.subjectId != null && a.subjectId == subjectId);
    return affects.isNotEmpty;
  }

  // ---- Evaluations CRUD ----
  List<EvaluationModel> getEvaluations() {
    if (isSuperAdmin() ||
        _currentUser == null ||
        _currentUser?.schoolId == null ||
        _currentUser!.schoolId!.isEmpty) {
      return List.unmodifiable(_evaluations);
    }
    final schoolId = _currentUser?.schoolId;
    return _evaluations
        .where((e) => e.schoolId.isEmpty || e.schoolId == schoolId)
        .toList();
  }

  EvaluationModel? getEvaluationById(String? id) {
    if (id == null || id.isEmpty) return null;
    final ev = _evaluations.firstWhere(
      (e) => e.id == id,
      orElse: () => EvaluationModel(
        id: '',
        title: '',
        type: 'devoir',
        academicYearId: '',
        classId: '',
        subjectId: '',
        createdBy: '',
        createdAt: '',
        schoolId: '',
      ),
    );
    return ev.id.isNotEmpty ? ev : null;
  }

  List<EvaluationModel> getEvaluationsByClass(String? classId) {
    if (classId == null || classId.isEmpty) return [];
    return getEvaluations().where((e) => e.classId == classId).toList();
  }

  List<EvaluationModel> getEvaluationsBySubject(String? subjectId) {
    if (subjectId == null || subjectId.isEmpty) return [];
    return getEvaluations().where((e) => e.subjectId == subjectId).toList();
  }

  List<EvaluationModel> getEvaluationsByPeriod(String? periodId) {
    if (periodId == null || periodId.isEmpty) return [];
    return getEvaluations().where((e) => e.periodId == periodId).toList();
  }

  String addEvaluation(EvaluationModel evaluation) {
    // Basic validations
    final schoolId = _currentUser?.schoolId ?? '';
    if (_currentUser != null &&
        schoolId.isNotEmpty &&
        evaluation.schoolId.isNotEmpty &&
        evaluation.schoolId != schoolId &&
        !isSuperAdmin()) return '';
    // ensure class and subject belong to school
    final cls = getClassById(evaluation.classId);
    if (cls != null &&
        schoolId.isNotEmpty &&
        cls.schoolId.isNotEmpty &&
        cls.schoolId != schoolId &&
        !isSuperAdmin()) return '';

    // If adding a draft evaluation, verify rule: only ONE evaluation open at a time per context
    if (evaluation.status == 'draft') {
      final existingContextEvals = getEvaluationsForContext(
        classId: evaluation.classId,
        subjectId: evaluation.subjectId,
        periodId: evaluation.periodId,
        academicYearId: evaluation.academicYearId,
      );
      final hasOpen = existingContextEvals.any((e) =>
          e.id != evaluation.id &&
          (e.status == 'draft' || e.status == 'rejected'));
      if (hasOpen) {
        if (_currentUser != null && !isSuperAdmin()) {
          return ''; // Cannot have two evaluations open in the same context
        }
      }
    }

    final id = evaluation.id.isNotEmpty
        ? evaluation.id
        : 'EV_${DateTime.now().millisecondsSinceEpoch.toString().substring(8)}';
    final toAdd = EvaluationModel(
      id: id,
      title: evaluation.title,
      type: evaluation.type,
      number: evaluation.number,
      academicYearId: evaluation.academicYearId,
      periodId: evaluation.periodId,
      classId: evaluation.classId,
      subjectId: evaluation.subjectId,
      date: evaluation.date,
      status: evaluation.status,
      maxScore: evaluation.maxScore,
      createdBy: evaluation.createdBy,
      createdAt: evaluation.createdAt.isNotEmpty
          ? evaluation.createdAt
          : DateTime.now().toIso8601String(),
      submittedAt: evaluation.submittedAt,
      validatedAt: evaluation.validatedAt,
      validatedBy: evaluation.validatedBy,
      rejectedAt: evaluation.rejectedAt,
      rejectedBy: evaluation.rejectedBy,
      rejectionReason: evaluation.rejectionReason,
      schoolId: evaluation.schoolId.isNotEmpty ? evaluation.schoolId : schoolId,
    );
    _evaluations.add(toAdd);
    _createRemote('evaluations', toAdd.toJson());
    _saveAll();
    notifyListeners();
    return id;
  }

  bool updateEvaluation(EvaluationModel evaluation) {
    final idx = _evaluations.indexWhere((e) => e.id == evaluation.id);
    if (idx == -1) return false;
    final existing = _evaluations[idx];
    // basic tenant check
    if (_currentUser != null &&
        _currentUser!.schoolId != null &&
        _currentUser!.schoolId!.isNotEmpty &&
        existing.schoolId.isNotEmpty &&
        _currentUser!.schoolId != existing.schoolId &&
        !isSuperAdmin()) return false;
    _evaluations[idx] = evaluation;
    _updateRemote('evaluations', evaluation.id, evaluation.toJson());
    _saveAll();
    notifyListeners();
    return true;
  }

  bool deleteEvaluation(String evaluationId) {
    if (evaluationId.isEmpty) return false;
    // Do not delete if grades exist for this evaluation
    final hasGrades = _grades.any((g) => g.evaluationId == evaluationId);
    if (hasGrades) return false;
    _evaluations.removeWhere((e) => e.id == evaluationId);
    _deleteRemote('evaluations', evaluationId);
    _saveAll();
    notifyListeners();
    return true;
  }

  // ---- Evaluation Period Configuration & Lifecycle ----
  List<EvaluationPeriodConfigModel> getEvaluationPeriodConfigs(
      {String? academicYearId, String? schoolId}) {
    final schId = schoolId ?? _currentUser?.schoolId ?? '';
    final yrId = academicYearId ?? getSelectedAcademicYearId() ?? '';

    final matches = _evaluationPeriodConfigs.where((c) {
      if (schId.isNotEmpty && c.schoolId.isNotEmpty && c.schoolId != schId)
        return false;
      if (yrId.isNotEmpty &&
          c.academicYearId.isNotEmpty &&
          c.academicYearId != yrId) return false;
      return true;
    }).toList();

    if (matches.isEmpty) {
      final defaults = [
        EvaluationPeriodConfigModel(
          id: 'CFG_${schId}_${yrId}_T1',
          schoolId: schId,
          academicYearId: yrId,
          periodId: 'T1',
          periodName: 'Trimestre 1',
          homeworkCount: 2,
          hasComposition: true,
          status: 'active',
        ),
        EvaluationPeriodConfigModel(
          id: 'CFG_${schId}_${yrId}_T2',
          schoolId: schId,
          academicYearId: yrId,
          periodId: 'T2',
          periodName: 'Trimestre 2',
          homeworkCount: 2,
          hasComposition: true,
          status: 'locked',
        ),
        EvaluationPeriodConfigModel(
          id: 'CFG_${schId}_${yrId}_T3',
          schoolId: schId,
          academicYearId: yrId,
          periodId: 'T3',
          periodName: 'Trimestre 3',
          homeworkCount: 3,
          hasComposition: true,
          status: 'locked',
        ),
      ];
      _evaluationPeriodConfigs.addAll(defaults);
      return defaults;
    }
    return matches;
  }

  EvaluationPeriodConfigModel getPeriodConfig(String periodId,
      {String? academicYearId, String? schoolId}) {
    final configs = getEvaluationPeriodConfigs(
        academicYearId: academicYearId, schoolId: schoolId);
    return configs.firstWhere(
      (c) => c.periodId == periodId,
      orElse: () => EvaluationPeriodConfigModel(
        id: 'CFG_${schoolId ?? ""}_${academicYearId ?? ""}_$periodId',
        schoolId: schoolId ?? _currentUser?.schoolId ?? '',
        academicYearId: academicYearId ?? getSelectedAcademicYearId() ?? '',
        periodId: periodId,
        periodName: periodId == 'T1'
            ? 'Trimestre 1'
            : (periodId == 'T2'
                ? 'Trimestre 2'
                : (periodId == 'T3' ? 'Trimestre 3' : periodId)),
        homeworkCount: 2,
        hasComposition: true,
        status: periodId == 'T1' ? 'active' : 'locked',
      ),
    );
  }

  void savePeriodConfig(EvaluationPeriodConfigModel config) {
    final idx = _evaluationPeriodConfigs.indexWhere((c) =>
        c.periodId == config.periodId &&
        c.schoolId == config.schoolId &&
        c.academicYearId == config.academicYearId);
    if (idx == -1) {
      _evaluationPeriodConfigs.add(config);
    } else {
      _evaluationPeriodConfigs[idx] = config;
    }
    _saveAll();
    notifyListeners();
  }

  String getActivePeriodId(
      {String? schoolId,
      String? academicYearId,
      String? classId,
      String? subjectId}) {
    final configs = getEvaluationPeriodConfigs(
        academicYearId: academicYearId, schoolId: schoolId);
    final activeConfig = configs.firstWhere(
      (c) => c.status == 'active',
      orElse: () => configs.firstWhere((c) => c.periodId == 'T1',
          orElse: () => configs.first),
    );
    return activeConfig.periodId;
  }

  bool isPeriodActive(String periodId,
      {String? schoolId,
      String? academicYearId,
      String? classId,
      String? subjectId}) {
    final config = getPeriodConfig(periodId,
        academicYearId: academicYearId, schoolId: schoolId);
    return config.status == 'active';
  }

  bool isPeriodClosed(String periodId,
      {String? schoolId,
      String? academicYearId,
      String? classId,
      String? subjectId}) {
    final config = getPeriodConfig(periodId,
        academicYearId: academicYearId, schoolId: schoolId);
    if (config.status == 'closed') return true;

    // Check if evaluations in this context are all finished
    if (classId != null && subjectId != null && academicYearId != null) {
      final evals = getEvaluationsForContext(
        classId: classId,
        subjectId: subjectId,
        periodId: periodId,
        academicYearId: academicYearId,
      );
      if (evals.isNotEmpty &&
          evals.every(
              (e) => e.status == 'submitted' || e.status == 'validated')) {
        return true;
      }
    }
    return false;
  }

  bool isPeriodLocked(String periodId,
      {String? schoolId,
      String? academicYearId,
      String? classId,
      String? subjectId}) {
    if (isPeriodActive(periodId,
        schoolId: schoolId,
        academicYearId: academicYearId,
        classId: classId,
        subjectId: subjectId)) return false;
    if (isPeriodClosed(periodId,
        schoolId: schoolId,
        academicYearId: academicYearId,
        classId: classId,
        subjectId: subjectId)) return false;
    return true;
  }

  bool canOpenPeriod(String periodId,
      {String? schoolId,
      String? academicYearId,
      String? classId,
      String? subjectId}) {
    if (periodId == 'T1') {
      return true;
    }
    if (periodId == 'T2') {
      // T1 must be completely finished / closed
      return isPeriodClosed('T1',
          schoolId: schoolId,
          academicYearId: academicYearId,
          classId: classId,
          subjectId: subjectId);
    }
    if (periodId == 'T3') {
      // T2 must be completely finished / closed
      return isPeriodClosed('T2',
          schoolId: schoolId,
          academicYearId: academicYearId,
          classId: classId,
          subjectId: subjectId);
    }
    return true;
  }

  bool openPeriod(String periodId,
      {String? schoolId,
      String? academicYearId,
      String? classId,
      String? subjectId}) {
    if (!canOpenPeriod(periodId,
        schoolId: schoolId,
        academicYearId: academicYearId,
        classId: classId,
        subjectId: subjectId)) {
      return false;
    }

    final schId = schoolId ?? _currentUser?.schoolId ?? '';
    final yrId = academicYearId ?? getSelectedAcademicYearId() ?? '';
    final configs =
        getEvaluationPeriodConfigs(academicYearId: yrId, schoolId: schId);

    // Only ONE period can be active at a time for this school/year
    for (final cfg in configs) {
      if (cfg.periodId == periodId) {
        savePeriodConfig(cfg.copyWith(status: 'active'));
      } else if (cfg.status == 'active') {
        savePeriodConfig(cfg.copyWith(status: 'closed'));
      }
    }

    if (classId != null && subjectId != null) {
      ensureEvaluationsGenerated(
        classId: classId,
        subjectId: subjectId,
        periodId: periodId,
        academicYearId: yrId,
        schoolId: schId,
      );
    }

    _saveAll();
    notifyListeners();
    return true;
  }

  bool closePeriod(String periodId,
      {String? schoolId,
      String? academicYearId,
      String? classId,
      String? subjectId}) {
    final schId = schoolId ?? _currentUser?.schoolId ?? '';
    final yrId = academicYearId ?? getSelectedAcademicYearId() ?? '';
    final config =
        getPeriodConfig(periodId, academicYearId: yrId, schoolId: schId);
    savePeriodConfig(config.copyWith(status: 'closed'));
    _saveAll();
    notifyListeners();
    return true;
  }

  /// Génère / Prépare automatiquement les évaluations selon la configuration de l'établissement
  /// et applique la logique d'ouverture séquentielle (D1 ouvert, suivants verrouillés)
  void ensureEvaluationsGenerated({
    required String classId,
    required String subjectId,
    required String periodId,
    required String academicYearId,
    String? schoolId,
  }) {
    if (classId.isEmpty || subjectId.isEmpty || periodId.isEmpty) return;
    final currentSchoolId = schoolId ??
        _currentUser?.schoolId ??
        (getClassById(classId)?.schoolId ?? '');
    final config = getPeriodConfig(periodId,
        academicYearId: academicYearId, schoolId: currentSchoolId);

    final existing = getEvaluationsForContext(
      classId: classId,
      subjectId: subjectId,
      periodId: periodId,
      academicYearId: academicYearId,
    );

    final isAct = isPeriodActive(periodId,
        schoolId: currentSchoolId,
        academicYearId: academicYearId,
        classId: classId,
        subjectId: subjectId);

    bool changed = false;

    // 1. Générer les Devoirs 1..N selon la configuration
    for (int i = 1; i <= config.homeworkCount; i++) {
      final hasDevoir =
          existing.any((e) => e.type == 'devoir' && e.number == i);
      if (!hasDevoir) {
        // D1 is draft only if period is active; D2..N are initially locked
        final initialStatus = (i == 1 && isAct) ? 'draft' : 'locked';
        final newDevoir = EvaluationModel(
          id: 'EV_${classId}_${subjectId}_${periodId}_D$i',
          title: 'Devoir $i',
          type: 'devoir',
          number: i,
          academicYearId: academicYearId,
          periodId: periodId,
          classId: classId,
          subjectId: subjectId,
          status: initialStatus,
          maxScore: 20.0,
          createdBy: _currentUser?.id ?? '',
          createdAt: DateTime.now().toIso8601String(),
          schoolId: currentSchoolId,
        );
        _evaluations.add(newDevoir);
        existing.add(newDevoir);
        changed = true;
      }
    }

    // 2. Générer la Composition si prévue dans la configuration
    if (config.hasComposition) {
      final hasComp = existing.any((e) => e.type == 'composition');
      if (!hasComp) {
        final newComp = EvaluationModel(
          id: 'EV_${classId}_${subjectId}_${periodId}_COMP',
          title: 'Composition',
          type: 'composition',
          number: null,
          academicYearId: academicYearId,
          periodId: periodId,
          classId: classId,
          subjectId: subjectId,
          status: 'locked',
          maxScore: 20.0,
          createdBy: _currentUser?.id ?? '',
          createdAt: DateTime.now().toIso8601String(),
          schoolId: currentSchoolId,
        );
        _evaluations.add(newComp);
        existing.add(newComp);
        changed = true;
      }
    }

    // 3. Évaluer la transition séquentielle si la période est active
    if (isAct && existing.isNotEmpty) {
      existing.sort((a, b) {
        if (a.type == 'devoir' && b.type == 'composition') return -1;
        if (a.type == 'composition' && b.type == 'devoir') return 1;
        if (a.type == 'devoir' && b.type == 'devoir') {
          return (a.number ?? 0).compareTo(b.number ?? 0);
        }
        return 0;
      });

      bool previousClosed = true;
      bool hasOpenDraftOrRejected = false;

      for (int k = 0; k < existing.length; k++) {
        final ev = existing[k];
        final storeIdx = _evaluations.indexWhere((e) => e.id == ev.id);
        if (storeIdx == -1) continue;

        if (ev.status == 'rejected') {
          hasOpenDraftOrRejected = true;
          previousClosed = false;
        } else if (ev.status == 'draft') {
          hasOpenDraftOrRejected = true;
          previousClosed = false;
        } else if (ev.status == 'submitted' || ev.status == 'validated') {
          previousClosed = true;
        } else if (ev.status == 'locked') {
          if (previousClosed && !hasOpenDraftOrRejected) {
            // Unlock this evaluation!
            _evaluations[storeIdx] = ev.copyWith(status: 'draft');
            hasOpenDraftOrRejected = true;
            previousClosed = false;
            changed = true;
          }
        }
      }
    }

    if (changed) {
      _saveAll();
      notifyListeners();
    }
  }

  List<EvaluationModel> getEvaluationsForContext({
    required String classId,
    required String subjectId,
    String? periodId,
    required String academicYearId,
  }) {
    final evals = getEvaluations().where((e) {
      if (e.classId != classId) return false;
      if (e.subjectId != subjectId) return false;
      if (academicYearId.isNotEmpty && e.academicYearId != academicYearId)
        return false;
      if (periodId != null && periodId.isNotEmpty && e.periodId != periodId)
        return false;
      return true;
    }).toList();

    evals.sort((a, b) {
      if (a.type == 'devoir' && b.type == 'composition') return -1;
      if (a.type == 'composition' && b.type == 'devoir') return 1;
      if (a.type == 'devoir' && b.type == 'devoir') {
        return (a.number ?? 0).compareTo(b.number ?? 0);
      }
      return 0;
    });

    return evals;
  }

  bool canOpenEvaluation(String evaluationId) {
    final ev = getEvaluationById(evaluationId);
    if (ev == null) return false;
    if (ev.status != 'locked') return false;

    // Period must be active
    if (ev.periodId != null &&
        !isPeriodActive(ev.periodId!,
            schoolId: ev.schoolId,
            academicYearId: ev.academicYearId,
            classId: ev.classId,
            subjectId: ev.subjectId)) {
      return false;
    }

    final contextEvals = getEvaluationsForContext(
      classId: ev.classId,
      subjectId: ev.subjectId,
      periodId: ev.periodId,
      academicYearId: ev.academicYearId,
    );

    final idx = contextEvals.indexWhere((e) => e.id == evaluationId);
    if (idx == -1) return false;

    // All prior evaluations must be submitted or validated (none draft, rejected, locked)
    for (int i = 0; i < idx; i++) {
      final prev = contextEvals[i];
      if (prev.status != 'submitted' && prev.status != 'validated') {
        return false;
      }
    }

    // No other evaluation in the same context can be open (draft)
    final hasOtherDraft = contextEvals.any((e) =>
        e.id != evaluationId &&
        (e.status == 'draft' || e.status == 'rejected'));
    if (hasOtherDraft) return false;

    return true;
  }

  bool openEvaluation(String evaluationId) {
    if (!canOpenEvaluation(evaluationId)) return false;
    final idx = _evaluations.indexWhere((e) => e.id == evaluationId);
    if (idx == -1) return false;
    _evaluations[idx] = _evaluations[idx].copyWith(status: 'draft');
    _saveAll();
    notifyListeners();
    return true;
  }

  // ---- Evaluation workflow actions ----
  bool submitEvaluation(String evaluationId) {
    final idx = _evaluations.indexWhere((e) => e.id == evaluationId);
    if (idx == -1) return false;
    final ev = _evaluations[idx];
    // Only creator or admin can submit; tenant check
    if (!isSuperAdmin() &&
        _currentUser != null &&
        ev.schoolId.isNotEmpty &&
        _currentUser!.schoolId != null &&
        ev.schoolId != _currentUser!.schoolId) return false;
    final updated = ev.copyWith(
      status: 'submitted',
      submittedAt: DateTime.now().toIso8601String(),
      rejectedAt: null,
      rejectedBy: null,
      rejectionReason: null,
    );
    _evaluations[idx] = updated;

    // Automatically transition next sequential evaluation to draft (open)
    final contextEvals = getEvaluationsForContext(
      classId: ev.classId,
      subjectId: ev.subjectId,
      periodId: ev.periodId,
      academicYearId: ev.academicYearId,
    );
    final curIndex = contextEvals.indexWhere((e) => e.id == evaluationId);
    if (curIndex != -1 && curIndex + 1 < contextEvals.length) {
      final nextEval = contextEvals[curIndex + 1];
      final nextIdxInStore =
          _evaluations.indexWhere((e) => e.id == nextEval.id);
      if (nextIdxInStore != -1 &&
          _evaluations[nextIdxInStore].status == 'locked') {
        _evaluations[nextIdxInStore] =
            _evaluations[nextIdxInStore].copyWith(status: 'draft');
      }
    }

    // If all evaluations for this period in this context are completed, mark period as closed
    if (ev.periodId != null) {
      final pConfig = getPeriodConfig(ev.periodId!,
          academicYearId: ev.academicYearId, schoolId: ev.schoolId);
      final expectedCount =
          pConfig.homeworkCount + (pConfig.hasComposition ? 1 : 0);
      final allFinished = contextEvals.length >= expectedCount &&
          contextEvals.every((e) =>
              e.id == evaluationId ||
              e.status == 'submitted' ||
              e.status == 'validated');
      if (allFinished && pConfig.status == 'active') {
        savePeriodConfig(pConfig.copyWith(status: 'closed'));
      }
    }

    // notify admins of submission and log action
    try {
      final title = 'Évaluation soumise';
      final message =
          'Une évaluation ${ev.title} (${ev.subjectId}) de la classe ${ev.classId} a été soumise.';
      _createNotification(title, message,
          type: 'evaluation_submitted', icon: '📝', schoolId: ev.schoolId);
      _logAction('SUBMIT_EVALUATION', 'evaluation', ev.id,
          oldValue: {'status': ev.status}, newValue: {'status': 'submitted'});
    } catch (_) {}

    _saveAll();
    notifyListeners();
    return true;
  }

  bool validateEvaluation(String evaluationId) {
    final idx = _evaluations.indexWhere((e) => e.id == evaluationId);
    if (idx == -1) return false;
    final ev = _evaluations[idx];
    // Only superadmin or school admin for the same school can validate
    if (_currentUser != null && !isSuperAdmin()) {
      if (_currentUser!.role != UserRole.admin) return false;
      if (ev.schoolId.isNotEmpty &&
          _currentUser!.schoolId != null &&
          ev.schoolId != _currentUser!.schoolId) return false;
    }
    final updated = ev.copyWith(
      status: 'validated',
      validatedAt: DateTime.now().toIso8601String(),
      validatedBy: _currentUser?.id,
      rejectedAt: null,
      rejectedBy: null,
      rejectionReason: null,
    );
    _evaluations[idx] = updated;

    // Check if next evaluation should be opened
    final contextEvals = getEvaluationsForContext(
      classId: ev.classId,
      subjectId: ev.subjectId,
      periodId: ev.periodId,
      academicYearId: ev.academicYearId,
    );
    final curIndex = contextEvals.indexWhere((e) => e.id == evaluationId);
    if (curIndex != -1 && curIndex + 1 < contextEvals.length) {
      final nextEval = contextEvals[curIndex + 1];
      final nextIdxInStore =
          _evaluations.indexWhere((e) => e.id == nextEval.id);
      if (nextIdxInStore != -1 &&
          _evaluations[nextIdxInStore].status == 'locked') {
        _evaluations[nextIdxInStore] =
            _evaluations[nextIdxInStore].copyWith(status: 'draft');
      }
    }

    // If all evaluations for this period in this context are completed, mark period as closed
    if (ev.periodId != null) {
      final pConfig = getPeriodConfig(ev.periodId!,
          academicYearId: ev.academicYearId, schoolId: ev.schoolId);
      final expectedCount =
          pConfig.homeworkCount + (pConfig.hasComposition ? 1 : 0);
      final allFinished = contextEvals.length >= expectedCount &&
          contextEvals.every((e) =>
              e.id == evaluationId ||
              e.status == 'submitted' ||
              e.status == 'validated');
      if (allFinished && pConfig.status == 'active') {
        savePeriodConfig(pConfig.copyWith(status: 'closed'));
      }
    }

    // notify submitting teacher and log action
    try {
      final title = 'Évaluation validée';
      final message = 'Votre évaluation ${ev.title} a été validée.';
      if (ev.createdBy.isNotEmpty) {
        _createNotification(title, message,
            type: 'evaluation_validated',
            icon: '✅',
            targetUserId: ev.createdBy,
            schoolId: ev.schoolId);
      } else {
        _createNotification(title, message,
            type: 'evaluation_validated', icon: '✅', schoolId: ev.schoolId);
      }
      _logAction('VALIDATE_EVALUATION', 'evaluation', ev.id,
          oldValue: {'status': ev.status}, newValue: {'status': 'validated'});
    } catch (_) {}

    _saveAll();
    notifyListeners();
    return true;
  }

  bool rejectEvaluation(String evaluationId, String reason) {
    if (reason.trim().isEmpty) return false;
    final idx = _evaluations.indexWhere((e) => e.id == evaluationId);
    if (idx == -1) return false;
    final ev = _evaluations[idx];
    // Only superadmin or school admin for the same school can reject
    if (_currentUser != null && !isSuperAdmin()) {
      if (_currentUser!.role != UserRole.admin) return false;
      if (ev.schoolId.isNotEmpty &&
          _currentUser!.schoolId != null &&
          ev.schoolId != _currentUser!.schoolId) return false;
    }
    final updated = ev.copyWith(
      status: 'rejected',
      rejectedAt: DateTime.now().toIso8601String(),
      rejectedBy: _currentUser?.id,
      rejectionReason: reason.trim(),
      validatedAt: null,
      validatedBy: null,
    );
    _evaluations[idx] = updated;

    // Lock all subsequent evaluations in the same context
    final contextEvals = getEvaluationsForContext(
      classId: ev.classId,
      subjectId: ev.subjectId,
      periodId: ev.periodId,
      academicYearId: ev.academicYearId,
    );
    final curIdx = contextEvals.indexWhere((e) => e.id == evaluationId);
    if (curIdx != -1) {
      for (int i = curIdx + 1; i < contextEvals.length; i++) {
        final subEval = contextEvals[i];
        final subStoreIdx = _evaluations.indexWhere((e) => e.id == subEval.id);
        if (subStoreIdx != -1 &&
            _evaluations[subStoreIdx].status != 'validated' &&
            _evaluations[subStoreIdx].status != 'submitted') {
          _evaluations[subStoreIdx] =
              _evaluations[subStoreIdx].copyWith(status: 'locked');
        }
      }
    }

    // notify submitting teacher and log action
    try {
      final title = 'Évaluation rejetée';
      final message =
          'Votre évaluation ${ev.title} a été rejetée. Motif : $reason';
      if (ev.createdBy.isNotEmpty) {
        _createNotification(title, message,
            type: 'evaluation_rejected',
            icon: '❌',
            targetUserId: ev.createdBy,
            schoolId: ev.schoolId);
      } else {
        _createNotification(title, message,
            type: 'evaluation_rejected', icon: '❌', schoolId: ev.schoolId);
      }
      _logAction('REJECT_EVALUATION', 'evaluation', ev.id,
          oldValue: {'status': ev.status},
          newValue: {'status': 'rejected', 'reason': reason});
    } catch (_) {}

    _saveAll();
    notifyListeners();
    return true;
  }

  // Optional: lock evaluation explicitly
  bool lockEvaluation(String evaluationId) {
    final idx = _evaluations.indexWhere((e) => e.id == evaluationId);
    if (idx == -1) return false;
    final ev = _evaluations[idx];
    // Only superadmin or school admin for the same school can lock
    if (_currentUser != null && !isSuperAdmin()) {
      if (_currentUser!.role != UserRole.admin) return false;
      if (ev.schoolId.isNotEmpty &&
          _currentUser!.schoolId != null &&
          ev.schoolId != _currentUser!.schoolId) return false;
    }
    final updated = ev.copyWith(
      status: 'locked',
    );
    _evaluations[idx] = updated;
    _saveAll();
    notifyListeners();
    return true;
  }

  // ---- Grades helpers / CRUD ----
  List<GradeModel> getGradesByEvaluation(String evaluationId) {
    return _grades.where((g) => g.evaluationId == evaluationId).toList();
  }

  GradeModel? getGradeByStudentAndEvaluation(
      String studentId, String evaluationId) {
    try {
      return _grades.firstWhere(
          (g) => g.studentId == studentId && g.evaluationId == evaluationId);
    } catch (_) {
      return null;
    }
  }

  String addGrade(GradeModel grade) {
    final schoolId = _currentUser?.schoolId ?? '';
    // evaluate existence
    final ev = getEvaluationById(grade.evaluationId);
    if (ev == null) return '';
    if (_currentUser != null &&
        !isSuperAdmin() &&
        ev.schoolId.isNotEmpty &&
        schoolId.isNotEmpty &&
        ev.schoolId != schoolId) return '';

    // Business rule: Check period is active
    if (ev.periodId != null &&
        !isPeriodActive(ev.periodId!,
            schoolId: ev.schoolId,
            academicYearId: ev.academicYearId,
            classId: ev.classId,
            subjectId: ev.subjectId)) {
      if (_currentUser != null && !isSuperAdmin()) return '';
    }

    // Business rule: Evaluation must be open ('draft') or 'rejected' (in correction)
    if (ev.status == 'locked' ||
        ev.status == 'submitted' ||
        ev.status == 'validated') {
      if (_currentUser != null && !isSuperAdmin()) return '';
    }

    // Business rule: If a prior evaluation in the same context is rejected, cannot add grades to this evaluation
    final contextEvals = getEvaluationsForContext(
      classId: ev.classId,
      subjectId: ev.subjectId,
      periodId: ev.periodId,
      academicYearId: ev.academicYearId,
    );
    final curIdx = contextEvals.indexWhere((e) => e.id == ev.id);
    if (curIdx > 0) {
      for (int i = 0; i < curIdx; i++) {
        if (contextEvals[i].status == 'rejected' ||
            contextEvals[i].status == 'draft' ||
            contextEvals[i].status == 'locked') {
          if (_currentUser != null && !isSuperAdmin()) return '';
        }
      }
    }

    final student = _students.firstWhere((s) => s.id == grade.studentId,
        orElse: () =>
            StudentModel(id: '', firstName: '', lastName: '', schoolId: ''));
    if (student.id.isEmpty) return '';
    if (_currentUser != null &&
        !isSuperAdmin() &&
        student.schoolId.isNotEmpty &&
        schoolId.isNotEmpty &&
        student.schoolId != schoolId) return '';

    // If bulletin for this student/year is locked, do not allow adding grades directly (must use request workflow)
    if (_currentUser != null &&
        !isSuperAdmin() &&
        isAnnualBulletinLocked(student.id, ev.academicYearId)) {
      return '';
    }

    // If current user is a teacher, they can only add grades for classes/subjects they're assigned to
    if (_currentUser != null &&
        !isSuperAdmin() &&
        _currentUser!.role == UserRole.teacher) {
      final teacherId = _currentUser!.id;
      final classId = ev.classId;
      final subjectId =
          grade.subjectId.isNotEmpty ? grade.subjectId : ev.subjectId;
      if (classId.isEmpty || subjectId.isEmpty) return '';
      final assigned = isTeacherAssignedTo(
          teacherId: teacherId,
          classId: classId,
          subjectId: subjectId,
          academicYearId: ev.academicYearId);
      if (!assigned) return '';
    }

    // Avoid duplicates: if exists, return existing id
    final existing = getGradeByStudentAndEvaluation(
        grade.studentId, grade.evaluationId ?? '');
    if (existing != null) return existing.id;

    final id = grade.id.isNotEmpty
        ? grade.id
        : 'GR_${DateTime.now().millisecondsSinceEpoch.toString().substring(8)}';
    final toAdd = GradeModel(
      id: id,
      studentId: grade.studentId,
      subjectId: grade.subjectId,
      subsubjectId: grade.subsubjectId,
      eval: grade.eval,
      grade: grade.grade,
      coef: grade.coef,
      evaluationId: grade.evaluationId,
      presence: grade.presence,
      // if teacher enters the grade, record enteredBy
      enteredBy: (_currentUser != null && _currentUser!.role == UserRole.teacher
          ? _currentUser!.id
          : grade.enteredBy),
      date: grade.date,
      comment: grade.comment,
      academicYearId:
          (grade.academicYearId != null && grade.academicYearId!.isNotEmpty)
              ? grade.academicYearId
              : ev.academicYearId,
      semesterId: (grade.semesterId != null && grade.semesterId!.isNotEmpty)
          ? grade.semesterId
          : ev.periodId,
    );
    _grades.add(toAdd);
    final gradePayload = toAdd.toJson()..['schoolId'] = ev.schoolId;
    _createRemote('grades', gradePayload);
    // audit: creation of grade
    try {
      _logAction('CREATE_GRADE', 'grade', id,
          oldValue: null, newValue: toAdd.toJson());
    } catch (_) {}
    _saveAll();
    notifyListeners();
    return id;
  }

  bool updateGrade(String id, GradeModel updated) {
    final idx = _grades.indexWhere((g) => g.id == id);
    if (idx == -1) return false;
    final existing = _grades[idx];
    // tenant check via student or evaluation
    if (!isSuperAdmin()) {
      final student = _students.firstWhere((s) => s.id == existing.studentId,
          orElse: () =>
              StudentModel(id: '', firstName: '', lastName: '', schoolId: ''));
      if (student.id.isEmpty || student.schoolId != _currentUser?.schoolId)
        return false;
    }

    final ev = getEvaluationById(existing.evaluationId);
    final approvedRequestExists = _gradeModificationRequests.any(
      (request) => request.gradeId == id && request.status == 'approved',
    );

    // Business rule: check period is active
    if (ev != null &&
        ev.periodId != null &&
        !isPeriodActive(ev.periodId!,
            schoolId: ev.schoolId,
            academicYearId: ev.academicYearId,
            classId: ev.classId,
            subjectId: ev.subjectId)) {
      if (!isSuperAdmin() && !approvedRequestExists) return false;
    }

    // Business rule: If a prior evaluation in the same context is rejected, cannot update this evaluation
    if (ev != null) {
      final contextEvals = getEvaluationsForContext(
        classId: ev.classId,
        subjectId: ev.subjectId,
        periodId: ev.periodId,
        academicYearId: ev.academicYearId,
      );
      final curIdx = contextEvals.indexWhere((e) => e.id == ev.id);
      if (curIdx > 0) {
        for (int i = 0; i < curIdx; i++) {
          if (contextEvals[i].status == 'rejected') {
            if (!isSuperAdmin()) return false;
          }
        }
      }
    }

    // If current user is a teacher, they must be assigned to this class/subject to update
    if (!isSuperAdmin() &&
        _currentUser != null &&
        _currentUser!.role == UserRole.teacher) {
      final teacherId = _currentUser!.id;
      final classId = ev?.classId;
      final subjectId = updated.subjectId;
      if (classId == null || classId.isEmpty || subjectId.isEmpty) return false;
      final assigned = isTeacherAssignedTo(
          teacherId: teacherId,
          classId: classId,
          subjectId: subjectId,
          academicYearId: ev?.academicYearId);
      if (!assigned) return false;
    }

    // If annual bulletin locked for this student/year, require an approved modification request before allowing direct update
    if (ev != null &&
        !isSuperAdmin() &&
        isAnnualBulletinLocked(existing.studentId, ev.academicYearId)) {
      final matchedReqIndexForLock = _gradeModificationRequests
          .indexWhere((r) => r.gradeId == id && r.status == 'approved');
      if (matchedReqIndexForLock == -1) return false;
    }

    // Business rule: cannot update a grade for a submitted/validated/locked evaluation except if there is an approved modification request for THIS grade AND belongs to the requesting teacher, OR current user is admin
    if (ev != null &&
        (ev.status == 'submitted' ||
            ev.status == 'validated' ||
            ev.status == 'locked') &&
        !isSuperAdmin()) {
      // find approved request for this grade
      final matchedReqIndex = _gradeModificationRequests
          .indexWhere((r) => r.gradeId == id && r.status == 'approved');
      if (matchedReqIndex == -1) return false;
      final req = _gradeModificationRequests[matchedReqIndex]
          as GradeModificationRequestModel;
      // ensure the modifier is the requester (teacher) or allowed user
      if (_currentUser != null &&
          _currentUser!.role == UserRole.teacher &&
          req.requestedBy != _currentUser!.id) return false;
      // if request specified a newValue, ensure update matches it
      if (req.newValue != null && updated.grade != req.newValue) return false;

      // record change log
      final oldVal = existing.grade;
      final newVal = updated.grade;
      if (oldVal != newVal) {
        final logId =
            'GCL_${DateTime.now().millisecondsSinceEpoch.toString().substring(8)}';
        final log = GradeChangeLogModel(
          id: logId,
          gradeId: id,
          evaluationId: existing.evaluationId ?? '',
          studentId: existing.studentId,
          oldValue: oldVal,
          newValue: newVal,
          changedBy: _currentUser?.id ?? '',
          changedAt: DateTime.now().toIso8601String(),
          note: 'Approved modification via request ${req.id}',
        );
        _gradeChangeLogs.add(log);
        // audit: grade changed via approved request
        try {
          _logAction('APPLY_APPROVED_GRADE_MOD', 'grade', id,
              oldValue: {'grade': oldVal},
              newValue: {'grade': newVal, 'requestId': req.id});
        } catch (_) {}
      }

      // mark request as completed so it cannot be reused
      req.status = 'completed';
      _gradeModificationRequests[matchedReqIndex] = req;

      // After modification, evaluation must re-enter workflow: submitted -> validated -> locked
      final evIdx = _evaluations.indexWhere((e) => e.id == ev.id);
      if (evIdx != -1) {
        final original = _evaluations[evIdx];
        final bumped = EvaluationModel(
          id: original.id,
          title: original.title,
          type: original.type,
          number: original.number,
          academicYearId: original.academicYearId,
          periodId: original.periodId,
          classId: original.classId,
          subjectId: original.subjectId,
          date: original.date,
          status: 'submitted',
          createdBy: original.createdBy,
          createdAt: original.createdAt,
          submittedAt: DateTime.now().toIso8601String(),
          validatedAt: null,
          validatedBy: null,
          schoolId: original.schoolId,
        );
        _evaluations[evIdx] = bumped;
      }
    } else if (ev != null &&
        (ev.status == 'validated' || ev.status == 'locked') &&
        isSuperAdmin()) {
      // admin can change; record log
      final oldVal = existing.grade;
      final newVal = updated.grade;
      if (oldVal != newVal) {
        final logId =
            'GCL_${DateTime.now().millisecondsSinceEpoch.toString().substring(8)}';
        final log = GradeChangeLogModel(
          id: logId,
          gradeId: id,
          evaluationId: existing.evaluationId ?? '',
          studentId: existing.studentId,
          oldValue: oldVal,
          newValue: newVal,
          changedBy: _currentUser?.id ?? '',
          changedAt: DateTime.now().toIso8601String(),
          note: 'Admin override',
        );
        _gradeChangeLogs.add(log);
        // audit: admin override applied to grade
        try {
          _logAction('ADMIN_OVERRIDE_GRADE', 'grade', id,
              oldValue: {'grade': oldVal}, newValue: {'grade': newVal});
        } catch (_) {}
      }
      // optionally, admin changes could also force evaluation back to submitted — keep behavior consistent: bump back to submitted
      final evIdx = _evaluations.indexWhere((e) => e.id == ev.id);
      if (evIdx != -1) {
        final original = _evaluations[evIdx];
        final bumped = EvaluationModel(
          id: original.id,
          title: original.title,
          type: original.type,
          number: original.number,
          academicYearId: original.academicYearId,
          periodId: original.periodId,
          classId: original.classId,
          subjectId: original.subjectId,
          date: original.date,
          status: 'submitted',
          createdBy: original.createdBy,
          createdAt: original.createdAt,
          submittedAt: DateTime.now().toIso8601String(),
          validatedAt: null,
          validatedBy: null,
          schoolId: original.schoolId,
        );
        _evaluations[evIdx] = bumped;
      }
    }

    // If not a validated/locked evaluation (normal flow), allow update (with assignment checks already performed)

    final merged = GradeModel(
      id: existing.id,
      studentId:
          updated.studentId.isNotEmpty ? updated.studentId : existing.studentId,
      subjectId:
          updated.subjectId.isNotEmpty ? updated.subjectId : existing.subjectId,
      subsubjectId: updated.subsubjectId ?? existing.subsubjectId,
      eval: updated.eval.isNotEmpty ? updated.eval : existing.eval,
      grade: updated.grade,
      coef: updated.coef,
      evaluationId: updated.evaluationId ?? existing.evaluationId,
      presence: updated.presence ?? existing.presence,
      enteredBy: updated.enteredBy ?? existing.enteredBy,
      date: updated.date ?? existing.date,
      comment: updated.comment ?? existing.comment,
      academicYearId: updated.academicYearId?.isNotEmpty == true
          ? updated.academicYearId
          : existing.academicYearId,
      semesterId: updated.semesterId?.isNotEmpty == true
          ? updated.semesterId
          : existing.semesterId,
    );
    _grades[idx] = merged;
    final gradePayload = merged.toJson()
      ..['schoolId'] = ev?.schoolId ?? _currentUser?.schoolId;
    _updateRemote('grades', id, gradePayload);
    // audit: record update
    try {
      _logAction('UPDATE_GRADE', 'grade', id,
          oldValue: existing.toJson(), newValue: merged.toJson());
    } catch (_) {}
    _saveAll();
    notifyListeners();
    return true;
  }

  void deleteGrade(String id) {
    final existing = _grades.firstWhere((g) => g.id == id,
        orElse: () => GradeModel(
            id: '',
            studentId: '',
            subjectId: '',
            subsubjectId: '',
            eval: '',
            grade: null,
            coef: 1,
            evaluationId: null,
            presence: 'present',
            enteredBy: '',
            date: '',
            comment: '',
            academicYearId: '',
            semesterId: ''));
    if (existing.id.isEmpty) return;
    final ev = getEvaluationById(existing.evaluationId);
    // If annual bulletin locked for this student/year, prevent deletion by non-superadmin
    if (ev != null &&
        !isSuperAdmin() &&
        isAnnualBulletinLocked(existing.studentId, ev.academicYearId)) return;
    if (ev != null &&
        (ev.status == 'validated' || ev.status == 'locked') &&
        !isSuperAdmin()) return;
    // audit: deletion
    try {
      _logAction('DELETE_GRADE', 'grade', id,
          oldValue: existing.toJson(), newValue: null);
    } catch (_) {}

    _grades.removeWhere((g) => g.id == id);
    _deleteRemote('grades', id);
    _saveAll();
    notifyListeners();
  }

  bool hasDuplicateAffectation(AffectationModel affectation,
      {String? excludeId}) {
    return _affectations.any((a) {
      if (excludeId != null && a.id == excludeId) return false;
      if (a.type != affectation.type) return false;
      if (a.teacherId != affectation.teacherId) return false;
      if (a.academicYearId != affectation.academicYearId) return false;
      final sameClass = (a.classId != null && affectation.classId != null)
          ? a.classId == affectation.classId
          : a.className != null &&
              affectation.className != null &&
              a.className == affectation.className;
      if (!sameClass) return false;
      if (affectation.type == 'main_teacher') return true;
      final sameSubject = (a.subjectId != null && affectation.subjectId != null)
          ? a.subjectId == affectation.subjectId
          : a.subject != null &&
              affectation.subject != null &&
              a.subject == affectation.subject;
      return sameSubject;
    });
  }

  List<GradeModel> getGrades() {
    if (isSuperAdmin()) return List.unmodifiable(_grades);
    final studentIds = getStudents().map((s) => s.id).toSet();
    return _grades.where((g) => studentIds.contains(g.studentId)).toList();
  }

  // ---- Annual bulletin lock API ----
  bool isAnnualBulletinLocked(String studentId, String academicYearId) {
    final key = '${studentId}_$academicYearId';
    return _lockedAnnualBulletins[key] == true;
  }

  void lockAnnualBulletin(String studentId, String academicYearId) {
    final key = '${studentId}_$academicYearId';
    _lockedAnnualBulletins[key] = true;
    _saveAll();
    notifyListeners();
  }

  void unlockAnnualBulletin(String studentId, String academicYearId) {
    final key = '${studentId}_$academicYearId';
    if (_lockedAnnualBulletins.containsKey(key)) {
      _lockedAnnualBulletins.remove(key);
      _saveAll();
      notifyListeners();
    }
  }

  List<String> getLockedAnnualBulletins() => _lockedAnnualBulletins.entries
      .where((e) => e.value)
      .map((e) => e.key)
      .toList();

  // ---- Grade modification requests ----
  List<GradeModificationRequestModel> getGradeModificationRequests() {
    if (isSuperAdmin())
      return List.unmodifiable(
          _gradeModificationRequests.cast<GradeModificationRequestModel>());
    final schoolId = _currentUser?.schoolId;
    return _gradeModificationRequests
        .cast<GradeModificationRequestModel>()
        .where((r) => getEvaluationById(r.evaluationId)?.schoolId == schoolId)
        .toList();
  }

  String requestGradeModification(
      {required String gradeId, double? newValue, required String reason}) {
    if (_currentUser == null) return '';
    final grade = _grades.firstWhere((g) => g.id == gradeId,
        orElse: () => GradeModel(
            id: '',
            studentId: '',
            subjectId: '',
            subsubjectId: '',
            eval: '',
            grade: null,
            coef: 1,
            evaluationId: null,
            presence: 'present',
            enteredBy: '',
            date: '',
            comment: '',
            academicYearId: '',
            semesterId: ''));
    if (grade.id.isEmpty) return '';
    final ev = getEvaluationById(grade.evaluationId);
    if (ev == null) return '';
    // only allow request for evaluations that are validated/locked
    if (!(ev.status == 'validated' || ev.status == 'locked')) return '';
    // tenant check
    if (!isSuperAdmin() && ev.schoolId != _currentUser!.schoolId) return '';

    // If current user is a teacher, ensure they are assigned to this class/subject
    if (!isSuperAdmin() && _currentUser!.role == UserRole.teacher) {
      final teacherId = _currentUser!.id;
      final classId = ev.classId;
      final subjectId = grade.subjectId;
      if (classId.isEmpty || subjectId.isEmpty) return '';
      final assigned = isTeacherAssignedTo(
          teacherId: teacherId,
          classId: classId,
          subjectId: subjectId,
          academicYearId: ev.academicYearId);
      if (!assigned) return '';
    }

    final id =
        'REQ_${DateTime.now().millisecondsSinceEpoch.toString().substring(8)}';
    final req = GradeModificationRequestModel(
      id: id,
      gradeId: gradeId,
      evaluationId: ev.id,
      studentId: grade.studentId,
      requestedBy: _currentUser!.id,
      requestedAt: DateTime.now().toIso8601String(),
      oldValue: grade.grade,
      newValue: newValue,
      reason: reason,
    );
    _gradeModificationRequests.add(req);
    // notify admins of new modification request and log
    try {
      final title = 'Nouvelle demande de modification de note';
      final message =
          'Demande de modification pour l\'élève ${grade.studentId} sur l\'évaluation ${ev.title} par ${_currentUser!.name}.';
      _createNotification(title, message,
          type: 'grade_mod_request', icon: '⚠️', schoolId: ev.schoolId);
      _logAction(
          'REQUEST_GRADE_MODIFICATION', 'gradeModificationRequest', req.id,
          oldValue: null,
          newValue: {'gradeId': grade.id, 'requestedBy': _currentUser!.id});
    } catch (_) {}

    _saveAll();
    notifyListeners();
    return id;
  }

  bool approveGradeModification(String requestId, {String? note}) {
    if (_currentUser == null) return false;
    final idx = _gradeModificationRequests.indexWhere((r) => r.id == requestId);
    if (idx == -1) return false;
    final req =
        _gradeModificationRequests[idx] as GradeModificationRequestModel;
    // only superadmin or school admin for same school can approve
    if (!isSuperAdmin()) {
      if (_currentUser!.role != UserRole.admin) return false;
      final ev = getEvaluationById(req.evaluationId);
      if (ev == null || ev.schoolId != _currentUser!.schoolId) return false;
    }
    req.status = 'approved';
    req.handledBy = _currentUser!.id;
    req.handledAt = DateTime.now().toIso8601String();
    req.handledReason = note;
    _gradeModificationRequests[idx] = req;
    // notify requester and log approval
    try {
      final title = 'Demande de modification approuvée';
      final message = 'Votre demande ${req.id} a été approuvée.';
      _createNotification(title, message,
          type: 'grade_mod_approved',
          icon: '✅',
          targetUserId: req.requestedBy,
          schoolId: getEvaluationById(req.evaluationId)?.schoolId);
      _logAction(
          'APPROVE_GRADE_MODIFICATION', 'gradeModificationRequest', req.id,
          oldValue: {'status': 'pending'},
          newValue: {'status': 'approved', 'handledBy': _currentUser!.id});
    } catch (_) {}

    _saveAll();
    notifyListeners();
    return true;
  }

  bool refuseGradeModification(String requestId, String reason) {
    if (_currentUser == null) return false;
    final idx = _gradeModificationRequests.indexWhere((r) => r.id == requestId);
    if (idx == -1) return false;
    final req =
        _gradeModificationRequests[idx] as GradeModificationRequestModel;
    // only superadmin or school admin for same school can refuse
    if (!isSuperAdmin()) {
      if (_currentUser!.role != UserRole.admin) return false;
      final ev = getEvaluationById(req.evaluationId);
      if (ev == null || ev.schoolId != _currentUser!.schoolId) return false;
    }
    req.status = 'rejected';
    req.handledBy = _currentUser!.id;
    req.handledAt = DateTime.now().toIso8601String();
    req.handledReason = reason;
    _gradeModificationRequests[idx] = req;
    // notify requester and log rejection
    try {
      final title = 'Demande de modification refusée';
      final message = 'Votre demande ${req.id} a été refusée. Motif: $reason';
      _createNotification(title, message,
          type: 'grade_mod_rejected',
          icon: '❌',
          targetUserId: req.requestedBy,
          schoolId: getEvaluationById(req.evaluationId)?.schoolId);
      _logAction(
          'REJECT_GRADE_MODIFICATION', 'gradeModificationRequest', req.id,
          oldValue: {'status': 'pending'},
          newValue: {'status': 'rejected', 'handledBy': _currentUser!.id});
    } catch (_) {}

    _saveAll();
    notifyListeners();
    return true;
  }

  /// Create an AnnualBulletinModel for a student using ResultService.generateAnnualBulletin
  /// Stores the calculated bulletin and returns its id, or empty string on failure
  String createAnnualBulletinRecord(
      {required String classId,
      required String studentId,
      List<String>? periodIds}) {
    if (_currentUser == null) return '';
    final student = _students.firstWhere((s) => s.id == studentId,
        orElse: () =>
            StudentModel(id: '', firstName: '', lastName: '', schoolId: ''));
    if (student.id.isEmpty) return '';
    // tenant check
    if (!isSuperAdmin() && _currentUser!.schoolId != student.schoolId)
      return '';

    final res = ResultService(this)
        .generateAnnualBulletin(classId, studentId, periodIds: periodIds);
    if (res.isEmpty) return '';

    final subjects = <AnnualSubjectResult>[];
    final subjList = res['subjects'] as List<dynamic>? ?? [];
    for (final s in subjList) {
      final map = Map<String, dynamic>.from(s as Map);
      final periodAverages = map['periodAverages'] as List<dynamic>? ?? [];
      double? t1 = periodAverages.length > 0
          ? (periodAverages[0] as num?)?.toDouble()
          : null;
      double? t2 = periodAverages.length > 1
          ? (periodAverages[1] as num?)?.toDouble()
          : null;
      double? t3 = periodAverages.length > 2
          ? (periodAverages[2] as num?)?.toDouble()
          : null;
      final ann = map['moyenneAnnuel'] != null
          ? (map['moyenneAnnuel'] as num).toDouble()
          : null;
      final coef = (map['coefficient'] as num?)?.toDouble() ?? 1.0;
      final isCalc = map['isCalculable'] == true;
      subjects.add(AnnualSubjectResult(
          subjectId: map['subjectId'] ?? '',
          subjectName: map['subjectName'] ?? '',
          t1: t1,
          t2: t2,
          t3: t3,
          annualAverage: ann,
          coefficient: coef,
          isCalculable: isCalc));
    }

    final genAvg = res['generalAverage'] != null
        ? (res['generalAverage'] as num?)?.toDouble()
        : null;
    final ranking = res['ranking'] as Map<String, dynamic>? ?? {};
    final rank = ranking['rank'] as int?;
    final effectif = ranking['effectif'] as int? ?? 0;

    final id =
        'AB_${DateTime.now().millisecondsSinceEpoch.toString().substring(8)}';
    final bulletin = AnnualBulletinModel(
      id: id,
      establishmentId: student.schoolId,
      academicYearId: res['academicYearId'] ?? '',
      studentId: studentId,
      classId: classId,
      subjectResults: subjects,
      generalAverage: genAvg,
      rank: rank,
      classSize: effectif,
      status: 'calculated',
      createdAt: DateTime.now().toIso8601String(),
    );

    _annualBulletins.add(bulletin);
    _saveAll();
    notifyListeners();
    return id;
  }

  AnnualBulletinModel? getAnnualBulletinById(String id) {
    final matches = _annualBulletins.where((b) => b.id == id).toList();
    if (matches.isEmpty) return null;
    return matches.first;
  }

  List<AnnualBulletinModel> getAnnualBulletinsForStudent(String studentId) {
    if (isSuperAdmin())
      return _annualBulletins.where((b) => b.studentId == studentId).toList();
    final student = _students.firstWhere((s) => s.id == studentId,
        orElse: () =>
            StudentModel(id: '', firstName: '', lastName: '', schoolId: ''));
    if (student.id.isEmpty) return [];
    if (_currentUser == null) return [];
    if (!isSuperAdmin() && _currentUser!.schoolId != student.schoolId)
      return [];
    return _annualBulletins.where((b) => b.studentId == studentId).toList();
  }

  bool validateAnnualBulletin(String bulletinId) {
    if (_currentUser == null) return false;
    final idx = _annualBulletins.indexWhere((b) => b.id == bulletinId);
    if (idx == -1) return false;
    final b = _annualBulletins[idx];
    // only admin or superadmin can validate
    if (!isSuperAdmin() && _currentUser!.role != UserRole.admin) return false;
    // tenant check
    if (!isSuperAdmin() && _currentUser!.schoolId != b.establishmentId)
      return false;
    b.status = 'validated';
    b.validatedAt = DateTime.now().toIso8601String();
    b.validatedBy = _currentUser!.id;
    _annualBulletins[idx] = b;
    try {
      _createNotification(
          'Bulletin validé', 'Le bulletin de ${b.studentId} a été validé.',
          type: 'annual_bulletin_validated',
          icon: '✅',
          schoolId: b.establishmentId,
          targetUserId: b.validatedBy ?? '');
      _logAction('VALIDATE_ANNUAL_BULLETIN', 'annualBulletin', b.id,
          oldValue: {'status': null}, newValue: {'status': 'validated'});
    } catch (_) {}
    _saveAll();
    notifyListeners();
    return true;
  }

  bool lockAnnualBulletinRecord(String bulletinId) {
    if (_currentUser == null) return false;
    final idx = _annualBulletins.indexWhere((b) => b.id == bulletinId);
    if (idx == -1) return false;
    final b = _annualBulletins[idx];
    // only admin or superadmin can lock
    if (!isSuperAdmin() && _currentUser!.role != UserRole.admin) return false;
    if (!isSuperAdmin() && _currentUser!.schoolId != b.establishmentId)
      return false;
    b.status = 'locked';
    b.validatedAt = b.validatedAt ?? DateTime.now().toIso8601String();
    b.validatedBy = b.validatedBy ?? _currentUser!.id;
    _annualBulletins[idx] = b;
    // mark map for blocking grade edits
    lockAnnualBulletin(b.studentId, b.academicYearId);
    try {
      _createNotification('Bulletin verrouillé',
          'Le bulletin de ${b.studentId} a été verrouillé.',
          type: 'annual_bulletin_locked',
          icon: '🔒',
          schoolId: b.establishmentId,
          targetUserId: b.validatedBy ?? '');
      _logAction('LOCK_ANNUAL_BULLETIN', 'annualBulletin', b.id,
          oldValue: {'status': 'validated'}, newValue: {'status': 'locked'});
    } catch (_) {}
    _saveAll();
    notifyListeners();
    return true;
  }

  bool unlockAnnualBulletinRecord(String bulletinId) {
    if (_currentUser == null) return false;
    final idx = _annualBulletins.indexWhere((b) => b.id == bulletinId);
    if (idx == -1) return false;
    final b = _annualBulletins[idx];
    if (!isSuperAdmin() && _currentUser!.role != UserRole.admin) return false;
    if (!isSuperAdmin() && _currentUser!.schoolId != b.establishmentId)
      return false;
    b.status = 'validated';
    _annualBulletins[idx] = b;
    unlockAnnualBulletin(b.studentId, b.academicYearId);
    _saveAll();
    notifyListeners();
    return true;
  }

  // --- Annual decisions API ---
  /// Propose a decision based on bulletin values and establishment rules (if configured).
  String proposeAnnualDecisionFromBulletin(String bulletinId) {
    final bulletin = getAnnualBulletinById(bulletinId);
    if (bulletin == null) return 'A_DECIDER';
    final school = getCurrentSchool();
    // Try to read a configurable threshold in school JSON under 'decisionRules'->'promotionThreshold'
    final schoolJson = school?.toJson() ?? {};
    try {
      final rules = schoolJson['decisionRules'];
      if (rules != null &&
          rules is Map &&
          rules['promotionThreshold'] != null) {
        final thr = (rules['promotionThreshold'] as num).toDouble();
        if (bulletin.generalAverage != null) {
          if ((bulletin.generalAverage ?? 0) >= thr) return 'ADMIS';
          return 'REDOUBLE';
        }
      }
    } catch (_) {}
    return 'A_DECIDER';
  }

  String createAnnualDecisionFromBulletin(String bulletinId,
      {String? proposedDecision}) {
    if (_currentUser == null) return '';
    final bulletin = getAnnualBulletinById(bulletinId);
    if (bulletin == null) return '';
    if (!isSuperAdmin() && _currentUser!.schoolId != bulletin.establishmentId)
      return '';

    final id =
        'AD_${DateTime.now().millisecondsSinceEpoch.toString().substring(8)}';
    final decision =
        proposedDecision ?? proposeAnnualDecisionFromBulletin(bulletinId);
    final model = AnnualDecisionModel(
      id: id,
      establishmentId: bulletin.establishmentId,
      academicYearId: bulletin.academicYearId,
      studentId: bulletin.studentId,
      currentClassId: bulletin.classId,
      nextClassId: null,
      annualAverage: bulletin.generalAverage,
      rank: bulletin.rank,
      decision: decision,
      status: 'draft',
      createdAt: DateTime.now().toIso8601String(),
    );
    _annualDecisions.add(model);
    _saveAll();
    notifyListeners();
    return id;
  }

  AnnualDecisionModel? getAnnualDecisionById(String id) {
    final matches = _annualDecisions.where((d) => d.id == id).toList();
    if (matches.isEmpty) return null;
    return matches.first;
  }

  List<AnnualDecisionModel> getDecisionsForStudent(String studentId) {
    if (isSuperAdmin())
      return _annualDecisions.where((d) => d.studentId == studentId).toList();
    final student = _students.firstWhere((s) => s.id == studentId,
        orElse: () =>
            StudentModel(id: '', firstName: '', lastName: '', schoolId: ''));
    if (student.id.isEmpty) return [];
    if (_currentUser == null) return [];
    if (!isSuperAdmin() && _currentUser!.schoolId != student.schoolId)
      return [];
    return _annualDecisions.where((d) => d.studentId == studentId).toList();
  }

  bool setAnnualDecision(String decisionId, String newDecision,
      {String? reason}) {
    if (_currentUser == null) return false;
    final idx = _annualDecisions.indexWhere((d) => d.id == decisionId);
    if (idx == -1) return false;
    final d = _annualDecisions[idx];
    if (!isSuperAdmin() && _currentUser!.schoolId != d.establishmentId)
      return false;
    // If validated or locked, prevent direct edits
    if ((d.status == 'validated' || d.status == 'locked') && !isSuperAdmin())
      return false;

    final old = d.decision;
    d.decision = newDecision;
    d.reason = reason ?? d.reason;
    d.updatedAt = DateTime.now().toIso8601String();
    d.decidedBy = _currentUser!.id;
    d.decidedAt = d.updatedAt;
    _annualDecisions[idx] = d;

    // log change
    final logId =
        'DCH_${DateTime.now().millisecondsSinceEpoch.toString().substring(8)}';
    final log = DecisionChangeLogModel(
        id: logId,
        decisionId: d.id,
        oldDecision: old,
        newDecision: newDecision,
        changedBy: _currentUser!.id,
        changedAt: DateTime.now().toIso8601String(),
        reason: reason);
    _decisionChangeLogs.add(log);

    _saveAll();
    notifyListeners();
    return true;
  }

  bool validateAnnualDecision(String decisionId) {
    if (_currentUser == null) return false;
    final idx = _annualDecisions.indexWhere((d) => d.id == decisionId);
    if (idx == -1) return false;
    final d = _annualDecisions[idx];
    if (!isSuperAdmin() && _currentUser!.role != UserRole.admin) return false;
    if (!isSuperAdmin() && _currentUser!.schoolId != d.establishmentId)
      return false;
    d.status = 'validated';
    d.decidedBy = _currentUser!.id;
    d.decidedAt = DateTime.now().toIso8601String();
    _annualDecisions[idx] = d;
    _saveAll();
    notifyListeners();
    return true;
  }

  bool lockAnnualDecision(String decisionId) {
    if (_currentUser == null) return false;
    final idx = _annualDecisions.indexWhere((d) => d.id == decisionId);
    if (idx == -1) return false;
    final d = _annualDecisions[idx];
    if (!isSuperAdmin() && _currentUser!.role != UserRole.admin) return false;
    if (!isSuperAdmin() && _currentUser!.schoolId != d.establishmentId)
      return false;
    d.status = 'locked';
    d.decidedBy = d.decidedBy ?? _currentUser!.id;
    d.decidedAt = d.decidedAt ?? DateTime.now().toIso8601String();
    _annualDecisions[idx] = d;
    _saveAll();
    notifyListeners();
    return true;
  }

  /// Prepare a re-enrollment request for a decision (does not modify StudentModel)
  String prepareReEnrollment(String decisionId, String toAcademicYearId,
      {String? toClassId}) {
    if (_currentUser == null) return '';
    final d = getAnnualDecisionById(decisionId);
    if (d == null) return '';
    if (!isSuperAdmin() && _currentUser!.schoolId != d.establishmentId)
      return '';
    final id =
        'RE_${DateTime.now().millisecondsSinceEpoch.toString().substring(8)}';
    final req = ReEnrollmentRequestModel(
      id: id,
      decisionId: d.id,
      studentId: d.studentId,
      fromAcademicYearId: d.academicYearId,
      toAcademicYearId: toAcademicYearId,
      fromClassId: d.currentClassId,
      toClassId: toClassId,
      createdAt: DateTime.now().toIso8601String(),
      createdBy: _currentUser!.id,
    );
    _reEnrollmentRequests.add(req);
    _saveAll();
    notifyListeners();
    return id;
  }

  List<ReEnrollmentRequestModel> getReEnrollmentRequestsForStudent(
      String studentId) {
    if (isSuperAdmin())
      return _reEnrollmentRequests
          .where((r) => r.studentId == studentId)
          .toList();
    final student = _students.firstWhere((s) => s.id == studentId,
        orElse: () =>
            StudentModel(id: '', firstName: '', lastName: '', schoolId: ''));
    if (student.id.isEmpty) return [];
    if (_currentUser == null) return [];
    if (!isSuperAdmin() && _currentUser!.schoolId != student.schoolId)
      return [];
    return _reEnrollmentRequests
        .where((r) => r.studentId == studentId)
        .toList();
  }

  List<DecisionChangeLogModel> getDecisionChangeLogs(String decisionId) {
    return _decisionChangeLogs
        .where((l) => l.decisionId == decisionId)
        .toList();
  }

  List<AbsenceModel> getAbsences() {
    if (isSuperAdmin()) return List.unmodifiable(_absences);
    final studentIds = getStudents().map((s) => s.id).toSet();
    return _absences.where((a) => studentIds.contains(a.studentId)).toList();
  }

  Future<bool> addAbsences(Iterable<AbsenceModel> absences) async {
    final records = absences.toList();
    if (records.isEmpty) return true;
    try {
      for (final record in records) {
        await _repository.create('absences', record.toJson());
      }
    } on ApiException {
      return false;
    }
    _absences
        .removeWhere((item) => records.any((record) => record.id == item.id));
    _absences.addAll(records);
    _saveAll();
    notifyListeners();
    return true;
  }

  String? getCurrentTeacherId() {
    if (_currentUser == null) return null;
    final teacher = _teachers
        .where((t) =>
            t.userId == _currentUser!.id ||
            t.email?.toLowerCase() == _currentUser!.email.toLowerCase())
        .toList();
    return teacher.isEmpty ? null : teacher.first.id;
  }

  String? getCurrentStudentId() {
    if (_currentUser == null) return null;
    final student =
        _students.where((item) => item.userId == _currentUser!.id).toList();
    return student.isEmpty ? null : student.first.id;
  }

  List<BehaviorAssessmentModel> getBehaviorAssessments({String? studentId}) {
    final current = _currentUser;
    var values = _behaviorAssessments
        .where((b) => isSuperAdmin() || b.schoolId == current?.schoolId);
    if (current?.role == UserRole.student) {
      values = values.where((b) => b.studentUserId == current?.id);
    }
    if (current?.role == UserRole.parent) {
      values = values.where((b) => b.parentUserId == current?.id);
    }
    if (studentId != null)
      values = values.where((b) => b.studentId == studentId);
    return values.toList();
  }

  @Deprecated(
      'Non officiel : utiliser behaviorResultsRemote pour un trimestre précis')
  double behaviorAverage(String studentId) {
    final values = getBehaviorAssessments(studentId: studentId);
    if (values.isEmpty) return 0;
    return values.fold<double>(0, (sum, value) => sum + value.score) /
        values.length;
  }

  Future<bool> addBehaviorAssessment(BehaviorAssessmentModel assessment) async {
    if (assessment.score < 1 || assessment.score > 5) return false;
    final current = _currentUser;
    if (current == null || current.role != UserRole.teacher) return false;
    if (assessment.schoolId != current.schoolId ||
        assessment.classId == null ||
        assessment.classId!.isEmpty ||
        assessment.periodId == null ||
        assessment.periodId!.isEmpty) return false;
    if (assessment.teacherId != getCurrentTeacherId() ||
        assessment.teacherUserId != current.id) return false;
    final stars = assessment.score.round();
    try {
      await createBehaviorEventRemote({
        'studentId': assessment.studentId,
        'classId': assessment.classId,
        'periodId': assessment.periodId,
        'category': 'stars:$stars',
        'eventType': stars >= 3 ? 'positive' : 'negative',
        'severity': 'normal',
        'title': '$stars étoile${stars > 1 ? 's' : ''}',
        if (assessment.comment?.trim().isNotEmpty == true)
          'description': assessment.comment!.trim(),
      });
    } on ApiException {
      return false;
    }
    return true;
  }

  List<SubscriptionModel> getSubscriptions() {
    return _subscriptions
        .map((s) => s.copyWith(status: _computeSubscriptionStatus(s)))
        .toList(growable: false);
  }

  Future<bool> saveSubscription(SubscriptionModel subscription) async {
    if (!isSuperAdmin() ||
        subscription.id.isEmpty ||
        subscription.schoolId == null ||
        subscription.schoolId!.isEmpty) return false;
    try {
      await _repository.create('subscriptions', subscription.toJson());
    } on ApiException {
      return false;
    }
    _subscriptions.removeWhere((item) => item.id == subscription.id);
    _subscriptions.add(subscription);
    _saveAll();
    notifyListeners();
    return true;
  }

  Future<Map<String, dynamic>> sendExternalNotification({
    required String channel,
    required String recipient,
    required String message,
    String? subject,
  }) =>
      _repository.sendExternalNotification({
        'channel': channel,
        'recipient': recipient,
        'message': message,
        if (subject != null && subject.trim().isNotEmpty)
          'subject': subject.trim(),
        'confirmed': true,
      });

  Future<Map<String, dynamic>> broadcastTeachers({
    required String channel,
    required String message,
    String? subject,
    String? schoolId,
  }) =>
      _repository.broadcastTeachers({
        'channel': channel,
        'message': message,
        if (subject != null && subject.trim().isNotEmpty)
          'subject': subject.trim(),
        if (schoolId != null && schoolId.trim().isNotEmpty)
          'schoolId': schoolId.trim(),
        'confirmed': true,
      });

  Future<Map<String, dynamic>> generateDocumentReport(
          Map<String, dynamic> payload) =>
      _repository.generateDocumentReport(payload);

  List<AnnouncementModel> getAnnouncements() {
    final current = _currentUser;
    if (current == null) return const [];
    return _announcements.where((item) {
      if (isSuperAdmin()) return true;
      if (item.schoolId != current.schoolId) return false;
      return item.targetRole == null ||
          item.targetRole!.isEmpty ||
          item.targetRole == current.role.value;
    }).toList();
  }

  Future<bool> saveAnnouncement(AnnouncementModel announcement) async {
    final current = _currentUser;
    if (current == null ||
        (current.role != UserRole.admin &&
            current.role != UserRole.teacher &&
            !isSuperAdmin())) return false;
    if (!isSuperAdmin() && announcement.schoolId != current.schoolId)
      return false;
    try {
      await _repository.create('announcements', announcement.toJson());
    } on ApiException {
      return false;
    }
    _announcements.removeWhere((item) => item.id == announcement.id);
    _announcements.add(announcement);
    _saveAll();
    notifyListeners();
    return true;
  }

  Future<bool> reactToAnnouncement(
      String announcementId, String reaction) async {
    try {
      final data =
          await _repository.reactToAnnouncement(announcementId, reaction);
      final announcement = AnnouncementModel.fromJson(data);
      final index =
          _announcements.indexWhere((item) => item.id == announcementId);
      if (index == -1) return false;
      _announcements[index] = announcement;
      _saveAll();
      notifyListeners();
      return true;
    } on ApiException {
      return false;
    }
  }

  String _computeSubscriptionStatus(SubscriptionModel subscription) {
    if (subscription.endDate.isEmpty || subscription.endDate == '—') {
      return 'active';
    }

    try {
      final end = DateTime.parse(subscription.endDate);
      final today = DateTime.now();
      if (!today.isAfter(end)) return 'active';
      final overdueDays = today.difference(end).inDays;
      if (overdueDays <= 30) return 'past_due';
      return 'expired';
    } catch (_) {
      return subscription.status;
    }
  }

  List<UserModel> getUsers() => List.unmodifiable(_users);

  UserModel? findUserByEmail(String email) {
    final cleanEmail = email.toLowerCase().trim();
    if (cleanEmail.isEmpty) return null;
    for (final user in _users) {
      if (user.email.toLowerCase().trim() == cleanEmail) return user;
    }
    return null;
  }

  UserModel? findUserBySchoolId(String schoolId) {
    if (schoolId.isEmpty) return null;
    for (final user in _users) {
      if (user.schoolId == schoolId && user.role == UserRole.admin) {
        return user;
      }
    }
    return null;
  }

  void addUser(UserModel user) {
    _users.add(user);
    _saveAll();
    notifyListeners();
  }

  void updateUser(UserModel user) {
    final idx = _users.indexWhere((u) => u.id == user.id);
    if (idx != -1) {
      _users[idx] = user;
      _saveAll();
      notifyListeners();
    }
  }

  void updateEstablishment(EstablishmentModel establishment) {
    final idx = _establishments.indexWhere((e) => e.id == establishment.id);
    if (idx != -1) {
      _establishments[idx] = establishment;
      _updateRemote('establishments', establishment.id, establishment.toJson());
      _saveAll();
      notifyListeners();
    }
  }

  List<NotificationModel> getNotifications() =>
      List.unmodifiable(_notifications);

  Future<void> refreshWorkflowNotificationsRemote() async {
    final rows = await _repository.workflowNotifications();
    _notifications = rows.map(NotificationModel.fromJson).toList()
      ..sort((left, right) => right.time.compareTo(left.time));
    notifyListeners();
  }

  Future<Map<String, dynamic>> notifyTeachersInApp({
    required String title,
    required String message,
    String category = 'administrative',
    List<String>? teacherIds,
  }) async {
    final result = await _repository.notifyTeachersInApp({
      'title': title.trim(),
      'message': message.trim(),
      'category': category,
      if (teacherIds != null && teacherIds.isNotEmpty)
        'teacherIds': teacherIds,
    });
    await refreshWorkflowNotificationsRemote();
    return result;
  }

  List<AuditLogModel> getAuditLogs({String? schoolId}) {
    if (isSuperAdmin()) return List.unmodifiable(_auditLogs);
    if (schoolId != null)
      return _auditLogs.where((a) => a.schoolId == schoolId).toList();
    return _auditLogs
        .where((a) => a.schoolId == _currentUser?.schoolId)
        .toList();
  }

  void markNotificationAsRead(String notificationId) {
    final idx = _notifications.indexWhere((n) => n.id == notificationId);
    if (idx == -1) return;
    _notifications[idx].read = true;
    unawaited(_saveAllAsync());
    unawaited(_ignoreRemoteFailure(
        _repository.markWorkflowNotificationRead(notificationId)));
    notifyListeners();
  }

  void markAllNotificationsAsRead({String? schoolId}) {
    for (var i = 0; i < _notifications.length; i++) {
      if (schoolId == null || _notifications[i].schoolId == schoolId) {
        _notifications[i].read = true;
      }
    }
    unawaited(_saveAllAsync());
    unawaited(
        _ignoreRemoteFailure(_repository.markAllWorkflowNotificationsRead()));
    notifyListeners();
  }

  // Helper to create a notification
  void _createNotification(String title, String message,
      {String? type, String? icon, String? targetUserId, String? schoolId}) {
    final id =
        'N_${DateTime.now().millisecondsSinceEpoch.toString().substring(8)}';
    final n = NotificationModel(
      id: id,
      title: title,
      message: message,
      type: type,
      icon: icon,
      targetUserId: targetUserId,
      schoolId: schoolId,
      read: false,
      time: DateTime.now().toIso8601String(),
    );
    _notifications.add(n);
    _saveAll();
    // in a real app, also push to user subscriptions / websocket
  }

  // Helper to append an audit log entry
  void _logAction(String action, String objectType, String objectId,
      {Map<String, dynamic>? oldValue,
      Map<String, dynamic>? newValue,
      String? reason}) {
    final id =
        'AL_${DateTime.now().millisecondsSinceEpoch.toString().substring(8)}';
    final log = AuditLogModel(
      id: id,
      action: action,
      objectType: objectType,
      objectId: objectId,
      userId: _currentUser?.id ?? '',
      userRole: _currentUser?.role.name ?? '',
      schoolId: _currentUser?.schoolId ?? '',
      timestamp: DateTime.now().toIso8601String(),
      oldValue: oldValue,
      newValue: newValue,
      reason: reason,
    );
    _auditLogs.add(log);
    _saveAll();
  }

  List<AssignmentModel> getAssignments() => _assignments;
  List<FeeModel> getFinanceFees() {
    if (isSuperAdmin()) return List.unmodifiable(_financeFees);
    final schoolId = _currentUser?.schoolId;
    return _financeFees.where((f) => f.schoolId == schoolId).toList();
  }

  List<FinanceRegistrationModel> getFinanceRegistrations() {
    if (isSuperAdmin()) return List.unmodifiable(_financeRegistrations);
    final schoolId = _currentUser?.schoolId;
    return _financeRegistrations.where((r) => r.schoolId == schoolId).toList();
  }

  /// Retourne une liste d'ids de frais par défaut à appliquer lors d'une inscription.
  /// Critères : frais ciblant la même classe, ou frais globaux (className == null),
  /// ou frais explicitement nommés comme 'inscription'|'scolarité'|'assurance'.
  /// Helper to check if a fee applies to a specific class
  bool isFeeApplicableToClass(FeeModel fee, ClassModel cls,
      {String? academicYearId}) {
    final effectiveClass = (fee.schoolId != null &&
            fee.schoolId!.isNotEmpty &&
            cls.schoolId != fee.schoolId)
        ? getClassByName(cls.name, schoolId: fee.schoolId)
        : cls;
    if (effectiveClass == null) return false;

    // tenant / school check
    if (fee.schoolId != null &&
        fee.schoolId!.isNotEmpty &&
        fee.schoolId != effectiveClass.schoolId) return false;
    // academic year restriction
    if (fee.academicYearId != null &&
        academicYearId != null &&
        fee.academicYearId != academicYearId) return false;

    final scope = fee.scope?.toLowerCase();
    if (scope == null || scope.isEmpty) {
      // Backwards compatibility: if legacy className set, treat as class-scoped, otherwise treat as establishment/global
      if (fee.className != null && fee.className!.isNotEmpty) {
        return (effectiveClass.name == fee.className);
      }
      return true; // no scope => global
    }

    switch (scope) {
      case 'establishment':
        return true;
      case 'cycle':
        if (fee.cycle == null || fee.cycle!.isEmpty) return false;
        return (effectiveClass.cycle != null &&
            effectiveClass.cycle!.toLowerCase() == fee.cycle!.toLowerCase());
      case 'level':
        if (fee.levelId != null && fee.levelId!.isNotEmpty) {
          return (effectiveClass.levelId != null &&
              effectiveClass.levelId == fee.levelId);
        }
        if (fee.level != null && fee.level!.isNotEmpty) {
          return (effectiveClass.level != null &&
              effectiveClass.level!.toLowerCase() == fee.level!.toLowerCase());
        }
        return false;
      case 'class':
        if (fee.classId != null && fee.classId!.isNotEmpty) {
          return effectiveClass.id == fee.classId;
        }
        if (fee.className != null && fee.className!.isNotEmpty) {
          return effectiveClass.name == fee.className;
        }
        return false;
      default:
        return false;
    }
  }

  List<String> getDefaultFeeIdsForRegistration(
      {String? classId,
      String? className,
      String? schoolId,
      String? academicYearId}) {
    final fees = getFinanceFees();
    final matches = <String>{};
    final resolvedSchoolId = schoolId ?? _currentUser?.schoolId;
    final cls = classId != null && classId.isNotEmpty
        ? getClassById(classId)
        : (className != null
            ? getClassByName(className, schoolId: resolvedSchoolId)
            : null);

    for (final f in fees) {
      // Do not auto-assign occasional fees
      if (f.isOccasional == true) continue;

      // Explicit mandatory flags always apply
      if (f.isMandatoryAtRegistration == true) {
        matches.add(f.id);
        continue;
      }

      // Academic-year specific mandatory or applicable fees
      if (academicYearId != null &&
          f.academicYearId != null &&
          f.academicYearId == academicYearId) {
        matches.add(f.id);
        continue;
      }

      // Determine applicability by scope / legacy className
      if (cls != null) {
        if (isFeeApplicableToClass(f, cls, academicYearId: academicYearId)) {
          matches.add(f.id);
          continue;
        }
      } else {
        // No class provided: if fee is global (establishment) or has no className, include
        final scope = f.scope?.toLowerCase();
        if (scope == null ||
            scope == 'establishment' ||
            (f.className == null && f.scope == null)) {
          matches.add(f.id);
          continue;
        }
      }
    }
    return matches.toList();
  }

  List<FinanceRegistrationModel> getStudentRegistrations(String studentId) {
    if (isSuperAdmin())
      return _financeRegistrations
          .where((r) => r.studentId == studentId)
          .toList();
    final schoolId = _currentUser?.schoolId;
    return _financeRegistrations
        .where((r) => r.studentId == studentId && r.schoolId == schoolId)
        .toList();
  }

  /// Récupère toutes les inscriptions scolaires (académiques) d'un élève
  List<StudentRegistrationModel> getStudentAcademicRegistrations(
      String studentId) {
    if (isSuperAdmin())
      return _studentRegistrations
          .where((r) => r.studentId == studentId)
          .toList();
    final schoolId = _currentUser?.schoolId;
    return _studentRegistrations
        .where((r) =>
            r.studentId == studentId &&
            (schoolId == null || r.schoolId == schoolId))
        .toList();
  }

  /// Récupère une inscription scolaire par son ID
  StudentRegistrationModel? getStudentAcademicRegistrationById(
      String registrationId) {
    try {
      return _studentRegistrations.firstWhere(
        (r) =>
            r.id == registrationId &&
            (isSuperAdmin() ||
                _currentUser?.schoolId == null ||
                r.schoolId == _currentUser?.schoolId),
      );
    } catch (_) {
      return null;
    }
  }

  // Debug helper: return all registrations for a student ignoring tenant filters.
  // This is only intended for local debugging (kDebugMode). Do NOT expose in production APIs.
  List<FinanceRegistrationModel> debug_getAllRegistrationsForStudent(
      String studentId) {
    try {
      return _financeRegistrations
          .where((r) => r.studentId == studentId)
          .toList();
    } catch (_) {
      return [];
    }
  }

  FinanceRegistrationModel? getActiveRegistrationForStudent(String studentId) {
    final selectedYear = _selectedAcademicYearId;
    final regs = getStudentRegistrations(studentId);
    if (regs.isEmpty) return null;
    if (selectedYear != null) {
      for (final r in regs) {
        if (r.academicYearId == selectedYear) return r;
      }
    }
    return regs.first;
  }

  List<FinancePaymentModel> getFinancePayments() {
    if (isSuperAdmin()) return List.unmodifiable(_financePayments);
    final schoolId = _currentUser?.schoolId;
    return _financePayments.where((p) => p.schoolId == schoolId).toList();
  }

  List<FinanceReceiptModel> getFinanceReceipts() {
    if (isSuperAdmin()) return List.unmodifiable(_financeReceipts);
    final schoolId = _currentUser?.schoolId;
    return _financeReceipts.where((r) => r.schoolId == schoolId).toList();
  }

  List<FinanceFeeAssignmentModel> getFinanceFeeAssignments() {
    if (isSuperAdmin()) return List.unmodifiable(_financeFeeAssignments);
    final schoolId = _currentUser?.schoolId;
    return _financeFeeAssignments.where((a) => a.schoolId == schoolId).toList();
  }

  List<FinanceFeeAssignmentModel> getFinanceFeeAssignmentsByRegistration(
      String registrationId) {
    return getFinanceFeeAssignments()
        .where((a) => a.registrationId == registrationId)
        .toList();
  }

  List<FinanceFeeAssignmentModel> getFinanceFeeAssignmentsByStudent(
      String studentId) {
    return getFinanceFeeAssignments()
        .where((a) => a.studentId == studentId)
        .toList();
  }

  List<FinancePaymentModel> getFinancePaymentsByRegistration(
      String registrationId) {
    return getFinancePayments()
        .where((p) => p.registrationId == registrationId)
        .toList();
  }

  FinanceRegistrationModel? getFinanceRegistrationById(String registrationId) {
    try {
      return _financeRegistrations.firstWhere(
        (r) =>
            r.id == registrationId &&
            (isSuperAdmin() || r.schoolId == _currentUser?.schoolId),
      );
    } catch (_) {
      return null;
    }
  }

  FinancePaymentModel? getFinancePaymentById(String paymentId) {
    try {
      return _financePayments.firstWhere(
        (p) =>
            p.id == paymentId &&
            (isSuperAdmin() || p.schoolId == _currentUser?.schoolId),
      );
    } catch (_) {
      return null;
    }
  }

  /// Mark a payment as cancelled (audit-friendly) instead of deleting it.
  /// Returns true on success.
  bool cancelFinancePayment(String paymentId, {String? reason}) {
    final idx = _financePayments.indexWhere((p) => p.id == paymentId);
    if (idx == -1) return false;
    final p = _financePayments[idx];
    if (!isSuperAdmin() && p.schoolId != _currentUser?.schoolId) return false;

    // Update status and append a note with the reason/user
    final prevNote = p.note ?? '';
    final by = _currentUser?.id ?? _currentUser?.name ?? 'system';
    final time = DateTime.now().toIso8601String();
    final cancelNote = reason != null && reason.trim().isNotEmpty
        ? 'Annulé: $reason (par $by le $time)'
        : 'Annulé par $by le $time';
    p.status = 'cancelled';
    p.note = prevNote.isNotEmpty ? '$prevNote | $cancelNote' : cancelNote;

    try {
      _logAction('CANCEL_PAYMENT', 'payment', p.id,
          oldValue: null, newValue: p.toJson());
    } catch (_) {}

    // Also try to cancel any mirrored FinancialPaymentRecord(s) that likely correspond to this legacy payment
    try {
      final matches = _financialPaymentsRecords
          .where((r) =>
              r.studentId == p.studentId &&
              (r.amount - p.amount).abs() < 1e-6 &&
              r.date == p.date &&
              r.status.toLowerCase() == 'active')
          .toList();
      for (final r in matches) {
        final ridx = _financialPaymentsRecords.indexWhere((x) => x.id == r.id);
        if (ridx != -1) {
          final rec = _financialPaymentsRecords[ridx];
          _financialPaymentsRecords[ridx] = FinancialPaymentRecord(
            id: rec.id,
            financialLineId: rec.financialLineId,
            studentId: rec.studentId,
            amount: rec.amount,
            date: rec.date,
            paymentMethod: rec.paymentMethod,
            reference: rec.reference,
            status: 'cancelled',
          );
          try {
            _logAction('CANCEL_FINANCIAL_PAYMENT', 'financialPayment', rec.id,
                oldValue: null,
                newValue: _financialPaymentsRecords[ridx].toJson());
          } catch (_) {}
        }
      }
    } catch (_) {}

    _saveAll();
    notifyListeners();
    return true;
  }

  FinanceReceiptModel? getFinanceReceiptById(String receiptId) {
    try {
      return _financeReceipts.firstWhere(
        (r) =>
            r.id == receiptId &&
            (isSuperAdmin() || r.schoolId == _currentUser?.schoolId),
      );
    } catch (_) {
      return null;
    }
  }

  Map<String, double> getFinanceTotalMetrics() {
    final assignments = getFinanceFeeAssignments();
    final payments = getFinancePayments();
    final totalFees = assignments.fold<double>(0, (sum, a) => sum + a.amount);
    // Exclude cancelled payments from total paid
    final totalPaid = payments
        .where((p) => p.status.toLowerCase() == 'active')
        .fold<double>(0, (sum, p) => sum + p.amount);
    final totalDue = assignments.fold<double>(
        0, (sum, a) => sum + getRemainingForAssignment(a.id));
    return {
      'fees': totalFees,
      'paid': totalPaid,
      'due': totalDue,
    };
  }

  Map<String, dynamic> getFinanceBalanceForRegistration(
      FinanceRegistrationModel registration) {
    final assignments = getFinanceFeeAssignmentsByRegistration(registration.id);
    final total = assignments.fold<double>(0, (sum, a) => sum + a.amount);
    final paid = assignments.fold<double>(
        0, (sum, a) => sum + getTotalPaidForAssignment(a.id));
    final due = total - paid;
    final status = due <= 0
        ? 'PAYÉ'
        : paid > 0
            ? 'PARTIEL'
            : 'IMPAYÉ';
    return {
      'total': total,
      'paid': paid,
      'due': due < 0 ? 0 : due,
      'status': status,
    };
  }

  // --- FinancialAccount / FinancialLine / FinancialPayment helpers ---
  String createFinancialAccountForRegistration(FinanceRegistrationModel reg) {
    // If exists, return existing id
    final existing = _financialAccounts.firstWhere(
        (a) => a.registrationId == reg.id,
        orElse: () =>
            FinancialAccountModel(id: '', studentId: '', registrationId: null));
    if (existing.id.isNotEmpty) return existing.id;
    final id =
        'FA_${DateTime.now().millisecondsSinceEpoch.toString().substring(8)}';
    final acc = FinancialAccountModel(
      id: id,
      studentId: reg.studentId,
      studentName: reg.studentName,
      registrationId: reg.id,
      schoolId: reg.schoolId,
      academicYearId: reg.academicYearId,
      status: 'active',
    );
    _financialAccounts.add(acc);
    _saveAll();
    notifyListeners();
    return id;
  }

  FinancialAccountModel? getFinancialAccountByRegistration(
      String registrationId) {
    try {
      return _financialAccounts.firstWhere((a) =>
          a.registrationId == registrationId &&
          (isSuperAdmin() || a.schoolId == _currentUser?.schoolId));
    } catch (_) {
      return null;
    }
  }

  List<FinancialLineModel> getFinancialLinesByAccount(String accountId) {
    return _financialLines
        .where((l) => l.financialAccountId == accountId)
        .toList();
  }

  void addFinancialLine(FinancialLineModel line) {
    // avoid duplicates by feeId+account
    final exists = _financialLines.any((l) =>
        l.financialAccountId == line.financialAccountId &&
        l.feeId == line.feeId);
    if (exists) return;
    _financialLines.add(line);
    _saveAll();
    notifyListeners();
  }

  FinancialLineModel? getFinancialLineByFeeAndAccount(
      String feeId, String accountId) {
    try {
      return _financialLines.firstWhere(
          (l) => l.feeId == feeId && l.financialAccountId == accountId);
    } catch (_) {
      return null;
    }
  }

  FinancialLineModel? getFinancialLineById(String id) {
    try {
      return _financialLines.firstWhere((l) => l.id == id);
    } catch (_) {
      return null;
    }
  }

  /// Returns financial payment records associated with a given financial account.
  /// Includes records attached to lines of the account and unallocated payments for the same student.
  List<FinancialPaymentRecord> getFinancialPaymentRecordsByAccount(
      String accountId) {
    try {
      final lineIds = _financialLines
          .where((l) => l.financialAccountId == accountId)
          .map((l) => l.id)
          .toSet();
      final acc = _financialAccounts.firstWhere((a) => a.id == accountId,
          orElse: () => FinancialAccountModel(id: '', studentId: ''));
      return _financialPaymentsRecords
          .where((r) =>
              lineIds.contains(r.financialLineId) ||
              (r.financialLineId.isEmpty &&
                  acc.id.isNotEmpty &&
                  r.studentId == acc.studentId))
          .toList();
    } catch (_) {
      return [];
    }
  }

  double getTotalPaidForFinancialLine(String lineId) {
    return _financialPaymentsRecords
        .where((p) =>
            p.financialLineId == lineId && p.status.toLowerCase() == 'active')
        .fold<double>(0, (s, p) => s + p.amount);
  }

  double getRemainingForFinancialLine(String lineId) {
    try {
      final line = _financialLines.firstWhere((l) => l.id == lineId);
      final paid = getTotalPaidForFinancialLine(lineId);
      final rem = line.amountDue - paid;
      return rem < 0 ? 0 : rem;
    } catch (_) {
      return 0.0;
    }
  }

  String addFinancialPaymentRecord(FinancialPaymentRecord rec) {
    final id = rec.id.isNotEmpty
        ? rec.id
        : 'FPR_${DateTime.now().millisecondsSinceEpoch.toString().substring(8)}';
    final toAdd = FinancialPaymentRecord(
      id: id,
      financialLineId: rec.financialLineId,
      studentId: rec.studentId,
      amount: rec.amount,
      date: rec.date,
      paymentMethod: rec.paymentMethod,
      reference: rec.reference,
      status: rec.status,
    );
    _financialPaymentsRecords.add(toAdd);
    _saveAll();
    notifyListeners();
    return id;
  }

  bool cancelFinancialPaymentRecord(String paymentId, {String? reason}) {
    final idx = _financialPaymentsRecords.indexWhere((p) => p.id == paymentId);
    if (idx == -1) return false;
    final p = _financialPaymentsRecords[idx];
    p.status = 'cancelled';
    try {
      _logAction('CANCEL_FINANCIAL_PAYMENT', 'financialPayment', p.id,
          oldValue: null, newValue: p.toJson());
    } catch (_) {}
    _saveAll();
    notifyListeners();
    return true;
  }

  // --- end financial helpers ---

  List<Map<String, dynamic>> getFinanceUnpaidStudents() {
    final accum = <String, Map<String, dynamic>>{};
    for (final registration in getFinanceRegistrations()) {
      final studentId = registration.studentId;
      final studentName = registration.studentName ?? registration.studentId;
      final className = registration.className;
      final balanceInfo = getFinanceBalanceForRegistration(registration);
      final due = balanceInfo['due'] as double;
      final paid = balanceInfo['paid'] as double;
      if (due <= 0) continue;
      final existing = accum[studentId];
      if (existing == null) {
        accum[studentId] = {
          'studentId': studentId,
          'studentName': studentName,
          'className': className,
          'totalDue': due,
          'totalPaid': paid,
          'balance': due,
          'status': 'IMPAYÉ',
        };
      } else {
        existing['totalDue'] = (existing['totalDue'] as double) + due;
        existing['totalPaid'] = (existing['totalPaid'] as double) + paid;
        existing['balance'] = (existing['balance'] as double) + due;
      }
    }
    return accum.values.toList();
  }

  Map<String, int> getClassDependencies(String classId) {
    final deps = <String, int>{};
    final cls = _classes.firstWhere((c) => c.id == classId,
        orElse: () => ClassModel(id: '', name: '', schoolId: ''));
    if (cls.id.isEmpty) return deps;
    final studentCount = _students.where((s) => s.className == cls.name).length;
    deps['students'] = studentCount;
    final affectCount = _affectations
        .where((a) => a.classId == classId || a.className == cls.name)
        .length;
    deps['affectations'] = affectCount;
    final subjectCount =
        _subjects.where((s) => s.classes.contains(cls.name)).length;
    deps['subjects'] = subjectCount;
    return deps;
  }

  Map<String, int> getSubjectDependencies(String subjectId) {
    final deps = <String, int>{};
    final affectCount =
        _affectations.where((a) => a.subjectId == subjectId).length;
    deps['affectations'] = affectCount;
    return deps;
  }

  Map<String, int> getTeacherDependencies(String teacherId) {
    final deps = <String, int>{};
    final affectCount =
        _affectations.where((a) => a.teacherId == teacherId).length;
    deps['affectations'] = affectCount;
    return deps;
  }

  Map<String, int> getStudentDependencies(String studentId) {
    final deps = <String, int>{};
    final gradeCount = _grades.where((g) => g.studentId == studentId).length;
    deps['grades'] = gradeCount;
    final absenceCount =
        _absences.where((a) => a.studentId == studentId).length;
    deps['absences'] = absenceCount;
    final regCount =
        _financeRegistrations.where((r) => r.studentId == studentId).length;
    deps['registrations'] = regCount;
    final paymentCount =
        _financePayments.where((p) => p.studentId == studentId).length;
    deps['payments'] = paymentCount;
    return deps;
  }

  Map<String, int> getEstablishmentDependencies(String schoolId) {
    final deps = <String, int>{};
    deps['students'] = _students.where((s) => s.schoolId == schoolId).length;
    deps['teachers'] = _teachers.where((t) => t.schoolId == schoolId).length;
    deps['classes'] = _classes.where((c) => c.schoolId == schoolId).length;
    deps['subjects'] = _subjects.where((s) => s.schoolId == schoolId).length;
    deps['academicYears'] =
        _academicYears.where((y) => y.schoolId == schoolId).length;
    deps['registrations'] =
        _financeRegistrations.where((r) => r.schoolId == schoolId).length;
    return deps;
  }

  Map<String, int> getAcademicYearDependencies(String yearId) {
    final deps = <String, int>{};
    deps['students'] =
        _students.where((s) => s.academicYearId == yearId).length;
    deps['registrations'] =
        _financeRegistrations.where((r) => r.academicYearId == yearId).length;
    deps['payments'] =
        _financePayments.where((p) => p.academicYearId == yearId).length;
    deps['receipts'] =
        _financeReceipts.where((rc) => rc.academicYearId == yearId).length;
    return deps;
  }

  bool deleteEstablishment(String schoolId) {
    final deps = getEstablishmentDependencies(schoolId);
    final total = deps.values.fold<int>(0, (a, b) => a + b);
    if (total > 0) return false;
    _establishments.removeWhere((e) => e.id == schoolId);
    _saveAll();
    notifyListeners();
    return true;
  }

  bool deleteAcademicYear(String yearId) {
    final deps = getAcademicYearDependencies(yearId);
    final total = deps.values.fold<int>(0, (a, b) => a + b);
    if (total > 0) return false;
    _academicYears.removeWhere((y) => y.id == yearId);
    _saveAll();
    notifyListeners();
    return true;
  }

  // ---- Institution Defaults Generator ----
  void ensureDefaultInstitutionSetup() {
    bool changed = false;
    for (final estab in _establishments) {
      final schoolId = estab.id;
      final instType = estab.institutionType;
      if (instType.isHigherEducation) continue;

      // Default Academic Year
      final yearExists = _academicYears.any((y) => y.schoolId == schoolId);
      if (!yearExists) {
        final now = DateTime.now();
        final startYear = now.year;
        final endYear = startYear + 1;
        final prefix = instType == InstitutionType.college
            ? 'C'
            : instType == InstitutionType.highSchool
                ? 'L'
                : 'P';
        final defaultYear = AcademicYearModel(
          id: 'AY$prefix${startYear.toString().substring(2)}${endYear.toString().substring(2)}',
          name: '$startYear-$endYear',
          start: '$startYear-09-01',
          end: '$endYear-07-31',
          establishment: estab.name,
          schoolId: schoolId,
          status: 'active',
          isActive: true,
        );
        _academicYears.add(defaultYear);
        changed = true;
      }

      // Default Classes
      final classExists = _classes.any((c) => c.schoolId == schoolId);
      if (!classExists) {
        final templates = _getDefaultClassNames(instType);
        for (int i = 0; i < templates.length; i++) {
          final primaryLevel = instType == InstitutionType.school
              ? templates[i].split(' ').first
              : instType.levelName;
          _classes.add(ClassModel(
            id: 'CL_${instType.idPrefix}_${(i + 1).toString().padLeft(2, '0')}',
            name: templates[i],
            cycle: instType.levelName,
            level: primaryLevel,
            schoolId: schoolId,
          ));
        }
        changed = true;
      }

      // Add explicit test classes for some demo schools to satisfy checks
      void ensureClass(String name,
          {required String levelName, String? seriesName, String? cycleName}) {
        if (_classes.any((c) => c.name == name && c.schoolId == schoolId))
          return;
        final yearForSchool = _academicYears.firstWhere(
            (y) => y.schoolId == schoolId,
            orElse: () => AcademicYearModel(
                id: '', name: '', start: '', end: '', schoolId: ''));
        String? yearId = yearForSchool.id.isNotEmpty ? yearForSchool.id : null;
        String? seriesId;
        if (seriesName != null) {
          final s = _series.firstWhere(
              (ss) => ss.name.toLowerCase() == seriesName.toLowerCase(),
              orElse: () => SeriesModel(id: '', name: '', schoolId: ''));
          if (s.id.isNotEmpty) seriesId = s.id;
        }
        _classes.add(ClassModel(
          id: 'CL_${schoolId}_${name.replaceAll(' ', '_')}',
          name: name,
          cycle: cycleName ?? instType.levelName,
          level: levelName,
          levelId: null,
          grade: levelName,
          series: seriesName,
          seriesId: seriesId,
          room: null,
          mainTeacher: null,
          students: 0,
          schoolId: schoolId,
          academicYearId: yearId,
        ));
        changed = true;
      }

      // Primary (ET013) -> ensure 'CM2 A'
      if (schoolId == 'ET013') {
        ensureClass('CM2 A',
            levelName: 'CM2', seriesName: null, cycleName: 'Primaire');
      }

      // College (ET014) -> ensure '3e A'
      if (schoolId == 'ET014') {
        ensureClass('3e A',
            levelName: '3e', seriesName: null, cycleName: 'Collège');
      }

      // High School (ET015) -> ensure 1ère A1, 1ère A2, Terminale C1
      if (schoolId == 'ET015') {
        ensureClass('1ère A1',
            levelName: 'Première', seriesName: 'A', cycleName: 'Lycée');
        ensureClass('1ère A2',
            levelName: 'Première', seriesName: 'A', cycleName: 'Lycée');
        ensureClass('Terminale C1',
            levelName: 'Terminale', seriesName: 'C', cycleName: 'Lycée');
      }

      // Default Subjects
      final subjectExists = _subjects.any((s) => s.schoolId == schoolId);
      if (!subjectExists) {
        final subjTemplates = _getDefaultSubjects(instType);
        for (int i = 0; i < subjTemplates.length; i++) {
          _subjects.add(SubjectModel(
            id: 'MA_${instType.idPrefix}_${(i + 1).toString().padLeft(2, '0')}',
            name: subjTemplates[i]['name'] as String,
            coefficient: subjTemplates[i]['coef'] as int,
            color: subjTemplates[i]['color'] as String,
            icon: subjTemplates[i]['icon'] as String,
            classes: _getDefaultClassNames(instType),
            schoolId: schoolId,
          ));
        }
        changed = true;
      }
    }
    if (changed) _saveAll();
  }

  List<String> _getDefaultClassNames(InstitutionType type) {
    switch (type) {
      case InstitutionType.school:
        return ['CP1 A', 'CP2 A', 'CE1 A', 'CE2 A', 'CM1 A', 'CM2 A'];
      case InstitutionType.college:
        return ['6e A', '6e B', '5e A', '5e B', '4e A', '4e B', '3e A', '3e B'];
      case InstitutionType.highSchool:
        return [
          '2nde A',
          '2nde C',
          '1ère A',
          '1ère C',
          'Terminale C',
          'Terminale D'
        ];
      default:
        return [];
    }
  }

  List<Map<String, dynamic>> _getDefaultSubjects(InstitutionType type) {
    switch (type) {
      case InstitutionType.school:
        return [
          {'name': 'Français', 'coef': 3, 'color': '#7C3AED', 'icon': '📚'},
          {
            'name': 'Mathématiques',
            'coef': 4,
            'color': '#4F46E5',
            'icon': '📐'
          },
          {'name': 'Sciences', 'coef': 2, 'color': '#10B981', 'icon': '🔬'},
          {'name': 'Histoire', 'coef': 2, 'color': '#EF4444', 'icon': '📜'},
          {'name': 'Géographie', 'coef': 2, 'color': '#F59E0B', 'icon': '🗺️'},
          {'name': 'Anglais', 'coef': 2, 'color': '#3B82F6', 'icon': '🌍'},
          {'name': 'EPS', 'coef': 1, 'color': '#F97316', 'icon': '⚽'},
        ];
      case InstitutionType.college:
        return [
          {'name': 'Français', 'coef': 3, 'color': '#7C3AED', 'icon': '📚'},
          {
            'name': 'Mathématiques',
            'coef': 4,
            'color': '#4F46E5',
            'icon': '📐'
          },
          {'name': 'Anglais', 'coef': 2, 'color': '#3B82F6', 'icon': '🌍'},
          {
            'name': 'Histoire-Géo',
            'coef': 2,
            'color': '#EF4444',
            'icon': '🗺️'
          },
          {'name': 'SVT', 'coef': 2, 'color': '#10B981', 'icon': '🌿'},
          {
            'name': 'Physique-Chimie',
            'coef': 3,
            'color': '#F59E0B',
            'icon': '⚗️'
          },
          {'name': 'EPS', 'coef': 1, 'color': '#F97316', 'icon': '⚽'},
        ];
      case InstitutionType.highSchool:
        return [
          {'name': 'Français', 'coef': 3, 'color': '#7C3AED', 'icon': '📚'},
          {
            'name': 'Mathématiques',
            'coef': 4,
            'color': '#4F46E5',
            'icon': '📐'
          },
          {'name': 'Anglais', 'coef': 2, 'color': '#3B82F6', 'icon': '🌍'},
          {
            'name': 'Histoire-Géo',
            'coef': 2,
            'color': '#EF4444',
            'icon': '🗺️'
          },
          {'name': 'Philosophie', 'coef': 3, 'color': '#8B5CF6', 'icon': '🤔'},
          {'name': 'Physique', 'coef': 3, 'color': '#F59E0B', 'icon': '🔬'},
          {'name': 'Chimie', 'coef': 3, 'color': '#F97316', 'icon': '⚗️'},
          {'name': 'SVT', 'coef': 2, 'color': '#10B981', 'icon': '🌿'},
        ];
      default:
        return [];
    }
  }

  // ---- CRUD Operations ----
  Future<bool> addEstablishment(EstablishmentModel estab) async {
    final establishmentPayload = estab.toJson()
      ..['planPrice'] = SubscriptionPlan.fromValue(estab.plan).price;
    try {
      await _repository.create('establishments', establishmentPayload);
    } on ApiException {
      return false;
    }
    _establishments.insert(0, estab);
    _subscriptions.insert(
      0,
      SubscriptionModel(
        id: 'SUB_${estab.id}',
        schoolId: estab.id,
        client: estab.name,
        plan: estab.plan.toUpperCase(),
        price: SubscriptionPlan.fromValue(estab.plan).price,
        startDate: estab.date,
        endDate: AppDateUtils.oneYearFromNow(),
        status: 'active',
      ),
    );
    _saveAll();
    ensureDefaultInstitutionSetup();
    notifyListeners();
    return true;
  }

  void addStudent(StudentModel student) {
    _students.add(student);
    _createRemote('students', student.toJson());
    _saveAll();
    notifyListeners();
  }

  void addAcademicYear(AcademicYearModel year) {
    _academicYears.insert(0, year);
    _createRemote('academic-years', year.toJson());
    _saveAll();
    notifyListeners();
  }

  void addTeacher(TeacherModel teacher) {
    _teachers.add(teacher);
    _createRemote('teachers', teacher.toJson());
    _saveAll();
    notifyListeners();
  }

  void updateStudent(StudentModel student) {
    final idx = _students.indexWhere((s) => s.id == student.id);
    if (idx != -1) {
      _students[idx] = student;
      _updateRemote('students', student.id, student.toJson());
      _saveAll();
      notifyListeners();
    }
  }

  void deleteStudent(String studentId) {
    _deleteRemote('students', studentId);
    _students.removeWhere((s) => s.id == studentId);
    _grades.removeWhere((g) => g.studentId == studentId);
    _absences.removeWhere((a) => a.studentId == studentId);
    final paymentIds = _financePayments
        .where((p) => p.studentId == studentId)
        .map((p) => p.id)
        .toSet();
    // Mark payments as cancelled instead of deleting to preserve audit
    for (final pid in paymentIds) {
      cancelFinancePayment(pid,
          reason: 'Cascade cancellation due to student deletion');
    }
    // Keep receipts for audit purposes; do NOT delete receipts.
    _saveAll();
    notifyListeners();
  }

  /// Update an existing teacher by id
  void updateTeacher(TeacherModel teacher) {
    final idx = _teachers.indexWhere((t) => t.id == teacher.id);
    if (idx != -1) {
      final oldTeacher = _teachers[idx];
      _teachers[idx] = teacher;
      _updateRemote('teachers', teacher.id, teacher.toJson());
      final nameChanged = oldTeacher.fullName != teacher.fullName;
      for (var i = 0; i < _affectations.length; i++) {
        if (_affectations[i].teacherId == teacher.id) {
          final affect = _affectations[i];
          _affectations[i] = AffectationModel(
            id: affect.id,
            teacherId: affect.teacherId,
            teacherName: teacher.fullName,
            subjectId: affect.subjectId,
            subject: affect.subject,
            classId: affect.classId,
            className: affect.className,
            schoolId: affect.schoolId,
            institutionId: affect.institutionId,
            academicYearId: affect.academicYearId,
            type: affect.type,
          );
          if (nameChanged &&
              affect.type == 'main_teacher' &&
              affect.classId != null) {
            final cls = _classes.firstWhere(
              (c) => c.id == affect.classId,
              orElse: () => ClassModel(id: '', name: '', schoolId: ''),
            );
            if (cls.id.isNotEmpty) {
              updateClass(cls.copyWith(mainTeacher: teacher.fullName));
            }
          }
        }
      }
      _saveAll();
      notifyListeners();
    }
  }

  /// Delete a teacher by id
  void deleteTeacher(String teacherId) {
    _deleteRemote('teachers', teacherId);
    final mainClassIds = _affectations
        .where((a) =>
            a.teacherId == teacherId &&
            a.type == 'main_teacher' &&
            a.classId != null)
        .map((a) => a.classId!)
        .toSet();
    _teachers.removeWhere((t) => t.id == teacherId);
    _affectations.removeWhere((a) => a.teacherId == teacherId);
    for (final classId in mainClassIds) {
      final cls = _classes.firstWhere(
        (c) => c.id == classId,
        orElse: () => ClassModel(id: '', name: '', schoolId: ''),
      );
      if (cls.id.isNotEmpty) {
        updateClass(cls.copyWith(mainTeacher: null));
      }
    }
    _saveAll();
    notifyListeners();
  }

  void addClass(ClassModel cls) {
    _classes.add(cls);
    _createRemote('classes', cls.toJson());
    _saveAll();
    notifyListeners();
  }

  String _getFeeScope(FeeModel fee) {
    final scope = fee.scope ?? '';
    if (scope.isNotEmpty) return scope.toLowerCase();
    if (fee.classId != null || fee.className != null) return 'class';
    if (fee.levelId != null || fee.level != null) return 'level';
    if (fee.cycle != null && fee.cycle!.isNotEmpty) return 'cycle';
    return 'establishment';
  }

  bool _registrationMatchesFee(
      FinanceRegistrationModel registration, FeeModel fee) {
    final registrationStatus = registration.status.trim();
    if (registrationStatus.isNotEmpty &&
        registrationStatus.toLowerCase() != 'active') return false;

    if (fee.schoolId != null &&
        fee.schoolId!.isNotEmpty &&
        registration.schoolId != fee.schoolId) return false;
    if (fee.academicYearId != null &&
        fee.academicYearId!.isNotEmpty &&
        registration.academicYearId != fee.academicYearId) return false;

    final classRef = registration.classId != null &&
            registration.classId!.isNotEmpty
        ? getClassById(registration.classId!)
        : (registration.className != null && registration.className!.isNotEmpty
            ? getClassByName(registration.className!,
                schoolId: registration.schoolId ?? _currentUser?.schoolId)
            : null);

    switch (_getFeeScope(fee)) {
      case 'establishment':
        return true;
      case 'cycle':
        if (fee.cycle == null || fee.cycle!.isEmpty) return true;
        if (classRef == null) return false;
        return classRef.cycle?.toLowerCase() == fee.cycle!.toLowerCase();
      case 'level':
        if (classRef == null) return false;
        if (fee.levelId != null && fee.levelId!.isNotEmpty) {
          return classRef.levelId == fee.levelId;
        }
        if (fee.level != null && fee.level!.isNotEmpty) {
          return classRef.level?.toLowerCase() == fee.level!.toLowerCase();
        }
        return false;
      case 'class':
        if (fee.classId != null && fee.classId!.isNotEmpty) {
          return registration.classId == fee.classId ||
              (classRef != null && classRef.id == fee.classId);
        }
        if (fee.className != null && fee.className!.isNotEmpty) {
          return registration.className == fee.className ||
              (classRef != null && classRef.name == fee.className);
        }
        return false;
      default:
        return false;
    }
  }

  void _applyFeeToMatchingRegistrations(FeeModel fee) {
    if (fee.id.isEmpty) return;

    for (final registration in _financeRegistrations) {
      if (!_registrationMatchesFee(registration, fee)) continue;

      final alreadyAssigned = _financeFeeAssignments.any(
        (assignment) =>
            assignment.registrationId == registration.id &&
            assignment.feeId == fee.id,
      );
      if (alreadyAssigned) continue;

      _financeFeeAssignments.add(
        FinanceFeeAssignmentModel(
          id: IdGenerator.generate('FA',
              existingCount: _financeFeeAssignments.length),
          registrationId: registration.id,
          feeId: fee.id,
          studentId: registration.studentId,
          studentName: registration.studentName,
          amount: fee.amount,
          dueDate: null,
          schoolId: registration.schoolId,
          institutionId: registration.institutionId,
          academicYearId: registration.academicYearId,
          status: 'assigned',
        ),
      );
    }
  }

  Future<FeeModel> createFinanceFeeRemote(FeeModel draft) async {
    final academicYearId = draft.academicYearId ??
        _selectedAcademicYearId ??
        getActiveAcademicYear()?.id;
    if (academicYearId == null || academicYearId.isEmpty) {
      throw StateError('Sélectionnez une année scolaire.');
    }
    final response = await _repository.createFinanceFee({
      'name': draft.name,
      'amount': draft.amount.round(),
      'scope': draft.scope ?? 'establishment',
      'cycle': draft.cycle,
      'levelId': draft.levelId,
      'classId': draft.classId,
      'academicYearId': academicYearId,
      'description': draft.description ?? '',
      'type': draft.type ?? 'tuition',
      'frequency': draft.frequency ?? 'monthly',
    });
    final fee =
        FeeModel.fromJson(Map<String, dynamic>.from(response['fee'] as Map));
    final assignments = List<Map<String, dynamic>>.from(
        (response['assignments'] as List? ?? const [])
            .map((item) => Map<String, dynamic>.from(item as Map)));
    _financeFees.removeWhere((item) => item.id == fee.id);
    _financeFees.add(fee);
    for (final payload in assignments) {
      final assignment = FinanceFeeAssignmentModel.fromJson(payload);
      _financeFeeAssignments.removeWhere((item) => item.id == assignment.id);
      _financeFeeAssignments.add(assignment);
    }
    await _saveAllAsync();
    notifyListeners();
    return fee;
  }

  Future<FinanceReceiptModel> receiveFinancePaymentRemote({
    required String registrationId,
    required String feeAssignmentId,
    required double amount,
    required String paymentMethod,
    String? reference,
    String? note,
  }) async {
    final response = await _repository.createFinancePayment({
      'registrationId': registrationId,
      'feeAssignmentId': feeAssignmentId,
      'amount': amount.round(),
      'paymentMethod': paymentMethod,
      'reference': reference?.trim().isEmpty == true ? null : reference?.trim(),
      'note': note?.trim().isEmpty == true ? null : note?.trim(),
    });
    final payment = FinancePaymentModel.fromJson(
        Map<String, dynamic>.from(response['payment'] as Map));
    final receipt = FinanceReceiptModel.fromJson(
        Map<String, dynamic>.from(response['receipt'] as Map));
    _financePayments.removeWhere((item) => item.id == payment.id);
    _financePayments.add(payment);
    _financeReceipts.removeWhere((item) => item.id == receipt.id);
    _financeReceipts.add(receipt);
    await _saveAllAsync();
    notifyListeners();
    return receipt;
  }

  Future<Map<String, dynamic>> searchFinanceStudentByMatricule(
          String matricule) =>
      _repository.financeStudentByMatricule(matricule.trim());

  Future<Map<String, dynamic>> loadFinanceSummary() =>
      _repository.financeSummary(
          academicYearId: getSelectedAcademicYearId(),
          schoolId: getCurrentSchool()?.id);

  Future<Map<String, dynamic>> loadSchoolFinance(Map<String, String> query) =>
      _repository.financeWorkspace(query);
  Future<Map<String, dynamic>> loadFinanceMonthlySituation(
          String registrationId, Map<String, String> query) =>
      _repository.financeMonthlySituation(registrationId, query);
  Future<Map<String, dynamic>> paySchoolFinance(Map<String, dynamic> body) =>
      _repository.schoolFinancePayment(body);
  Future<Map<String, dynamic>> saveFinanceTariff(Map<String, dynamic> body,
          {String? id}) =>
      id == null
          ? _repository.createFinanceFee(body)
          : _repository.updateFinanceTariff(id, body);
  Future<Map<String, dynamic>> fetchFinanceReceipt(
          String id, String? schoolId) =>
      _repository.financeReceipt(id, schoolId);
  Future<void> cancelSchoolPayment(
      String id, String reason, String? schoolId) async {
    await _repository.cancelFinancePaymentRemote(id, reason,
        schoolId: schoolId);
  }

  Future<bool> cancelFinancePaymentRemote(String paymentId,
      {String reason = 'Annulation administrative'}) async {
    final payment = getFinancePaymentById(paymentId);
    if (payment == null ||
        (!isSuperAdmin() && payment.schoolId != _currentUser?.schoolId)) {
      return false;
    }
    final response = await _repository.cancelFinancePaymentRemote(
        paymentId, reason,
        schoolId: isSuperAdmin() ? payment.schoolId : null);
    final index = _financePayments.indexWhere((item) => item.id == paymentId);
    if (index >= 0) {
      _financePayments[index] = FinancePaymentModel.fromJson(response);
    }
    final receiptIndex =
        _financeReceipts.indexWhere((item) => item.paymentId == paymentId);
    if (receiptIndex >= 0) {
      final receipt = _financeReceipts[receiptIndex];
      _financeReceipts[receiptIndex] = FinanceReceiptModel(
        id: receipt.id,
        paymentId: receipt.paymentId,
        receiptNumber: receipt.receiptNumber,
        date: receipt.date,
        studentId: receipt.studentId,
        studentName: receipt.studentName,
        amount: receipt.amount,
        schoolId: receipt.schoolId,
        status: 'cancelled',
        institutionId: receipt.institutionId,
        academicYearId: receipt.academicYearId,
      );
    }
    await _saveAllAsync();
    notifyListeners();
    return true;
  }

  List<DocumentModel> getDocuments() {
    if (isSuperAdmin()) return List.unmodifiable(_documents);
    return _documents
        .where((item) => item.schoolId == _currentUser?.schoolId)
        .toList();
  }

  Future<List<Map<String, dynamic>>> documentsRemote() =>
      _repository.schoolDocuments();

  Future<DocumentModel> createDocumentRemote({
    required String title,
    required String type,
    String? entityId,
    Map<String, dynamic> metadata = const {},
    String? schoolId,
  }) async {
    final response = await _repository.createSchoolDocument({
      if (schoolId != null) 'schoolId': schoolId,
      'title': title,
      'type': type,
      'entityId': entityId,
      'academicYearId': _selectedAcademicYearId ?? getActiveAcademicYear()?.id,
      'metadata': metadata,
    });
    final document = DocumentModel.fromJson(response);
    _documents.removeWhere((item) => item.id == document.id);
    _documents.add(document);
    await _saveAllAsync();
    notifyListeners();
    return document;
  }

  void addFinanceFee(FeeModel fee) {
    _financeFees.add(fee);
    _applyFeeToMatchingRegistrations(fee);
    _saveAll();
    notifyListeners();
  }

  /// Migration helper: convert legacy fees that only used className/level into explicit scope fields
  /// Returns the number of migrated fee records.
  int migrateLegacyFeesToScope() {
    var migrated = 0;
    for (var i = 0; i < _financeFees.length; i++) {
      final f = _financeFees[i];
      final hasScope = f.scope != null && f.scope!.isNotEmpty;
      if (hasScope) continue;

      // Determine a sensible scope based on legacy fields
      String newScope = 'establishment';
      String? newClassId = f.classId;
      String? newLevelId = f.levelId;

      if (f.className != null && f.className!.isNotEmpty) {
        // Prefer resolving className -> classId when possible
        final cls = getClassByName(f.className);
        if (cls != null) {
          newScope = 'class';
          newClassId = cls.id;
        } else {
          // keep as class-scoped but classId unknown
          newScope = 'class';
        }
      } else if (f.levelId != null && f.levelId!.isNotEmpty) {
        newScope = 'level';
        newLevelId = f.levelId;
      } else if (f.level != null && f.level!.isNotEmpty) {
        // try to resolve level name to id
        final matched = getSchoolLevels()
            .where((l) => l.name.toLowerCase() == f.level!.toLowerCase())
            .toList();
        if (matched.isNotEmpty) {
          newScope = 'level';
          newLevelId = matched.first.id;
        } else {
          newScope = 'level';
        }
      } else if (f.cycle != null && f.cycle!.isNotEmpty) {
        newScope = 'cycle';
      } else {
        newScope = 'establishment';
      }

      final updated = FeeModel(
        id: f.id,
        name: f.name,
        amount: f.amount,
        className: f.className,
        level: f.level,
        scope: newScope,
        cycle: f.cycle,
        levelId: newLevelId,
        classId: newClassId,
        description: f.description,
        schoolId: f.schoolId,
        institutionId: f.institutionId,
        academicYearId: f.academicYearId,
        type: f.type,
        isMandatoryAtRegistration: f.isMandatoryAtRegistration,
        isOccasional: f.isOccasional,
        frequency: f.frequency,
        applicableTo: f.applicableTo,
        status: f.status,
      );

      _financeFees[i] = updated;
      migrated++;
    }

    if (migrated > 0) {
      _saveAll();
      notifyListeners();
    }

    return migrated;
  }

  /// Preview migration without persisting changes. Returns a list of suggested updates.
  List<Map<String, dynamic>> previewLegacyFeeMigration() {
    final preview = <Map<String, dynamic>>[];
    for (final f in _financeFees) {
      final hasScope = f.scope != null && f.scope!.isNotEmpty;
      if (hasScope) continue;

      String newScope = 'establishment';
      String? newClassId = f.classId;
      String? newLevelId = f.levelId;

      if (f.className != null && f.className!.isNotEmpty) {
        final cls = getClassByName(f.className);
        if (cls != null) {
          newScope = 'class';
          newClassId = cls.id;
        } else {
          newScope = 'class';
        }
      } else if (f.levelId != null && f.levelId!.isNotEmpty) {
        newScope = 'level';
        newLevelId = f.levelId;
      } else if (f.level != null && f.level!.isNotEmpty) {
        final matched = getSchoolLevels()
            .where((l) => l.name.toLowerCase() == f.level!.toLowerCase())
            .toList();
        if (matched.isNotEmpty) {
          newScope = 'level';
          newLevelId = matched.first.id;
        } else {
          newScope = 'level';
        }
      } else if (f.cycle != null && f.cycle!.isNotEmpty) {
        newScope = 'cycle';
      } else {
        newScope = 'establishment';
      }

      preview.add({
        'feeId': f.id,
        'name': f.name,
        'currentScope': f.scope,
        'suggestedScope': newScope,
        'suggestedClassId': newClassId,
        'suggestedLevelId': newLevelId,
        'cycle': f.cycle,
      });
    }
    return preview;
  }

  void updateFinanceFee(FeeModel fee) {
    final idx = _financeFees.indexWhere((f) => f.id == fee.id);
    if (idx != -1) {
      _financeFees[idx] = fee;
      _applyFeeToMatchingRegistrations(fee);
      _saveAll();
      notifyListeners();
    }
  }

  bool deleteFinanceFee(String feeId) {
    final linkedAssignments =
        _financeFeeAssignments.where((a) => a.feeId == feeId).toList();
    final linkedPayments = _financePayments
        .where((p) => linkedAssignments.any((a) => a.id == p.feeAssignmentId))
        .toList();
    if (linkedAssignments.isNotEmpty || linkedPayments.isNotEmpty) {
      return false;
    }
    _financeFees.removeWhere((f) => f.id == feeId);
    _saveAll();
    notifyListeners();
    return true;
  }

  bool addFinancePayment(FinancePaymentModel payment) {
    if (payment.registrationId.trim().isEmpty) return false;
    final registration = getFinanceRegistrationById(payment.registrationId);
    if (registration == null) return false;
    if (payment.studentId.trim().isEmpty ||
        payment.studentId != registration.studentId) return false;
    if (payment.feeAssignmentId != null &&
        payment.feeAssignmentId!.trim().isNotEmpty) {
      final assignment = _financeFeeAssignments.firstWhere(
        (a) => a.id == payment.feeAssignmentId,
        orElse: () => FinanceFeeAssignmentModel(
            id: '',
            registrationId: '',
            feeId: '',
            studentId: '',
            studentName: '',
            amount: 0),
      );
      if (assignment.id.isEmpty ||
          assignment.registrationId != payment.registrationId ||
          assignment.studentId != payment.studentId) {
        return false;
      }
      final remaining = getRemainingForAssignment(assignment.id);
      if (payment.amount > remaining + 1e-9) return false;
    }
    _financePayments.add(payment);

    // Mirror into FinancialPaymentRecord when possible (link to FinancialLine)
    var _mirroredFprCreated = false;
    try {
      if (payment.feeAssignmentId != null &&
          payment.feeAssignmentId!.isNotEmpty) {
        final assignment = _financeFeeAssignments.firstWhere(
            (a) => a.id == payment.feeAssignmentId,
            orElse: () => FinanceFeeAssignmentModel(
                id: '',
                registrationId: '',
                feeId: '',
                studentId: '',
                studentName: '',
                amount: 0));
        if (assignment.id.isNotEmpty) {
          final acc =
              getFinancialAccountByRegistration(assignment.registrationId);
          if (acc != null) {
            final line =
                getFinancialLineByFeeAndAccount(assignment.feeId, acc.id);
            if (line != null) {
              final fpr = FinancialPaymentRecord(
                id: IdGenerator.generate('FPR',
                    existingCount: _financialPaymentsRecords.length),
                financialLineId: line.id,
                studentId: payment.studentId,
                amount: payment.amount,
                date: payment.date,
                paymentMethod: payment.paymentMethod,
                reference: payment.reference,
                status: payment.status,
              );
              _financialPaymentsRecords.add(fpr);
              _mirroredFprCreated = true;
            }
          }
        }
      }
    } catch (_) {}

    // If not mirrored to a specific FinancialLine (e.g., unallocated payment), still record it as an unallocated FinancialPaymentRecord
    try {
      if (!_mirroredFprCreated) {
        final fpr = FinancialPaymentRecord(
          id: IdGenerator.generate('FPR',
              existingCount: _financialPaymentsRecords.length),
          financialLineId: payment.feeAssignmentId ?? '',
          studentId: payment.studentId,
          amount: payment.amount,
          date: payment.date,
          paymentMethod: payment.paymentMethod,
          reference: payment.reference,
          status: payment.status,
        );
        _financialPaymentsRecords.add(fpr);
      }
    } catch (_) {}

    _saveAll();
    notifyListeners();
    return true;
  }

  void updateFinancePayment(FinancePaymentModel payment) {
    final idx = _financePayments.indexWhere((p) => p.id == payment.id);
    if (idx != -1) {
      _financePayments[idx] = payment;
      _saveAll();
      notifyListeners();
    }
  }

  void deleteFinancePayment(String paymentId) {
    // Prefer audit-friendly cancellation. Mark legacy payment cancelled and mirror cancellation to FinancialPaymentRecords.
    final cancelled = cancelFinancePayment(paymentId,
        reason: 'deleted via deleteFinancePayment()');
    if (!cancelled) return;

    // Also cancel any mirrored financial payment records that likely correspond
    try {
      final p = getFinancePaymentById(paymentId);
      if (p != null) {
        final matches = _financialPaymentsRecords
            .where((r) =>
                r.studentId == p.studentId &&
                (r.amount - p.amount).abs() < 1e-6 &&
                r.date == p.date &&
                r.status.toLowerCase() == 'active')
            .toList();
        for (final r in matches) {
          cancelFinancialPaymentRecord(r.id, reason: 'Legacy payment deleted');
        }
      }
    } catch (_) {}

    _saveAll();
    notifyListeners();
  }

  void addFinanceReceipt(FinanceReceiptModel receipt) {
    _financeReceipts.add(receipt);
    _saveAll();
    notifyListeners();
  }

  void updateFinanceReceipt(FinanceReceiptModel receipt) {
    final idx = _financeReceipts.indexWhere((r) => r.id == receipt.id);
    if (idx != -1) {
      _financeReceipts[idx] = receipt;
      _saveAll();
      notifyListeners();
    }
  }

  void deleteFinanceReceipt(String receiptId) {
    _financeReceipts.removeWhere((r) => r.id == receiptId);
    _saveAll();
    notifyListeners();
  }

  /// Add a student inscription (Scolarité). This is separate from the financial registration/account.
  void addStudentRegistration(StudentRegistrationModel registration) {
    _studentRegistrations.add(registration);
    _saveAll();
    notifyListeners();
  }

  /// Validate a student inscription. When validated, a financial registration/account
  /// is created for the student for the given academic year (if createFinance==true).
  bool validateStudentRegistration(String registrationId,
      {bool createFinance = true}) {
    final idx = _studentRegistrations.indexWhere((r) => r.id == registrationId);
    if (idx == -1) return false;
    final reg = _studentRegistrations[idx];
    reg.status = 'validated';
    _studentRegistrations[idx] = reg;
    _saveAll();
    notifyListeners();

    if (!createFinance) return true;

    // Build and create the finance registration/account from this validated inscription
    final currentClass = reg.classId != null && reg.classId!.isNotEmpty
        ? getClassById(reg.classId!)
        : (reg.className != null ? getClassByName(reg.className!) : null);
    final defaultFeeIds = getDefaultFeeIdsForRegistration(
      classId: currentClass?.id ?? reg.classId,
      className: currentClass?.name ?? reg.className,
      schoolId: reg.schoolId ?? currentClass?.schoolId,
      academicYearId: reg.academicYearId,
    );
    final effectiveFeeIds = <String>{...reg.feeIds, ...defaultFeeIds}.toList();

    final finReg = FinanceRegistrationModel(
      id: IdGenerator.generate('REG',
          existingCount: _financeRegistrations.length),
      studentId: reg.studentId,
      studentName: reg.studentName,
      className: reg.className ?? currentClass?.name,
      classId: reg.classId ?? currentClass?.id,
      feeIds: effectiveFeeIds,
      schoolId: reg.schoolId,
      institutionId: reg.institutionId,
      academicYearId: reg.academicYearId,
      type: reg.type,
      createdAt: reg.registrationDate ??
          reg.createdAt ??
          DateTime.now().toIso8601String(),
      facultyId: reg.facultyId,
      departmentId: reg.departmentId,
      programId: reg.programId,
      optionId: reg.optionId,
      levelId: reg.levelId ?? currentClass?.levelId,
      status: 'active',
    );

    addFinanceRegistration(finReg);
    return true;
  }

  void addFinanceRegistration(FinanceRegistrationModel registration) {
    final currentClass =
        registration.classId != null && registration.classId!.isNotEmpty
            ? getClassById(registration.classId!)
            : (registration.className != null
                ? getClassByName(registration.className!)
                : null);
    final defaultFeeIds = getDefaultFeeIdsForRegistration(
      classId: currentClass?.id ?? registration.classId,
      className: currentClass?.name ?? registration.className,
      schoolId: registration.schoolId ?? currentClass?.schoolId,
      academicYearId: registration.academicYearId,
    );
    final effectiveFeeIds =
        <String>{...registration.feeIds, ...defaultFeeIds}.toList();
    final effectiveRegistration = FinanceRegistrationModel(
      id: registration.id,
      studentId: registration.studentId,
      studentName: registration.studentName,
      className: registration.className ?? currentClass?.name,
      classId: registration.classId ?? currentClass?.id,
      feeIds: effectiveFeeIds,
      schoolId: registration.schoolId,
      institutionId: registration.institutionId,
      academicYearId: registration.academicYearId,
      type: registration.type,
      createdAt: registration.createdAt,
      facultyId: registration.facultyId,
      departmentId: registration.departmentId,
      programId: registration.programId,
      optionId: registration.optionId,
      levelId: registration.levelId ?? currentClass?.levelId,
      status: registration.status,
    );

    _financeRegistrations.add(effectiveRegistration);
    try {
      _logAction(
          'CREATE_REGISTRATION', 'registration', effectiveRegistration.id,
          oldValue: null, newValue: effectiveRegistration.toJson());
    } catch (_) {}
    _createFeeAssignmentsForRegistration(effectiveRegistration);
    _saveAll();
    notifyListeners();
  }

  void updateFinanceRegistration(FinanceRegistrationModel registration) {
    final idx =
        _financeRegistrations.indexWhere((r) => r.id == registration.id);
    if (idx != -1) {
      final currentClass =
          registration.classId != null && registration.classId!.isNotEmpty
              ? getClassById(registration.classId!)
              : (registration.className != null
                  ? getClassByName(registration.className!)
                  : null);
      final defaultFeeIds = getDefaultFeeIdsForRegistration(
        classId: currentClass?.id ?? registration.classId,
        className: currentClass?.name ?? registration.className,
        schoolId: registration.schoolId ?? currentClass?.schoolId,
        academicYearId: registration.academicYearId,
      );
      final effectiveRegistration = FinanceRegistrationModel(
        id: registration.id,
        studentId: registration.studentId,
        studentName: registration.studentName,
        className: registration.className ?? currentClass?.name,
        classId: registration.classId ?? currentClass?.id,
        feeIds: <String>{...registration.feeIds, ...defaultFeeIds}.toList(),
        schoolId: registration.schoolId,
        institutionId: registration.institutionId,
        academicYearId: registration.academicYearId,
        type: registration.type,
        createdAt: registration.createdAt,
        facultyId: registration.facultyId,
        departmentId: registration.departmentId,
        programId: registration.programId,
        optionId: registration.optionId,
        levelId: registration.levelId ?? currentClass?.levelId,
        status: registration.status,
      );
      _financeRegistrations[idx] = effectiveRegistration;
      deleteFinanceFeeAssignmentsByRegistration(effectiveRegistration.id);
      _createFeeAssignmentsForRegistration(effectiveRegistration);
      _saveAll();
      notifyListeners();
    }
  }

  void deleteFinanceRegistration(String registrationId) {
    _financeRegistrations.removeWhere((r) => r.id == registrationId);
    // do not delete historical payments/receipts; remove assignments for this registration
    deleteFinanceFeeAssignmentsByRegistration(registrationId);
    _saveAll();
    notifyListeners();
  }

  void addFinanceFeeAssignment(FinanceFeeAssignmentModel assignment) {
    _financeFeeAssignments.add(assignment);
    _saveAll();
    notifyListeners();
  }

  void _createFeeAssignmentsForRegistration(
      FinanceRegistrationModel registration) {
    final assignedFeeIds = <String>{};
    for (final feeId in registration.feeIds) {
      if (assignedFeeIds.contains(feeId)) continue;
      assignedFeeIds.add(feeId);
      final exists = _financeFeeAssignments.any((a) =>
          a.registrationId == registration.id &&
          a.feeId == feeId &&
          a.studentId == registration.studentId);
      if (exists) continue;
      final feeDef = _financeFees.firstWhere((f) => f.id == feeId,
          orElse: () => FeeModel(id: '', name: '', amount: 0));
      if (feeDef.id.isEmpty) continue;
      final assignment = FinanceFeeAssignmentModel(
        id: IdGenerator.generate('FA',
            existingCount: _financeFeeAssignments.length),
        registrationId: registration.id,
        feeId: feeDef.id,
        studentId: registration.studentId,
        studentName: registration.studentName,
        amount: feeDef.amount,
        dueDate: null,
        schoolId: registration.schoolId,
        institutionId: registration.institutionId,
        academicYearId: registration.academicYearId,
        status: 'assigned',
      );
      _financeFeeAssignments.add(assignment);

      // Create FinancialLine in FinancialAccount for this registration if not present
      try {
        FinancialAccountModel? acc =
            getFinancialAccountByRegistration(registration.id);
        if (acc == null) {
          final accId = createFinancialAccountForRegistration(registration);
          acc = _financialAccounts.firstWhere((a) => a.id == accId,
              orElse: () => FinancialAccountModel(id: '', studentId: ''));
        }
        if (acc.id.isNotEmpty) {
          final existingLine =
              getFinancialLineByFeeAndAccount(feeDef.id, acc.id);
          if (existingLine == null) {
            final line = FinancialLineModel(
              id: IdGenerator.generate('FL',
                  existingCount: _financialLines.length),
              financialAccountId: acc.id,
              feeId: feeDef.id,
              label: feeDef.name,
              amountDue: feeDef.amount,
            );
            _financialLines.add(line);
          }
        }
      } catch (_) {}
    }
    _saveAll();
    notifyListeners();
  }

  List<FinancePaymentModel> getPaymentsByAssignment(String assignmentId) {
    return _financePayments
        .where((p) => p.feeAssignmentId == assignmentId)
        .toList();
  }

  double getTotalPaidForAssignment(String assignmentId) {
    final payments = getPaymentsByAssignment(assignmentId);
    // Only consider active payments in totals; cancelled payments are kept for history but ignored in balances
    final active = payments.where((p) => p.status.toLowerCase() == 'active');
    return active.fold<double>(0, (sum, p) => sum + p.amount);
  }

  double getRemainingForAssignment(String assignmentId) {
    final assignment = _financeFeeAssignments.firstWhere(
        (a) => a.id == assignmentId,
        orElse: () => FinanceFeeAssignmentModel(
            id: '',
            registrationId: '',
            feeId: '',
            studentId: '',
            studentName: '',
            amount: 0));
    if (assignment.id.isEmpty) return 0;
    final totalPaid = getTotalPaidForAssignment(assignmentId);
    final rem = assignment.amount - totalPaid;
    return rem < 0 ? 0 : rem;
  }

  /// Sum remaining amounts for all assignments of a registration
  double getTotalRemainingForRegistration(String registrationId) {
    final assignments = getFinanceFeeAssignmentsByRegistration(registrationId);
    return assignments.fold<double>(
        0, (sum, a) => sum + getRemainingForAssignment(a.id));
  }

  /// Reçoit un paiement pour une inscription et répartit automatiquement
  /// le montant sur les affectations de frais selon la règle:
  /// 1) frais échus (dueDate before now), 2) les plus anciens (dueDate asc), 3) autres
  /// Retourne la liste des reçus générés.
  List<FinanceReceiptModel> receivePayment({
    required String registrationId,
    required double amount,
    required String paymentMethod,
    String? reference,
    String? note,
    bool allowOverpayment = false,
  }) {
    final receipts = <FinanceReceiptModel>[];
    if (amount <= 0) return receipts;
    final reg = getFinanceRegistrationById(registrationId);
    if (reg == null) return receipts;

    final assignments = getFinanceFeeAssignmentsByRegistration(registrationId)
        .where((a) => getRemainingForAssignment(a.id) > 0)
        .toList();
    final now = DateTime.now();
    assignments.sort((a, b) {
      final aDue = a.dueDate != null ? DateTime.tryParse(a.dueDate!) : null;
      final bDue = b.dueDate != null ? DateTime.tryParse(b.dueDate!) : null;
      final aOver = aDue != null && aDue.isBefore(now);
      final bOver = bDue != null && bDue.isBefore(now);
      if (aOver != bOver) return aOver ? -1 : 1;
      if (aDue != null && bDue != null) return aDue.compareTo(bDue);
      if (aDue != null) return -1;
      if (bDue != null) return 1;
      return a.id.compareTo(b.id);
    });

    // Compute total remaining for this registration (sum of assignment.remaining)
    final totalRemaining = assignments.fold<double>(
        0, (s, a) => s + getRemainingForAssignment(a.id));
    if (!allowOverpayment && amount > totalRemaining && totalRemaining > 0) {
      // Refuse overpayment by default. Return empty receipts so callers can show a warning.
      return <FinanceReceiptModel>[];
    }

    var remainingAmount = amount;
    final studentId = reg.studentId;
    final studentName = reg.studentName;
    final schoolId = reg.schoolId;
    final today = DateTime.now().toIso8601String().split('T')[0];

    for (final a in assignments) {
      if (remainingAmount <= 0) break;
      final rem = getRemainingForAssignment(a.id);
      if (rem <= 0) continue;
      final take = rem <= remainingAmount ? rem : remainingAmount;
      final payId =
          IdGenerator.generate('PAY', existingCount: _financePayments.length);
      final payment = FinancePaymentModel(
        id: payId,
        registrationId: reg.id,
        feeAssignmentId: a.id,
        studentId: studentId,
        studentName: studentName,
        amount: take,
        date: today,
        paymentMethod: paymentMethod,
        reference: reference,
        receivedBy: _currentUser?.id ?? _currentUser?.name,
        note: note,
        schoolId: schoolId,
        academicYearId: reg.academicYearId,
      );
      addFinancePayment(payment);

      final receiptsCount = _financeReceipts.length;
      final receipt = FinanceReceiptModel(
        id: 'RC_${DateTime.now().millisecondsSinceEpoch.toString().substring(8)}',
        paymentId: payId,
        receiptNumber: IdGenerator.receiptNumber(receiptsCount),
        date: today,
        studentId: studentId,
        studentName: studentName,
        amount: take,
        schoolId: schoolId,
        academicYearId: reg.academicYearId,
      );
      addFinanceReceipt(receipt);
      // audit
      try {
        _logAction('RECEIVE_PAYMENT', 'payment', payId,
            oldValue: null, newValue: payment.toJson());
      } catch (_) {}

      receipts.add(receipt);
      remainingAmount -= take;
    }

    // If still remaining amount (overpayment), record as unallocated payment (feeAssignmentId=null)
    if (remainingAmount > 0) {
      final payId =
          'PAY_${DateTime.now().millisecondsSinceEpoch.toString().substring(8)}';
      final payment = FinancePaymentModel(
        id: payId,
        registrationId: reg.id,
        feeAssignmentId: null,
        studentId: reg.studentId,
        studentName: reg.studentName,
        amount: remainingAmount,
        date: DateTime.now().toIso8601String().split('T')[0],
        paymentMethod: paymentMethod,
        reference: reference,
        receivedBy: _currentUser?.id ?? _currentUser?.name,
        note: note,
        schoolId: reg.schoolId,
        academicYearId: reg.academicYearId,
      );
      addFinancePayment(payment);
      final receiptsCount = _financeReceipts.length;
      final receipt = FinanceReceiptModel(
        id: 'RC_${DateTime.now().millisecondsSinceEpoch.toString().substring(8)}',
        paymentId: payId,
        receiptNumber: IdGenerator.receiptNumber(receiptsCount),
        date: DateTime.now().toIso8601String().split('T')[0],
        studentId: reg.studentId,
        studentName: reg.studentName,
        amount: remainingAmount,
        schoolId: reg.schoolId,
        academicYearId: reg.academicYearId,
      );
      addFinanceReceipt(receipt);
      receipts.add(receipt);
    }

    return receipts;
  }

  String getAssignmentStatus(String assignmentId) {
    final assignment = _financeFeeAssignments.firstWhere(
        (a) => a.id == assignmentId,
        orElse: () => FinanceFeeAssignmentModel(
            id: '',
            registrationId: '',
            feeId: '',
            studentId: '',
            studentName: '',
            amount: 0));
    if (assignment.id.isEmpty) return 'UNPAID';
    final totalPaid = getTotalPaidForAssignment(assignmentId);
    if (totalPaid >= assignment.amount && assignment.amount > 0) return 'PAID';
    if (totalPaid > 0) return 'PARTIAL';
    return 'UNPAID';
  }

  List<FinancePaymentModel> getPaymentHistoryForAssignment(
      String assignmentId) {
    return getPaymentsByAssignment(assignmentId);
  }

  /// Assign a fee to registrations matching the provided filters.
  /// Filters: schoolId, className, level, studentIds, academicYearId
  void assignFeeToTargets({
    required String feeId,
    String? schoolId,
    String? classId,
    String? className,
    String? level,
    List<String>? studentIds,
    String? academicYearId,
  }) {
    final regs = _financeRegistrations.where((r) {
      if (schoolId != null && r.schoolId != schoolId) return false;
      if (academicYearId != null && r.academicYearId != academicYearId)
        return false;
      final normalizedStatus = r.status.trim();
      if (normalizedStatus.isNotEmpty &&
          normalizedStatus.toLowerCase() != 'active') return false;
      if (classId != null && classId.isNotEmpty && r.classId != classId)
        return false;
      if (className != null && className.isNotEmpty && r.className != className)
        return false;
      if (level != null && r.levelId != null && r.levelId != level) {
        final regClass = r.classId != null && r.classId!.isNotEmpty
            ? getClassById(r.classId!)
            : (r.className != null ? getClassByName(r.className!) : null);
        if (regClass == null || regClass.levelId != level) return false;
      }
      if (studentIds != null &&
          studentIds.isNotEmpty &&
          !studentIds.contains(r.studentId)) return false;
      return true;
    }).toList();

    for (final r in regs) {
      final exists = _financeFeeAssignments.any((a) =>
          a.registrationId == r.id &&
          a.feeId == feeId &&
          a.studentId == r.studentId);
      if (exists) continue;
      final feeDef = _financeFees.firstWhere((f) => f.id == feeId,
          orElse: () => FeeModel(id: '', name: '', amount: 0));
      if (feeDef.id.isEmpty) continue;
      final assignment = FinanceFeeAssignmentModel(
        id: IdGenerator.generate('FA',
            existingCount: _financeFeeAssignments.length),
        registrationId: r.id,
        feeId: feeDef.id,
        studentId: r.studentId,
        studentName: r.studentName,
        amount: feeDef.amount,
        dueDate: null,
        schoolId: r.schoolId,
        institutionId: r.institutionId,
        academicYearId: r.academicYearId,
      );
      _financeFeeAssignments.add(assignment);
    }
    _saveAll();
    notifyListeners();
  }

  List<FinanceFeeAssignmentModel> getAssignmentsByFee(String feeId) {
    return _financeFeeAssignments.where((a) => a.feeId == feeId).toList();
  }

  int getAssignedCountForFee(String feeId) {
    return getAssignmentsByFee(feeId).length;
  }

  double getTotalExpectedForFee(String feeId) {
    final assigns = getAssignmentsByFee(feeId);
    return assigns.fold<double>(0, (sum, a) => sum + a.amount);
  }

  double getCollectedForFee(String feeId) {
    final assigns = getAssignmentsByFee(feeId);
    double total = 0;
    for (final a in assigns) {
      total += getTotalPaidForAssignment(a.id);
    }
    return total;
  }

  double getOutstandingForFee(String feeId) {
    final expected = getTotalExpectedForFee(feeId);
    final collected = getCollectedForFee(feeId);
    final out = expected - collected;
    return out < 0 ? 0 : out;
  }

  void updateFinanceFeeAssignment(FinanceFeeAssignmentModel assignment) {
    final idx = _financeFeeAssignments.indexWhere((a) => a.id == assignment.id);
    if (idx != -1) {
      _financeFeeAssignments[idx] = assignment;
      _saveAll();
      notifyListeners();
    }
  }

  void deleteFinanceFeeAssignment(String assignmentId) {
    _financeFeeAssignments.removeWhere((a) => a.id == assignmentId);
    _saveAll();
    notifyListeners();
  }

  void deleteFinanceFeeAssignmentsByRegistration(String registrationId) {
    _financeFeeAssignments
        .removeWhere((a) => a.registrationId == registrationId);
    _saveAll();
    notifyListeners();
  }

  /// Update an existing class by id or name
  void updateClass(ClassModel cls) {
    final idx = _classes.indexWhere((c) => c.id == cls.id && c.id.isNotEmpty);
    final foundClass = idx != -1
        ? _classes[idx]
        : _classes.firstWhere((c) => c.name == cls.name,
            orElse: () => ClassModel(id: '', name: '', schoolId: ''));
    if (foundClass.id.isEmpty) return;

    final oldName = foundClass.name;
    _classes[_classes.indexWhere((c) => c.id == foundClass.id)] = cls;
    _updateRemote('classes', cls.id, cls.toJson());

    for (var i = 0; i < _students.length; i++) {
      if (_students[i].classId == foundClass.id ||
          _students[i].className == oldName) {
        _students[i] = _students[i].copyWith(
          classId: cls.id,
          className: cls.name,
          cycle: cls.cycle,
          level: cls.level,
          levelId: cls.levelId,
          grade: cls.grade,
          series: cls.series,
          seriesId: cls.seriesId,
        );
      }
    }

    if (oldName != cls.name) {
      for (var i = 0; i < _affectations.length; i++) {
        final affect = _affectations[i];
        if (affect.classId == cls.id || affect.className == oldName) {
          _affectations[i] = AffectationModel(
            id: affect.id,
            teacherId: affect.teacherId,
            teacherName: affect.teacherName,
            subjectId: affect.subjectId,
            subject: affect.subject,
            classId: cls.id,
            className: cls.name,
            schoolId: affect.schoolId,
            institutionId: affect.institutionId,
            academicYearId: affect.academicYearId,
            type: affect.type,
          );
        }
      }
    }

    // Remove stale main_teacher affectation if this class is now unassigned.
    if (foundClass.mainTeacher != null && cls.mainTeacher == null) {
      _affectations
          .removeWhere((a) => a.classId == cls.id && a.type == 'main_teacher');
    }

    _saveAll();
    notifyListeners();
  }

  void addSubject(SubjectModel subject) {
    _subjects.add(subject);
    _createRemote('subjects', subject.toJson());
    _saveAll();
    notifyListeners();
  }

  bool addAffectation(AffectationModel affectation) {
    if (hasDuplicateAffectation(affectation)) {
      return false;
    }
    // Maintain one main_teacher per class
    if (affectation.type == 'main_teacher' && affectation.classId != null) {
      _affectations.removeWhere(
          (a) => a.classId == affectation.classId && a.type == 'main_teacher');
      final cls = _classes.firstWhere((c) => c.id == affectation.classId,
          orElse: () => ClassModel(
              id: '',
              name: affectation.className ?? '',
              schoolId: affectation.schoolId));
      if (cls.id.isNotEmpty) {
        final updated = cls.copyWith(mainTeacher: affectation.teacherName);
        updateClass(updated);
      }
    }

    _affectations.add(affectation);
    _saveAll();
    notifyListeners();
    return true;
  }

  /// Update an affectation by id
  bool updateAffectation(AffectationModel affectation) {
    final idx = _affectations.indexWhere((a) => a.id == affectation.id);
    if (idx == -1) return false;
    if (hasDuplicateAffectation(affectation, excludeId: affectation.id)) {
      return false;
    }

    final old = _affectations[idx];
    if (old.type == 'main_teacher' &&
        old.classId != null &&
        affectation.type != 'main_teacher') {
      final oldClass = _classes.firstWhere((c) => c.id == old.classId,
          orElse: () => ClassModel(
              id: '', name: old.className ?? '', schoolId: old.schoolId));
      if (oldClass.id.isNotEmpty) {
        updateClass(oldClass.copyWith(mainTeacher: null));
      }
    }

    if (affectation.type == 'main_teacher' && affectation.classId != null) {
      _affectations.removeWhere((a) =>
          a.id != affectation.id &&
          a.classId == affectation.classId &&
          a.type == 'main_teacher');
    }

    _affectations[idx] = affectation;
    if (affectation.type == 'main_teacher' && affectation.classId != null) {
      final cls = _classes.firstWhere((c) => c.id == affectation.classId,
          orElse: () => ClassModel(
              id: '',
              name: affectation.className ?? '',
              schoolId: affectation.schoolId));
      if (cls.id.isNotEmpty) {
        updateClass(cls.copyWith(mainTeacher: affectation.teacherName));
      }
    }

    _saveAll();
    notifyListeners();
    return true;
  }

  /// Supprime une affectation par id
  void deleteAffectation(String affectationId) {
    final affect = _affectations.firstWhere((a) => a.id == affectationId,
        orElse: () => AffectationModel(id: '', teacherId: '', schoolId: ''));
    _affectations.removeWhere((a) => a.id == affectationId);
    if (affect.id.isNotEmpty &&
        affect.type == 'main_teacher' &&
        affect.classId != null) {
      final cls = _classes.firstWhere((c) => c.id == affect.classId,
          orElse: () => ClassModel(
              id: '', name: affect.className ?? '', schoolId: affect.schoolId));
      if (cls.id.isNotEmpty) {
        final stillMain = _affectations.any(
            (a) => a.classId == affect.classId && a.type == 'main_teacher');
        if (!stillMain) {
          updateClass(cls.copyWith(mainTeacher: null));
        }
      }
    }
    _saveAll();
    notifyListeners();
  }

  void updateSubject(SubjectModel subject) {
    final idx = _subjects.indexWhere((s) => s.id == subject.id);
    if (idx != -1) {
      _subjects[idx] = subject;
      _updateRemote('subjects', subject.id, subject.toJson());
      for (var i = 0; i < _affectations.length; i++) {
        if (_affectations[i].subjectId == subject.id) {
          final affect = _affectations[i];
          _affectations[i] = AffectationModel(
            id: affect.id,
            teacherId: affect.teacherId,
            teacherName: affect.teacherName,
            subjectId: affect.subjectId,
            subject: subject.name,
            classId: affect.classId,
            className: affect.className,
            schoolId: affect.schoolId,
            institutionId: affect.institutionId,
            academicYearId: affect.academicYearId,
            type: affect.type,
          );
        }
      }
      _saveAll();
      notifyListeners();
    }
  }

  void deleteSubject(String subjectId) {
    _deleteRemote('subjects', subjectId);
    final subject = _subjects.firstWhere((s) => s.id == subjectId,
        orElse: () =>
            SubjectModel(id: '', name: '', coefficient: 1, schoolId: ''));
    _subjects.removeWhere((s) => s.id == subjectId);
    // Remove affectations referring to this subject
    _affectations.removeWhere(
        (a) => a.subjectId == subjectId || a.subject == subject.name);
    _saveAll();
    notifyListeners();
  }

  void deleteClass(String classId) {
    final cls = _classes.firstWhere((c) => c.id == classId,
        orElse: () => ClassModel(id: '', name: '', schoolId: ''));
    if (cls.id.isEmpty) return;
    _deleteRemote('classes', classId);

    _classes.removeWhere((c) => c.id == classId);
    _affectations
        .removeWhere((a) => a.classId == classId || a.className == cls.name);
    for (var i = 0; i < _students.length; i++) {
      if (_students[i].classId == cls.id ||
          _students[i].className == cls.name) {
        _students[i] = _students[i].copyWith(
          classId: null,
          className: null,
          level: null,
          grade: null,
          series: null,
        );
      }
    }
    _saveAll();
    notifyListeners();
  }

  Future<bool> toggleEstablishmentStatus(String schoolId) async {
    final idx = _establishments.indexWhere((e) => e.id == schoolId);
    if (idx != -1) {
      final e = _establishments[idx];
      final previous = e.status;
      e.status = e.status == 'active' ? 'suspended' : 'active';
      if (!await updateManagedEstablishment(e)) {
        e.status = previous;
        return false;
      }
      return true;
    }
    return false;
  }
}

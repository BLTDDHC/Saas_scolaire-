import 'dart:convert';

import 'package:edupro_flutter_web/data/datasources/api_client.dart';
import 'package:edupro_flutter_web/data/models/education/school_cycle_model.dart';
import 'package:edupro_flutter_web/data/models/establishment_model.dart';
import 'package:edupro_flutter_web/data/services/store_service.dart';
import 'package:edupro_flutter_web/features/superadmin/establishments_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> establishment(
        {required String id,
        required String name,
        required String status,
        required String city}) =>
    {
      'id': id,
      'databaseId': '00000000-0000-0000-0000-00000000000$id',
      'name': name,
      'code': 'E$id',
      'type': 'Lycée',
      'institutionType': 'high_school',
      'city': city,
      'country': 'Congo',
      'status': status,
      'date': '2026-08-23',
      'createdAt': '2026-08-23T08:00:00Z',
      'plan': 'pro',
      'enabledModules': ['students', 'teachers'],
      'planFeatures': ['students', 'teachers', 'grades'],
      'planFeatureLabels': ['Élèves', 'Enseignants', 'Notes'],
      'enabledModuleLabels': ['Élèves', 'Enseignants'],
      'cycles': [
        {
          'id': '20000000-0000-0000-0000-00000000000$id',
          'schoolId': id,
          'code': 'PRIMAIRE',
          'name': 'Primaire',
          'status': 'active',
          'sortOrder': 20,
        },
        {
          'id': '30000000-0000-0000-0000-00000000000$id',
          'schoolId': id,
          'code': 'COLLEGE',
          'name': 'Collège',
          'status': 'active',
          'sortOrder': 30,
        },
      ],
      'administrator': {
        'id': '10000000-0000-0000-0000-00000000000$id',
        'name': 'Admin $name',
        'email': 'admin$id@school.test',
        'phone': '+242 06000000$id',
        'status': 'active',
        'mustChangePassword': true,
      },
      'subscription': {
        'id': 'SUB_$id',
        'plan': 'PRO',
        'price': '25000 FCFA',
        'startDate': '2026-08-23',
        'endDate': '2027-08-23',
        'status': 'active',
      },
    };

class Backend {
  Backend({this.failFirst = false, this.empty = false});

  bool failFirst;
  bool empty;
  int listCalls = 0;
  int moduleGetCalls = 0;
  String? lastSearch;
  String? lastStatus;
  Map<String, dynamic>? lastCreationPayload;
  List<String> moduleState = ['students'];

  late final rows = <Map<String, dynamic>>[
    establishment(id: '1', name: 'Lycée Alpha', status: 'active', city: 'Oyo'),
    establishment(
        id: '2', name: 'Lycée Beta', status: 'suspended', city: 'Dolisie'),
  ];

  MockClient client() => MockClient((request) async {
        if (request.url.path == '/api/v1/superadmin/establishments' &&
            request.method == 'GET') {
          listCalls++;
          if (failFirst) {
            failFirst = false;
            return http.Response(jsonEncode({'detail': 'Erreur test'}), 500);
          }
          lastSearch = request.url.queryParameters['search'];
          lastStatus = request.url.queryParameters['status_filter'];
          if (empty) return http.Response('[]', 200);
          var result = List<Map<String, dynamic>>.from(rows);
          if (lastSearch?.isNotEmpty ?? false) {
            final query = lastSearch!.toLowerCase();
            result = result
                .where((item) => [
                      item['name'],
                      item['city'],
                      (item['administrator'] as Map)['name'],
                    ].any((value) =>
                        value.toString().toLowerCase().contains(query)))
                .toList();
          }
          if (lastStatus != null) {
            result =
                result.where((item) => item['status'] == lastStatus).toList();
          }
          return http.Response(jsonEncode(result), 200);
        }
        if (request.url.path == '/api/v1/superadmin/establishments' &&
            request.method == 'POST') {
          lastCreationPayload =
              Map<String, dynamic>.from(jsonDecode(request.body) as Map);
          final created = establishment(
              id: '3',
              name: lastCreationPayload!['name'],
              status: 'active',
              city: lastCreationPayload!['city']);
          created['code'] = lastCreationPayload!['code'];
          created['code'] = lastCreationPayload!['code'];
          created['cycles'] = [
            {
              'id': 'cycle-primary',
              'schoolId': '3',
              'code': 'PRIMAIRE',
              'name': 'Primaire',
              'status': 'active',
              'sortOrder': 20,
            },
            {
              'id': 'cycle-college',
              'schoolId': '3',
              'code': 'COLLEGE',
              'name': 'Collège',
              'status': 'active',
              'sortOrder': 30,
            },
          ];
          return http.Response(
              jsonEncode({
                'establishment': created,
                'administrator': created['administrator'],
                'initialPassword': 'temporary-test-value',
              }),
              201);
        }
        if (request.url.path == '/api/v1/bootstrap') {
          return http.Response(
              jsonEncode({
                'establishments': rows,
                'cycles': [],
                'school-levels': [],
              }),
              200);
        }
        if (request.url.path.endsWith('/modules') && request.method == 'GET') {
          moduleGetCalls++;
          return http.Response(
              jsonEncode({
                'establishment': {
                  'id': '1',
                  'name': 'Lycée Alpha',
                  'status': 'active'
                },
                'availableModules': [
                  {'id': 'students', 'label': 'Élèves'},
                  {'id': 'teachers', 'label': 'Enseignants'},
                ],
                'currentPlan': {
                  'id': 'plan-pro',
                  'name': 'PRO',
                  'status': 'active'
                },
                'planFeatures': ['students', 'teachers'],
                'enabledModules': moduleState,
              }),
              200);
        }
        if (request.url.path.endsWith('/modules') && request.method == 'PUT') {
          moduleState = List<String>.from(
              (jsonDecode(request.body) as Map)['enabledModules']);
          return http.Response(
              jsonEncode({
                'establishment': {
                  'id': '1',
                  'name': 'Lycée Alpha',
                  'status': 'active'
                },
                'availableModules': [
                  {'id': 'students', 'label': 'Élèves'},
                  {'id': 'teachers', 'label': 'Enseignants'},
                ],
                'currentPlan': {
                  'id': 'plan-pro',
                  'name': 'PRO',
                  'status': 'active'
                },
                'planFeatures': ['students', 'teachers'],
                'enabledModules': moduleState,
              }),
              200);
        }
        if (request.url.path.startsWith('/api/v1/superadmin/establishments/') &&
            request.method == 'GET') {
          final id = request.url.pathSegments.last;
          return http.Response(
              jsonEncode(rows.firstWhere((item) => item['id'] == id)), 200);
        }
        if (request.url.path == '/api/v1/superadmin/subscriptions') {
          return http.Response(
              '{"items":[],"summary":{},"expirationAutomatic":false}', 200);
        }
        if (request.url.path == '/api/v1/superadmin/plans') {
          return http.Response(
              jsonEncode([
                {
                  'id': 'plan-pro',
                  'name': 'PRO',
                  'description': '',
                  'price': 49900,
                  'durationDays': 365,
                  'currency': 'FCFA',
                  'status': 'active',
                  'features': ['students', 'teachers'],
                  'limits': {},
                  'subscriptionCount': 5,
                },
                {
                  'id': 'plan-archive',
                  'name': 'ARCHIVE',
                  'description': '',
                  'price': 10000,
                  'durationDays': 30,
                  'currency': 'FCFA',
                  'status': 'inactive',
                  'features': [],
                  'limits': {},
                  'subscriptionCount': 1,
                }
              ]),
              200);
        }
        if (request.url.path == '/api/v1/school/cycles/catalog') {
          return http.Response(
              jsonEncode([
                {'code': 'MATERNELLE', 'name': 'Maternelle', 'sortOrder': 10},
                {'code': 'PRIMAIRE', 'name': 'Primaire', 'sortOrder': 20},
                {'code': 'COLLEGE', 'name': 'Collège', 'sortOrder': 30},
                {'code': 'LYCEE', 'name': 'Lycée', 'sortOrder': 40},
              ]),
              200);
        }
        return http.Response(jsonEncode({'detail': 'Not Found'}), 404);
      });
}

Widget app(Backend backend) => ChangeNotifierProvider(
      create: (_) => StoreService(api: ApiClient(client: backend.client())),
      child: const MaterialApp(home: EstablishmentsPage()),
    );

void main() {
  testWidgets('initial list is loaded from API and explicit empty is supported',
      (tester) async {
    final backend = Backend(empty: true);
    await tester.pumpWidget(app(backend));
    expect(find.byKey(const Key('establishments-loading')), findsOneWidget);
    await tester.pumpAndSettle();
    expect(backend.listCalls, 1);
    expect(find.text('Aucun établissement trouvé'), findsOneWidget);
  });

  testWidgets('error clears the list and retry loads backend data',
      (tester) async {
    final backend = Backend(failFirst: true);
    await tester.pumpWidget(app(backend));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('establishments-error')), findsOneWidget);
    expect(find.text('Lycée Alpha'), findsNothing);
    await tester.tap(find.text('Réessayer'));
    await tester.pumpAndSettle();
    expect(backend.listCalls, 2);
    expect(find.text('Lycée Alpha'), findsOneWidget);
  });

  testWidgets('search and status filters are sent to FastAPI', (tester) async {
    final backend = Backend();
    await tester.pumpWidget(app(backend));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField), 'Dolisie');
    await tester.pumpAndSettle();
    expect(backend.lastSearch, 'Dolisie');
    expect(find.text('Lycée Beta'), findsOneWidget);
    expect(find.text('Lycée Alpha'), findsNothing);

    await tester.tap(find.text('Tous').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Suspendus').last);
    await tester.pumpAndSettle();
    expect(backend.lastStatus, 'suspended');
  });

  testWidgets('detail displays real ADMIN and independent subscription status',
      (tester) async {
    tester.view.physicalSize = const Size(2000, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final backend = Backend();
    await tester.pumpWidget(app(backend));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Consulter').first);
    await tester.pumpAndSettle();
    expect(find.text('ADMIN ASSOCIÉ'), findsOneWidget);
    expect(find.text('Admin Lycée Alpha'), findsWidgets);
    expect(find.text('Changement de mot de passe obligatoire'), findsOneWidget);
    expect(find.text('Statut : Actif'), findsOneWidget);
    expect(find.text('Montant : 25000 FCFA'), findsOneWidget);
    expect(find.text('MODULES DISPONIBLES'), findsOneWidget);
    expect(find.text('Plan actuel : PRO'), findsOneWidget);
    expect(find.text('Élèves, Enseignants'), findsOneWidget);
    expect(find.text('CYCLES'), findsOneWidget);
    expect(find.text('Primaire'), findsOneWidget);
    expect(find.text('Collège'), findsOneWidget);
  });

  testWidgets('new subscription proposes only active catalog plans',
      (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final backend = Backend();
    await tester.pumpWidget(app(backend));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('create-establishment')));
    await tester.pumpAndSettle();
    expect(find.textContaining('PRO (49900 FCFA / 365 jours)'), findsOneWidget);
    expect(find.textContaining('ARCHIVE'), findsNothing);
    expect(find.text('2 fonctionnalité(s) incluse(s) dans ce plan'),
        findsOneWidget);
    expect(find.text('CYCLES DE L’ÉTABLISSEMENT *'), findsOneWidget);
    expect(find.text('Type d\'établissement *'), findsNothing);
    expect(find.byKey(const Key('create-cycle-PRIMAIRE')), findsOneWidget);
    expect(find.byKey(const Key('create-cycle-COLLEGE')), findsOneWidget);
    expect(find.text('Voulez-vous commencer avec la configuration de base ?'),
        findsOneWidget);
    expect(find.byKey(const Key('base-configuration-yes')), findsOneWidget);
    expect(find.byKey(const Key('base-configuration-no')), findsOneWidget);
    expect(find.byKey(const Key('initial-academic-year')), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('base-configuration-no')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('base-configuration-no')));
    await tester.pump();
    expect(find.byKey(const Key('initial-academic-year')), findsNothing);
    await tester.ensureVisible(find.byKey(const Key('base-configuration-yes')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('base-configuration-yes')));
    await tester.pump();
    expect(find.byKey(const Key('initial-academic-year')), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('create-cycle-PRIMAIRE')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('create-cycle-PRIMAIRE')));
    await tester.ensureVisible(find.byKey(const Key('create-cycle-COLLEGE')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('create-cycle-COLLEGE')));
    await tester.pump();
    final primary = tester.widget<CheckboxListTile>(
        find.byKey(const Key('create-cycle-PRIMAIRE')));
    final college = tester.widget<CheckboxListTile>(
        find.byKey(const Key('create-cycle-COLLEGE')));
    expect(primary.value, isTrue);
    expect(college.value, isTrue);
  });

  testWidgets('modification charge et permet plusieurs cycles', (tester) async {
    tester.view.physicalSize = const Size(2400, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final backend = Backend();
    await tester.pumpWidget(app(backend));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Modifier').first);
    await tester.pumpAndSettle();

    final primary = tester
        .widget<CheckboxListTile>(find.byKey(const Key('edit-cycle-PRIMAIRE')));
    final college = tester
        .widget<CheckboxListTile>(find.byKey(const Key('edit-cycle-COLLEGE')));
    expect(primary.value, isTrue);
    expect(college.value, isTrue);
    await tester.tap(find.byKey(const Key('edit-cycle-LYCEE')));
    await tester.pump();
    expect(
        tester
            .widget<CheckboxListTile>(find.byKey(const Key('edit-cycle-LYCEE')))
            .value,
        isTrue);
  });

  testWidgets('modules action opens the backend-backed configuration',
      (tester) async {
    tester.view.physicalSize = const Size(1800, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final backend = Backend();
    await tester.pumpWidget(app(backend));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Gérer les modules').first);
    await tester.pumpAndSettle();
    expect(find.text('Modules disponibles'), findsOneWidget);
    expect(find.text('Élèves'), findsOneWidget);
    expect(
        tester
            .widget<CheckboxListTile>(find.byKey(const Key('module-students')))
            .value,
        isTrue);

    await tester.tap(find.byKey(const Key('module-teachers')));
    await tester.tap(find.byKey(const Key('modules-save')));
    await tester.pumpAndSettle();
    expect(backend.moduleState, ['students', 'teachers']);
    await tester.tap(find.text('Fermer'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Gérer les modules').first);
    await tester.pumpAndSettle();
    expect(backend.moduleGetCalls, 2);
    expect(
        tester
            .widget<CheckboxListTile>(find.byKey(const Key('module-teachers')))
            .value,
        isTrue);
  });

  test('StoreService envoie les cycles sans institution_type', () async {
    SharedPreferences.setMockInitialValues({});
    final backend = Backend();
    final store = StoreService(api: ApiClient(client: backend.client()));
    await store.createManagedEstablishment(
      establishment: EstablishmentModel(
        id: '',
        name: 'Complexe Multi-cycle',
        code: 'CMC',
        type: 'Groupe scolaire',
        institutionType: InstitutionType.school,
        city: 'Brazzaville',
        country: 'Congo',
        plan: 'PRO',
        cycles: const [
          SchoolCycleModel(
            id: '',
            schoolId: '',
            code: 'PRIMAIRE',
            name: 'Primaire',
            sortOrder: 20,
          ),
          SchoolCycleModel(
            id: '',
            schoolId: '',
            code: 'COLLEGE',
            name: 'Collège',
            sortOrder: 30,
          ),
        ],
      ),
      adminName: 'Admin Test',
      adminEmail: 'admin.multi@test.local',
      useBaseConfiguration: false,
    );

    expect(
        backend.lastCreationPayload?.containsKey('institution_type'), isFalse);
    expect(backend.lastCreationPayload?['cycles'], ['PRIMAIRE', 'COLLEGE']);
    expect(backend.lastCreationPayload?['code'], 'CMC');
    expect(backend.lastCreationPayload?['code'], 'CMC');
    expect(backend.lastCreationPayload?['use_base_configuration'], isFalse);
    expect(backend.lastCreationPayload?.containsKey('initial_academic_year'),
        isFalse);
  });

  test('StoreService transmet la configuration de base et son année', () async {
    SharedPreferences.setMockInitialValues({});
    final backend = Backend();
    final store = StoreService(api: ApiClient(client: backend.client()));
    await store.createManagedEstablishment(
      establishment: EstablishmentModel(
        id: '',
        name: 'École configurée',
        code: 'ECF',
        type: 'Établissement scolaire',
        institutionType: InstitutionType.school,
        city: 'Pointe-Noire',
        country: 'Congo',
        plan: 'PRO',
        cycles: const [
          SchoolCycleModel(
            id: '',
            schoolId: '',
            code: 'LYCEE',
            name: 'Lycée',
            sortOrder: 40,
          ),
        ],
      ),
      adminName: 'Admin Base',
      adminEmail: 'admin.base@test.local',
      useBaseConfiguration: true,
      initialAcademicYear: '2026-2027',
    );

    expect(backend.lastCreationPayload?['use_base_configuration'], isTrue);
    expect(backend.lastCreationPayload?['initial_academic_year'], '2026-2027');
    expect(backend.lastCreationPayload?['cycles'], ['LYCEE']);
  });
}

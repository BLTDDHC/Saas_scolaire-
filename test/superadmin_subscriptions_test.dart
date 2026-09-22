import 'package:edupro_flutter_web/features/superadmin/subscriptions_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> response() => {
      'summary': {
        'total': 1,
        'active': 1,
        'pastDue': 0,
        'expired': 0,
        'activeAmount': 25000,
      },
      'expirationAutomatic': true,
      'items': [
        {
          'id': 'subscription_test',
          'client': 'École suspendue',
          'establishmentId': 'school_test',
          'establishmentStatus': 'suspended',
          'plan': 'premium',
          'planStatus': 'active',
          'planDefinition': {
            'name': 'Premium',
            'price': 25000,
            'currency': 'FCFA',
          },
          'price': '25000 FCFA',
          'startDate': '2025-01-01',
          'endDate': '2025-02-01',
          'daysRemaining': 31,
          'status': 'active',
        }
      ],
    };

void main() {
  testWidgets('uses backend summary and keeps establishment state distinct',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    await tester.pumpWidget(MaterialApp(
      home: SubscriptionsPage(loader: () async => response()),
    ));
    await tester.pumpAndSettle();

    expect(find.text('École suspendue'), findsOneWidget);
    expect(find.text('Suspendu'), findsOneWidget);
    expect(find.text('Actif'), findsNWidgets(2));
    expect(find.text('25000 FCFA'), findsWidgets);
    expect(find.text('01-02-2025'), findsOneWidget);
    expect(find.textContaining('calculées à partir du plan'), findsOneWidget);
    expect(find.text('31 jour(s)'), findsOneWidget);
    expect(find.text('Renouveler'), findsOneWidget);
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('shows backend loading failure and supports retry',
      (tester) async {
    var calls = 0;
    Future<Map<String, dynamic>> loader() async {
      calls++;
      if (calls == 1) throw Exception('network');
      return response();
    }

    await tester
        .pumpWidget(MaterialApp(home: SubscriptionsPage(loader: loader)));
    await tester.pumpAndSettle();
    expect(find.text('Impossible de charger les abonnements.'), findsOneWidget);
    await tester.tap(find.textContaining('essayer'));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(find.text('École suspendue'), findsOneWidget);
  });
}

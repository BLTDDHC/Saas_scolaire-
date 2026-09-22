import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:edupro_flutter_web/app.dart';
import 'package:edupro_flutter_web/data/services/store_service.dart';
import 'package:edupro_flutter_web/shared/widgets/app_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  testWidgets('EduProApp smoke test', (WidgetTester tester) async {
    final storeService = StoreService();
    await storeService.init();

    await tester.pumpWidget(
      ChangeNotifierProvider<StoreService>.value(
        value: storeService,
        child: const EduProApp(),
      ),
    );

    expect(find.byType(EduProApp), findsOneWidget);
  });

  testWidgets('AppCard keeps ListTile ink and tap on a Material surface',
      (WidgetTester tester) async {
    var tapped = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppCard(
            child: ListTile(
              title: const Text('Classe test'),
              onTap: () => tapped = true,
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(
      find.ancestor(of: find.byType(ListTile), matching: find.byType(Material)),
      findsWidgets,
    );

    await tester.tap(find.byType(ListTile));
    await tester.pump();

    expect(tapped, isTrue);
    expect(tester.takeException(), isNull);
  });
}

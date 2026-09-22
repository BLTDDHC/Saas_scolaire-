import 'package:edupro_flutter_web/shared/widgets/app_button.dart';
import 'package:edupro_flutter_web/shared/widgets/app_page_header.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('page header actions stay usable without overflow at every size',
      (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.devicePixelRatio = 1;

    for (final size in const [
      Size(1440, 900),
      Size(900, 800),
      Size(390, 844)
    ]) {
      tester.view.physicalSize = size;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(24),
              child: AppPageHeader(
                title: 'Gestion académique avec un titre suffisamment long',
                subtitle:
                    'Une description utile qui doit rester lisible sur mobile.',
                actions: [
                  AppButton(
                    label: 'Action secondaire',
                    onPressed: () {},
                    variant: AppButtonVariant.secondary,
                  ),
                  AppButton(
                    label: 'Nouvelle ressource',
                    icon: Icons.add,
                    onPressed: () {},
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Nouvelle ressource'), findsOneWidget);
      expect(find.text('Action secondaire'), findsOneWidget);
      final errors = <Object>[];
      Object? error;
      while ((error = tester.takeException()) != null) {
        errors.add(error!);
      }
      expect(errors, isEmpty, reason: 'Layout ${size.width}x${size.height}');
    }
  });
}

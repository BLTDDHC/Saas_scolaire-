import 'package:edupro_flutter_web/data/services/store_service.dart';
import 'package:edupro_flutter_web/features/auth/login_page.dart';
import 'package:edupro_flutter_web/features/auth/required_password_change_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

Widget page(StoreService store, Widget child) => ChangeNotifierProvider.value(
      value: store,
      child: MaterialApp(home: child),
    );

bool isObscured(WidgetTester tester, Finder field) => tester
    .widget<EditableText>(
        find.descendant(of: field, matching: find.byType(EditableText)))
    .obscureText;

void main() {
  testWidgets(
      'login password starts empty and visibility toggle preserves value',
      (tester) async {
    final store = StoreService();
    await tester.pumpWidget(page(store, const LoginPage()));
    final password = find.byType(TextFormField).at(1);
    expect(tester.widget<TextFormField>(password).controller!.text, isEmpty);
    expect(isObscured(tester, password), isTrue);

    await tester.enterText(password, 'SecretTemporaire2026!');
    await tester.tap(find.byKey(const Key('password-visibility-Mot de passe')));
    await tester.pump();
    expect(isObscured(tester, password), isFalse);
    expect(tester.widget<TextFormField>(password).controller!.text,
        'SecretTemporaire2026!');

    await tester.tap(find.byKey(const Key('password-visibility-Mot de passe')));
    await tester.pump();
    expect(isObscured(tester, password), isTrue);

    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pumpWidget(page(store, const LoginPage()));
    expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField).at(1))
            .controller!
            .text,
        isEmpty);
  });

  testWidgets('required password fields toggle independently and reopen empty',
      (tester) async {
    final store = StoreService();
    await tester.pumpWidget(page(store, const RequiredPasswordChangePage()));
    final fields = find.byType(TextFormField);
    expect(
        tester.widget<TextFormField>(fields.at(0)).controller!.text, isEmpty);
    expect(
        tester.widget<TextFormField>(fields.at(1)).controller!.text, isEmpty);

    await tester.enterText(fields.at(0), 'NouveauSecret2026!');
    await tester.enterText(fields.at(1), 'NouveauSecret2026!');
    await tester
        .tap(find.byKey(const Key('password-visibility-Nouveau mot de passe')));
    await tester.pump();
    expect(isObscured(tester, fields.at(0)), isFalse);
    expect(isObscured(tester, fields.at(1)), isTrue);
    expect(tester.widget<TextFormField>(fields.at(0)).controller!.text,
        'NouveauSecret2026!');

    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pumpWidget(page(store, const RequiredPasswordChangePage()));
    expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField).at(0))
            .controller!
            .text,
        isEmpty);
    expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField).at(1))
            .controller!
            .text,
        isEmpty);
  });
}

import 'package:edupro_flutter_web/core/utils/date_utils.dart';
import 'package:edupro_flutter_web/features/school/documents/receipt_pdf.dart';
import 'package:edupro_flutter_web/features/school/school_shell.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('standardisation JJ-MM-AAAA', () {
    test('formate toutes les catégories de dates utilisateur', () {
      const iso = '2006-12-31';
      for (final context in const [
        'naissance',
        'inscription',
        'année scolaire',
        'présence',
        'paiement',
        'reçu',
        'document',
        'emploi du temps',
      ]) {
        expect(
          AppDateUtils.formatNumeric(iso),
          '31-12-2006',
          reason: context,
        );
      }
    });

    test('accepte uniquement une saisie stricte jour-mois-année', () {
      expect(AppDateUtils.parseUserInputStrict('31-12-2006'), isNotNull);
      expect(AppDateUtils.parseUserInputStrict('12-31-2006'), isNull);
      expect(AppDateUtils.parseUserInputStrict('31/12/2006'), isNull);
      expect(AppDateUtils.parseUserInputStrict('29-02-2007'), isNull);
      expect(
        AppDateUtils.toIso(
          AppDateUtils.parseUserInputStrict('31-12-2006')!,
        ),
        '2006-12-31',
      );
    });

    test('le reçu Finance ne laisse pas apparaître la date ISO', () {
      final rows = financeReceiptFields({
        'schoolName': 'Le cogito',
        'receiptNumber': 'REC-001',
        'date': '2026-09-10T12:30:00Z',
        'studentName': 'Élève Test',
        'amount': 10000,
      });
      final date = rows.singleWhere((row) => row.first == 'Date').last;
      expect(date, '10-09-2026');
      expect(date, isNot(contains('2026-09-10')));
    });

    test('le compte à rebours abonnement apparaît uniquement de J-15 à J-0', () {
      final today = DateTime(2026, 9, 20);
      expect(subscriptionCountdownDays('2026-10-05', today: today), 15);
      expect(subscriptionCountdownDays('2026-09-21', today: today), 1);
      expect(subscriptionCountdownDays('2026-09-20', today: today), 0);
      expect(subscriptionCountdownDays('2026-10-06', today: today), isNull);
      expect(subscriptionCountdownDays('2026-09-19', today: today), isNull);
    });
  });
}

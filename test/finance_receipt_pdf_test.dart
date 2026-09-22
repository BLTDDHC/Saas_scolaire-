import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:edupro_flutter_web/features/school/documents/receipt_pdf.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for(final label in ['Inscription','Réinscription',"Frais du mois d'octobre 2026",'TD']) {
    test('PDF receipt $label',() async {
      final row={'schoolName':'Établissement de test PDF','directionName':'Direction Collège',
        'receiptNumber':'REC-TEST-001','date':'2026-10-01','studentName':'BOUAKO Leader',
        'matricule':'TEST-001','className':'3e A','label':label,'amount':4000,
        'totalPaid':7000,'remaining':3000,'paymentMethod':'cash','authorName':'Responsable de test','status':'active'};
      final pdf=await buildFinanceReceiptPdf(row);final bytes=await pdf.save();
      expect(String.fromCharCodes(bytes.take(5)),'%PDF-');
      expect(financeReceiptText(row),contains(label));
      if(label=='TD' && Platform.environment['RECEIPT_QA_OUTPUT']!=null) {
        final file=File(Platform.environment['RECEIPT_QA_OUTPUT']!);
        await file.parent.create(recursive:true);await file.writeAsBytes(bytes);
      }
    });
  }
  test('cancelled receipt clearly invalid',() async {
    final data={'status':'cancelled','amount':4000,'cancellationReason':'Erreur de saisie'};
    expect(financeReceiptText(data),contains('ANNULÉ - justificatif non valable'));
    expect((await (await buildFinanceReceiptPdf(data)).save()).length,greaterThan(500));
  });
}

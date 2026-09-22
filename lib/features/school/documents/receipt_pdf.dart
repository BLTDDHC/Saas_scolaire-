import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../../../core/utils/date_utils.dart';
import 'pdf_font_theme.dart';

List<List<String>> financeReceiptFields(Map<String, dynamic> data) => [
      ['Établissement', '${data['schoolName'] ?? ''}'],
      if ((data['directionName'] ?? '').toString().isNotEmpty)
        ['Direction', '${data['directionName']}'],
      ['Reçu', '${data['receiptNumber'] ?? ''}'],
      ['Date', AppDateUtils.formatNumeric(data['date']?.toString())],
      ['Élève', '${data['studentName'] ?? ''}'],
      ['Matricule', '${data['matricule'] ?? ''}'],
      ['Classe', '${data['className'] ?? ''}'],
      ['Nature', '${data['label'] ?? 'Paiement historique'}'],
      ['Montant du versement', '${data['amount']} FCFA'],
      if (data['totalPaid'] != null)
        ['Cumul au moment du versement', '${data['totalPaid']} FCFA'],
      if (data['remaining'] != null)
        ['Reste au moment du versement', '${data['remaining']} FCFA'],
      [
        'Moyen de paiement',
        '${const {
              'cash': 'Espèces',
              'mobile': 'Mobile money',
              'transfer': 'Virement',
              'card': 'Carte',
              'other': 'Autre'
            }[data['paymentMethod']] ?? ''}'
      ],
      ['Enregistré par', '${data['authorName'] ?? ''}'],
      [
        'Statut',
        data['status'] == 'cancelled'
            ? 'ANNULÉ - justificatif non valable'
            : 'Actif'
      ],
      if (data['cancellationReason'] != null)
        ["Motif d'annulation", '${data['cancellationReason']}'],
    ];

String financeReceiptText(Map<String, dynamic> data) =>
    financeReceiptFields(data).map((row) => '${row[0]} : ${row[1]}').join('\n');

Future<pw.Document> buildFinanceReceiptPdf(Map<String, dynamic> data) async {
  final pdf = pw.Document();
  final theme = await buildSchoolPdfTheme();
  pdf.addPage(pw.MultiPage(
      theme: theme,
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(36),
      footer: (context) => pw.Text(
          'Page ${context.pageNumber} / ${context.pagesCount}',
          style: const pw.TextStyle(fontSize: 9)),
      build: (context) => [
            pw.Text('${data['schoolName'] ?? ''}',
                style:
                    pw.TextStyle(fontSize: 19, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 18),
            pw.Text(
                'Reçu de paiement - ${data['label'] ?? 'Paiement historique'}',
                style:
                    pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold)),
            if (data['status'] == 'cancelled')
              pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(vertical: 12),
                  child: pw.Text('ANNULÉ - justificatif non valable',
                      style: pw.TextStyle(
                          color: PdfColors.red,
                          fontWeight: pw.FontWeight.bold))),
            pw.SizedBox(height: 18),
            pw.TableHelper.fromTextArray(
                data: financeReceiptFields(data),
                headerCount: 0,
                cellPadding: const pw.EdgeInsets.all(8),
                cellAlignment: pw.Alignment.centerLeft),
            pw.SizedBox(height: 24),
            pw.Text(
                'Pièce correspondant au versement enregistré à la date indiquée.'),
          ]));
  return pdf;
}

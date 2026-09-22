import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/widgets.dart' as pw;

Future<pw.ThemeData> buildSchoolPdfTheme() async {
  final regular =
      pw.Font.ttf(await rootBundle.load('assets/fonts/Roboto-Regular.ttf'));
  final medium =
      pw.Font.ttf(await rootBundle.load('assets/fonts/Roboto-Medium.ttf'));
  return pw.ThemeData.withFont(base: regular, bold: medium);
}

import 'dart:convert';
import 'package:edupro_flutter_web/data/datasources/api_client.dart';
import 'package:edupro_flutter_web/data/services/store_service.dart';
import 'package:edupro_flutter_web/features/school/attendance/attendance_admin_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('consultation établissement, suivi, direction, période et historique', (tester) async {
    tester.view.physicalSize = const Size(1600, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final queries = <Map<String,String>>[];
    final row = {'teacherId':'t', 'teacher':'Enseignant A', 'classId':'c', 'class':'Terminale',
      'subjectId':'s','subject':'Français','scheduleId':'slot','startTime':'10:00','endTime':'11:00',
      'directionId':'d','direction':'Lycée','date':'2026-09-09','status':'submitted'};
    final store = StoreService(api:ApiClient(client:MockClient((request) async {
      if (request.url.path.endsWith('/contexts')) {
        return http.Response(jsonEncode([{'academicYearId':'y','year':'2026–2027','schoolId':'school',
          'school':'École réelle','periods':[{'periodId':'p','period':'Trimestre 1'}]}]),200,
          headers:{'content-type':'application/json; charset=utf-8'});
      }
      queries.add(request.url.queryParameters);
      return http.Response(jsonEncode({'sessions':[row], 'teacherSubmissions':[],
        'receivedCount':2,'expectedCount':3,'allReceived':false,
        'statistics':{'present':1,'absent':0,'justified':0,'attendanceRate':100},
        'records':[{...row,'studentId':'student','student':'Élève historique','status':'present'}]}),200,
        headers:{'content-type':'application/json; charset=utf-8'});
    })));
    await tester.pumpWidget(ChangeNotifierProvider.value(value:store,
      child:const MaterialApp(home:Scaffold(body:AttendanceAdminPage()))));
    await tester.pumpAndSettle();
    Future<void> choose(String label,String value) async {
      await tester.tap(find.widgetWithText(DropdownButtonFormField<String>,label));
      await tester.pumpAndSettle();
      await tester.tap(find.text(value).last);await tester.pumpAndSettle();
    }
    await choose('Établissement','École réelle');
    await choose('Année scolaire','2026–2027');
    expect(find.text('2 relevés reçus / 3 attendus'),findsOneWidget);
    expect(find.text('Tous les relevés de présence attendus sont reçus.'),findsNothing);
    await choose('Direction','Lycée');
    await choose('Période','Trimestre 1');
    await tester.tap(find.text('Consulter / actualiser'));await tester.pumpAndSettle();
    expect(queries.last['direction_id'],'d');expect(queries.last['period_id'],'p');
    expect(queries.last['academic_year_id'],'y');
    await tester.tap(find.byType(SwitchListTile));await tester.pumpAndSettle();
    expect(queries.last.containsKey('attendance_date'),false);
    await choose('Élève','Élève historique');
    await tester.tap(find.text('Consulter / actualiser'));await tester.pumpAndSettle();
    expect(queries.last['student_id'],'student');
    expect(find.text('Élève historique'),findsWidgets);
    expect(find.text('Présent'),findsOneWidget);
  });
}

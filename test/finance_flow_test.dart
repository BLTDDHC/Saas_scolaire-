import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:edupro_flutter_web/data/models/finance/finance_models.dart';
import 'support/legacy_store_test_harness.dart';

void main() {
  testWidgets('Finance workflow scenario', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = await createLegacyStore(withSeedData: true);
    await store.login('admin@edupro.com', legacyTestPassword);
    // The super administrator can see all seeded students during the test.

    // Use existing seed student in 6e A (ET014)
    final student = store
        .getStudents()
        .firstWhere((s) => s.className != null && s.className!.contains('6e'));

    // Create fees
    final feeRegistration = FeeModel(
        id: 'F_REG',
        name: 'Registration',
        amount: 10000,
        schoolId: student.schoolId);
    final feeTuition = FeeModel(
        id: 'F_TUITION',
        name: 'Tuition',
        amount: 150000,
        schoolId: student.schoolId);
    final feeInsurance = FeeModel(
        id: 'F_INS',
        name: 'Insurance',
        amount: 5000,
        schoolId: student.schoolId);

    store.addFinanceFee(feeRegistration);
    store.addFinanceFee(feeTuition);
    store.addFinanceFee(feeInsurance);

    // Create registration for 2026-2027
    final reg = FinanceRegistrationModel(
      id: 'REG_TEST_01',
      studentId: student.id,
      studentName: student.fullName,
      className: student.className,
      feeIds: [feeRegistration.id, feeTuition.id, feeInsurance.id],
      schoolId: student.schoolId,
      academicYearId: store.getSelectedAcademicYearId() ?? '',
    );

    store.addFinanceRegistration(reg);

    // Verify 3 assignments created
    final assignments = store.getFinanceFeeAssignmentsByRegistration(reg.id);
    expect(assignments.length, 3);

    // Create additional fee targeted to class
    final feeTrip = FeeModel(
        id: 'F_TRIP',
        name: 'School trip to the park',
        amount: 5000,
        className: student.className,
        schoolId: student.schoolId);
    store.addFinanceFee(feeTrip);
    store.assignFeeToTargets(
        feeId: feeTrip.id,
        schoolId: student.schoolId,
        className: student.className,
        academicYearId: reg.academicYearId);

    final assignmentsAfter =
        store.getFinanceFeeAssignmentsByRegistration(reg.id);
    expect(assignmentsAfter.length, 4);

    // Find assignments
    final regAssign =
        assignmentsAfter.firstWhere((a) => a.feeId == feeRegistration.id);
    final tuitionAssign =
        assignmentsAfter.firstWhere((a) => a.feeId == feeTuition.id);
    final tripAssign =
        assignmentsAfter.firstWhere((a) => a.feeId == feeTrip.id);

    // Make payments
    final today = DateTime.now().toIso8601String().split('T')[0];
    store.addFinancePayment(FinancePaymentModel(
        id: 'PAY1',
        registrationId: reg.id,
        feeAssignmentId: regAssign.id,
        studentId: student.id,
        studentName: student.fullName,
        amount: 10000,
        date: today,
        paymentMethod: 'cash',
        schoolId: student.schoolId));
    store.addFinancePayment(FinancePaymentModel(
        id: 'PAY2',
        registrationId: reg.id,
        feeAssignmentId: tuitionAssign.id,
        studentId: student.id,
        studentName: student.fullName,
        amount: 50000,
        date: today,
        paymentMethod: 'cash',
        schoolId: student.schoolId));
    store.addFinancePayment(FinancePaymentModel(
        id: 'PAY3',
        registrationId: reg.id,
        feeAssignmentId: tripAssign.id,
        studentId: student.id,
        studentName: student.fullName,
        amount: 3000,
        date: today,
        paymentMethod: 'cash',
        schoolId: student.schoolId));

    // Verify statuses and remaining
    expect(store.getTotalPaidForAssignment(regAssign.id), 10000);
    expect(store.getRemainingForAssignment(regAssign.id), 0);
    expect(store.getAssignmentStatus(regAssign.id), 'PAID');

    expect(store.getTotalPaidForAssignment(tuitionAssign.id), 50000);
    expect(store.getRemainingForAssignment(tuitionAssign.id), 100000);
    expect(store.getAssignmentStatus(tuitionAssign.id), 'PARTIAL');

    expect(store.getTotalPaidForAssignment(tripAssign.id), 3000);
    expect(store.getRemainingForAssignment(tripAssign.id), 2000);
    expect(store.getAssignmentStatus(tripAssign.id), 'PARTIAL');

    // Pay remaining 2000 for trip
    store.addFinancePayment(FinancePaymentModel(
        id: 'PAY4',
        registrationId: reg.id,
        feeAssignmentId: tripAssign.id,
        studentId: student.id,
        studentName: student.fullName,
        amount: 2000,
        date: today,
        paymentMethod: 'cash',
        schoolId: student.schoolId));

    expect(store.getTotalPaidForAssignment(tripAssign.id), 5000);
    expect(store.getRemainingForAssignment(tripAssign.id), 0);
    expect(store.getAssignmentStatus(tripAssign.id), 'PAID');

    // Payment history for trip should have 2 entries
    final history = store.getPaymentHistoryForAssignment(tripAssign.id);
    expect(history.length, 2);
  });
}

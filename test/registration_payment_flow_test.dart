import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:edupro_flutter_web/data/models/finance/finance_models.dart';
import 'support/legacy_store_test_harness.dart';

void main() {
  test('Registration creates mandatory fees and allows payment allocation',
      () async {
    SharedPreferences.setMockInitialValues({});
    final store = await createLegacyStore(withSeedData: true);
    await store.login('admin@edupro.com', legacyTestPassword);

    // Create a school fee flagged as mandatory at registration
    final fee1 = FeeModel(
        id: 'F_REG',
        name: 'Frais d\'inscription',
        amount: 25000,
        schoolId: store.getCurrentSchool()?.id,
        type: 'registration',
        isMandatoryAtRegistration: true);
    final fee2 = FeeModel(
        id: 'F_TUI',
        name: 'Scolarité',
        amount: 150000,
        schoolId: store.getCurrentSchool()?.id,
        type: 'tuition');
    final fee3 = FeeModel(
        id: 'F_OCC',
        name: 'Sortie scolaire',
        amount: 5000,
        schoolId: store.getCurrentSchool()?.id,
        type: 'occasional',
        isOccasional: true);

    store.addFinanceFee(fee1);
    store.addFinanceFee(fee2);
    store.addFinanceFee(fee3);

    // Create a student
    final student = store.getStudents().first;

    // Create registration -> should include fee1 but not fee3 (occasional)
    final reg = FinanceRegistrationModel(
        id: 'REG_TEST',
        studentId: student.id,
        studentName: student.fullName,
        className: student.className,
        feeIds: store.getDefaultFeeIdsForRegistration(
            className: student.className,
            academicYearId: store.getSelectedAcademicYearId()),
        schoolId: student.schoolId,
        academicYearId: store.getSelectedAcademicYearId());
    store.addFinanceRegistration(reg);

    final assignments = store.getFinanceFeeAssignmentsByRegistration(reg.id);
    expect(assignments.any((a) => a.feeId == 'F_REG'), true);
    expect(assignments.any((a) => a.feeId == 'F_OCC'), false);

    // Pay part of tuition (simulate allocation)
    final receipts = store.receivePayment(
        registrationId: reg.id,
        amount: 50000,
        paymentMethod: 'cash',
        reference: null);
    expect(receipts.isNotEmpty, true);

    // Ensure payments have been recorded
    final payments = store.getFinancePaymentsByRegistration(reg.id);
    expect(payments.fold<double>(0, (s, p) => s + p.amount) >= 50000, true);
  });
}

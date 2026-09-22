import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:edupro_flutter_web/data/models/finance/finance_models.dart';
import 'package:edupro_flutter_web/data/models/education/school_level_model.dart';
import 'package:edupro_flutter_web/data/models/class_model.dart';
import 'support/legacy_store_test_harness.dart';

void main() {
  testWidgets('Fee applicability and default assignment tests (TEST 1..TEST 8)',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = await createLegacyStore(withSeedData: true);
    await store.login('admin@edupro.com', legacyTestPassword);

    // Prepare a school id and academic year
    final schoolId = 'SCH_TEST';
    final academicYearId = store.getSelectedAcademicYearId();

    // Ensure school-level (Seconde) and classes (2nde A, 2nde B)
    final levelSeconde = SchoolLevelModel(
        id: 'L_SECONDE', name: 'Seconde', cycle: 'Lycée', schoolId: schoolId);
    store.addSchoolLevel(levelSeconde);

    final class2A = ClassModel(
        id: 'C_2A',
        name: '2nde A',
        cycle: 'Lycée',
        level: 'Seconde',
        levelId: 'L_SECONDE',
        schoolId: schoolId);
    final class2B = ClassModel(
        id: 'C_2B',
        name: '2nde B',
        cycle: 'Lycée',
        level: 'Seconde',
        levelId: 'L_SECONDE',
        schoolId: schoolId);
    store.addClass(class2A);
    store.addClass(class2B);

    // TEST 1: Fee level Seconde applicable to 2nde A and 2nde B
    final feeLevel = FeeModel(
        id: 'F_LVL',
        name: 'Frais niveau Seconde',
        amount: 100000,
        scope: 'level',
        levelId: 'L_SECONDE',
        schoolId: schoolId);
    store.addFinanceFee(feeLevel);
    expect(store.isFeeApplicableToClass(feeLevel, class2A), true);
    expect(store.isFeeApplicableToClass(feeLevel, class2B), true);

    // TEST 2: Fee niveau Premiere not applicable to 2nde A
    final levelPrem = SchoolLevelModel(
        id: 'L_PREM', name: 'Première', cycle: 'Lycée', schoolId: schoolId);
    store.addSchoolLevel(levelPrem);
    final feePrem = FeeModel(
        id: 'F_PREM',
        name: 'Frais niveau Première',
        amount: 90000,
        scope: 'level',
        levelId: 'L_PREM',
        schoolId: schoolId);
    store.addFinanceFee(feePrem);
    expect(store.isFeeApplicableToClass(feePrem, class2A), false);

    // TEST 3: Fee class 2nde A applicable to 2nde A and not to 2nde B
    final feeClass2A = FeeModel(
        id: 'F_C2A',
        name: 'Uniforme 2nde A',
        amount: 15000,
        scope: 'class',
        classId: 'C_2A',
        schoolId: schoolId);
    store.addFinanceFee(feeClass2A);
    expect(store.isFeeApplicableToClass(feeClass2A, class2A), true);
    expect(store.isFeeApplicableToClass(feeClass2A, class2B), false);

    // TEST 4: Fee cycle Lycée applies to Seconde, Première, Terminale
    final feeCycle = FeeModel(
        id: 'F_CYCLE',
        name: 'Cycle Lycée Fee',
        amount: 20000,
        scope: 'cycle',
        cycle: 'Lycée',
        schoolId: schoolId);
    store.addFinanceFee(feeCycle);
    // Create a class in Premiere and Terminale
    final classPrem = ClassModel(
        id: 'C_PREM',
        name: '1ère A',
        cycle: 'Lycée',
        level: 'Première',
        levelId: 'L_PREM',
        schoolId: schoolId);
    final classTerm = ClassModel(
        id: 'C_TERM',
        name: 'Terminale C',
        cycle: 'Lycée',
        level: 'Terminale',
        levelId: 'L_PREM',
        schoolId: schoolId);
    store.addClass(classPrem);
    store.addClass(classTerm);
    expect(store.isFeeApplicableToClass(feeCycle, class2A), true);
    expect(store.isFeeApplicableToClass(feeCycle, classPrem), true);
    expect(store.isFeeApplicableToClass(feeCycle, classTerm), true);

    // TEST 5: Fee establishment applies to all classes
    final feeEst = FeeModel(
        id: 'F_EST',
        name: 'Assurance Etablissement',
        amount: 5000,
        scope: 'establishment',
        schoolId: schoolId);
    store.addFinanceFee(feeEst);
    expect(store.isFeeApplicableToClass(feeEst, class2A), true);
    expect(store.isFeeApplicableToClass(feeEst, class2B), true);
    expect(store.isFeeApplicableToClass(feeEst, classPrem), true);

    // TEST 6: Registration in 2nde A should retrieve establishment + cycle + level + class fees
    // Create fees for each scope explicitly
    final feeEst2 = FeeModel(
        id: 'F_EST2',
        name: 'Establishment Fee',
        amount: 1000,
        scope: 'establishment',
        schoolId: schoolId);
    final feeCycle2 = FeeModel(
        id: 'F_CYC2',
        name: 'Cycle Fee',
        amount: 2000,
        scope: 'cycle',
        cycle: 'Lycée',
        schoolId: schoolId);
    final feeLevel2 = FeeModel(
        id: 'F_LV2',
        name: 'Level Fee',
        amount: 3000,
        scope: 'level',
        levelId: 'L_SECONDE',
        schoolId: schoolId);
    final feeClass2 = FeeModel(
        id: 'F_CL2',
        name: 'Class Fee',
        amount: 4000,
        scope: 'class',
        classId: 'C_2A',
        schoolId: schoolId);
    store.addFinanceFee(feeEst2);
    store.addFinanceFee(feeCycle2);
    store.addFinanceFee(feeLevel2);
    store.addFinanceFee(feeClass2);

    final defaultFees = store.getDefaultFeeIdsForRegistration(
      className: class2A.name,
      schoolId: schoolId,
      academicYearId: academicYearId,
    );
    // Should contain each of the four ids
    expect(defaultFees.contains('F_EST2'), true);
    expect(defaultFees.contains('F_CYC2'), true);
    expect(defaultFees.contains('F_LV2'), true);
    expect(defaultFees.contains('F_CL2'), true);

    // TEST 7: Occasional fee applicable to 2nde A should NOT be auto-added
    final feeOcc = FeeModel(
        id: 'F_OCC',
        name: 'Occasional Fee',
        amount: 2500,
        scope: 'class',
        classId: 'C_2A',
        isOccasional: true,
        schoolId: schoolId);
    store.addFinanceFee(feeOcc);
    final defaultsAfterOcc = store.getDefaultFeeIdsForRegistration(
        className: class2A.name,
        schoolId: schoolId,
        academicYearId: academicYearId);
    expect(defaultsAfterOcc.contains('F_OCC'), false);

    // TEST 8: Ensure same fee not assigned twice (mandatory + academic year match)
    final feeDup = FeeModel(
        id: 'F_DUP',
        name: 'Dup Fee',
        amount: 1234,
        scope: 'establishment',
        schoolId: schoolId,
        isMandatoryAtRegistration: true,
        academicYearId: academicYearId);
    store.addFinanceFee(feeDup);
    final defaultsDup = store.getDefaultFeeIdsForRegistration(
        className: class2A.name,
        schoolId: schoolId,
        academicYearId: academicYearId);
    // Should include F_DUP only once
    final occurrences = defaultsDup.where((id) => id == 'F_DUP').length;
    expect(occurrences, 1);
  });
}

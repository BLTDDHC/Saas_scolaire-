"""Regime-aware school finance tests on isolated PostgreSQL rollback fixtures."""
import unittest
import uuid
from datetime import date

from fastapi import HTTPException
from sqlalchemy import select

from app import main as m, finance as f
import test_behavior_foundations as fixtures


class StudentRegimeFinanceTests(unittest.TestCase):
    add = fixtures.BehaviorFoundations.add
    cleanup = fixtures.BehaviorFoundations.cleanup

    def setUp(self):
        fixtures.BehaviorFoundations.setUp(self)
        self.tenant.enabled_modules = [
            *self.tenant.enabled_modules,
            'finance',
            'students',
        ]
        self.cycle.code = 'PRIMAIRE'
        self.cycle.name = 'Primaire'
        self.reg = self.s.scalar(select(m.StudentAcademicRegistration).where(
            m.StudentAcademicRegistration.student_id == self.students[0].id
        ))
        self.reg.registration_date = date(2026, 9, 1)
        self.reg.school_regime = 'full_time'
        self.s.flush()
        m.ensure_initial_regime_history(
            self.s, self.reg, uuid.UUID(self.principals[0].id)
        )
        self.s.flush()
        self.school = m.public_school_id(self.s, self.tenant.id)

    def fee(self, amount, regime=None, kind='tuition'):
        return m.create_finance_fee(
            m.FinanceFeeInput(
                name='Tarif $kind ${regime or "general"}',
                amount=amount,
                scope='class',
                classId=str(self.cl.id),
                type=kind,
                frequency='monthly' if kind == 'tuition' else 'once',
                academicYearId=str(self.year.id),
                schoolId=self.school,
                schoolRegime=regime,
            ),
            self.admin,
            self.s,
        )['fee']

    def invoice(self, month):
        student = self.students[0]
        return f.invoice(
            self.s,
            self.admin,
            self.school,
            self.reg,
            self.cl,
            student,
            'tuition',
            month,
        )[0]

    def test_primary_pre_enrollment_requires_regime_and_college_rejects_it(self):
        self.fee(25000, kind='registration')
        with self.assertRaises(HTTPException) as missing:
            m.create_student_pre_enrollment(
                m.StudentPreEnrollmentInput(
                    firstName='Regime',
                    lastName='Obligatoire',
                    academicYearId=self.year.id,
                    desiredClassId=self.cl.id,
                    registrationKind='registration',
                    status='submitted',
                ),
                self.admin,
                self.s,
            )
        self.assertEqual(missing.exception.status_code, 422)

        created = m.create_student_pre_enrollment(
            m.StudentPreEnrollmentInput(
                firstName='Mi',
                lastName='Temps',
                academicYearId=self.year.id,
                desiredClassId=self.cl.id,
                registrationKind='registration',
                schoolRegime='part_time',
                status='submitted',
            ),
            self.admin,
            self.s,
        )
        self.assertEqual(created['schoolRegime'], 'part_time')

        college = self.add(m.SchoolCycle(
            establishment_id=self.tenant.id,
            code='COLLEGE',
            name='Collège',
        ))
        college_class = self.add(m.SchoolClass(
            establishment_id=self.tenant.id,
            academic_year_id=self.year.id,
            cycle_id=college.id,
            name='6e',
            status='active',
        ))
        with self.assertRaises(HTTPException) as forbidden:
            m.create_student_pre_enrollment(
                m.StudentPreEnrollmentInput(
                    firstName='Sans',
                    lastName='Regime',
                    academicYearId=self.year.id,
                    desiredClassId=college_class.id,
                    registrationKind='registration',
                    schoolRegime='full_time',
                    status='submitted',
                ),
                self.admin,
                self.s,
            )
        self.assertEqual(forbidden.exception.status_code, 422)

    def test_regime_change_preserves_past_payment_and_changes_future_tariff(self):
        self.fee(10000, 'full_time')
        self.fee(6000, 'part_time')

        october = self.invoice('2026-10')
        self.assertEqual(october['expected'], 10000)
        result = f.pay(
            f.SchoolPaymentInput(
                registrationId=self.reg.id,
                type='tuition',
                month='2026-10',
                amount=10000,
                schoolId=self.school,
            ),
            self.admin,
            self.s,
        )
        self.assertEqual(result['balance']['remaining'], 0)

        changed = m.change_student_registration_regime(
            self.reg.id,
            m.StudentRegimeChangeInput(
                schoolRegime='part_time',
                effectiveDate=date(2027, 2, 1),
            ),
            self.admin,
            self.s,
        )
        self.assertEqual(changed['registration']['schoolRegime'], 'part_time')
        history = changed['registration']['regimeHistory']
        self.assertEqual(len(history), 2)
        self.assertEqual(history[0]['regime'], 'full_time')
        self.assertEqual(history[0]['effectiveTo'], '2027-01-31')
        self.assertEqual(history[1]['effectiveFrom'], '2027-02-01')

        october_after = self.invoice('2026-10')
        february = self.invoice('2027-02')
        self.assertEqual(
            (october_after['expected'], october_after['paid'],
             october_after['remaining']),
            (10000, 10000, 0),
        )
        self.assertEqual(february['expected'], 6000)
        self.assertEqual(february['regimeLabel'], 'Mi-temps')

    def test_parent_finance_is_limited_to_linked_children(self):
        self.fee(10000, 'full_time')
        user = self.add(m.User(
            email=f'parent-{uuid.uuid4()}@example.invalid',
            password_hash='not-a-login',
            name='Parent',
            role='parent',
            school_id=self.tenant.id,
        ))
        guardian = self.add(m.Guardian(
            establishment_id=self.tenant.id,
            user_id=user.id,
            first_name='Parent',
            last_name='Test',
            status='active',
        ))
        self.add(m.StudentGuardian(
            establishment_id=self.tenant.id,
            student_id=self.students[0].id,
            guardian_id=guardian.id,
            relationship='tuteur',
            is_primary=True,
        ))
        principal = m.Principal(
            id=str(user.id),
            role='parent',
            school_id=self.school,
        )
        payload = f.parent_situation(
            self.students[0].id,
            self.year.id,
            principal,
            self.s,
        )
        self.assertEqual(payload['studentId'], str(self.students[0].id))
        self.assertEqual(payload['schoolRegime'], 'full_time')
        self.assertTrue(payload['months'])
        self.assertEqual(payload['months'][0]['regimeLabel'], 'Plein temps')

        with self.assertRaises(HTTPException) as denied:
            f.parent_situation(
                self.students[1].id,
                self.year.id,
                principal,
                self.s,
            )
        self.assertEqual(denied.exception.status_code, 404)


if __name__ == '__main__':
    unittest.main()

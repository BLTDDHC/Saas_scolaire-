"""Canonical enrollment -> finance, using PostgreSQL outer rollback fixtures."""
import unittest
import uuid
from datetime import date
from concurrent.futures import ThreadPoolExecutor
from sqlalchemy import select, func
from sqlalchemy.orm import Session
from fastapi import HTTPException
from app import main as m, finance as f
import test_behavior_foundations as fixtures


class SchoolFinance(unittest.TestCase):
    add=fixtures.BehaviorFoundations.add
    assign=fixtures.BehaviorFoundations.assign
    cleanup=fixtures.BehaviorFoundations.cleanup

    def setUp(self):
        fixtures.BehaviorFoundations.setUp(self)
        self.tenant.enabled_modules=[*self.tenant.enabled_modules,'finance','students']
        self.school=m.public_school_id(self.s,self.tenant.id)
        self.add(m.Resource(
            id=f"school-matricule-{self.tenant.id}",
            kind="establishments",
            establishment_id=self.tenant.id,
            payload={
                "databaseId": str(self.tenant.id),
                "code": "RBF",
            },
        ))
        self.school=m.public_school_id(self.s,self.tenant.id)
        self.reg=self.s.scalar(select(m.StudentAcademicRegistration).where(
            m.StudentAcademicRegistration.student_id==self.students[0].id))
        self.level=self.add(m.SchoolLevel(establishment_id=self.tenant.id,cycle_id=self.cycle.id,
            code='3E',name='3e'))
        self.cl.school_level_id=self.level.id
        self.s.flush()

    def fee(self,kind='tuition',amount=10000,scope='class'):
        return m.create_finance_fee(m.FinanceFeeInput(name=f'Tarif {kind}',amount=amount,
            scope=scope,classId=str(self.cl.id) if scope=='class' else None,
            levelId=str(self.level.id) if scope=='level' else None,
            type=kind,frequency='monthly' if kind=='tuition' else 'once',
            academicYearId=str(self.year.id),schoolId=self.school),self.admin,self.s)['fee']

    def roster(self,kind='tuition',month='2026-10',**kw):
        return f.roster(self.year.id,kind=kind,month=month,school_id=self.school,
            current=self.admin,session=self.s,**kw)

    def pay(self,amount=4000,kind='tuition',month='2026-10',reference=None,principal=None):
        return f.pay(f.SchoolPaymentInput(registrationId=self.reg.id,type=kind,month=month,
            amount=amount,reference=reference,schoolId=self.school),principal or self.admin,self.s)

    def own(self,**kw):
        return next(row for row in self.roster(**kw)['students'] if row['registrationId']==str(self.reg.id))


    def test_primary_regime_tariff_changes_by_effective_month_without_rewriting_history(self):
        self.cycle.code = 'PRIMAIRE'
        self.cycle.name = 'Primaire'
        self.reg.school_regime = 'full_time'
        self.reg.options = {
            'regimeHistory': [{
                'regime': 'full_time',
                'startDate': '2026-09-01',
                'endDate': None,
                'changedBy': self.admin.id,
                'changedAt': '2026-09-01T00:00:00+00:00',
            }]
        }
        self.s.flush()
        for regime, amount in [('full_time', 12000), ('part_time', 8000)]:
            m.create_finance_fee(m.FinanceFeeInput(
                name=f'Tarif {regime}', amount=amount, scope='class',
                classId=str(self.cl.id), type='tuition', frequency='monthly',
                schoolRegime=regime, academicYearId=str(self.year.id),
                schoolId=self.school,
            ), self.admin, self.s)

        self.assertEqual(self.own(month='2026-10')['expected'], 12000)
        self.assertEqual(self.pay(12000, month='2026-10')['receipt']['amount'], 12000)

        changed = m.change_student_registration_regime(
            self.reg.id,
            m.StudentRegimeChangeInput(
                schoolRegime='part_time', effectiveDate=date(2027, 2, 1)
            ),
            self.admin,
            self.s,
        )
        self.assertEqual(changed['schoolRegime'], 'part_time')
        self.assertEqual(self.own(month='2027-01')['expected'], 12000)
        self.assertEqual(self.own(month='2027-02')['expected'], 8000)
        october = self.own(month='2026-10')
        self.assertEqual(
            (october['expected'], october['paid'], october['remaining']),
            (12000, 12000, 0),
        )
        history = changed['options']['regimeHistory']
        self.assertEqual(history[0]['endDate'], '2027-01-31')
        self.assertEqual(history[1]['startDate'], '2027-02-01')

    def test_primary_pre_enrollment_requires_regime_and_college_rejects_it(self):
        self.fee('registration', 25000)
        self.cycle.code = 'PRIMAIRE'
        self.cycle.name = 'Primaire'
        self.s.flush()
        with self.assertRaises(HTTPException) as missing:
            m.create_student_pre_enrollment(
                m.StudentPreEnrollmentInput(
                    firstName='Primaire', lastName='Sans régime',
                    academicYearId=self.year.id, desiredClassId=self.cl.id,
                    registrationKind='registration', status='submitted',
                ),
                self.admin, self.s,
            )
        self.assertEqual(missing.exception.status_code, 422)

        created = m.create_student_pre_enrollment(
            m.StudentPreEnrollmentInput(
                firstName='Primaire', lastName='Plein temps',
                academicYearId=self.year.id, desiredClassId=self.cl.id,
                registrationKind='registration', schoolRegime='full_time',
                status='submitted',
            ),
            self.admin, self.s,
        )
        self.assertEqual(created['schoolRegime'], 'full_time')
        provisional = self.s.get(
            m.StudentAcademicRegistration,
            uuid.UUID(created['provisionalRegistrationId']),
        )
        self.assertEqual(provisional.school_regime, 'full_time')

        self.cycle.code = 'COLLEGE'
        self.cycle.name = 'Collège'
        self.s.flush()
        student = m.create_relational_student(
            m.StudentIdentityInput(
                firstName='Collège', lastName='Sans régime',
                birthDate=date(2010, 1, 1), nationality='Test', address='Test',
            ),
            self.school, self.admin, self.s,
        )
        with self.assertRaises(HTTPException) as forbidden:
            m.create_student_registration(
                uuid.UUID(student['id']),
                m.StudentRegistrationInput(
                    classId=self.cl.id, schoolRegime='part_time'
                ),
                self.admin, self.s,
            )
        self.assertEqual(forbidden.exception.status_code, 422)

    def test_parent_finance_is_strictly_scoped_to_linked_child(self):
        self.cycle.code = 'PRIMAIRE'
        self.cycle.name = 'Primaire'
        self.reg.school_regime = 'full_time'
        self.reg.options = {
            'regimeHistory': [{
                'regime': 'full_time',
                'startDate': '2026-09-01',
                'endDate': None,
                'changedBy': self.admin.id,
                'changedAt': '2026-09-01T00:00:00+00:00',
            }]
        }
        self.s.flush()
        m.create_finance_fee(m.FinanceFeeInput(
            name='Plein temps', amount=10000, scope='class',
            classId=str(self.cl.id), type='tuition', frequency='monthly',
            schoolRegime='full_time', academicYearId=str(self.year.id),
            schoolId=self.school,
        ), self.admin, self.s)
        self.pay(4000, month='2026-10')

        parent_user = self.add(m.User(
            email=f'{uuid.uuid4()}@parent.invalid',
            password_hash='not-a-login', name='Parent Test', role='parent',
            school_id=self.tenant.id, status='active',
        ))
        guardian = self.add(m.Guardian(
            establishment_id=self.tenant.id,
            user_id=parent_user.id,
            first_name='Parent', last_name='Test',
            status='active',
        ))
        self.add(m.StudentGuardian(
            establishment_id=self.tenant.id,
            student_id=self.students[0].id,
            guardian_id=guardian.id,
            relationship='parent',
            is_primary=True,
        ))
        parent = m.Principal(
            id=str(parent_user.id), role='parent', school_id=self.school
        )
        situation = f.parent_situation(
            self.students[0].id, self.year.id, parent, self.s
        )
        self.assertEqual(situation['currentRegime'], 'full_time')
        october = next(
            row for row in situation['months'] if row['month'] == '2026-10'
        )
        self.assertEqual((october['paid'], october['remaining']), (4000, 6000))
        self.assertEqual(situation['summary']['paid'], 4000)

        with self.assertRaises(HTTPException) as denied:
            f.parent_situation(
                self.students[1].id, self.year.id, parent, self.s
            )
        self.assertEqual(denied.exception.status_code, 404)


    def test_school_creation_registration_automatically_visible(self):
        student=m.create_relational_student(m.StudentIdentityInput(firstName='Leader',lastName='BOUAKO',
            birthDate=date(2010,1,1),nationality='Test',address='Test'),self.school,self.admin,self.s)
        registration=m.create_student_registration(uuid.UUID(student['id']),
            m.StudentRegistrationInput(classId=self.cl.id),self.admin,self.s)
        rows=self.roster(class_id=self.cl.id)['students']
        self.assertTrue(any(row['registrationId']==registration['id'] for row in rows))
        self.assertEqual(self.s.scalar(select(func.count()).select_from(m.Resource).where(
            m.Resource.school_id==self.school,m.Resource.kind=='finance-registrations')),0)

    def test_pre_enrollment_receipt_finance_and_finalization_share_one_registration(self):
        self.fee('registration', 25000)
        created = m.create_student_pre_enrollment(
            m.StudentPreEnrollmentInput(
                firstName='Grâce', lastName='MASSAMBA',
                academicYearId=self.year.id, desiredClassId=self.cl.id,
                registrationKind='registration', status='submitted',
            ),
            self.admin, self.s,
        )
        self.assertEqual(created['status'], 'submitted')
        self.assertEqual(created['receipt']['amount'], 25000)
        registration_id = created['provisionalRegistrationId']
        provisional = self.s.get(
            m.StudentAcademicRegistration, uuid.UUID(registration_id)
        )
        self.assertEqual(provisional.status, 'pre_enrolled')
        budget = f.budget(self.year.id, self.school, self.admin, self.s)
        registration_total = next(
            row for row in budget['breakdown'] if row['type'] == 'registration'
        )
        self.assertGreaterEqual(registration_total['paid'], 25000)
        result = m.approve_student_pre_enrollment(
            uuid.UUID(created['id']),
            m.StudentPreEnrollmentApprovalInput(
                classId=self.cl.id,
                options={'orphanFather': False, 'orphanMother': False,
                         'fitness': 'fit'},
            ),
            self.admin, self.s,
        )
        self.assertEqual(result['registration']['id'], registration_id)
        self.assertEqual(result['registration']['status'], 'validated')

    def test_transfer_uses_current_school_class(self):
        new=self.add(m.SchoolClass(establishment_id=self.tenant.id,academic_year_id=self.year.id,
            cycle_id=self.cycle.id,school_level_id=self.level.id,name='3e B'))
        m.change_student_registration_class(self.reg.id,m.StudentClassTransferInput(classId=new.id,
            reason='Test'),self.admin,self.s)
        self.assertEqual(self.own()['className'],'3e B')
        self.assertFalse(any(row['registrationId']==str(self.reg.id)
            for row in self.roster(class_id=self.cl.id)['students']))

    def test_transfer_preserves_paid_amount_and_historical_receipt(self):
        self.fee(scope='level',amount=8000)
        self.fee(amount=10000)
        receipt=self.pay(4000)['receipt']
        old_name=self.cl.name
        new=self.add(m.SchoolClass(establishment_id=self.tenant.id,academic_year_id=self.year.id,
            cycle_id=self.cycle.id,school_level_id=self.level.id,name='3e B'))
        m.change_student_registration_class(self.reg.id,m.StudentClassTransferInput(classId=new.id,
            reason='Test'),self.admin,self.s)
        row=self.own()
        self.assertEqual((row['className'],row['expected'],row['paid'],row['remaining']),('3e B',8000,4000,4000))
        self.assertEqual(f.receipt(receipt['id'],self.school,self.admin,self.s)['className'],old_name)

    def test_level_tariff_configuration_and_update(self):
        fee=self.fee(scope='level')
        self.assertEqual(self.own()['expected'],10000)
        body=m.FinanceFeeInput(**{key:fee[key] for key in m.FinanceFeeInput.model_fields if key in fee})
        f.update_fee(fee['id'],body.model_copy(update={'amount':12000}),self.admin,self.s)
        self.assertEqual(self.own()['expected'],12000)

    def test_cycle_tariff_and_roster_context_are_explicit(self):
        m.create_finance_fee(m.FinanceFeeInput(
            name='Tarif cycle rollback', amount=9000, scope='cycle',
            cycle=str(self.cycle.id), type='tuition', frequency='monthly',
            academicYearId=str(self.year.id), schoolId=self.school,
        ), self.admin, self.s)
        result = self.roster()
        self.assertEqual(self.own()['expected'], 9000)
        self.assertEqual(result['classes'][0]['cycleId'], str(self.cycle.id))
        self.assertEqual(result['classes'][0]['cycleName'], self.cycle.name)

    def test_tariff_context_duplicate_and_precedence(self):
        self.fee(scope='level',amount=8000)
        self.fee(amount=10000)
        self.assertEqual(self.own()['expected'],10000)
        with self.assertRaises(HTTPException):self.fee(amount=11000)

    def test_no_tariff_is_explicit(self):
        self.assertEqual(self.own()['status'],'no_tariff')
        with self.assertRaises(HTTPException):self.pay()

    def test_monthly_unpaid_partial_multiple_paid_and_next_month(self):
        self.fee()
        self.assertEqual(self.own()['status'],'unpaid')
        self.pay(4000)
        self.pay(3000)
        row=self.own()
        self.assertEqual((row['paid'],row['remaining'],row['status']),(7000,3000,'partial'))
        self.pay(3000)
        self.assertEqual(self.own()['status'],'paid')
        self.assertEqual(self.own(month='2026-11')['paid'],0)
        self.assertEqual(self.own()['label'],"Tarif tuition — octobre 2026")

    def test_multi_month_payment_is_allocated_oldest_first_and_has_one_receipt(self):
        self.fee()
        result = f.pay(f.SchoolPaymentInput(
            registrationId=self.reg.id,
            type='tuition',
            months=['2027-01', '2026-12', '2026-10', '2026-11'],
            amount=25000,
            schoolId=self.school,
        ), self.admin, self.s)
        allocations = result['allocations']
        self.assertEqual(
            [(item['month'], item['amount'], item['status']) for item in allocations],
            [
                ('2026-10', 10000, 'paid'),
                ('2026-11', 10000, 'paid'),
                ('2026-12', 5000, 'partial'),
                ('2027-01', 0, 'unpaid'),
            ],
        )
        self.assertEqual(self.own(month='2026-10')['status'], 'paid')
        self.assertEqual(self.own(month='2026-11')['status'], 'paid')
        self.assertEqual(self.own(month='2026-12')['remaining'], 5000)
        self.assertEqual(self.own(month='2027-01')['paid'], 0)
        receipts = [item for item in f.receipts(
            self.year.id, self.school, self.admin, self.s
        ) if item.get('paymentId') == result['payment']['id']]
        self.assertEqual(len(receipts), 1)
        self.assertEqual(receipts[0]['className'], self.cl.name)
        self.assertEqual(receipts[0]['type'], 'tuition')
        self.assertEqual(receipts[0]['months'], [
            '2026-10', '2026-11', '2026-12', '2027-01'
        ])

    def test_monthly_situation_returns_all_months_in_one_projection(self):
        self.fee()
        situation = f.monthly_situation(
            self.reg.id, self.year.id, self.school, self.admin, self.s
        )
        self.assertEqual(situation['registrationId'], str(self.reg.id))
        self.assertEqual(situation['studentId'], str(self.students[0].id))
        self.assertEqual(situation['className'], self.cl.name)
        self.assertEqual(
            [row['month'] for row in situation['months']],
            [
                '2026-09', '2026-10', '2026-11', '2026-12',
                '2027-01', '2027-02', '2027-03', '2027-04',
                '2027-05', '2027-06', '2027-07',
            ],
        )

    def test_cancelling_multi_month_payment_restores_every_month(self):
        self.fee()
        result = f.pay(f.SchoolPaymentInput(
            registrationId=self.reg.id,
            type='tuition',
            months=['2026-10', '2026-11'],
            amount=15000,
            schoolId=self.school,
        ), self.admin, self.s)
        m.cancel_finance_payment(
            result['payment']['id'],
            m.FinanceCancelInput(reason='Annulation multi-mois test'),
            self.school,
            self.admin,
            self.s,
        )
        self.assertEqual(self.own(month='2026-10')['paid'], 0)
        self.assertEqual(self.own(month='2026-11')['paid'], 0)
        self.assertEqual(
            f.receipt(result['receipt']['id'], self.school, self.admin, self.s)['status'],
            'cancelled',
        )

    def test_exact_amount_and_excess_refused_without_loss(self):
        self.fee()
        with self.assertRaises(HTTPException):self.pay(15000)
        self.assertEqual(self.own()['paid'],0)
        self.pay(10000)
        self.assertEqual(self.own()['remaining'],0)

    def test_registration_receipt(self):
        self.fee('registration')
        result=self.pay(10000,'registration')
        self.assertEqual(result['receipt']['label'],'Tarif registration')
        self.assertEqual(result['receipt']['totalPaid'],10000)

    def test_reenrollment_eligibility_and_receipt(self):
        oldyear=self.add(m.AcademicYear(establishment_id=self.tenant.id,name='2025-2026',
            start_date=date(2025,9,1),end_date=date(2026,7,1)))
        self.add(m.StudentAcademicRegistration(establishment_id=self.tenant.id,
            student_id=self.reg.student_id,academic_year_id=oldyear.id,class_id=self.cl.id))
        self.fee('reenrollment')
        self.assertEqual(self.own(kind='registration')['status'],'not_applicable')
        self.assertEqual(self.pay(10000,'reenrollment')['receipt']['label'],'Tarif reenrollment')

    def test_td_uses_official_registration_option(self):
        self.fee('td',5000)
        with self.assertRaises(HTTPException):self.pay(5000,'td')
        self.reg.has_td=True;self.s.flush()
        self.assertEqual(self.pay(5000,'td')['receipt']['label'],'Tarif td')

    def annual(self):
        return f.budget(self.year.id,self.school,self.admin,self.s)

    def test_budget_reacts_to_official_enrollment_and_filters_do_not_reduce_it(self):
        self.fee('registration',50000)
        before=self.annual()
        student=m.create_relational_student(m.StudentIdentityInput(firstName='Leader',lastName='BOUAKO',
            birthDate=date(2010,1,1),nationality='Test',address='Test'),self.school,self.admin,self.s)
        m.create_student_registration(uuid.UUID(student['id']),
            m.StudentRegistrationInput(classId=self.cl.id),self.admin,self.s)
        after=self.annual()
        self.assertEqual(after['summary']['expected']-before['summary']['expected'],50000)
        self.assertEqual(after['registrationCount'],before['registrationCount']+1)
        filtered=self.roster(search='does not exist')
        self.assertEqual(filtered['students'],[])
        self.assertEqual(filtered['budget'],after)

    def test_budget_month_tariffs_labels_periods_payments_and_td(self):
        self.fee('registration',50000)
        self.fee('td',5000)
        self.reg.has_td=True;self.s.flush()
        for month,amount in [(10,10000),(11,12000)]:
            self.add(m.AcademicPeriod(establishment_id=self.tenant.id,academic_year_id=self.year.id,
                code=f'M{month}',name=f'Mois {month}',period_type='month',start_date=date(2026,month,1)))
            m.create_finance_fee(m.FinanceFeeInput(name=f'Libellé libre {month}',amount=amount,
                scope='class',classId=str(self.cl.id),type='tuition',month=f'2026-{month}',
                academicYearId=str(self.year.id),schoolId=self.school),self.admin,self.s)
        self.assertEqual(self.own()['expected'],10000)
        self.assertEqual(self.own(month='2026-11')['expected'],12000)
        self.assertEqual(self.pay(3000)['receipt']['label'],'Libellé libre 10')
        self.pay(4000)
        result=self.annual()
        parts={row['type']:row for row in result['breakdown']}
        self.assertEqual(result['months'],['2026-10','2026-11'])
        self.assertEqual(parts['registration']['expected'],100000)
        self.assertEqual(parts['td']['expected'],5000)
        self.assertEqual(parts['tuition']['expected'],44000)
        self.assertEqual(parts['tuition']['paid'],7000)
        self.assertEqual(parts['tuition']['remaining'],37000)
        self.assertEqual(result['summary']['expected'],149000)

    def test_budget_reenrollment_is_not_counted_as_new_registration(self):
        self.fee('registration',50000);self.fee('reenrollment',30000)
        oldyear=self.add(m.AcademicYear(establishment_id=self.tenant.id,name='2025-2026',
            start_date=date(2025,9,1),end_date=date(2026,7,1)))
        self.add(m.StudentAcademicRegistration(establishment_id=self.tenant.id,
            student_id=self.reg.student_id,academic_year_id=oldyear.id,class_id=self.cl.id))
        parts={row['type']:row for row in self.annual()['breakdown']}
        self.assertEqual(parts['registration']['expected'],50000)
        self.assertEqual(parts['reenrollment']['expected'],30000)

    def test_month_specific_tariff_overrides_general_without_double_billing(self):
        self.fee(amount=8000)
        m.create_finance_fee(m.FinanceFeeInput(name='Octobre libre',amount=10000,
            scope='class',classId=str(self.cl.id),type='tuition',month='2026-10',
            academicYearId=str(self.year.id),schoolId=self.school),self.admin,self.s)
        self.assertEqual(self.own()['expected'],10000)
        self.assertEqual(self.own(month='2026-11')['expected'],8000)

    def test_multiple_other_fees_have_separate_balances_and_receipts(self):
        fees=[]
        for name,amount in [('Bibliothèque',2000),('Assurance',3000)]:
            fees.append(m.create_finance_fee(m.FinanceFeeInput(name=name,amount=amount,
                scope='class',classId=str(self.cl.id),type='other',frequency='once',
                academicYearId=str(self.year.id),schoolId=self.school),self.admin,self.s)['fee'])
        self.assertEqual(len(self.roster(kind='other')['students']),4)
        result=f.pay(f.SchoolPaymentInput(registrationId=self.reg.id,type='other',feeId=fees[0]['id'],
            amount=1000,schoolId=self.school),self.admin,self.s)
        self.assertEqual(result['receipt']['label'],'Bibliothèque')
        parts={row['type']:row for row in self.annual()['breakdown']}
        self.assertEqual((parts['other']['expected'],parts['other']['paid'],parts['other']['remaining']),
            (10000,1000,9000))

    def test_budget_keeps_cash_after_enrollment_becomes_inactive(self):
        self.fee()
        self.pay(4000)
        self.reg.status='inactive';self.s.flush()
        self.assertEqual(self.annual()['summary']['paid'],4000)

    def test_server_annual_student_status_counts(self):
        self.fee('registration',50000);self.fee()
        self.add(m.AcademicPeriod(establishment_id=self.tenant.id,academic_year_id=self.year.id,
            code='M10',name='Octobre',period_type='month',start_date=date(2026,10,1)))
        self.assertEqual(self.annual()['counts'],{'students':2,'paid':0,'partial':2,'unpaid':0,'unconfigured':0})
        self.pay(4000)
        self.assertEqual(self.annual()['counts']['partial'],2)
        self.pay(6000);self.pay(50000,'registration')
        self.assertEqual(self.annual()['counts']['paid'],1)

    def test_school_registration_is_settled_and_receipt_is_available_without_cash_entry(self):
        self.cycle.code='LYCEE'; self.level.cycle_id=self.cycle.id; self.cl.cycle_id=self.cycle.id; self.s.flush()
        self.reg.has_td=True; self.cl.level='3E'; self.fee('registration',50000); self.fee('td',10000)
        row = self.own(kind='registration')
        self.assertEqual((row['expected'],row['paid'],row['remaining'],row['status']), (50000,50000,0,'paid'))
        td = self.own(kind='td')
        self.assertEqual((td['expected'],td['paid'],td['remaining'],td['status']), (10000,0,10000,'unpaid'))
        budget = self.annual()
        parts = {item['type']: item for item in budget['breakdown']}
        self.assertEqual(parts['registration']['paid'],100000)
        self.assertEqual(parts['td']['paid'],0)
        receipts = f.receipts(self.year.id,self.school,self.admin,self.s)
        self.assertTrue(any(item['type']=='registration' and item['amount']==50000 for item in receipts))
        result = self.pay(10000,'td')
        self.assertEqual(result['receipt']['label'],'Tarif td')
        self.assertEqual(f.budget(self.year.id,self.school,self.admin,self.s)['summary']['paid'],110000)

    def test_monthly_receipt_contains_real_context(self):
        self.fee()
        receipt=self.pay()['receipt']
        self.assertEqual(receipt['className'],self.cl.name)
        self.assertEqual(receipt['schoolName'],self.tenant.name)
        self.assertEqual(receipt['remaining'],6000)
        self.assertEqual(receipt['studentName'],'Rollback S0')
        self.assertEqual(f.receipt(receipt['id'],self.school,self.admin,self.s)['amount'],4000)

    def test_search_name_firstname_and_class(self):
        self.assertEqual(len(self.roster(search='rollback')['students']),2)
        self.assertEqual(len(self.roster(search='s0')['students']),1)
        self.assertEqual(len(self.roster(search='s0 rollback')['students']),1)
        self.assertEqual(len(self.roster(class_id=self.cl.id)['students']),2)

    def test_three_directions_all_direct_ids_guarded(self):
        fee=self.fee()
        result=self.pay()
        for code in ('MATERNELLE','PRIMAIRE','COLLEGE','LYCEE'):
            self.cycle.code=code;self.s.flush()
            denied=m.Principal(id=self.admin.id,role='admin',school_id=self.school,
                direction_id=str(uuid.uuid4()),direction_cycle_ids=[str(uuid.uuid4())])
            with self.assertRaises(HTTPException):self.pay(principal=denied)
            with self.assertRaises(HTTPException):f.receipt(result['receipt']['id'],self.school,denied,self.s)
            for kind,identifier in [('finance-fees',fee['id']),('finance-payments',result['payment']['id'])]:
                with self.assertRaises(HTTPException):m.finance_resource(self.s,kind,identifier,self.school,denied)
            self.assertEqual(f.roster(self.year.id,month='2026-10',school_id=self.school,
                current=denied,session=self.s)['students'],[])

    def test_duplicate_reference_and_cancelled_receipt(self):
        self.fee()
        result=self.pay(reference='UNIQUE-TEST')
        with self.assertRaises(HTTPException):self.pay(reference='unique-test')
        m.cancel_finance_payment(result['payment']['id'],m.FinanceCancelInput(reason='Test annulation'),
            self.school,self.admin,self.s)
        self.assertEqual(self.own()['paid'],0)
        self.assertEqual(f.receipt(result['receipt']['id'],self.school,self.admin,self.s)['status'],'cancelled')

    def test_concurrent_payment_lock(self):
        self.fee()
        result=self.pay()
        key='assignment:'+result['payment']['feeAssignmentId']
        def attempt():
            with m.engine.connect() as connection,connection.begin(),Session(bind=connection) as second:
                try:m.finance_lock(second,key)
                except HTTPException as error:return error.status_code
        with ThreadPoolExecutor(max_workers=1) as pool:
            self.assertEqual(pool.submit(attempt).result(),409)

    def test_month_outside_year_rejected(self):
        with self.assertRaises(HTTPException):self.roster(month='2027-12')

    def test_teacher_http_access_denied(self):
        m.app.dependency_overrides[m.principal]=lambda:self.principals[0]
        m.app.dependency_overrides[m.db]=lambda:self.s
        try:
            response=fixtures.ASGIClient().get('/api/v1/school/finance/roster',params={
                'academic_year_id':str(self.year.id),'month':'2026-10','school_id':self.school})
            self.assertEqual(response.status_code,403)
        finally:m.app.dependency_overrides.clear()

    def test_http_admin_roster_payment_receipt(self):
        self.fee()
        m.app.dependency_overrides[m.principal]=lambda:self.admin
        m.app.dependency_overrides[m.db]=lambda:self.s
        try:
            client=fixtures.ASGIClient()
            response=client.get('/api/v1/school/finance/roster',params={
                'academic_year_id':str(self.year.id),'month':'2026-10','school_id':self.school})
            self.assertEqual(response.status_code,200)
            result=client.request('POST','/api/v1/school/finance/school-payments',{
                'registrationId':str(self.reg.id),'type':'tuition','month':'2026-10',
                'amount':4000,'schoolId':self.school})
            self.assertEqual(result.status_code,201)
            receipt=client.get('/api/v1/school/finance/receipts/'+result.json()['receipt']['id'],
                params={'school_id':self.school})
            self.assertEqual(receipt.status_code,200)
            self.assertEqual(receipt.json()['remaining'],6000)
        finally:m.app.dependency_overrides.clear()

    def test_own_direction_can_pay_in_every_cycle(self):
        self.fee()
        for code in ('MATERNELLE','PRIMAIRE','COLLEGE','LYCEE'):
            self.cycle.code=code;self.s.flush()
            allowed=m.Principal(id=self.admin.id,role='admin',school_id=self.school,
                direction_id=str(uuid.uuid4()),direction_cycle_ids=[str(self.cycle.id)])
            result=self.pay(1000,principal=allowed)
            self.assertEqual(f.receipt(result['receipt']['id'],self.school,allowed,self.s)['amount'],1000)
            annual=f.budget(self.year.id,self.school,allowed,self.s)
            self.assertEqual(annual['registrationCount'],2)
            self.assertEqual(annual['summary']['expected'],220000)
            denied=allowed.model_copy(update={'direction_cycle_ids':[str(uuid.uuid4())]})
            self.assertEqual(f.budget(self.year.id,self.school,denied,self.s)['summary']['expected'],0)

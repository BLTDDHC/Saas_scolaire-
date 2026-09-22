"""Targeted finance invariants. Every fixture runs in an outer rollback."""
import unittest
import uuid
from concurrent.futures import ThreadPoolExecutor
from sqlalchemy.orm import Session
from fastapi import HTTPException

from app import main as m
import test_behavior_foundations as fixtures


class FinanceGuards(unittest.TestCase):
    add = fixtures.BehaviorFoundations.add
    assign = fixtures.BehaviorFoundations.assign
    cleanup = fixtures.BehaviorFoundations.cleanup

    def setUp(self):
        fixtures.BehaviorFoundations.setUp(self)
        self.tenant.enabled_modules = [*self.tenant.enabled_modules, "finance"]
        self.s.flush()
        self.school_id = m.public_school_id(self.s, self.tenant.id)
        registration_id = "FIN_REG_ROLLBACK"
        self.add(m.Resource(id=registration_id, kind="finance-registrations",
            school_id=self.school_id, establishment_id=self.tenant.id,
            academic_year_id=self.year.id, payload={"id": registration_id,
                "studentId": str(self.students[0].id), "studentName": "Rollback S0",
                "classId": str(self.cl.id), "academicYearId": str(self.year.id), "status": "active"}))
        self.assignment_id = "FIN_ASSIGN_ROLLBACK"
        self.add(m.Resource(id=self.assignment_id, kind="finance-fee-assignments",
            school_id=self.school_id, establishment_id=self.tenant.id,
            academic_year_id=self.year.id, payload={"id": self.assignment_id,
                "registrationId": registration_id, "studentId": str(self.students[0].id),
                "amount": 10000, "academicYearId": str(self.year.id), "status": "assigned"}))
        self.registration_id = registration_id

    def payment(self, reference="REF-ROLLBACK"):
        return m.FinancePaymentInput(registrationId=self.registration_id,
            feeAssignmentId=self.assignment_id, amount=4000, paymentMethod="cash",
            reference=reference, schoolId=self.school_id)

    def test_payment_receipt_balance_duplicate_and_cancellation_audit(self):
        result = m.create_finance_payment(self.payment(), self.admin, self.s)
        self.assertEqual(result["balance"], {"expected": 10000, "paid": 4000,
            "remaining": 6000, "status": "partial"})
        with self.assertRaises(HTTPException) as duplicate:
            m.create_finance_payment(self.payment(), self.admin, self.s)
        self.assertEqual(duplicate.exception.status_code, 409)
        cancelled = m.cancel_finance_payment(result["payment"]["id"],
            m.FinanceCancelInput(reason="Erreur de caisse"), self.school_id, self.admin, self.s)
        self.assertEqual(cancelled["status"], "cancelled")
        receipt = m.finance_resource(self.s, "finance-receipts", result["receipt"]["id"], self.school_id, self.admin)
        self.assertEqual(receipt.payload["status"], "cancelled")
        self.assertEqual(receipt.payload["cancellationReason"], "Erreur de caisse")
        assignment = m.finance_resource(self.s, 'finance-fee-assignments', self.assignment_id, self.school_id, self.admin)
        self.assertEqual(m.finance_assignment_balance(self.s, self.school_id, assignment)['paid'], 0)
        with self.assertRaises(HTTPException) as reused:
            m.create_finance_payment(self.payment('ref-rollback'), self.admin, self.s)
        self.assertEqual(reused.exception.status_code, 409)

    def test_payment_cannot_use_another_registration_assignment(self):
        other = "FIN_OTHER_REG_ROLLBACK"
        self.add(m.Resource(id=other, kind="finance-registrations", school_id=self.school_id,
            establishment_id=self.tenant.id, academic_year_id=self.year.id,
            payload={"id": other, "studentId": str(self.students[1].id),
                "classId": str(self.cl.id), "academicYearId": str(self.year.id), "status": "active"}))
        body = self.payment("REF-MISMATCH").model_copy(update={"registrationId": other})
        with self.assertRaises(HTTPException) as mismatch:
            m.create_finance_payment(body, self.admin, self.s)
        self.assertEqual(mismatch.exception.status_code, 422)

    def test_direction_scope_and_direct_id(self):
        for code in ('MATERNELLE', 'PRIMAIRE', 'COLLEGE', 'LYCEE'):
            self.cycle.code = code
            self.s.flush()
            allowed = self.admin.model_copy(update={'role': 'admin', 'school_id': self.school_id,
                'direction_id': str(uuid.uuid4()), 'direction_cycle_ids': [str(self.cycle.id)]})
            self.assertEqual(m.finance_resource(self.s, 'finance-registrations',
                self.registration_id, self.school_id, allowed).id, self.registration_id)
            denied = allowed.model_copy(update={'direction_cycle_ids': [str(uuid.uuid4())]})
            with self.assertRaises(HTTPException) as error:
                m.finance_resource(self.s, 'finance-registrations', self.registration_id, self.school_id, denied)
            self.assertEqual(error.exception.status_code, 403)

    def test_concurrent_lock_rejects_second_connection(self):
        key = f'assignment:{uuid.uuid4()}'
        m.finance_lock(self.s, key)
        def attempt():
            with m.engine.connect() as conn, conn.begin(), Session(bind=conn) as other:
                try:
                    m.finance_lock(other, key)
                except HTTPException as error:
                    return error.status_code
        with ThreadPoolExecutor(max_workers=1) as pool:
            self.assertEqual(pool.submit(attempt).result(), 409)

    def test_fee_creation_assignment_duplicate_and_summary(self):
        body = m.FinanceFeeInput(name='Scolarité rollback', amount=3000,
            scope='class', classId=str(self.cl.id), academicYearId=str(self.year.id),
            schoolId=self.school_id)
        result = m.create_finance_fee(body, self.admin, self.s)
        self.assertEqual(len(result['assignments']), 1)
        self.assertEqual(result['assignments'][0]['amount'], 3000)
        with self.assertRaises(HTTPException) as duplicate:
            m.create_finance_fee(body, self.admin, self.s)
        self.assertEqual(duplicate.exception.status_code, 409)
        summary = m.finance_summary(self.admin, self.s, self.school_id, self.year.id)
        self.assertEqual(summary['expected'], 13000)
        self.assertEqual(summary['remaining'], 13000)

    def test_generic_mutations_cannot_bypass_audit(self):
        for kind in ('finance-payments', 'finance-receipts', 'documents', 'finance-registrations',
                     'finance-fees', 'finance-fee-assignments', 'financial-payment-records'):
            with self.assertRaises(HTTPException):
                m.create_resource(kind, m.ResourceInput(payload={}), self.admin, self.s)
            with self.assertRaises(HTTPException):
                m.update_resource(kind, 'unknown', m.ResourceInput(payload={}), self.admin, self.s)
            with self.assertRaises(HTTPException):
                m.delete_resource(kind, 'unknown', self.admin, self.s)


if __name__ == "__main__":
    unittest.main(verbosity=2)

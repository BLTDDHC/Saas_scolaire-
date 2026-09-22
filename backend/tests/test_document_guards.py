"""Document source and scope checks, with all database writes rolled back."""
import unittest
import uuid
from datetime import datetime, timezone
from unittest.mock import patch
from fastapi import HTTPException
from app import main as m
import test_behavior_foundations as fixtures


class DocumentGuards(unittest.TestCase):
    add = fixtures.BehaviorFoundations.add
    assign = fixtures.BehaviorFoundations.assign
    cleanup = fixtures.BehaviorFoundations.cleanup

    def setUp(self):
        fixtures.BehaviorFoundations.setUp(self)
        self.tenant.enabled_modules = [*self.tenant.enabled_modules, 'documents']
        self.s.flush()

    def body(self, period=0):
        return m.DocumentCreateInput(title=f'Bulletin — {self.periods[period].name}',
            type='official_results', entityId=str(self.cl.id),
            schoolId=m.public_school_id(self.s, self.tenant.id),
            academicYearId=str(self.year.id), metadata={'periodId': str(self.periods[period].id),
                'studentId': str(self.students[0].id), 'documentKind': 'bulletin'})

    def result(self, status='official'):
        return {'calculationStatus': status, 'calculatedAt': '2026-09-09T00:00:00Z',
            'students': [{'studentId': str(self.students[0].id), 'average': 14.25,
                'rank': 1, 'subjects': [{'subject': 'Français', 'average': 14.25, 'coefficient': 1}]}]}

    def test_three_bulletins_consume_official_snapshot(self):
        behavior = {
            'calculationStatus': 'official',
            'students': [{
                'studentId': str(self.students[0].id),
                'average': 4.5,
            }],
        }
        with patch.object(m, 'school_results', return_value=self.result()), \
                patch('app.behavior.results', return_value=behavior):
            source = m.student_bulletin(self.students[0].id, self.year.id, self.admin, self.s)
            self.assertEqual(len(source['periods']), 3)
            created_ids = set()
            for index, period in enumerate(source['periods']):
                self.assertEqual(period['average'], 14.25)
                self.assertEqual(period['subjects'][0]['average'], 14.25)
                doc = m.create_school_document(self.body(index), self.admin, self.s)
                created_ids.add(doc['id'])
                self.assertEqual(doc['title'], f'Bulletin — {self.periods[index].name}')
                self.assertEqual(doc['metadata']['calculatedAt'], self.result()['calculatedAt'])
            overview = m.document_overview(self.admin, self.s)
            visible_ids = {
                item['id'] for item in overview['Bulletins']['items']
            }
            self.assertTrue(created_ids.issubset(visible_ids))

    def test_saved_finance_receipt_is_visible_as_document_without_duplication(self):
        receipt = self.add(m.Resource(
            id='RECEIPT-DOCUMENT-ROLLBACK',
            kind='finance-receipts',
            school_id=m.public_school_id(self.s, self.tenant.id),
            establishment_id=self.tenant.id,
            academic_year_id=self.year.id,
            payload={
                'id': 'RECEIPT-DOCUMENT-ROLLBACK',
                'receiptNumber': 'REC-ROLLBACK',
                'studentId': str(self.students[0].id),
                'studentName': 'Élève rollback',
                'classId': str(self.cl.id),
                'className': self.cl.name,
                'matricule': 'MAT-ROLLBACK-RECEIPT',
                'type': 'tuition',
                'amount': 25000,
                'academicYearId': str(self.year.id),
                'date': '2026-10-01',
                'status': 'active',
            },
        ))
        current = m.Principal(id=str(uuid.uuid4()), role='superadmin')
        rows = m.document_history_rows(current, self.s)
        self.assertEqual(sum(row.id == receipt.id for row in rows), 1)
        payload = m.document_history_payload(receipt, current, self.s)
        self.assertEqual(payload['type'], 'payment_receipt')
        self.assertEqual(payload['metadata']['receiptId'], receipt.id)
        self.assertEqual(payload['status'], 'generated')
        self.assertEqual(payload['classId'], str(self.cl.id))
        self.assertEqual(payload['matricule'], 'MAT-ROLLBACK-RECEIPT')
        self.assertEqual(payload['nature'], 'tuition')
        self.assertEqual(payload['amount'], 25000)
        self.assertEqual(payload['receiptNumber'], 'REC-ROLLBACK')

    def test_receipt_history_combines_server_side_filters_without_losing_context(self):
        school = m.public_school_id(self.s, self.tenant.id)
        current = m.Principal(
            id=self.principals[0].id, role='admin', school_id=school,
            direction_id=str(uuid.uuid4()),
            direction_cycle_ids=[str(self.cycle.id)],
        )
        student = self.students[0]
        student.registration_number = 'MAT-RECEIPT-001'
        for identifier, nature, month in (
            ('RECEIPT-MATCH', 'tuition', '2026-11'),
            ('RECEIPT-OTHER-NATURE', 'other', '2026-11'),
            ('RECEIPT-OTHER-MONTH', 'tuition', '2026-10'),
        ):
            self.add(m.Resource(
                id=identifier, kind='finance-receipts', school_id=school,
                establishment_id=self.tenant.id,
                academic_year_id=self.year.id,
                created_at=datetime.fromisoformat(f'{month}-02T10:00:00+00:00'),
                payload={
                    'id': identifier, 'receiptNumber': f'REC-{identifier}',
                    'studentId': str(student.id),
                    'studentName': f'{student.last_name} {student.first_name}',
                    'classId': str(self.cl.id), 'className': self.cl.name,
                    'matricule': student.registration_number,
                    'type': nature, 'amount': 10000,
                    'academicYearId': str(self.year.id),
                    'date': f'{month}-02', 'status': 'active',
                },
            ))
        page = m.paged_document_history(
            current, self.s, category='Reçus', page=1, page_size=100,
            academic_year_id=str(self.year.id), class_id=str(self.cl.id),
            nature='tuition', generated_month='2026-11',
            last_name='roll', first_name='s0', matricule='receipt-001',
        )
        self.assertEqual(page['total'], 1)
        self.assertEqual(page['items'][0]['id'], 'DOC_RECEIPT_RECEIPT-MATCH')
        self.assertEqual(page['items'][0]['className'], self.cl.name)
        self.assertEqual(page['items'][0]['receiptNumber'], 'REC-RECEIPT-MATCH')

    def test_student_and_parent_cannot_open_documents_module(self):
        guard = m.require_module_roles('documents', 'superadmin', 'admin')
        for role in ('student', 'parent'):
            current = m.Principal(
                id=str(uuid.uuid4()),
                role=role,
                school_id=m.public_school_id(self.s, self.tenant.id),
                student_id=(str(self.students[0].id)
                            if role == 'student' else None),
            )
            with self.assertRaises(HTTPException) as error:
                guard(current, self.s)
            self.assertEqual(error.exception.status_code, 403)

    def test_unofficial_or_wrong_student_rejected(self):
        for status in ('waiting', 'ready', 'stale'):
            with patch.object(m, 'school_results', return_value=self.result(status)):
                with self.assertRaises(HTTPException) as error:
                    m.create_school_document(self.body(), self.admin, self.s)
                self.assertEqual(error.exception.status_code, 409)
        result = self.result()
        result['students'] = []
        with patch.object(m, 'school_results', return_value=result):
            with self.assertRaises(HTTPException) as error:
                m.create_school_document(self.body(), self.admin, self.s)
            self.assertEqual(error.exception.status_code, 403)

    def test_all_cycles_deny_document_outside_direction(self):
        for code in ('MATERNELLE', 'PRIMAIRE', 'COLLEGE', 'LYCEE'):
            self.cycle.code = code
            self.s.flush()
            denied = self.admin.model_copy(update={'role': 'admin',
                'school_id': m.public_school_id(self.s, self.tenant.id),
                'direction_id': str(uuid.uuid4()), 'direction_cycle_ids': [str(uuid.uuid4())]})
            with self.assertRaises(HTTPException) as error:
                m.create_school_document(self.body(), denied, self.s)
            self.assertEqual(error.exception.status_code, 403)

    def test_archived_document_detects_stale_source(self):
        with patch.object(m, 'school_results', return_value=self.result()):
            doc = m.create_school_document(self.body(), self.admin, self.s)
        row = self.s.get(m.Resource, {'kind': 'documents', 'id': doc['id']})
        with patch.object(m, 'school_results', return_value=self.result('stale')):
            self.assertEqual(m.resource_view(row, self.admin, self.s)['status'], 'stale')
        self.assertEqual(row.payload['status'], 'generated')

    def test_history_metadata_is_batched_and_direction_scoped(self):
        school = m.public_school_id(self.s, self.tenant.id)
        current = m.Principal(
            id=self.principals[0].id, role='admin', school_id=school,
            direction_id=str(uuid.uuid4()),
            direction_cycle_ids=[str(self.cycle.id)],
        )
        other_cycle = self.add(m.SchoolCycle(
            establishment_id=self.tenant.id, code='LYCEE', name='Lycée'
        ))
        other_class = self.add(m.SchoolClass(
            establishment_id=self.tenant.id,
            academic_year_id=self.year.id,
            cycle_id=other_cycle.id,
            name='Terminale test',
        ))
        for identifier, school_class, cycle in (
            ('DOC-OWN', self.cl, self.cycle),
            ('DOC-OTHER', other_class, other_cycle),
        ):
            self.add(m.Resource(
                id=identifier, kind='documents', school_id=school,
                establishment_id=self.tenant.id, cycle_id=cycle.id,
                academic_year_id=self.year.id,
                payload={'id': identifier, 'type': 'official_results',
                         'entityId': str(school_class.id),
                         'status': 'generated'},
            ))
        result = m.list_resources('documents', current, self.s)
        self.assertEqual([item['id'] for item in result], ['DOC-OWN'])

    def test_teacher_cannot_access_document_history(self):
        teacher = m.Principal(
            id=str(uuid.uuid4()), role='teacher',
            school_id=m.public_school_id(self.s, self.tenant.id),
            teacher_id=str(self.teachers[0].id),
        )
        with self.assertRaises(HTTPException) as error:
            m.list_resources('documents', teacher, self.s)
        self.assertEqual(error.exception.status_code, 403)

    def test_bulletin_history_is_filtered_sorted_and_paginated_server_side(self):
        school = m.public_school_id(self.s, self.tenant.id)
        current = m.Principal(
            id=self.principals[0].id, role='admin', school_id=school,
            direction_id=str(uuid.uuid4()),
            direction_cycle_ids=[str(self.cycle.id)],
        )
        self.students[0].registration_number = 'MAT-ROLLBACK-001'
        for index in range(7):
            self.add(m.Resource(
                id=f'DOC-PAGED-{index}', kind='documents', school_id=school,
                establishment_id=self.tenant.id, cycle_id=self.cycle.id,
                academic_year_id=self.year.id,
                created_at=datetime(2026, 11, index + 1, tzinfo=timezone.utc),
                payload={
                    'id': f'DOC-PAGED-{index}', 'title': f'Bulletin {index}',
                    'type': 'official_results', 'entityId': str(self.cl.id),
                    'academicYearId': str(self.year.id),
                    'date': f'2026-11-{index + 1:02d}', 'status': 'generated',
                    'metadata': {'documentKind': 'bulletin',
                                 'studentId': str(self.students[0].id)},
                },
            ))
        page = m.paged_document_history(
            current, self.s, category='Bulletins', page=1, page_size=5,
            generated_month='2026-11', class_id=str(self.cl.id),
            last_name='ROLL', matricule='rollback-001',
        )
        self.assertEqual(page['total'], 7)
        self.assertEqual(page['pageCount'], 2)
        self.assertEqual(len(page['items']), 5)
        self.assertEqual(page['items'][0]['id'], 'DOC-PAGED-6')

    def test_document_overview_never_returns_more_than_five_per_category(self):
        school = m.public_school_id(self.s, self.tenant.id)
        current = m.Principal(
            id=self.principals[0].id, role='admin', school_id=school,
            direction_id=str(uuid.uuid4()),
            direction_cycle_ids=[str(self.cycle.id)],
        )
        for index in range(6):
            self.add(m.Resource(
                id=f'DOC-OVERVIEW-{index}', kind='documents', school_id=school,
                establishment_id=self.tenant.id, cycle_id=self.cycle.id,
                academic_year_id=self.year.id,
                payload={'id': f'DOC-OVERVIEW-{index}',
                         'type': 'official_results',
                         'entityId': str(self.cl.id),
                         'status': 'generated',
                         'metadata': {'documentKind': 'bulletin'}},
            ))
        result = m.document_overview(current, self.s)
        self.assertEqual(result['Bulletins']['total'], 6)
        self.assertEqual(len(result['Bulletins']['items']), 5)
        self.assertTrue(all(
            len(result[category]['items']) <= 5
            for category in m.DOCUMENT_CATEGORIES
        ))

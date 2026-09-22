"""Attendance against real PostgreSQL. All writes roll back, including fixture identities."""
import unittest
import uuid
from datetime import date, datetime, time, timedelta, timezone
from unittest.mock import patch
from concurrent.futures import ThreadPoolExecutor
from sqlalchemy import select, func
from sqlalchemy.orm import Session
from fastapi import HTTPException
from pydantic import ValidationError

from app import main as m, attendance as a
import test_behavior_foundations as fixtures
from test_behavior_foundations import ASGIClient


class AttendanceTests(unittest.TestCase):
    add = fixtures.BehaviorFoundations.add
    assign = fixtures.BehaviorFoundations.assign
    cleanup = fixtures.BehaviorFoundations.cleanup

    def setUp(self):
        fixtures.BehaviorFoundations.setUp(self)
        self.tenant.enabled_modules = [*self.tenant.enabled_modules, 'attendance', 'schedule']
        self.s.flush()
        self.day=date.today()
        self.clock=datetime.combine(self.day,time(10,15),tzinfo=timezone.utc)
        self.clock_patch=patch.object(a,'now_local',lambda:self.clock)
        self.clock_patch.start();self.addCleanup(self.clock_patch.stop)
        self.schedules=[]
        for i,teacher in enumerate(self.teachers):
            assignment=self.s.scalar(select(m.Affectation).where(m.Affectation.teacher_id==teacher.id))
            schedule=m.ScheduleEntry(establishment_id=self.tenant.id,academic_year_id=self.year.id,
                class_id=self.cl.id,teacher_id=teacher.id,subject_id=assignment.subject_id,
                affectation_id=assignment.id,weekday=self.day.isoweekday(),
                start_time=time(10+i),end_time=time(11+i),created_at=self.clock-timedelta(days=2))
            schedule.attendance_context=a.snapshot(self.s,schedule)
            self.schedules.append(self.add(schedule))

    def body(self,i=0,action='submit',statuses=('present','absent'),entries=None,day=None):
        return m.AttendanceBatchInput(classId=self.cl.id,scheduleId=self.schedules[i].id,
            date=day or self.day, action=action, entries=entries if entries is not None else
            [{'studentId':s.id,'status':statuses[n]} for n,s in enumerate(self.students)])

    def send(self,i=0,**kw):
        self.clock=datetime.combine(self.day,time(10+i,15),tzinfo=timezone.utc)
        return a.save(self.principals[i],self.s,self.body(i,**kw))

    def report(self,**kw):
        return a.report(self.admin,self.s,self.year.id,day=self.day,**kw)

    def test_all_statuses_and_server_roster(self):
        opened=a.open_sheet(self.principals[0],self.s,self.schedules[0].id,self.day)
        self.assertEqual({s['id'] for s in opened['students']},{str(s.id) for s in self.students})
        result=self.send(statuses=('present','justified'))
        self.assertEqual({r['status'] for r in result['records']},{'present','justified'})
        self.send(1,statuses=('absent','present'))
        self.assertEqual(self.report()['statistics'],{'present':2,'absent':1,'justified':1,'total':4,'attendanceRate':50})

    def test_incomplete_extra_duplicate_invalid(self):
        for entries in ([{'studentId':self.students[0].id,'status':'present'}],
                        [{'studentId':uuid.uuid4(),'status':'present'}],
                        [{'studentId':self.students[0].id,'status':'present'}]*2):
            with self.assertRaises(HTTPException): self.send(entries=entries)
        with self.assertRaises(ValidationError): self.body(statuses=('late','present'))

    def test_draft_repeated_save_reload_submit_lock(self):
        for _ in range(3): self.send(action='draft')
        self.assertEqual(self.report()['receivedCount'],0)
        self.assertEqual(self.report()['records'],[])
        self.assertEqual(len(a.open_sheet(self.principals[0],self.s,self.schedules[0].id,self.day)['records']),2)
        self.assertEqual(self.s.scalar(select(func.count()).select_from(m.AttendanceRecord).where(m.AttendanceRecord.class_id==self.cl.id)),2)
        self.send()
        for action in ('draft','submit'):
            with self.assertRaises(HTTPException) as error:self.send(action=action)
            self.assertEqual(error.exception.status_code,409)

    def test_teacher_wrong_schedule_unassigned_inactive(self):
        with self.assertRaises(HTTPException): a.save(self.principals[1],self.s,self.body())
        assignment=self.s.get(m.Affectation,self.schedules[0].affectation_id)
        assignment.status='inactive';self.s.flush()
        with self.assertRaises(HTTPException): self.send()
        assignment.status='active';self.teachers[0].status='inactive';self.s.flush()
        with self.assertRaises(HTTPException): self.send()

    def test_wrong_day_time_year_class(self):
        with self.assertRaises(HTTPException) as future: self.send(day=self.day+timedelta(days=1))
        self.assertIn('date prévue', future.exception.detail)
        with self.assertRaises(HTTPException) as past: self.send(day=self.day-timedelta(days=1))
        self.assertIn('période de saisie', past.exception.detail)
        self.clock=datetime.combine(self.day,time(14),tzinfo=timezone.utc)
        self.assertEqual(a.save(self.principals[0],self.s,self.body())['sheetStatus'],'locked')
        self.year.start_date=self.day+timedelta(days=1);self.s.flush()
        with self.assertRaises(HTTPException):self.send()
        self.year.start_date=self.day-timedelta(days=1);self.s.flush()
        body=self.body().model_copy(update={'class_id':uuid.uuid4()})
        with self.assertRaises(HTTPException):a.save(self.principals[0],self.s,body)

    def test_start_boundary_and_all_remaining_day(self):
        self.clock=datetime.combine(self.day,time(9,59),tzinfo=timezone.utc)
        with self.assertRaises(HTTPException) as early:
            a.save(self.principals[0],self.s,self.body(action='draft'))
        self.assertEqual(early.exception.status_code,409)
        self.assertFalse(m.schedule_json(self.schedules[0],self.s)['canTakeAttendance'])
        self.assertEqual(datetime.fromisoformat(m.schedule_json(self.schedules[0],self.s)['nextAttendanceChangeAt']).time(),time(10))
        for hour, minute in [(10,0),(10,30),(11,0),(14,0),(22,0),(23,59)]:
            self.clock=datetime.combine(self.day,time(hour,minute),tzinfo=timezone.utc)
            self.assertTrue(m.schedule_json(self.schedules[0],self.s)['canTakeAttendance'])
            self.assertEqual(datetime.fromisoformat(m.schedule_json(self.schedules[0],self.s)['nextAttendanceChangeAt']).date(),self.day+timedelta(days=1))
            self.assertEqual(a.save(self.principals[0],self.s,self.body(action='draft'))['sheetStatus'],'draft')

    def test_schedule_ui_reports_school_year_block_without_changing_dates(self):
        self.year.start_date=self.day+timedelta(days=1);self.s.flush()
        row=m.schedule_json(self.schedules[0],self.s)
        self.assertFalse(row['canTakeAttendance'])
        self.assertEqual(row['attendanceDate'],self.day.isoformat())
        self.assertIn(self.year.start_date.strftime('%d/%m/%Y'),row['attendanceUnavailableReason'])

    def test_wrong_subject_assignment_refused(self):
        self.schedules[0].subject_id=self.schedules[1].subject_id
        self.s.flush()
        with self.assertRaises(HTTPException) as error:self.send()
        self.assertEqual(error.exception.status_code,403)

    def test_two_teachers_do_not_share_lines(self):
        self.send(0)
        self.clock=self.clock.replace(hour=11)
        self.assertEqual(a.open_sheet(self.principals[1],self.s,self.schedules[1].id,self.day)['records'],[])
        self.send(1)
        with self.assertRaises(HTTPException):a.open_sheet(self.principals[1],self.s,self.schedules[0].id,self.day)

    def test_followup_two_of_three_then_all(self):
        self.send(0);self.send(1)
        report=self.report()
        self.assertEqual((report['expectedCount'],report['receivedCount'],report['missingCount']),(3,2,1))
        self.assertFalse(report['allReceived'])
        self.send(2)
        self.assertTrue(self.report()['allReceived'])

    def test_history_stable_after_planning_and_class_change(self):
        self.send(0)
        old=self.schedules[0]
        before=self.report()['records']
        # Real schedule route creates a new version, preserving the retired row.
        admin=m.Principal(id=self.admin.id,role='admin',school_id=str(self.tenant.id),
            direction_id=str(uuid.uuid4()),direction_cycle_ids=[str(self.cycle.id)])
        body=m.ScheduleEntryInput(classId=self.cl.id,teacherId=old.teacher_id,subjectId=old.subject_id,
            weekday=old.weekday,startTime='15:00',endTime='16:00')
        updated=m.update_schedule_entry(old.id,body,admin,self.s)
        self.assertNotEqual(updated['id'],str(old.id))
        self.assertEqual(old.status,'archived')
        self.cl.name='Changed class';self.s.flush()
        self.assertEqual(self.report()['records'],before)
        self.assertEqual(len(self.report(student_id=self.students[0].id)['records']),1)

    def test_directions_and_superadmin_filters(self):
        self.send()
        for cycle_code in ('MATERNELLE','PRIMAIRE','COLLEGE','LYCEE'):
            foreign=m.Principal(id=self.admin.id,role='admin',school_id=str(self.tenant.id),
                direction_id=str(uuid.uuid4()),direction_cycle_ids=[str(uuid.uuid4())])
            self.assertEqual(a.report(foreign,self.s,self.year.id,day=self.day)['records'],[])
            with self.assertRaises(HTTPException):a.open_sheet(foreign,self.s,self.schedules[0].id,self.day)
        self.assertEqual(len(self.report(subject_id=self.schedules[0].subject_id)['records']),2)
        self.assertEqual(len(self.report(teacher_id=self.teachers[1].id)['records']),0)
        self.assertEqual(len(self.report(class_id=self.cl.id,schedule_id=self.schedules[0].id)['records']),2)

    def test_concurrent_second_session_refused(self):
        self.send()
        body=self.body()
        def attempt():
            with m.engine.connect() as connection:
                transaction=connection.begin()
                second=Session(bind=connection)
                try:
                    try:a.save(self.principals[0],second,body)
                    except HTTPException as error:return error.status_code
                    return 200
                finally:second.close();transaction.rollback()
        with ThreadPoolExecutor(max_workers=1) as pool:
            self.assertEqual(pool.submit(attempt).result(timeout=10),409)

    def test_period_context_and_filter(self):
        self.send()
        period=self.periods[0]
        period.start_date=self.day;period.end_date=self.day;self.s.flush()
        self.assertEqual(self.report(period_id=period.id)['receivedCount'],1)
        period.start_date=self.day+timedelta(days=1);period.end_date=self.day+timedelta(days=2);self.s.flush()
        self.assertEqual(self.report(period_id=period.id)['expectedCount'],0)
        self.assertEqual(len(a.contexts(self.admin,self.s)[-1]['periods'])>0,True)

    def test_three_real_direction_scopes(self):
        admins=[]
        for i,code in enumerate(('PRIMAIRE','COLLEGE','LYCEE')):
            cycle=self.cycle if code=='COLLEGE' else self.add(m.SchoolCycle(
                establishment_id=self.tenant.id,code=code,name=code))
            direction=self.add(m.SchoolDirection(establishment_id=self.tenant.id,code=code,name=code))
            self.add(m.SchoolDirectionCycle(establishment_id=self.tenant.id,
                direction_id=direction.id,cycle_id=cycle.id))
            self.cl.cycle_id=cycle.id;self.s.flush()
            self.schedules[i].attendance_context=a.snapshot(self.s,self.schedules[i]);self.s.flush()
            self.send(i)
            admins.append(m.Principal(id=self.admin.id,role='admin',school_id=str(self.tenant.id),
                direction_id=str(direction.id),direction_cycle_ids=[str(cycle.id)]))
        for i,admin in enumerate(admins):
            self.assertEqual(len(a.report(admin,self.s,self.year.id,day=self.day)['records']),2)
            self.assertEqual(len(a.report(self.admin,self.s,self.year.id,direction_id=admin.direction_id)['records']),2)
            for j in range(3):
                if i!=j:
                    with self.assertRaises(HTTPException):a.open_sheet(admin,self.s,self.schedules[j].id,self.day)
        self.assertEqual(len(self.report()['records']),6)

    def test_registration_after_session_not_expected(self):
        reg=self.s.scalar(select(m.StudentAcademicRegistration).where(m.StudentAcademicRegistration.student_id==self.students[0].id))
        reg.registration_date=self.day+timedelta(days=1);self.s.flush()
        with self.assertRaises(HTTPException):self.send()
        self.assertEqual(len(a.open_sheet(self.principals[0],self.s,self.schedules[0].id,self.day)['students']),1)

    def test_schedule_is_scoped_for_teacher_student_and_parent(self):
        teacher_rows = m.list_schedule(
            self.year.id, None, self.principals[0], self.s
        )
        self.assertEqual(len(teacher_rows), 1)
        self.assertEqual(teacher_rows[0]['teacherId'], str(self.teachers[0].id))

        student = self.students[0]
        student_current = m.Principal(
            id=str(uuid.uuid4()), role='student',
            school_id=str(self.tenant.id), student_id=str(student.id),
        )
        student_rows = m.list_schedule(
            self.year.id, None, student_current, self.s
        )
        self.assertEqual(len(student_rows), 3)
        with self.assertRaises(HTTPException):
            m.list_schedule(self.year.id, uuid.uuid4(), student_current, self.s)

        parent_user = self.add(m.User(
            email=f'{uuid.uuid4()}@rollback.invalid', password_hash='not-a-login',
            name='Parent Rollback', role='parent', school_id=self.tenant.id,
        ))
        guardian = self.add(m.Guardian(
            establishment_id=self.tenant.id, user_id=parent_user.id,
            first_name='Parent', last_name='Rollback', phone='+242060000001',
            status='active',
        ))
        self.add(m.StudentGuardian(
            establishment_id=self.tenant.id, student_id=student.id,
            guardian_id=guardian.id, relationship='parent', is_primary=True,
        ))
        parent_current = m.Principal(
            id=str(parent_user.id), role='parent', school_id=str(self.tenant.id),
        )
        parent_rows = m.list_schedule(
            self.year.id, None, parent_current, self.s
        )
        self.assertEqual(len(parent_rows), 3)

    def test_http_sheet_save_and_permissions(self):
        actor=[self.principals[0]]
        previous=dict(m.app.dependency_overrides)
        m.app.dependency_overrides[m.principal]=lambda:actor[0]
        m.app.dependency_overrides[m.db]=lambda:self.s
        client=ASGIClient()
        try:
            self.assertEqual(client.put('/api/v1/school/attendance',json=self.body().model_dump(mode='json',by_alias=True)).status_code,200)
            self.assertEqual(client.put('/api/v1/school/attendance',json=self.body().model_dump(mode='json',by_alias=True)).status_code,409)
            actor[0]=self.admin
            self.assertEqual(client.get('/api/v1/school/attendance/report',params={'academic_year_id':str(self.year.id),'attendance_date':self.day.isoformat()}).status_code,403)
            actor[0]=m.Principal(id=self.principals[0].id,role='admin',school_id=str(self.tenant.id),
                direction_id=str(uuid.uuid4()),direction_cycle_ids=[str(self.cycle.id)])
            self.assertEqual(client.get('/api/v1/school/attendance/report',params={'academic_year_id':str(self.year.id),'attendance_date':self.day.isoformat()}).status_code,200)
        finally:m.app.dependency_overrides.clear();m.app.dependency_overrides.update(previous)


if __name__=='__main__':unittest.main(verbosity=2)

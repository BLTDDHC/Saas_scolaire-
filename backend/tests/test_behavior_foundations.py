"""Real PostgreSQL tests; every fixture and write stays in an outer rollback."""
import unittest
import asyncio
import json
from urllib.parse import urlencode
import uuid
from datetime import datetime, timezone
from datetime import date
from concurrent.futures import ThreadPoolExecutor
from types import SimpleNamespace

from fastapi import HTTPException
from pydantic import ValidationError
from sqlalchemy import select, func, text
from sqlalchemy.orm import Session
from sqlalchemy.exc import IntegrityError

from app import main as m, behavior as b


class ASGIClient:
    """Exercise the real ASGI routing/dependencies without optional httpx."""
    def request(self, method, path, json_body=None, params=None):
        async def run():
            sent=[]
            body=json.dumps(json_body).encode() if json_body is not None else b""
            delivered=False
            async def receive():
                nonlocal delivered
                if not delivered:
                    delivered=True
                    return {"type":"http.request","body":body,"more_body":False}
                await asyncio.Event().wait()
            async def send(message): sent.append(message)
            await m.app({"type":"http","asgi":{"version":"3.0"},"http_version":"1.1",
                "method":method,"scheme":"http","path":path,"raw_path":path.encode(),
                "query_string":urlencode(params or {}).encode(),
                "headers":[(b"content-type",b"application/json")],
                "server":("test",80),"client":("test",1),"root_path":""},receive,send)
            status=next(x["status"] for x in sent if x["type"]=="http.response.start")
            raw=b"".join(x.get("body",b"") for x in sent if x["type"]=="http.response.body")
            return SimpleNamespace(status_code=status,json=lambda:json.loads(raw))
        return asyncio.run(run())
    def put(self,path,json): return self.request("PUT",path,json)
    def get(self,path,params=None): return self.request("GET",path,params=params)
    def close(self): pass


class BehaviorFoundations(unittest.TestCase):
    def setUp(self):
        self.connection = m.engine.connect()
        self.outer = self.connection.begin()
        self.s = Session(bind=self.connection, join_transaction_mode="create_savepoint")
        self.addCleanup(self.cleanup)
        self.tenant = self.add(m.Establishment(name="ROLLBACK behavior", institution_type="secondary",
            city="Test", enabled_modules=["behavior", "grades"]))
        self.cycle = self.add(m.SchoolCycle(establishment_id=self.tenant.id, code="COLLEGE", name="Collège"))
        self.year = self.add(m.AcademicYear(establishment_id=self.tenant.id, name="2026-2027",
            start_date=date(2026,9,1), end_date=date(2027,7,1), status="active", is_active=True))
        self.cl = self.add(m.SchoolClass(establishment_id=self.tenant.id, academic_year_id=self.year.id,
            cycle_id=self.cycle.id, name="Test", status="active"))
        self.periods = [self.add(m.AcademicPeriod(establishment_id=self.tenant.id,
            academic_year_id=self.year.id, code=f"T{i}", name=f"Trimestre {i}", period_type="trimester",
            sort_order=i)) for i in (1,2,3)]
        self.students = [self.add(m.Student(establishment_id=self.tenant.id, first_name=f"S{i}",
            last_name="Rollback")) for i in range(2)]
        for student in self.students:
            self.add(m.StudentAcademicRegistration(establishment_id=self.tenant.id, student_id=student.id,
                class_id=self.cl.id, academic_year_id=self.year.id, status="validated"))
        self.teachers = []
        self.principals = []
        for i in range(3):
            user = self.add(m.User(email=f"{uuid.uuid4()}@rollback.invalid", password_hash="not-a-login",
                name="Rollback", role="teacher", school_id=self.tenant.id))
            teacher = self.add(m.Teacher(establishment_id=self.tenant.id, user_id=user.id,
                first_name=f"T{i}", last_name="Rollback"))
            self.teachers.append(teacher)
            self.principals.append(m.Principal(id=str(user.id), role="teacher", teacher_id=str(teacher.id),
                school_id=str(self.tenant.id)))
            self.assign(teacher)
        self.admin = m.Principal(id=self.principals[0].id, role="superadmin")

    def cleanup(self):
        self.s.close()
        self.outer.rollback()
        self.connection.close()

    def add(self, row):
        self.s.add(row)
        self.s.flush()
        return row

    def assign(self, teacher):
        subject = self.add(m.Subject(establishment_id=self.tenant.id, name=str(uuid.uuid4())))
        return self.add(m.Affectation(establishment_id=self.tenant.id, teacher_id=teacher.id,
            class_id=self.cl.id, subject_id=subject.id))

    def body(self, stars=3, period=0, entries=None, action="submit"):
        return m.BehaviorBatchInput(classId=self.cl.id, periodId=self.periods[period].id,
            entries=entries if entries is not None else [{"studentId": s.id, "stars": stars} for s in self.students],
            action=action)

    def send(self, teacher=0, stars=3, period=0, **kw):
        return b.save_sheet(self.principals[teacher], self.s, self.body(stars, period, **kw))

    def result(self, period=0):
        return b.results(self.admin, self.s, self.cl.id, self.periods[period].id)

    def complete(self, scores=(3,2,4)):
        for i, score in enumerate(scores): self.send(i, score)
        return b.calculate(self.admin, self.s, self.cl.id, self.periods[0].id)

    def test_two_teachers_independent_and_duplicate_refused(self):
        self.assertEqual(len(self.send(0)), 2)
        self.assertEqual(len(self.send(1)), 2)
        with self.assertRaises(HTTPException) as error: self.send(0)
        self.assertEqual(error.exception.status_code,409)
        own=b.list_events(self.principals[1],self.s,self.cl.id,self.periods[0].id)
        self.assertTrue(all(x["teacherId"]==str(self.teachers[1].id) for x in own))

    def test_multi_subject_once_and_exact_mean(self):
        self.assign(self.teachers[0])
        result=self.complete()
        self.assertEqual(result["expectedCount"],3)
        self.assertEqual(result["students"][0]["average"],3)
        self.assertEqual(result["students"][0]["contributionCount"],3)

    def test_decimal_mean(self):
        self.teachers[2].status="inactive"
        self.s.flush()
        self.send(0,4); self.send(1,5)
        result=b.calculate(self.admin,self.s,self.cl.id,self.periods[0].id)
        self.assertEqual(result["students"][0]["average"],4.5)
        self.assertEqual(result["students"][0]["sum"],9)

    def test_multi_subject_two_teachers_mean_3_5_and_database_uniqueness(self):
        self.assign(self.teachers[0])
        self.teachers[2].status="inactive";self.s.flush()
        saved=self.send(0,3);self.send(1,4)
        result=b.calculate(self.admin,self.s,self.cl.id,self.periods[0].id)
        self.assertEqual(result["expectedCount"],2)
        self.assertEqual(result["students"][0]["average"],3.5)
        original=self.s.get(m.BehaviorEvent,uuid.UUID(saved[0]["id"]))
        values={c.name:getattr(original,c.name) for c in m.BehaviorEvent.__table__.columns if c.name!="id"}
        with self.assertRaises(IntegrityError):
            with self.s.begin_nested():
                self.s.add(m.BehaviorEvent(**values));self.s.flush()

    def test_stale_contribution_period_year_and_class(self):
        for source in ("contribution","period","year","class"):
            with self.subTest(source=source):
                # A savepoint lets each mutation start from the same official state.
                if source == "contribution": self.complete()
                with self.s.begin_nested() as mutation:
                    if source=="contribution":
                        event=self.s.scalar(select(m.BehaviorEvent).where(m.BehaviorEvent.class_id==self.cl.id))
                        event.status="archived"
                    elif source=="period": self.periods[0].status="archived"
                    elif source=="year": self.year.end_date=date(2027,8,1)
                    else: self.cl.status="archived"
                    self.s.flush()
                    self.assertEqual(self.result()["calculationStatus"],"stale")
                    mutation.rollback()

    def test_incomplete_foreign_duplicate_and_invalid_stars(self):
        for entries in ([{"studentId":self.students[0].id,"stars":3}],
                        [{"studentId":uuid.uuid4(),"stars":3}],
                        [{"studentId":self.students[0].id,"stars":3}]*2):
            with self.assertRaises(HTTPException): self.send(entries=entries)
        for stars in (0,6,None,3.5,True):
            with self.assertRaises(ValidationError): self.body(stars)

    def test_draft_reload_then_lock(self):
        self.send(action="draft", entries=[{"studentId":self.students[0].id,"stars":1}])
        self.assertEqual(self.result()["calculationStatus"],"waiting")
        self.send()
        with self.assertRaises(HTTPException): self.send(action="draft")

    def test_periods_and_years_separated(self):
        self.complete()
        self.assertEqual(self.result(1)["calculationStatus"],"waiting")
        self.send(0,5,1)
        self.assertEqual(self.result()["students"][0]["average"],3)
        other=self.add(m.AcademicYear(establishment_id=self.tenant.id,name="other",
            start_date=date(2027,9,1),end_date=date(2028,7,1)))
        self.periods[1].academic_year_id=other.id;self.s.flush()
        with self.assertRaises(HTTPException): self.send(1,period=1)

    def test_direction_tenant_and_unassigned_refused(self):
        bad=m.Principal(id=self.admin.id,role="admin",school_id=str(self.tenant.id),
            direction_id=str(uuid.uuid4()),direction_cycle_ids=[str(uuid.uuid4())])
        with self.assertRaises(HTTPException): b.results(bad,self.s,self.cl.id,self.periods[0].id)
        bad=self.principals[0].model_copy(update={"teacher_id":str(uuid.uuid4())})
        with self.assertRaises(HTTPException): b.save_sheet(bad,self.s,self.body())
        with self.assertRaises(HTTPException):
            b.results(self.admin,self.s,self.cl.id,self.periods[0].id,str(uuid.uuid4()))

    def test_stale_on_source_changes_and_no_false_multi_subject_stale(self):
        self.complete()
        self.assign(self.teachers[0])
        self.s.flush()
        self.assertEqual(self.result()["calculationStatus"],"official")
        self.teachers[2].status="inactive";self.s.flush()
        self.assertEqual(self.result()["calculationStatus"],"stale")
        self.assertEqual(self.result()["students"],[])

    def test_stale_registration_removed(self):
        self.complete()
        reg=self.s.scalar(select(m.StudentAcademicRegistration).where(
            m.StudentAcademicRegistration.student_id==self.students[0].id))
        reg.status="archived";self.s.flush()
        self.assertEqual(self.result()["calculationStatus"],"stale")

    def test_waiting_ready_official(self):
        self.assertEqual(self.result()["calculationStatus"],"waiting")
        with self.assertRaises(HTTPException): b.calculate(self.admin,self.s,self.cl.id,self.periods[0].id)
        for i in range(3): self.send(i)
        self.assertEqual(self.result()["calculationStatus"],"ready")
        self.assertEqual(b.calculate(self.admin,self.s,self.cl.id,self.periods[0].id)["calculationStatus"],"official")

    def test_concurrent_context_lock_real_connections(self):
        # No committed test fixtures are needed: the production advisory key is
        # shared between connections, independently of fixture visibility.
        b.lock_context(self.s,self.cl,self.periods[0])
        cl=SimpleNamespace(establishment_id=self.tenant.id,id=self.cl.id)
        period=SimpleNamespace(id=self.periods[0].id)
        def attempt():
            with m.engine.connect() as conn, conn.begin(), Session(bind=conn) as second:
                try: b.lock_context(second,cl,period)
                except HTTPException as error: return error.status_code
                return 200
        with ThreadPoolExecutor(max_workers=1) as pool:
            self.assertEqual(pool.submit(attempt).result(timeout=10),409)

    def test_annual_exactly_three_no_months(self):
        self.assertEqual(len(m.annual_trimester_periods(self.s,self.tenant.id,self.year.id)),3)
        self.add(m.AcademicPeriod(establishment_id=self.tenant.id,academic_year_id=self.year.id,
            code="MONTH",name="Month",period_type="month"))
        self.assertEqual(len(m.annual_trimester_periods(self.s,self.tenant.id,self.year.id)),3)
        self.periods[2].status="archived";self.s.flush()
        self.assertEqual(m.annual_trimester_periods(self.s,self.tenant.id,self.year.id),[])

    def test_annual_decisions_require_three_official_results_and_preserve_excluded(self):
        now=datetime.now(timezone.utc)
        for period in self.periods:
            self.add(m.ResultCalculation(establishment_id=self.tenant.id,academic_year_id=self.year.id,
                class_id=self.cl.id,academic_period_id=period.id,status="official",
                source_updated_at=now,calculated_at=now,
                payload={"students":[{"studentId":str(s.id),"average":12} for s in self.students]}))
        excluded=self.add(m.StudentAnnualDecision(establishment_id=self.tenant.id,
            academic_year_id=self.year.id,student_id=self.students[1].id,decision="excluded",
            reason="Discipline",decided_by=uuid.UUID(self.admin.id),decided_at=now))
        self.periods[2].status="archived";self.s.flush()
        self.assertEqual(m.sync_automatic_annual_decisions_for_class(self.cl,self.admin,self.s,now),0)
        self.periods[1].status="archived";self.s.flush()
        self.assertEqual(m.sync_automatic_annual_decisions_for_class(self.cl,self.admin,self.s,now),0)
        self.periods[1].status="active";self.periods[2].status="active";self.s.flush()
        self.assertEqual(m.sync_automatic_annual_decisions_for_class(self.cl,self.admin,self.s,now),1)
        self.assertEqual(excluded.decision,"excluded")

    def test_real_concurrent_submission_rollback(self):
        # Use an existing authorized context, only INSERT transient contributions.
        # Neither connection commits its outer transaction; no test data survives.
        with m.engine.connect() as conn:
            outer=conn.begin()
            first=Session(bind=conn,join_transaction_mode="create_savepoint")
            try:
                row=first.execute(select(m.SchoolClass,m.AcademicPeriod,m.Teacher).join(
                    m.AcademicPeriod,m.AcademicPeriod.academic_year_id==m.SchoolClass.academic_year_id
                ).join(m.Affectation,m.Affectation.class_id==m.SchoolClass.id).join(
                    m.Teacher,m.Teacher.id==m.Affectation.teacher_id).where(
                    m.AcademicPeriod.period_type=="trimester",m.AcademicPeriod.status=="active",
                    m.Affectation.status=="active",m.Teacher.user_id.is_not(None))).first()
                if not row: self.skipTest("No existing authorized context for real concurrency check")
                cl,period,teacher=row
                current=m.Principal(id=str(teacher.user_id),role="teacher",teacher_id=str(teacher.id),
                    school_id=m.public_school_id(first,cl.establishment_id))
                year=first.get(m.AcademicYear,cl.academic_year_id)
                students,_,events=b.sources(first,cl,period,year)
                if not students or any(e.teacher_id==teacher.id for e in events):
                    self.skipTest("Existing context has no students or already has a sheet")
                body=m.BehaviorBatchInput(classId=cl.id,periodId=period.id,
                    entries=[{"studentId":s.id,"stars":4} for s in students])
                self.assertTrue(b.save_sheet(current,first,body))
                def attempt():
                    with m.engine.connect() as other:
                        transaction=other.begin()
                        second=Session(bind=other,join_transaction_mode="create_savepoint")
                        try:
                            try: b.save_sheet(current,second,body)
                            except HTTPException as error: return error.status_code
                            return 200
                        finally: second.close();transaction.rollback()
                with ThreadPoolExecutor(max_workers=1) as pool:
                    self.assertEqual(pool.submit(attempt).result(timeout=15),409)
            finally:
                first.close();outer.rollback()

    def test_http_routes_roles_and_teacher_isolation(self):
        actor=[self.principals[0]]
        overrides=dict(m.app.dependency_overrides)
        m.app.dependency_overrides[m.principal]=lambda: actor[0]
        m.app.dependency_overrides[m.db]=lambda: self.s
        client=ASGIClient()
        try:
            payload=self.body().model_dump(mode="json",by_alias=True)
            self.assertEqual(client.put('/api/v1/school/behavior',json=payload).status_code,200)
            self.assertEqual(client.put('/api/v1/school/behavior',json=payload).status_code,409)
            actor[0]=self.principals[1]
            query={"class_id":str(self.cl.id),"period_id":str(self.periods[0].id)}
            self.assertEqual(client.get('/api/v1/school/behavior',params=query).json(),[])
            self.assertEqual(client.put('/api/v1/school/behavior',json=payload).status_code,200)
            self.assertEqual(client.get('/api/v1/school/behavior/results',params=query).status_code,403)
            actor[0]=self.admin
            self.assertEqual(client.get('/api/v1/school/behavior/results',params=query).status_code,403)
            self.assertEqual(client.get('/api/v1/school/behavior/contexts').status_code,403)
            actor[0]=m.Principal(id=self.principals[0].id,role='admin',school_id=str(self.tenant.id),
                direction_id=str(uuid.uuid4()),direction_cycle_ids=[str(self.cycle.id)])
            self.assertEqual(client.get('/api/v1/school/behavior/results',params=query).status_code,200)
        finally:
            client.close()
            m.app.dependency_overrides.clear();m.app.dependency_overrides.update(overrides)


if __name__ == "__main__":
    unittest.main(verbosity=2)

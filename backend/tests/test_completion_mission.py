"""Regression coverage for the mission-completion audit.

All writes use the shared PostgreSQL rollback fixture and never persist.
"""

import unittest
import uuid
from datetime import date, time

from app import main as m
import test_behavior_foundations as fixtures


class MissionCompletionTests(unittest.TestCase):
    add = fixtures.BehaviorFoundations.add
    assign = fixtures.BehaviorFoundations.assign
    cleanup = fixtures.BehaviorFoundations.cleanup

    def setUp(self):
        fixtures.BehaviorFoundations.setUp(self)

    def _user(self, role: str, password: str) -> m.User:
        return self.add(m.User(
            email=f"{role}-{uuid.uuid4()}@rollback.invalid",
            password_hash=m.passwords.hash(password),
            name=f"Rollback {role}",
            role=role,
            school_id=self.tenant.id,
            status="active",
            password_set=True,
        ))

    def _school_admin(self) -> m.Principal:
        return m.Principal(
            id=self.admin.id,
            role="admin",
            school_id=m.public_school_id(self.s, self.tenant.id),
            direction_id=str(uuid.uuid4()),
            direction_cycle_ids=[str(self.cycle.id)],
        )

    def test_teacher_student_and_parent_can_login_with_normalized_phone(self):
        password = "Phone-login-rollback!9"

        teacher = self.teachers[0]
        teacher.phone = "06 123 45 67"
        teacher_user = self.s.get(m.User, teacher.user_id)
        teacher_user.password_hash = m.passwords.hash(password)

        student_user = self._user("student", password)
        student = self.students[0]
        student.user_id = student_user.id
        student.phone = "+242 06 987 65 43"

        parent_user = self._user("parent", password)
        guardian = self.add(m.Guardian(
            establishment_id=self.tenant.id,
            user_id=parent_user.id,
            first_name="Parent",
            last_name="Rollback",
            phone="00242 05 111 22 33",
            status="active",
        ))
        self.add(m.StudentGuardian(
            establishment_id=self.tenant.id,
            student_id=student.id,
            guardian_id=guardian.id,
            relationship="parent",
            is_primary=True,
        ))
        self.s.flush()

        teacher_login = m.login(m.LoginInput(
            identifier="+242061234567", password=password
        ), self.s)
        student_login = m.login(m.LoginInput(
            identifier="06 987 65 43", password=password
        ), self.s)
        parent_login = m.login(m.LoginInput(
            identifier="+242051112233", password=password
        ), self.s)

        self.assertEqual(teacher_login["user"]["role"], "teacher")
        self.assertEqual(student_login["user"]["role"], "student")
        self.assertEqual(parent_login["user"]["role"], "parent")

    def test_year_configuration_copy_is_complete_additive_and_idempotent(self):
        level = self.add(m.SchoolLevel(
            establishment_id=self.tenant.id,
            cycle_id=self.cycle.id,
            code="3E-ROLLBACK",
            name="3e rollback",
            status="active",
        ))
        self.cl.school_level_id = level.id
        first_affectation = self.s.scalar(m.select(m.Affectation).where(
            m.Affectation.class_id == self.cl.id
        ))
        self.add(m.SubjectLevelSetting(
            establishment_id=self.tenant.id,
            academic_year_id=self.year.id,
            school_level_id=level.id,
            subject_id=first_affectation.subject_id,
            coefficient=3,
            grading_scale=20,
            status="active",
        ))
        self.add(m.EvaluationRule(
            establishment_id=self.tenant.id,
            academic_year_id=self.year.id,
            cycle_id=self.cycle.id,
            school_level_id=level.id,
            evaluation_type="devoir",
            label="Devoir rollback",
            expected_count=2,
            contributes_to_average=True,
            is_required=True,
            status="active",
        ))
        self.add(m.SchoolCalendarSetting(
            establishment_id=self.tenant.id,
            academic_year_id=self.year.id,
            teaching_days=[1, 2, 3, 4, 5],
            day_start=time(7, 30),
            day_end=time(17, 0),
            course_duration_minutes=55,
            status="active",
        ))
        target = self.add(m.AcademicYear(
            establishment_id=self.tenant.id,
            name="2027-2028 rollback",
            start_date=date(2027, 9, 1),
            end_date=date(2028, 7, 1),
            status="draft",
            is_active=False,
        ))

        first = m.copy_academic_year_configuration(
            target.id,
            m.AcademicYearCopyConfigurationInput(sourceYearId=self.year.id),
            self.admin,
            self.s,
        )
        self.assertEqual(first["created"]["classes"], 1)
        self.assertEqual(first["created"]["teacherAffectations"], 3)
        self.assertEqual(first["created"]["subjectSettings"], 1)
        self.assertEqual(first["created"]["evaluationRules"], 1)
        self.assertEqual(first["created"]["calendarSettings"], 1)

        second = m.copy_academic_year_configuration(
            target.id,
            m.AcademicYearCopyConfigurationInput(sourceYearId=self.year.id),
            self.admin,
            self.s,
        )
        self.assertEqual(sum(second["created"].values()), 0)
        self.assertEqual(self.s.scalar(m.select(m.func.count()).select_from(
            m.StudentAcademicRegistration
        ).where(m.StudentAcademicRegistration.academic_year_id == target.id)), 0)

    def test_statistics_use_official_results_and_locked_attendance(self):
        payload = {
            "calculationRuleVersion": m.RESULT_CALCULATION_RULE_VERSION,
            "students": [
                {
                    "studentId": str(self.students[0].id),
                    "studentName": "Rollback S0",
                    "average": 16,
                    "subjects": [{"subject": "Mathématiques", "average": 16}],
                },
                {
                    "studentId": str(self.students[1].id),
                    "studentName": "Rollback S1",
                    "average": 8,
                    "subjects": [{"subject": "Mathématiques", "average": 8}],
                },
            ],
        }
        self.add(m.ResultCalculation(
            establishment_id=self.tenant.id,
            academic_year_id=self.year.id,
            class_id=self.cl.id,
            academic_period_id=self.periods[0].id,
            status="official",
            payload=payload,
            source_updated_at=m.datetime.now(m.timezone.utc),
            calculated_at=m.datetime.now(m.timezone.utc),
        ))
        affectation = self.s.scalar(m.select(m.Affectation).where(
            m.Affectation.class_id == self.cl.id,
            m.Affectation.teacher_id == self.teachers[0].id,
        ))
        schedule = self.add(m.ScheduleEntry(
            establishment_id=self.tenant.id,
            academic_year_id=self.year.id,
            class_id=self.cl.id,
            teacher_id=self.teachers[0].id,
            subject_id=affectation.subject_id,
            affectation_id=affectation.id,
            weekday=1,
            start_time=time(8, 0),
            end_time=time(9, 0),
            status="active",
        ))
        sheet = self.add(m.AttendanceSheet(
            establishment_id=self.tenant.id,
            academic_year_id=self.year.id,
            schedule_entry_id=schedule.id,
            class_id=self.cl.id,
            teacher_id=self.teachers[0].id,
            subject_id=affectation.subject_id,
            attendance_date=date(2026, 10, 5),
            status="locked",
            context_snapshot={},
            expected_students=[],
            submitted_at=m.datetime.now(m.timezone.utc),
        ))
        statuses = ("present", "absent")
        for index, status in enumerate(statuses):
            self.add(m.AttendanceRecord(
                establishment_id=self.tenant.id,
                academic_year_id=self.year.id,
                class_id=self.cl.id,
                student_id=self.students[index % 2].id,
                attendance_date=date(2026, 10, 5),
                status=status,
                sheet_id=sheet.id,
            ))

        result = m.statistics(
            school_id=m.public_school_id(self.s, self.tenant.id),
            academic_year_id=str(self.year.id),
            current=self._school_admin(),
            session=self.s,
        )
        self.assertEqual(result["studentCount"], 2)
        self.assertEqual(result["teacherCount"], 3)
        self.assertEqual(result["overallAverage"], 12)
        self.assertEqual(result["successRate"], 50)
        self.assertEqual(result["failureRate"], 50)
        self.assertEqual(result["attendanceRate"], 50)
        self.assertEqual(result["absenceCount"], 1)
        self.assertTrue(result["insights"])
        self.assertTrue(any(item["type"] == "attendance" for item in result["alerts"]))

    def test_statistics_success_rates_follow_the_selected_class(self):
        other = self.add(m.SchoolClass(
            establishment_id=self.tenant.id,
            academic_year_id=self.year.id,
            cycle_id=self.cycle.id,
            name="Classe résultat distinct",
            status="active",
        ))
        for school_class, values in ((self.cl, (15, 16)), (other, (7, 8))):
            self.add(m.ResultCalculation(
                establishment_id=self.tenant.id,
                academic_year_id=self.year.id,
                class_id=school_class.id,
                academic_period_id=self.periods[0].id,
                status="official",
                payload={
                    "calculationRuleVersion": m.RESULT_CALCULATION_RULE_VERSION,
                    "students": [
                        {"studentId": str(uuid.uuid4()), "studentName": f"Élève {value}",
                         "average": value, "subjects": []}
                        for value in values
                    ],
                },
                source_updated_at=m.datetime.now(m.timezone.utc),
                calculated_at=m.datetime.now(m.timezone.utc),
            ))

        first = m.statistics(
            academic_year_id=str(self.year.id), class_id=str(self.cl.id),
            current=self._school_admin(), session=self.s,
        )
        second = m.statistics(
            academic_year_id=str(self.year.id), class_id=str(other.id),
            current=self._school_admin(), session=self.s,
        )

        self.assertEqual(first["successRate"], 100)
        self.assertEqual(first["failureRate"], 0)
        self.assertEqual(second["successRate"], 0)
        self.assertEqual(second["failureRate"], 100)

    def test_statistics_snapshot_reports_and_applies_the_complete_filter_scope(self):
        level = self.add(m.SchoolLevel(
            establishment_id=self.tenant.id,
            cycle_id=self.cycle.id,
            code="3E-STATS",
            name="3e statistiques",
            status="active",
        ))
        self.cl.school_level_id = level.id
        affectation = self.s.scalar(m.select(m.Affectation).where(
            m.Affectation.class_id == self.cl.id,
        ))
        for period, average, subject_average in (
            (self.periods[0], 15, 14),
            (self.periods[1], 8, 7),
        ):
            self.add(m.ResultCalculation(
                establishment_id=self.tenant.id,
                academic_year_id=self.year.id,
                class_id=self.cl.id,
                academic_period_id=period.id,
                status="official",
                payload={
                    "calculationRuleVersion": m.RESULT_CALCULATION_RULE_VERSION,
                    "students": [{
                        "studentId": str(self.students[0].id),
                        "studentName": "Élève statistiques",
                        "average": average,
                        "subjects": [{
                            "subjectId": str(affectation.subject_id),
                            "subject": "Matière statistiques",
                            "average": subject_average,
                        }],
                    }],
                },
                source_updated_at=m.datetime.now(m.timezone.utc),
                calculated_at=m.datetime.now(m.timezone.utc),
            ))

        result = m.statistics(
            academic_year_id=str(self.year.id),
            cycle=str(self.cycle.id),
            level_id=str(level.id),
            class_id=str(self.cl.id),
            period_id=str(self.periods[0].id),
            subject_id=str(affectation.subject_id),
            current=self._school_admin(),
            session=self.s,
        )

        self.assertEqual(result["overallAverage"], 14)
        self.assertEqual(result["successRate"], 100)
        self.assertEqual(result["bySubject"][0]["average20"], 14)
        self.assertEqual(result["appliedFilters"], {
            "academicYearId": str(self.year.id),
            "cycleId": str(self.cycle.id),
            "levelId": str(level.id),
            "classId": str(self.cl.id),
            "periodId": str(self.periods[0].id),
            "subjectId": str(affectation.subject_id),
            "eventCode": None,
        })
        self.assertTrue(result["snapshotGeneratedAt"])


    def test_departmental_assessment_is_available_only_from_college(self):
        def cycle(code: str):
            existing = self.s.scalar(m.select(m.SchoolCycle).where(
                m.SchoolCycle.establishment_id == self.tenant.id,
                m.SchoolCycle.code == code,
            ))
            if existing:
                return existing
            return self.add(m.SchoolCycle(
                establishment_id=self.tenant.id,
                code=code,
                name=code.title(),
                status="active",
            ))

        def school_class(code: str):
            cycle_row = cycle(code)
            return self.add(m.SchoolClass(
                establishment_id=self.tenant.id,
                academic_year_id=self.year.id,
                cycle_id=cycle_row.id,
                name=f"Classe {code} départemental {uuid.uuid4().hex[:6]}",
                status="active",
            ))

        for code in ("MATERNELLE", "PRIMAIRE"):
            with self.assertRaises(m.HTTPException) as raised:
                m.validate_program_type_for_class(
                    school_class(code), "exam", "devoir_departemental", self.s
                )
            self.assertEqual(raised.exception.status_code, 422)

        m.validate_program_type_for_class(
            school_class("COLLEGE"), "exam", "devoir_departemental", self.s
        )
        m.validate_program_type_for_class(
            school_class("LYCEE"), "exam", "devoir_departemental", self.s
        )

    def test_statistics_can_filter_departmental_official_result(self):
        affectation = self.s.scalar(m.select(m.Affectation).where(
            m.Affectation.class_id == self.cl.id,
        ))
        self.add(m.Evaluation(
            establishment_id=self.tenant.id,
            class_id=self.cl.id,
            subject_id=affectation.subject_id,
            academic_year_id=self.year.id,
            academic_period_id=self.periods[0].id,
            affectation_id=affectation.id,
            name="Devoir départemental",
            type="exam",
            exam_code="devoir_departemental",
            period="T1",
            max_value=20,
            status="submitted",
            created_by=m.uuid.UUID(self.principals[0].id),
        ))
        payload = {
            "calculationRuleVersion": m.RESULT_CALCULATION_RULE_VERSION,
            "students": [{
                "studentId": str(self.students[0].id),
                "studentName": "Résultat général",
                "average": 8,
                "subjects": [],
            }],
            "eventResults": {
                "devoir_departemental": {
                    "event": "Devoir départemental",
                    "students": [{
                        "studentId": str(self.students[0].id),
                        "studentName": "Résultat départemental",
                        "average": 15,
                        "subjects": [{
                            "subjectId": str(affectation.subject_id),
                            "subject": "Mathématiques",
                            "average": 15,
                        }],
                    }],
                },
            },
        }
        self.add(m.ResultCalculation(
            establishment_id=self.tenant.id,
            academic_year_id=self.year.id,
            class_id=self.cl.id,
            academic_period_id=self.periods[0].id,
            status="official",
            payload=payload,
            source_updated_at=m.datetime.now(m.timezone.utc),
            calculated_at=m.datetime.now(m.timezone.utc),
        ))

        result = m.statistics(
            academic_year_id=str(self.year.id),
            class_id=str(self.cl.id),
            period_id=str(self.periods[0].id),
            event_code="devoir_departemental",
            current=self._school_admin(),
            session=self.s,
        )

        self.assertEqual(result["overallAverage"], 15)
        self.assertEqual(result["successRate"], 100)
        self.assertEqual(result["appliedFilters"]["eventCode"],
                         "devoir_departemental")
        self.assertIn(
            {"code": "devoir_departemental", "name": "Devoir départemental"},
            result["filters"]["resultEvents"],
        )


if __name__ == "__main__":
    unittest.main()

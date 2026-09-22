"""Base establishment configuration tests; all writes stay in an outer rollback."""
import unittest
import uuid
from datetime import date
from unittest.mock import patch

from fastapi import HTTPException
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app import main as m


class EstablishmentBaseConfigurationTests(unittest.TestCase):
    def setUp(self):
        self.connection = m.engine.connect()
        self.outer = self.connection.begin()
        self.s = Session(
            bind=self.connection,
            join_transaction_mode="create_savepoint",
        )
        self.addCleanup(self.cleanup)
        self.plan_name = f"Base-{uuid.uuid4().hex[:12]}"
        self.s.add(m.Resource(
            id=f"plan-{uuid.uuid4()}",
            kind="plans",
            payload={
                "name": self.plan_name,
                "price": "0",
                "currency": "XAF",
                "durationDays": 365,
                "features": [],
                "status": "active",
            },
        ))
        self.s.flush()
        self.superadmin = m.Principal(id=str(uuid.uuid4()), role="superadmin")

    def cleanup(self):
        self.s.close()
        self.outer.rollback()
        self.connection.close()

    def create(self, cycles, *, configured=True):
        suffix = uuid.uuid4().hex
        body = m.SuperAdminEstablishmentCreateInput(
            name=f"École base {suffix}",
            code=f"E{suffix[:5].upper()}",
            city="Pointe-Noire",
            country="Congo",
            plan=self.plan_name,
            admin_name="Responsable initial",
            admin_email=f"admin-{suffix}@rollback.invalid",
            cycles=cycles,
            use_base_configuration=configured,
            initial_academic_year="2026-2027" if configured else None,
        )
        response = m.create_superadmin_establishment(
            body, self.superadmin, self.s
        )
        return uuid.UUID(response["establishment"]["databaseId"]), response

    def count(self, model, establishment_id):
        return self.s.scalar(select(func.count()).select_from(model).where(
            model.establishment_id == establishment_id
        )) or 0

    def test_yes_creates_only_the_requested_references(self):
        establishment_id, response = self.create(
            ["MATERNELLE", "PRIMAIRE", "COLLEGE", "LYCEE"]
        )
        self.assertTrue(response["baseConfigurationCreated"])
        year = self.s.scalar(select(m.AcademicYear).where(
            m.AcademicYear.establishment_id == establishment_id
        ))
        self.assertIsNotNone(year)
        self.assertEqual((year.name, year.start_date, year.end_date), (
            "2026-2027", date(2026, 10, 1), date(2027, 6, 30)
        ))
        periods = list(self.s.scalars(select(m.AcademicPeriod).where(
            m.AcademicPeriod.establishment_id == establishment_id
        ).order_by(m.AcademicPeriod.sort_order)).all())
        self.assertEqual([period.code for period in periods], ["T1", "T2", "T3"])
        self.assertEqual([period.period_type for period in periods], [
            "trimester", "trimester", "trimester"
        ])

        levels = list(self.s.scalars(select(m.SchoolLevel).where(
            m.SchoolLevel.establishment_id == establishment_id
        )).all())
        self.assertEqual(len(levels), 17)
        series = list(self.s.scalars(select(m.SchoolSeries).where(
            m.SchoolSeries.establishment_id == establishment_id
        )).all())
        self.assertEqual({item.code for item in series}, {"A", "C", "D", "G2"})
        self.assertEqual(
            self.count(m.Subject, establishment_id),
            len(m.BASE_SUBJECT_CATALOG),
        )

        rules = list(self.s.scalars(select(m.EvaluationRule).where(
            m.EvaluationRule.establishment_id == establishment_id
        )).all())
        self.assertTrue({
            "Devoir 1", "Devoir 2", "Composition", "CEPE Test",
            "CEPE Blanc", "BEPC Test", "BEPC Blanc", "BAC Test", "BAC Blanc",
        }.issubset({rule.label for rule in rules}))

        settings = list(self.s.scalars(select(m.SubjectLevelSetting).where(
            m.SubjectLevelSetting.establishment_id == establishment_id
        )).all())
        cycle_by_id = {
            cycle.id: cycle.code for cycle in self.s.scalars(select(m.SchoolCycle).where(
                m.SchoolCycle.establishment_id == establishment_id
            )).all()
        }
        level_by_id = {level.id: level for level in levels}
        for setting in settings:
            cycle_code = cycle_by_id[level_by_id[setting.school_level_id].cycle_id]
            if cycle_code == "PRIMAIRE":
                self.assertEqual(float(setting.grading_scale), 10.0)
            else:
                self.assertEqual(float(setting.grading_scale), 20.0)
            if cycle_code == "LYCEE":
                self.assertEqual(float(setting.coefficient), 1.0)
                self.assertIsNotNone(setting.series_id)
            else:
                self.assertIsNone(setting.coefficient)

        for cycle in self.s.scalars(select(m.SchoolCycle).where(
            m.SchoolCycle.establishment_id == establishment_id
        )).all():
            empty_class = m.SchoolClass(
                establishment_id=establishment_id,
                academic_year_id=year.id,
                cycle_id=cycle.id,
                name="Non persistée",
            )
            expected = 10.0 if cycle.code in {"MATERNELLE", "PRIMAIRE"} else 20.0
            self.assertEqual(m.general_average_scale(self.s, empty_class), expected)

        for model in (
            m.SchoolDirection, m.SchoolClass, m.Teacher, m.Student,
            m.Guardian, m.Affectation, m.ScheduleEntry, m.AttendanceSheet,
            m.AttendanceRecord, m.BehaviorEvent, m.Evaluation, m.Grade,
            m.ResultCalculation,
        ):
            self.assertEqual(self.count(model, establishment_id), 0, model.__name__)
        forbidden_resource_kinds = {
            "teachers", "students", "parents", "payments", "documents",
            "results", "grades", "attendance", "behaviors", "schedules",
        }
        created_kinds = set(self.s.scalars(select(m.Resource.kind).where(
            m.Resource.establishment_id == establishment_id
        )).all())
        self.assertTrue(created_kinds.isdisjoint(forbidden_resource_kinds))

    def test_no_creates_no_automatic_reference(self):
        establishment_id, response = self.create(["PRIMAIRE"], configured=False)
        self.assertFalse(response["baseConfigurationCreated"])
        self.assertIsNone(response["initialConfiguration"])
        for model in (
            m.AcademicYear, m.AcademicPeriod, m.SchoolLevel, m.SchoolSeries,
            m.Subject, m.SubjectLevelSetting, m.EvaluationRule,
            m.SchoolDirection, m.SchoolClass,
        ):
            self.assertEqual(self.count(model, establishment_id), 0, model.__name__)

    def test_configuration_is_idempotent(self):
        establishment_id, response = self.create(["PRIMAIRE", "COLLEGE"])
        establishment = self.s.get(m.Establishment, establishment_id)
        models = (
            m.AcademicYear, m.AcademicPeriod, m.SchoolLevel, m.SchoolSeries,
            m.Subject, m.SubjectLevelSetting, m.EvaluationRule,
        )
        before = {model: self.count(model, establishment_id) for model in models}
        m.ensure_base_establishment_configuration(
            establishment, ["PRIMAIRE", "COLLEGE"], "2026-2027", self.s
        )
        after = {model: self.count(model, establishment_id) for model in models}
        self.assertEqual(after, before)
        self.assertEqual(response["initialConfiguration"]["periodCount"], 3)

    def test_partial_cycles_create_only_their_levels_and_lycee_series(self):
        scenarios = (
            (["PRIMAIRE"], {"CP1", "CP2", "CE1", "CE2", "CM1", "CM2"}, set()),
            (["COLLEGE"], {"6E", "5E", "4E", "3E"}, set()),
            (["LYCEE"], {"SECONDE", "PREMIERE", "TERMINALE"}, {"A", "C", "D", "G2"}),
            (["MATERNELLE", "PRIMAIRE"], {
                "GARDERIE", "P1", "P2", "P3", "CP1", "CP2", "CE1", "CE2", "CM1", "CM2"
            }, set()),
        )
        for cycles, expected_levels, expected_series in scenarios:
            establishment_id, _ = self.create(cycles)
            levels = set(self.s.scalars(select(m.SchoolLevel.code).where(
                m.SchoolLevel.establishment_id == establishment_id
            )).all())
            series = set(self.s.scalars(select(m.SchoolSeries.code).where(
                m.SchoolSeries.establishment_id == establishment_id
            )).all())
            self.assertEqual(levels, expected_levels)
            self.assertEqual(series, expected_series)

    def test_configuration_failure_rolls_back_the_whole_establishment(self):
        suffix = uuid.uuid4().hex
        name = f"École atomique {suffix}"
        body = m.SuperAdminEstablishmentCreateInput(
            name=name,
            code=f"A{suffix[:5].upper()}",
            city="Dolisie",
            country="Congo",
            plan=self.plan_name,
            admin_name="Responsable atomique",
            admin_email=f"atomic-{suffix}@rollback.invalid",
            cycles=["PRIMAIRE"],
            use_base_configuration=True,
            initial_academic_year="2026-2027",
        )
        with patch.object(
            m,
            "ensure_base_establishment_configuration",
            side_effect=RuntimeError("internal test failure"),
        ):
            with self.assertRaises(HTTPException) as error:
                m.create_superadmin_establishment(
                    body, self.superadmin, self.s
                )
        self.assertEqual(error.exception.status_code, 409)
        self.assertNotIn("internal test failure", error.exception.detail)
        self.assertIsNone(self.s.scalar(select(m.Establishment).where(
            m.Establishment.name == name
        )))


if __name__ == "__main__":
    unittest.main()

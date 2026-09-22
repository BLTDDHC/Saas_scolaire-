"""Plan capability enforcement remains server-side and transactionally isolated."""
import unittest
import uuid

from fastapi import HTTPException
from app import main as m
import test_behavior_foundations as fixtures


class PlanCapabilityTests(unittest.TestCase):
    add = fixtures.BehaviorFoundations.add
    assign = fixtures.BehaviorFoundations.assign
    cleanup = fixtures.BehaviorFoundations.cleanup

    def setUp(self):
        fixtures.BehaviorFoundations.setUp(self)
        self.school_id = f"school-cap-{uuid.uuid4()}"
        self.plan_name = f"Plan capabilities {uuid.uuid4()}"
        self.add(m.Resource(
            id=self.school_id, kind="establishments", school_id=self.school_id,
            establishment_id=self.tenant.id,
            payload={"id": self.school_id, "databaseId": str(self.tenant.id),
                     "plan": self.plan_name},
        ))
        self.plan = self.add(m.Resource(
            id=f"plan-{uuid.uuid4()}", kind="plans",
            payload={"name": self.plan_name, "features": ["grades"],
                     "limits": {"capabilitiesConfigured": True,
                                "capabilities": ["grades.publish_teacher"]}},
        ))
        self.current = m.Principal(
            id=self.principals[0].id, role="admin", school_id=self.school_id,
            direction_id=str(uuid.uuid4()),
            direction_cycle_ids=[str(self.cycle.id)],
        )

    def test_included_capability_is_allowed(self):
        m.ensure_plan_capability(
            self.current, self.s, "grades.publish_teacher"
        )

    def test_missing_publication_capability_is_denied(self):
        with self.assertRaises(HTTPException) as error:
            m.ensure_plan_capability(
                self.current, self.s, "grades.publish_parent"
            )
        self.assertEqual(error.exception.status_code, 403)
        self.assertIn("forfait", error.exception.detail.lower())

    def test_admin_internal_results_remain_available(self):
        result = m.school_results(
            self.cl.id, self.periods[0].id, self.current, self.s
        )
        self.assertIn(result["calculationStatus"], {"waiting", "ready", "official"})

    def test_teacher_route_accepts_included_publication(self):
        result = m.school_results(
            self.cl.id, self.periods[0].id, self.principals[0], self.s
        )
        self.assertIn(result["calculationStatus"], {"waiting", "ready", "official"})

    def test_parent_cannot_bypass_missing_plan_access(self):
        parent = self.current.model_copy(update={"role": "parent"})
        with self.assertRaises(HTTPException) as error:
            m.my_children_for_results(parent, self.s)
        self.assertEqual(error.exception.status_code, 403)

    def test_authorized_parent_sees_all_linked_children_only(self):
        self.plan.payload = {
            **self.plan.payload,
            "limits": {
                "capabilitiesConfigured": True,
                "capabilities": ["parents.access", "grades.publish_parent"],
            },
        }
        guardian = self.add(m.Guardian(
            establishment_id=self.tenant.id,
            user_id=uuid.UUID(self.current.id),
            first_name="Parent", last_name="Rollback",
            phone="060000000",
        ))
        for student in self.students:
            self.add(m.StudentGuardian(
                establishment_id=self.tenant.id, student_id=student.id,
                guardian_id=guardian.id, relationship="parent",
            ))
        unlinked = self.add(m.Student(
            establishment_id=self.tenant.id,
            first_name="Non lié", last_name="Rollback",
        ))
        self.add(m.StudentAcademicRegistration(
            establishment_id=self.tenant.id, student_id=unlinked.id,
            class_id=self.cl.id, academic_year_id=self.year.id,
            status="validated",
        ))
        parent = self.current.model_copy(update={"role": "parent"})
        children = m.my_children_for_results(parent, self.s)
        self.assertEqual({item["id"] for item in children},
                         {str(student.id) for student in self.students})
        workspace = m.parent_workspace(parent, self.s)
        self.assertEqual(
            {item["id"] for item in workspace["students"]},
            {str(student.id) for student in self.students},
        )
        self.assertNotIn(str(unlinked.id), {
            item["id"] for item in workspace["students"]
        })
        self.assertEqual(
            {item["id"] for student in workspace["students"]
             for item in student["guardians"]},
            {str(guardian.id)},
        )
        self.assertEqual(
            {item["id"] for item in workspace["classes"]},
            {str(self.cl.id)},
        )

    def test_student_cannot_bypass_missing_plan_access(self):
        student = self.current.model_copy(update={"role": "student"})
        with self.assertRaises(HTTPException) as error:
            m.my_student_results(student, self.s)
        self.assertEqual(error.exception.status_code, 403)

    def test_legacy_plan_without_configuration_remains_compatible(self):
        self.plan.payload = {**self.plan.payload, "limits": {}}
        self.s.flush()
        m.ensure_plan_capability(
            self.current, self.s, "grades.publish_parent"
        )

    def test_plan_input_rejects_unknown_capability(self):
        with self.assertRaises(ValueError):
            m.PlanCreateInput(
                name="Plan invalide", price=1000, duration_days=30,
                limits={"capabilitiesConfigured": True,
                        "capabilities": ["feature.invented"]},
            )

    def test_plan_input_preserves_an_explicit_empty_configuration(self):
        plan = m.PlanCreateInput(
            name="Essentiel", price=1000, duration_days=30,
            limits={"capabilitiesConfigured": True, "capabilities": []},
        )
        self.assertTrue(plan.limits["capabilitiesConfigured"])
        self.assertEqual(plan.limits["capabilities"], [])


if __name__ == "__main__":
    unittest.main()

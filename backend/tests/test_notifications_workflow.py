"""In-app notification isolation tests; every write is rolled back."""
import unittest
import uuid

from app import main as m
import test_behavior_foundations as fixtures


class NotificationWorkflowTests(unittest.TestCase):
    add = fixtures.BehaviorFoundations.add
    assign = fixtures.BehaviorFoundations.assign
    cleanup = fixtures.BehaviorFoundations.cleanup

    def setUp(self):
        fixtures.BehaviorFoundations.setUp(self)
        self.school_id = m.public_school_id(self.s, self.tenant.id)
        self.admin = m.Principal(
            id=self.principals[0].id,
            role="admin",
            school_id=self.school_id,
        )

    def test_group_notification_targets_only_active_scoped_teachers(self):
        body = m.InAppTeacherNotificationInput(
            title="Réunion pédagogique",
            message="Merci de consulter le programme.",
            category="administrative",
        )
        payload = m.create_teacher_in_app_notification(
            body, self.admin, self.s
        )
        self.assertEqual(payload["recipientCount"], 3)
        row = self.s.get(
            m.Resource,
            {"kind": "notifications", "id": payload["id"]},
        )
        self.assertIsNotNone(row)
        self.assertTrue(m.visible(row, self.principals[0], self.s))
        self.assertTrue(m.visible(row, self.principals[1], self.s))

        outsider = m.Principal(
            id=str(uuid.uuid4()),
            role="teacher",
            teacher_id=str(uuid.uuid4()),
            school_id=self.school_id,
        )
        self.assertFalse(m.visible(row, outsider, self.s))

    def test_read_state_is_per_user(self):
        payload = m.create_teacher_in_app_notification(
            m.InAppTeacherNotificationInput(
                title="Échéance",
                message="Finalisez les relevés.",
                category="deadline",
            ),
            self.admin,
            self.s,
        )
        row = self.s.get(
            m.Resource,
            {"kind": "notifications", "id": payload["id"]},
        )
        first = self.principals[0]
        second = self.principals[1]

        self.assertFalse(m.resource_view(row, first, self.s)["read"])
        self.assertFalse(m.resource_view(row, second, self.s)["read"])
        m.mark_workflow_notification_read(payload["id"], first, self.s)
        self.assertTrue(m.resource_view(row, first, self.s)["read"])
        self.assertFalse(m.resource_view(row, second, self.s)["read"])

    def test_teacher_selection_rejects_out_of_scope_id(self):
        with self.assertRaises(m.HTTPException) as error:
            m.create_teacher_in_app_notification(
                m.InAppTeacherNotificationInput(
                    title="Info",
                    message="Message",
                    teacherIds=[uuid.uuid4()],
                ),
                self.admin,
                self.s,
            )
        self.assertEqual(error.exception.status_code, 403)


if __name__ == "__main__":
    unittest.main()

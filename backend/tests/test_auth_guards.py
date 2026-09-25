"""Authentication invariants protected by PostgreSQL rollback fixtures."""

from datetime import date, datetime, timedelta, timezone
import unittest
import uuid

from fastapi import HTTPException
from fastapi.security import HTTPAuthorizationCredentials
from pydantic import ValidationError
from starlette.requests import Request

from app import main as m
import test_behavior_foundations as fixtures


def request(path: str = "/api/v1/auth/me") -> Request:
    return Request({
        "type": "http",
        "method": "GET",
        "scheme": "http",
        "path": path,
        "raw_path": path.encode(),
        "query_string": b"",
        "headers": [],
        "server": ("test", 80),
        "client": ("test", 1),
    })


def credentials(token: str) -> HTTPAuthorizationCredentials:
    return HTTPAuthorizationCredentials(scheme="Bearer", credentials=token)


class AuthenticationGuards(unittest.TestCase):
    add = fixtures.BehaviorFoundations.add
    assign = fixtures.BehaviorFoundations.assign
    cleanup = fixtures.BehaviorFoundations.cleanup

    def setUp(self):
        fixtures.BehaviorFoundations.setUp(self)

    def user(self, *, email: str, role: str, school_id=None, direction_id=None):
        return self.add(m.User(
            email=email,
            password_hash=m.passwords.hash("Rollback-auth-password!9"),
            name=f"Rollback {role}",
            role=role,
            school_id=school_id,
            direction_id=direction_id,
            status="active",
            password_set=True,
        ))

    def test_password_length_accepts_eight_and_rejects_seven(self):
        with self.assertRaises(HTTPException) as too_short:
            m.validate_new_password("Aa1!bbb")
        self.assertEqual(too_short.exception.status_code, 422)
        m.validate_new_password("Aa1!bbbb")
        m.validate_new_password("Aa1!bbbbbbbb")

    def test_permanent_matricule_uses_school_code_year_and_safe_counter(self):
        school_id = "school-rollback-matricule"
        self.add(m.Resource(
            kind="establishments",
            id=school_id,
            school_id=school_id,
            establishment_id=self.tenant.id,
            payload={
                "id": school_id,
                "databaseId": str(self.tenant.id),
                "name": self.tenant.name,
                "code": "KHE",
            },
        ))
        first = self.add(m.Student(
            establishment_id=self.tenant.id,
            first_name="Premier",
            last_name="Matricule",
        ))
        second = self.add(m.Student(
            establishment_id=self.tenant.id,
            first_name="Deuxième",
            last_name="Matricule",
        ))

        first_number = m.ensure_student_permanent_matricule(
            self.s, first, self.year.id
        )
        second_number = m.ensure_student_permanent_matricule(
            self.s, second, self.year.id
        )
        self.assertRegex(first_number, r"^KHE26-\d{3,}$")
        self.assertRegex(second_number, r"^KHE26-\d{3,}$")
        self.assertNotEqual(first_number, second_number)

        later_year = self.add(m.AcademicYear(
            establishment_id=self.tenant.id,
            name="2027-2028",
            start_date=date(2027, 9, 1),
            end_date=date(2028, 7, 1),
            status="draft",
            is_active=False,
        ))
        self.assertEqual(
            m.ensure_student_permanent_matricule(self.s, first, later_year.id),
            first_number,
        )

    def test_duplicate_establishment_code_is_rejected_case_insensitively(self):
        self.add(m.Resource(
            kind="establishments",
            id="school-code-owner",
            payload={"code": "LDK"},
        ))
        with self.assertRaises(HTTPException) as duplicate:
            m.ensure_establishment_code_available(self.s, "LDK")
        self.assertEqual(duplicate.exception.status_code, 409)

    def test_guardian_update_preserves_the_student_link_and_persists_fields(self):
        student = self.students[0]
        guardian = self.add(m.Guardian(
            establishment_id=self.tenant.id,
            first_name="Ancien",
            last_name="Responsable",
            phone="+242060000001",
            address="Ancienne adresse",
            profession="Ancienne profession",
        ))
        self.add(m.StudentGuardian(
            establishment_id=self.tenant.id,
            student_id=student.id,
            guardian_id=guardian.id,
            relationship="tuteur",
            is_primary=True,
        ))
        updated = m.update_guardian(
            guardian.id,
            m.GuardianInput(
                firstName="Nouveau",
                lastName="Responsable",
                phone="+242060000002",
                address="Nouvelle adresse",
                profession="Nouvelle profession",
            ),
            m.Principal(id=str(uuid.uuid4()), role="superadmin"),
            self.s,
        )
        self.assertEqual(updated["firstName"], "Nouveau")
        self.assertEqual(updated["profession"], "Nouvelle profession")
        self.assertEqual(
            self.s.scalar(m.select(m.StudentGuardian).where(
                m.StudentGuardian.student_id == student.id,
                m.StudentGuardian.guardian_id == guardian.id,
            )).relationship,
            "tuteur",
        )

    def test_guardian_is_reused_for_multiple_children_but_same_link_is_rejected(self):
        guardian_body = m.GuardianInput(
            firstName="Damas",
            lastName="Bouako",
            phone="06 777 88 99",
            email="guardian.multi.rollback@example.invalid",
            address="Brazzaville",
            profession="Parent",
        )
        current = m.Principal(id=str(uuid.uuid4()), role="superadmin")

        first_response = m.Response()
        first = m.create_guardian(
            guardian_body,
            first_response,
            str(self.tenant.id),
            current,
            self.s,
        )
        self.assertEqual(first_response.status_code, 200)
        guardian_id = uuid.UUID(first["id"])

        second_response = m.Response()
        second = m.create_guardian(
            guardian_body,
            second_response,
            str(self.tenant.id),
            current,
            self.s,
        )
        self.assertEqual(second_response.status_code, 200)
        self.assertEqual(second["id"], first["id"])
        self.assertEqual(
            self.s.scalar(m.select(m.func.count()).select_from(m.Guardian).where(
                m.Guardian.establishment_id == self.tenant.id,
                m.Guardian.person_id == uuid.UUID(first["personId"]),
            )),
            1,
        )

        m.link_student_guardian(
            self.students[0].id,
            m.StudentGuardianLinkInput(
                guardianId=guardian_id,
                relationship="parent",
                isPrimary=True,
            ),
            current,
            self.s,
        )
        m.link_student_guardian(
            self.students[1].id,
            m.StudentGuardianLinkInput(
                guardianId=guardian_id,
                relationship="parent",
                isPrimary=True,
            ),
            current,
            self.s,
        )
        self.assertEqual(
            self.s.scalar(m.select(m.func.count()).select_from(m.StudentGuardian).where(
                m.StudentGuardian.guardian_id == guardian_id
            )),
            2,
        )

        with self.assertRaises(HTTPException) as duplicate:
            m.link_student_guardian(
                self.students[0].id,
                m.StudentGuardianLinkInput(
                    guardianId=guardian_id,
                    relationship="parent",
                    isPrimary=True,
                ),
                current,
                self.s,
            )
        self.assertEqual(duplicate.exception.status_code, 409)
        self.assertIn("déjà associé", duplicate.exception.detail)

    def test_academic_year_update_persists_name_and_dates_in_its_tenant(self):
        updated = m.update_academic_year(
            self.year.id,
            m.AcademicYearUpdateInput(
                name="2026-2027 corrigée",
                start="2026-09-01",
                end="2027-07-15",
            ),
            m.Principal(id=str(uuid.uuid4()), role="superadmin"),
            self.s,
        )
        self.assertEqual(updated["name"], "2026-2027 corrigée")
        persisted = self.s.get(m.AcademicYear, self.year.id)
        self.assertEqual(persisted.start_date, date(2026, 9, 1))
        self.assertEqual(persisted.end_date, date(2027, 7, 15))

    def test_superadmin_login_me_and_normalized_email(self):
        user = self.user(email="adminm.rollback@example.invalid", role="superadmin")
        result = m.login(m.LoginInput(
            email="  ADMINM.ROLLBACK@EXAMPLE.INVALID  ",
            password="Rollback-auth-password!9",
        ), self.s)

        self.assertEqual(result["user"]["id"], str(user.id))
        self.assertEqual(result["user"]["role"], "superadmin")
        self.assertIsNone(result["user"]["schoolId"])
        self.assertIsNone(result["user"]["directionId"])
        principal = m.principal(
            request(), credentials(result["accessToken"]), self.s
        )
        self.assertEqual(principal.role, "superadmin")
        self.assertEqual(m.me(principal, self.s)["email"], user.email)

    def test_subscription_duration_expiration_and_renewal_follow_plan(self):
        school_id = m.public_school_id(self.s, self.tenant.id)
        plan = self.add(m.Resource(
            id="PLAN-ROLLBACK-120",
            kind="plans",
            school_id=None,
            payload={
                "id": "PLAN-ROLLBACK-120",
                "name": "Plan 120 rollback",
                "price": 12000,
                "currency": "FCFA",
                "durationDays": 120,
                "features": [],
                "status": "active",
            },
        ))
        subscription = self.add(m.Resource(
            id="SUB-ROLLBACK-120",
            kind="subscriptions",
            school_id=school_id,
            establishment_id=self.tenant.id,
            payload={
                "id": "SUB-ROLLBACK-120",
                "schoolId": school_id,
                "client": self.tenant.name,
                "plan": "Ancien plan",
                "price": "1",
                "startDate": (date.today() - timedelta(days=10)).isoformat(),
                "endDate": (date.today() - timedelta(days=1)).isoformat(),
                "status": "active",
            },
        ))
        self.assertEqual(m.canonical_subscription_status(subscription.payload), "expired")
        self.assertFalse(m.subscription_allows_access(self.s, self.tenant.id))

        start = date.today()
        result = m.renew_superadmin_subscription(
            subscription.id,
            m.SubscriptionRenewInput(plan=plan.payload["name"], startDate=start),
            m.Principal(id=str(uuid.uuid4()), role="superadmin"),
            self.s,
        )
        self.assertEqual(result["status"], "active")
        self.assertEqual(
            date.fromisoformat(result["endDate"]) - date.fromisoformat(result["startDate"]),
            timedelta(days=120),
        )
        self.assertEqual(result["planDefinition"]["durationDays"], 120)
        self.assertEqual(result["daysRemaining"], 120)
        self.assertTrue(m.subscription_allows_access(self.s, self.tenant.id))

    def test_direction_admin_login_keeps_direction_and_cycles(self):
        direction = self.add(m.SchoolDirection(
            establishment_id=self.tenant.id,
            code="ROLLBACK_DIRECTION",
            name="Direction rollback",
            status="active",
        ))
        self.add(m.SchoolDirectionCycle(
            establishment_id=self.tenant.id,
            direction_id=direction.id,
            cycle_id=self.cycle.id,
        ))
        user = self.user(
            email="admin.direction.rollback@example.invalid",
            role="admin",
            school_id=self.tenant.id,
            direction_id=direction.id,
        )

        result = m.login(m.LoginInput(
            email=user.email,
            password="Rollback-auth-password!9",
        ), self.s)
        payload = result["user"]
        self.assertEqual(payload["role"], "admin")
        self.assertEqual(payload["directionId"], str(direction.id))
        self.assertEqual(
            [cycle["id"] for cycle in payload["direction"]["cycles"]],
            [str(self.cycle.id)],
        )

    def test_teacher_login_resolves_relational_profile(self):
        teacher = self.teachers[0]
        teacher.employee_number = "ENS-ROLLBACK-001"
        user = self.s.get(m.User, teacher.user_id)
        user.password_hash = m.passwords.hash("Rollback-auth-password!9")
        self.s.flush()

        result = m.login(m.LoginInput(
            identifier=" ens-rollback-001 ",
            password="Rollback-auth-password!9",
        ), self.s)
        principal = m.principal(
            request(), credentials(result["accessToken"]), self.s
        )
        self.assertEqual(principal.role, "teacher")
        self.assertEqual(principal.teacher_id, str(teacher.id))

    def test_parent_login_requires_and_keeps_its_relational_guardian_profile(self):
        parent = self.user(
            email="parent.rollback@example.invalid",
            role="parent",
            school_id=self.tenant.id,
        )
        guardian = self.add(m.Guardian(
            establishment_id=self.tenant.id,
            user_id=parent.id,
            first_name="Parent",
            last_name="Rollback",
            phone="+242060000009",
            status="active",
        ))
        result = m.login(m.LoginInput(
            email=" PARENT.ROLLBACK@EXAMPLE.INVALID ",
            password="Rollback-auth-password!9",
        ), self.s)
        principal = m.principal(
            request(), credentials(result["accessToken"]), self.s
        )
        self.assertEqual(principal.role, "parent")
        self.assertEqual(result["user"]["schoolId"], m.public_school_id(
            self.s, guardian.establishment_id
        ))

        guardian.status = "archived"
        self.s.flush()
        with self.assertRaises(HTTPException) as error:
            m.login(m.LoginInput(
                email=parent.email,
                password="Rollback-auth-password!9",
            ), self.s)
        self.assertEqual(error.exception.status_code, 403)

    def test_parent_access_is_provisioned_on_the_linked_guardian_and_can_reset(self):
        guardian = self.add(m.Guardian(
            establishment_id=self.tenant.id,
            first_name="Parent",
            last_name="Provision",
            phone="+242060000008",
            email="parent.provision.rollback@example.invalid",
            status="active",
        ))
        self.add(m.StudentGuardian(
            establishment_id=self.tenant.id,
            student_id=self.students[0].id,
            guardian_id=guardian.id,
            relationship="parent",
            is_primary=True,
        ))
        current = m.Principal(id=str(uuid.uuid4()), role="superadmin")
        first = m.provision_parent_access(guardian.id, current, self.s)
        user_id = guardian.user_id
        self.assertIsNotNone(user_id)
        self.assertEqual(first["email"], guardian.email)
        self.assertEqual(self.s.get(m.User, user_id).role, "parent")
        logged_in = m.login(m.LoginInput(
            email=guardian.email,
            password=first["temporaryPassword"],
        ), self.s)
        self.assertEqual(logged_in["user"]["role"], "parent")

        second = m.provision_parent_access(guardian.id, current, self.s)
        self.assertEqual(guardian.user_id, user_id)
        self.assertNotEqual(
            second["temporaryPassword"], first["temporaryPassword"]
        )

    def test_wrong_password_is_refused(self):
        user = self.user(email="wrong.password.rollback@example.invalid", role="superadmin")
        with self.assertRaises(HTTPException) as error:
            m.login(m.LoginInput(email=user.email, password="incorrect"), self.s)
        self.assertEqual(error.exception.status_code, 401)

    def test_repeated_login_failures_are_rate_limited_per_peer_and_identifier(self):
        user = self.user(email="limited.rollback@example.invalid", role="superadmin")
        peer = f"test-peer-{uuid.uuid4()}"
        try:
            for _ in range(m.AUTH_RATE_LIMIT_ATTEMPTS):
                with self.assertRaises(HTTPException) as error:
                    m.login(
                        m.LoginInput(email=user.email, password="incorrect"),
                        self.s,
                        rate_key=peer,
                    )
                self.assertEqual(error.exception.status_code, 401)
            with self.assertRaises(HTTPException) as blocked:
                m.login(
                    m.LoginInput(
                        email=user.email,
                        password="Rollback-auth-password!9",
                    ),
                    self.s,
                    rate_key=peer,
                )
            self.assertEqual(blocked.exception.status_code, 429)
            self.assertIn("Retry-After", blocked.exception.headers)
        finally:
            m.clear_login_failures(user.email, peer)

    def test_inactive_account_is_refused_even_with_the_right_password(self):
        user = self.user(email="inactive.rollback@example.invalid", role="superadmin")
        user.status = "inactive"
        self.s.flush()
        with self.assertRaises(HTTPException) as error:
            m.login(m.LoginInput(
                email=user.email,
                password="Rollback-auth-password!9",
            ), self.s)
        self.assertEqual(error.exception.status_code, 401)

    def test_voluntary_password_change_rotates_jwt_and_invalidates_old_password(self):
        user = self.user(email="change.rollback@example.invalid", role="superadmin")
        login = m.login(m.LoginInput(
            email=user.email,
            password="Rollback-auth-password!9",
        ), self.s)
        current = m.principal(request("/api/v1/auth/change-password"), credentials(login["accessToken"]), self.s)

        with self.assertRaises(HTTPException) as wrong_current:
            m.change_password(m.ChangePasswordInput(
                current_password="Wrong-current-password!9",
                new_password="Changed-auth-password!8",
                new_password_confirmation="Changed-auth-password!8",
            ), current, self.s)
        self.assertEqual(wrong_current.exception.status_code, 401)

        with self.assertRaises(HTTPException) as mismatch:
            m.change_password(m.ChangePasswordInput(
                current_password="Rollback-auth-password!9",
                new_password="Changed-auth-password!8",
                new_password_confirmation="Different-auth-password!8",
            ), current, self.s)
        self.assertEqual(mismatch.exception.status_code, 422)

        with self.assertRaises(HTTPException) as weak:
            m.change_password(m.ChangePasswordInput(
                current_password="Rollback-auth-password!9",
                new_password="weakpassword",
                new_password_confirmation="weakpassword",
            ), current, self.s)
        self.assertEqual(weak.exception.status_code, 422)

        changed = m.change_password(m.ChangePasswordInput(
            current_password="Rollback-auth-password!9",
            new_password="Changed-auth-password!8",
            new_password_confirmation="Changed-auth-password!8",
        ), current, self.s)
        self.assertEqual(changed["user"]["email"], user.email)
        m.principal(request(), credentials(changed["accessToken"]), self.s)
        with self.assertRaises(HTTPException):
            m.principal(request(), credentials(login["accessToken"]), self.s)
        with self.assertRaises(HTTPException):
            m.login(m.LoginInput(
                email=user.email,
                password="Rollback-auth-password!9",
            ), self.s)
        self.assertIn("accessToken", m.login(m.LoginInput(
            email=user.email,
            password="Changed-auth-password!8",
        ), self.s))

    def test_admin_reset_is_expiring_single_use_and_keeps_the_same_account(self):
        direction = self.add(m.SchoolDirection(
            establishment_id=self.tenant.id,
            code="RESET_DIRECTION",
            name="Direction reset",
            status="active",
        ))
        admin = self.user(
            email="reset.admin.rollback@example.invalid",
            role="admin",
            school_id=self.tenant.id,
            direction_id=direction.id,
        )
        superadmin = self.user(
            email="reset.super.rollback@example.invalid",
            role="superadmin",
        )
        current = m.Principal(id=str(superadmin.id), role="superadmin")

        reset = m.reset_admin_password(admin.id, current, self.s)
        temporary = reset["temporaryPassword"]
        self.assertEqual(self.s.get(m.User, admin.id).id, admin.id)
        self.assertFalse(admin.password_set)
        grant = m.temporary_access(self.s, admin)
        self.assertIsNotNone(grant)
        self.assertNotIn(temporary, str(grant.payload))

        first = m.login(m.LoginInput(email=admin.email, password=temporary), self.s)
        self.assertTrue(first["user"]["mustChangePassword"])
        with self.assertRaises(HTTPException) as reused:
            m.login(m.LoginInput(email=admin.email, password=temporary), self.s)
        self.assertEqual(reused.exception.status_code, 401)

        forced = m.principal(
            request("/api/v1/auth/change-password"),
            credentials(first["accessToken"]),
            self.s,
        )
        changed = m.change_password(m.ChangePasswordInput(
            new_password="Final-admin-password!7",
            new_password_confirmation="Final-admin-password!7",
        ), forced, self.s)
        self.assertFalse(changed["user"]["mustChangePassword"])
        self.assertIsNone(m.temporary_access(self.s, admin))
        with self.assertRaises(HTTPException):
            m.login(m.LoginInput(email=admin.email, password=temporary), self.s)
        self.assertIn("accessToken", m.login(m.LoginInput(
            email=admin.email,
            password="Final-admin-password!7",
        ), self.s))

    def test_expired_temporary_access_is_refused(self):
        user = self.user(email="expired.reset.rollback@example.invalid", role="superadmin")
        temporary = m.issue_temporary_access(self.s, user, "rollback-expiration-test")
        grant = m.temporary_access(self.s, user)
        grant.payload = {
            **grant.payload,
            "expiresAt": (datetime.now(timezone.utc) - timedelta(seconds=1)).isoformat(),
        }
        self.s.flush()
        with self.assertRaises(HTTPException) as error:
            m.login(m.LoginInput(email=user.email, password=temporary), self.s)
        self.assertEqual(error.exception.status_code, 401)

    def test_teacher_access_reset_preserves_the_real_profile_link(self):
        teacher = self.teachers[0]
        teacher.employee_number = "ENS-ROLLBACK-ACCESS"
        original_user_id = teacher.user_id
        teacher.email = self.s.get(m.User, original_user_id).email
        self.s.flush()
        original_teacher_count = self.s.scalar(
            m.select(m.func.count()).select_from(m.Teacher)
        )
        current = m.Principal(id=str(uuid.uuid4()), role="superadmin")

        reset = m.provision_teacher_access(teacher.id, current, self.s)

        self.assertEqual(reset["teacher"]["id"], str(teacher.id))
        self.assertEqual(teacher.user_id, original_user_id)
        self.assertEqual(
            self.s.scalar(m.select(m.func.count()).select_from(m.Teacher)),
            original_teacher_count,
        )
        user = self.s.get(m.User, original_user_id)
        self.assertTrue(m.passwords.verify(reset["temporaryPassword"], user.password_hash))
        self.assertFalse(user.password_set)
        self.assertIsNotNone(m.temporary_access(self.s, user))

    def test_student_access_uses_official_registration_without_duplicate_profile(self):
        student = self.students[0]
        registration = self.s.scalar(m.select(m.StudentAcademicRegistration).where(
            m.StudentAcademicRegistration.student_id == student.id
        ))
        registration.registration_number = "MAT-ROLLBACK-2026-0001"
        self.s.flush()
        original_student_count = self.s.scalar(
            m.select(m.func.count()).select_from(m.Student)
        )

        access = m.provision_student_access(
            student.id,
            m.Principal(id=str(uuid.uuid4()), role="superadmin"),
            self.s,
        )
        self.assertEqual(access["matricule"], registration.registration_number)
        self.assertEqual(
            self.s.scalar(m.select(m.func.count()).select_from(m.Student)),
            original_student_count,
        )
        self.assertIsNotNone(student.user_id)

        logged_in = m.login(m.LoginInput(
            identifier="mat-rollback-2026-0001",
            password=access["temporaryPassword"],
        ), self.s)
        principal = m.principal(
            request(), credentials(logged_in["accessToken"]), self.s
        )
        self.assertEqual(principal.role, "student")
        self.assertEqual(principal.student_id, str(student.id))
        public_school_id = "school-rollback-student"
        self.add(m.Resource(
            kind="establishments",
            id=public_school_id,
            school_id=public_school_id,
            establishment_id=self.tenant.id,
            payload={
                "id": public_school_id,
                "databaseId": str(self.tenant.id),
                "name": self.tenant.name,
                "type": "Établissement scolaire",
                "plan": "standard",
            },
        ))
        principal.school_id = public_school_id
        workspace = m.student_workspace(principal, self.s)
        self.assertEqual(workspace["student"]["id"], str(student.id))
        self.assertEqual(len(workspace["registrations"]), 1)

    def test_colliding_teacher_matricules_are_resolved_by_password_and_fail_closed(self):
        first_teacher = self.teachers[0]
        first_teacher.employee_number = "ENS-COLLISION"
        first_user = self.s.get(m.User, first_teacher.user_id)
        first_user.password_hash = m.passwords.hash("First-collision-password!1")
        other_tenant = self.add(m.Establishment(
            name="ROLLBACK collision", institution_type="secondary", city="Test"
        ))
        second_user = self.user(
            email="collision.teacher@example.invalid",
            role="teacher",
            school_id=other_tenant.id,
        )
        second_user.password_hash = m.passwords.hash("Second-collision-password!2")
        second_teacher = self.add(m.Teacher(
            establishment_id=other_tenant.id,
            user_id=second_user.id,
            first_name="Second",
            last_name="Collision",
            employee_number="ENS-COLLISION",
            status="active",
        ))
        self.s.flush()

        result = m.login(m.LoginInput(
            identifier="ENS-COLLISION",
            password="Second-collision-password!2",
        ), self.s)
        self.assertEqual(result["user"]["id"], str(second_user.id))

        second_user.password_hash = first_user.password_hash
        self.s.flush()
        with self.assertRaises(HTTPException) as ambiguous:
            m.login(m.LoginInput(
                identifier="ENS-COLLISION",
                password="First-collision-password!1",
            ), self.s)
        self.assertEqual(ambiguous.exception.status_code, 401)
        self.assertIsNotNone(second_teacher.id)

    def test_expired_and_unknown_user_tokens_are_refused(self):
        now = datetime.now(timezone.utc)
        expired = m.jwt.encode({
            "sub": str(uuid.uuid4()),
            "role": "superadmin",
            "exp": now - timedelta(seconds=1),
        }, m.JWT_SECRET, algorithm="HS256")
        unknown = m.jwt.encode({
            "sub": str(uuid.uuid4()),
            "role": "superadmin",
            "exp": now + timedelta(minutes=5),
        }, m.JWT_SECRET, algorithm="HS256")

        for token in (expired, unknown):
            with self.subTest(token=token[:12]):
                with self.assertRaises(HTTPException) as error:
                    m.principal(request(), credentials(token), self.s)
                self.assertEqual(error.exception.status_code, 401)

    def test_valid_token_is_refused_after_user_deletion(self):
        user = self.user(email="deleted.rollback@example.invalid", role="superadmin")
        result = m.login(m.LoginInput(
            email=user.email,
            password="Rollback-auth-password!9",
        ), self.s)
        token = result["accessToken"]

        with self.s.begin_nested() as mutation:
            self.s.delete(user)
            self.s.flush()
            with self.assertRaises(HTTPException) as error:
                m.principal(request(), credentials(token), self.s)
            self.assertEqual(error.exception.status_code, 401)
            mutation.rollback()

    def test_superadmin_is_denied_attendance_and_behavior_modules_only(self):
        current = m.Principal(id=str(uuid.uuid4()), role="superadmin")
        for module in ("attendance", "behavior"):
            with self.subTest(module=module):
                with self.assertRaises(HTTPException) as error:
                    m.require_module_roles(module, "superadmin")(current, self.s)
                self.assertEqual(error.exception.status_code, 403)
        self.assertIs(m.require_module_roles("grades", "superadmin")(current, self.s), current)

    def test_lycee_series_and_student_gender_are_server_validated(self):
        lycee = m.SchoolCycle(
            establishment_id=self.tenant.id,
            code="LYCEE",
            name="Lycée",
        )
        with self.assertRaises(HTTPException) as missing_series:
            m.validate_class_series_requirement(lycee, None)
        self.assertEqual(missing_series.exception.detail, "Veuillez sélectionner une série.")
        m.validate_class_series_requirement(lycee, uuid.uuid4())

        valid_identity = {
            "firstName": "Aline",
            "lastName": "Test",
            "birthDate": "2012-01-01",
            "nationality": "Congolaise",
            "address": "Brazzaville",
        }
        for gender in ("M", "F"):
            self.assertEqual(
                m.StudentIdentityInput(**valid_identity, gender=gender).gender,
                gender,
            )
        with self.assertRaises(ValidationError):
            m.StudentIdentityInput(**valid_identity, gender="X")


if __name__ == "__main__":
    unittest.main(verbosity=2)

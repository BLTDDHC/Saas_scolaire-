from __future__ import annotations

import json
import secrets
import uuid
import urllib.error
import urllib.request
from datetime import datetime, timedelta, timezone

from sqlalchemy import delete, func, select, update
from sqlalchemy.orm import Session

from app.main import (
    AcademicYear,
    Affectation,
    Establishment,
    JWT_SECRET,
    Resource,
    SchoolClass,
    SchoolCycle,
    SchoolDirection,
    SchoolDirectionCycle,
    SchoolLevel,
    SchoolSeries,
    Student,
    Subject,
    SubjectLevelSetting,
    Teacher,
    User,
    engine,
    jwt,
)


class LocalResponse:
    def __init__(self, status_code: int, body: bytes):
        self.status_code = status_code
        self._body = body
        self.text = body.decode("utf-8", errors="replace")

    def json(self):
        return json.loads(self.text)


class LocalClient:
    base_url = "http://127.0.0.1:8000"

    def request(self, method: str, path: str, *, headers=None, json_body=None):
        request_headers = {"Content-Type": "application/json"}
        request_headers.update(headers or {})
        payload = (
            json.dumps(json_body).encode("utf-8")
            if json_body is not None
            else None
        )
        request = urllib.request.Request(
            self.base_url + path,
            data=payload,
            headers=request_headers,
            method=method,
        )
        try:
            with urllib.request.urlopen(request, timeout=15) as response:
                return LocalResponse(response.status, response.read())
        except urllib.error.HTTPError as error:
            return LocalResponse(error.code, error.read())

    def get(self, path: str, *, headers=None):
        return self.request("GET", path, headers=headers)

    def post(self, path: str, *, headers=None, json=None):
        return self.request("POST", path, headers=headers, json_body=json)

    def put(self, path: str, *, headers=None, json=None):
        return self.request("PUT", path, headers=headers, json_body=json)


def bearer(user: User) -> dict[str, str]:
    token = jwt.encode(
        {
            "sub": str(user.id),
            "role": user.role,
            "school_id": None,
            "exp": datetime.now(timezone.utc) + timedelta(hours=2),
        },
        JWT_SECRET,
        algorithm="HS256",
    )
    return {"Authorization": f"Bearer {token}"}


def counts(session, school_id):
    return {
        "users": session.scalar(
            select(func.count()).select_from(User).where(User.school_id == school_id)
        ),
        "teachers": session.scalar(
            select(func.count())
            .select_from(Teacher)
            .where(Teacher.establishment_id == school_id)
        ),
        "students": session.scalar(
            select(func.count())
            .select_from(Student)
            .where(Student.establishment_id == school_id)
        ),
        "classes": session.scalar(
            select(func.count())
            .select_from(SchoolClass)
            .where(SchoolClass.establishment_id == school_id)
        ),
    }


client = LocalClient()
session = Session(engine)
marker = uuid.uuid4().hex[:10]
teacher_email = f"validation.teacher.{marker}@edupro.local"
teacher_id = None
teacher_user_id = None
class_id = None
offer_id = None
test_school_id = None
report: dict[str, object] = {}

protected = list(
    session.scalars(
        select(Establishment).where(
            func.lower(Establishment.name).in_(("godfirst", "le cogito"))
        )
    ).all()
)
if {item.name.lower() for item in protected} != {"godfirst", "le cogito"}:
    raise AssertionError("Les deux établissements protégés sont requis")
all_schools = list(session.scalars(select(Establishment)).all())
if {item.name.lower() for item in all_schools} != {"godfirst", "le cogito"}:
    raise AssertionError("Des établissements hors périmètre sont encore présents")
godfirst = next(item for item in protected if item.name.lower() == "godfirst")
superadmin = session.scalar(select(User).where(User.role == "superadmin"))
if not superadmin:
    raise AssertionError("Super Admin introuvable")
superadmin_snapshot = (superadmin.id, superadmin.password_hash, superadmin.status)
protected_before = {str(item.id): counts(session, item.id) for item in protected}

try:
    admin = session.scalar(
        select(User).where(
            User.school_id == godfirst.id,
            User.role == "admin",
            User.status == "active",
            User.direction_id.is_not(None),
        )
    )
    if not admin:
        raise AssertionError("Administrateur de direction GodFirst introuvable")
    admin_headers = bearer(admin)

    direction_cycle_ids = list(
        session.scalars(
            select(SchoolDirectionCycle.cycle_id).where(
                SchoolDirectionCycle.direction_id == admin.direction_id
            )
        ).all()
    )
    source_class = session.scalar(
        select(SchoolClass).where(
            SchoolClass.establishment_id == godfirst.id,
            SchoolClass.cycle_id.in_(direction_cycle_ids),
            SchoolClass.status == "active",
        )
    )
    if not source_class:
        raise AssertionError("Classe de référence introuvable dans la direction")

    teacher_response = client.post(
        "/api/v1/school/teachers",
        headers=admin_headers,
        json={
            "firstName": "Validation",
            "lastName": "CODEX",
            "email": teacher_email,
            "specialization": "Validation",
        },
    )
    if teacher_response.status_code != 201:
        raise AssertionError(
            f"Création enseignant refusée: {teacher_response.status_code} {teacher_response.text}"
        )
    teacher_data = teacher_response.json()
    teacher_id = uuid.UUID(teacher_data["id"])
    if teacher_data.get("directionId") != str(admin.direction_id):
        raise AssertionError("La direction de création de l'enseignant est incorrecte")

    listed = client.get("/api/v1/school/teachers", headers=admin_headers)
    if listed.status_code != 200 or not any(
        item["id"] == str(teacher_id) for item in listed.json()
    ):
        raise AssertionError("Le nouvel enseignant disparaît avant son affectation")

    access = client.post(
        f"/api/v1/school/teachers/{teacher_id}/access",
        headers=admin_headers,
        json={},
    )
    if access.status_code != 200:
        raise AssertionError(
            f"Création accès refusée: {access.status_code} {access.text}"
        )
    temporary_password = access.json()["temporaryPassword"]
    teacher_user_id = uuid.UUID(access.json()["teacher"]["userId"])

    login = client.post(
        "/api/v1/auth/login",
        json={"email": teacher_email, "password": temporary_password},
    )
    if login.status_code != 200 or not login.json()["user"]["mustChangePassword"]:
        raise AssertionError("Connexion temporaire ou changement obligatoire incorrect")
    teacher_headers = {"Authorization": f"Bearer {login.json()['accessToken']}"}

    blocked_workspace = client.get(
        "/api/v1/school/teacher/workspace", headers=teacher_headers
    )
    if blocked_workspace.status_code != 403:
        raise AssertionError("Le workspace doit rester bloqué avant le changement")

    new_password = f"Vx!{secrets.token_urlsafe(18)}9"
    changed = client.post(
        "/api/v1/auth/change-password",
        headers=teacher_headers,
        json={
            "current_password": temporary_password,
            "new_password": new_password,
        },
    )
    if changed.status_code != 200:
        raise AssertionError(f"Changement refusé: {changed.status_code} {changed.text}")
    me = client.get("/api/v1/auth/me", headers=teacher_headers)
    if me.status_code != 200 or me.json()["mustChangePassword"]:
        raise AssertionError("Le profil actualisé conserve le changement obligatoire")

    class_name = f"Validation {marker}"
    class_response = client.post(
        "/api/v1/school/classes",
        headers=admin_headers,
        json={
            "academicYearId": str(source_class.academic_year_id),
            "cycleId": str(source_class.cycle_id),
            "schoolLevelId": str(source_class.school_level_id),
            "seriesId": str(source_class.series_id) if source_class.series_id else None,
            "name": class_name,
            "status": "active",
        },
    )
    if class_response.status_code != 201:
        raise AssertionError(
            f"Création classe de validation refusée: {class_response.status_code} {class_response.text}"
        )
    class_id = uuid.UUID(class_response.json()["id"])

    context_settings = list(
        session.scalars(
            select(SubjectLevelSetting).where(
                SubjectLevelSetting.establishment_id == godfirst.id,
                SubjectLevelSetting.academic_year_id == source_class.academic_year_id,
                SubjectLevelSetting.school_level_id == source_class.school_level_id,
                SubjectLevelSetting.series_id == source_class.series_id,
                SubjectLevelSetting.status == "active",
            )
        ).all()
    )
    if context_settings:
        subject_id = context_settings[0].subject_id
    else:
        subject_id = session.scalar(
            select(Subject.id).where(
                Subject.establishment_id == godfirst.id,
                Subject.status == "active",
            )
        )
    if not subject_id:
        raise AssertionError("Matière active introuvable")

    assignment = client.post(
        "/api/v1/school/affectations",
        headers=admin_headers,
        json={
            "teacherId": str(teacher_id),
            "classId": str(class_id),
            "subjectId": str(subject_id),
        },
    )
    if assignment.status_code != 201:
        raise AssertionError(
            f"Affectation refusée: {assignment.status_code} {assignment.text}"
        )
    duplicate = client.post(
        "/api/v1/school/affectations",
        headers=admin_headers,
        json={
            "teacherId": str(teacher_id),
            "classId": str(class_id),
            "subjectId": str(subject_id),
        },
    )
    if duplicate.status_code != 409:
        raise AssertionError("Le doublon classe + matière n'est pas refusé")

    main_teacher = client.put(
        f"/api/v1/school/classes/{class_id}/main-teacher",
        headers=admin_headers,
        json={"teacherId": str(teacher_id)},
    )
    if main_teacher.status_code != 200:
        raise AssertionError(
            f"Affectation du professeur principal refusée: "
            f"{main_teacher.status_code} {main_teacher.text}"
        )

    current_login = client.post(
        "/api/v1/auth/login",
        json={"email": teacher_email, "password": new_password},
    )
    old_login = client.post(
        "/api/v1/auth/login",
        json={"email": teacher_email, "password": temporary_password},
    )
    if current_login.status_code != 200 or old_login.status_code != 401:
        raise AssertionError("La bascule du mot de passe enseignant est incorrecte")
    current_headers = {
        "Authorization": f"Bearer {current_login.json()['accessToken']}"
    }
    workspace = client.get(
        "/api/v1/school/teacher/workspace", headers=current_headers
    )
    if workspace.status_code != 200 or not any(
        item["id"] == str(class_id) for item in workspace.json()["classes"]
    ):
        raise AssertionError("La classe affectée n'apparaît pas dans le workspace")

    outside_class = session.scalar(
        select(SchoolClass).where(
            SchoolClass.establishment_id == godfirst.id,
            SchoolClass.status == "active",
            SchoolClass.cycle_id.not_in(direction_cycle_ids),
        )
    )
    outside_status = None
    if outside_class:
        outside_status = client.put(
            f"/api/v1/school/classes/{outside_class.id}/main-teacher",
            headers=admin_headers,
            json={"teacherId": str(teacher_id)},
        ).status_code
        if outside_status != 403:
            raise AssertionError("L'accès hors direction n'est pas refusé")

    offer_name = f"Validation {marker}"
    offer = client.post(
        "/api/v1/superadmin/plans",
        headers=bearer(superadmin),
        json={
            "name": offer_name,
            "description": "Validation automatique",
            "price": 1000,
            "durationDays": 30,
            "status": "active",
            "features": ["students", "teachers", "classes", "subjects"],
            "limits": {},
        },
    )
    if offer.status_code != 201:
        raise AssertionError(f"Création offre refusée: {offer.status_code} {offer.text}")
    offer_id = offer.json()["id"]

    school = client.post(
        "/api/v1/superadmin/establishments",
        headers=bearer(superadmin),
        json={
            "name": f"Validation établissement {marker}",
            "city": "Brazzaville",
            "country": "Congo",
            "plan": offer_name,
            "admin_name": "CODEX Validation",
            "admin_email": f"validation.admin.{marker}@edupro.local",
            "admin_direction_code": "MATERNELLE_PRIMAIRE",
            "cycles": ["PRIMAIRE"],
        },
    )
    if school.status_code != 201:
        raise AssertionError(
            f"Création établissement avec offre refusée: {school.status_code} {school.text}"
        )
    test_school_id = uuid.UUID(school.json()["establishment"]["databaseId"])
    created_school = session.get(Establishment, test_school_id)
    session.refresh(created_school)
    expected_modules = ["students", "teachers", "classes", "subjects"]
    if created_school.enabled_modules != expected_modules:
        raise AssertionError(
            f"Modules hérités incorrects: {created_school.enabled_modules}"
        )
    created_directions = list(
        session.scalars(
            select(SchoolDirection).where(
                SchoolDirection.establishment_id == test_school_id
            )
        ).all()
    )
    if [item.code for item in created_directions] != ["MATERNELLE_PRIMAIRE"]:
        raise AssertionError("Les directions ne correspondent pas aux cycles choisis")

    report = {
        "establishments": sorted(item.name for item in all_schools),
        "teacher_access": {
            "created": teacher_response.status_code,
            "visible_before_assignment": True,
            "temporary_login": login.status_code,
            "workspace_before_password_change": blocked_workspace.status_code,
            "change_password": changed.status_code,
            "me_after_change": me.status_code,
            "new_password_login": current_login.status_code,
            "old_password_login": old_login.status_code,
            "workspace_after_assignment": workspace.status_code,
        },
        "assignment": {
            "created": assignment.status_code,
            "duplicate_refused": duplicate.status_code,
            "main_teacher": main_teacher.status_code,
            "outside_direction_refused": outside_status,
        },
        "offer": {
            "created": offer.status_code,
            "school_created": school.status_code,
            "modules_inherited": created_school.enabled_modules,
            "directions": [item.code for item in created_directions],
        },
    }
finally:
    session.rollback()
    if test_school_id:
        session.execute(
            delete(Resource).where(Resource.establishment_id == test_school_id)
        )
        session.execute(delete(User).where(User.school_id == test_school_id))
        session.execute(
            delete(SchoolDirectionCycle).where(
                SchoolDirectionCycle.establishment_id == test_school_id
            )
        )
        session.execute(
            delete(SchoolDirection).where(
                SchoolDirection.establishment_id == test_school_id
            )
        )
        session.execute(
            delete(SchoolSeries).where(
                SchoolSeries.establishment_id == test_school_id
            )
        )
        session.execute(
            delete(SchoolLevel).where(
                SchoolLevel.establishment_id == test_school_id
            )
        )
        session.execute(
            delete(SchoolCycle).where(
                SchoolCycle.establishment_id == test_school_id
            )
        )
        test_school = session.get(Establishment, test_school_id)
        if test_school:
            session.delete(test_school)
    if offer_id:
        offer_row = session.get(Resource, {"kind": "plans", "id": offer_id})
        if offer_row:
            session.delete(offer_row)
    if class_id:
        session.execute(
            update(SchoolClass)
            .where(SchoolClass.id == class_id)
            .values(main_teacher_id=None)
        )
    if teacher_id or class_id:
        conditions = []
        if teacher_id:
            conditions.append(Affectation.teacher_id == teacher_id)
        if class_id:
            conditions.append(Affectation.class_id == class_id)
        for condition in conditions:
            session.execute(delete(Affectation).where(condition))
    session.flush()
    if teacher_id:
        teacher = session.get(Teacher, teacher_id)
        if teacher:
            session.delete(teacher)
    if teacher_user_id:
        user = session.get(User, teacher_user_id)
        if user:
            session.delete(user)
    if class_id:
        school_class = session.get(SchoolClass, class_id)
        if school_class:
            session.delete(school_class)
    session.commit()

    refreshed_superadmin = session.get(User, superadmin_snapshot[0])
    if (
        not refreshed_superadmin
        or refreshed_superadmin.password_hash != superadmin_snapshot[1]
        or refreshed_superadmin.status != superadmin_snapshot[2]
    ):
        raise AssertionError("Le Super Admin a été modifié")
    protected_after = {str(item.id): counts(session, item.id) for item in protected}
    if protected_after != protected_before:
        raise AssertionError(
            f"Les compteurs protégés ont changé: {protected_before} -> {protected_after}"
        )
    final_school_names = {
        item.name.lower() for item in session.scalars(select(Establishment)).all()
    }
    if final_school_names != {"godfirst", "le cogito"}:
        raise AssertionError(f"Nettoyage incomplet: {final_school_names}")
    session.close()

report["cleanup"] = {
    "temporary_data_removed": True,
    "protected_counts_unchanged": True,
    "superadmin_unchanged": True,
}
print(json.dumps(report, ensure_ascii=False, indent=2))

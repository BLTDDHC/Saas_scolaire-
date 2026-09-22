import uuid

import jwt
from urllib.request import Request, urlopen
from fastapi import HTTPException
from sqlalchemy import func, select

from app.main import (
    JWT_SECRET,
    Affectation,
    Principal,
    SchoolClass,
    SchoolCycle,
    SchoolDirection,
    SchoolDirectionCycle,
    Session,
    User,
    engine,
    list_affectations,
    list_relational_students,
    list_school_classes,
    list_school_cycles,
    list_subjects,
    list_teachers,
    public_school_id,
    school_organization_summary,
    scoped_cycle,
)


with Session(engine) as session:
    direction = session.scalar(
        select(SchoolDirection)
        .join(SchoolDirectionCycle, SchoolDirectionCycle.direction_id == SchoolDirection.id)
        .join(SchoolClass, SchoolClass.cycle_id == SchoolDirectionCycle.cycle_id)
        .where(SchoolDirection.status == "active")
        .group_by(SchoolDirection.id)
        .order_by(func.count(SchoolClass.id).desc())
    )
    assert direction is not None, "No direction with classes"
    allowed = list(
        session.scalars(
            select(SchoolDirectionCycle.cycle_id).where(
                SchoolDirectionCycle.direction_id == direction.id
            )
        ).all()
    )
    public_id = public_school_id(session, direction.establishment_id)
    principal = Principal(
        id=str(uuid.uuid4()),
        role="admin",
        school_id=public_id,
        direction_id=str(direction.id),
        direction_name=direction.name,
        direction_cycle_ids=[str(item) for item in allowed],
    )
    cycles = list_school_cycles(None, principal, session)
    assert {uuid.UUID(item["id"]) for item in cycles} == set(allowed)
    classes = list_school_classes(None, None, None, None, principal, session)
    assert all(uuid.UUID(item["cycleId"]) in set(allowed) for item in classes)
    students = list_relational_students(
        None, None, None, None, None, None, None, principal, session
    )
    teachers = list_teachers(None, None, None, principal, session)
    subjects = list_subjects(None, principal, session)
    affectations = list_affectations(None, None, principal, session)
    summary = school_organization_summary(None, principal, session)
    assert summary["direction"]["id"] == str(direction.id)
    denied = session.scalar(
        select(SchoolCycle).where(
            SchoolCycle.establishment_id == direction.establishment_id,
            SchoolCycle.id.not_in(allowed),
        )
    )
    if denied:
        try:
            scoped_cycle(denied.id, principal, session)
            raise AssertionError("Out-of-direction cycle was accepted")
        except HTTPException as exc:
            assert exc.status_code == 403
    superadmin = session.scalar(select(User).where(User.role == "superadmin"))
    assert superadmin is not None
    token = jwt.encode(
        {"sub": str(superadmin.id), "role": "superadmin"},
        JWT_SECRET,
        algorithm="HS256",
    )
    request = Request(
        f"http://127.0.0.1:8000/api/v1/superadmin/establishments/{public_id}/directions",
        headers={"Authorization": f"Bearer {token}"},
    )
    with urlopen(request, timeout=10) as response:
        status_code = response.status
        import json
        payload = json.loads(response.read().decode("utf-8"))
    assert status_code == 200
    assert payload["directions"]
    print("DIRECTION", direction.name)
    print("CYCLES", len(cycles))
    print("CLASSES", len(classes))
    print("STUDENTS", len(students))
    print("TEACHERS", len(teachers))
    print("SUBJECTS", len(subjects))
    print("AFFECTATIONS", len(affectations))
    print("OUT_OF_SCOPE", "403" if denied else "NO_OTHER_CYCLE")
    print("SUPERADMIN_DIRECTIONS", status_code)
    print("DIRECTION_VALIDATION_OK")

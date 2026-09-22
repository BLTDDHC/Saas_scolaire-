"""Teacher-owned trimester sheets. No local-cache authority or grade workflow changes."""
import hashlib
import json
import re
import uuid
from datetime import datetime, timezone
from decimal import Decimal

from fastapi import HTTPException
from sqlalchemy import select, text
from sqlalchemy.exc import IntegrityError

from . import main as m


def context(current, session, class_id, period_id, school_id=None):
    school_class = session.get(m.SchoolClass, class_id)
    if not school_class:
        raise HTTPException(404, "Classe introuvable")
    # A selected class is an explicit tenant context, never the global user's tenant.
    requested = school_id
    if current.role == "superadmin" and not requested:
        requested = m.public_school_id(session, school_class.establishment_id)
    _, tenant = m.module_tenant_scope(current, session, requested)
    m.ensure_class_module_access(current, school_class, tenant, session)
    period = session.get(m.AcademicPeriod, period_id)
    if (not period or period.establishment_id != tenant
            or period.academic_year_id != school_class.academic_year_id
            or period.period_type != "trimester"):
        raise HTTPException(422, "Le trimestre ne correspond pas à l’année de cette classe")
    year = session.get(m.AcademicYear, school_class.academic_year_id)
    return school_class, period, year


def lock_context(session, school_class, period):
    acquired = session.scalar(text("SELECT pg_try_advisory_xact_lock(hashtextextended(:key, 0))"),
                    {"key": f"behavior:{school_class.establishment_id}:{school_class.id}:{period.id}"})
    if not acquired:
        raise HTTPException(409, "Un envoi ou calcul est déjà en cours. Actualisez dans un instant")


def sources(session, school_class, period, year):
    tenant = school_class.establishment_id
    students = list(session.scalars(select(m.Student).join(
        m.StudentAcademicRegistration, m.StudentAcademicRegistration.student_id == m.Student.id
    ).where(m.Student.establishment_id == tenant, m.Student.status == "active",
        m.StudentAcademicRegistration.establishment_id == tenant,
        m.StudentAcademicRegistration.class_id == school_class.id,
        m.StudentAcademicRegistration.academic_year_id == year.id,
        m.StudentAcademicRegistration.status.in_(("pending", "validated", "active"))
    ).distinct().order_by(m.Student.id)))
    teachers = list(session.scalars(select(m.Teacher).join(m.User, m.Teacher.user_id == m.User.id)
        .join(m.Affectation, m.Affectation.teacher_id == m.Teacher.id).where(
            m.Teacher.establishment_id == tenant, m.Teacher.status == "active",
            m.User.school_id == tenant, m.User.role == "teacher", m.User.status == "active",
            m.Affectation.establishment_id == tenant, m.Affectation.class_id == school_class.id,
            m.Affectation.status == "active").distinct().order_by(m.Teacher.id)))
    events = list(session.scalars(select(m.BehaviorEvent).where(
        m.BehaviorEvent.establishment_id == tenant, m.BehaviorEvent.class_id == school_class.id,
        m.BehaviorEvent.academic_year_id == year.id, m.BehaviorEvent.academic_period_id == period.id,
        m.BehaviorEvent.status != "archived").order_by(m.BehaviorEvent.id)))
    return students, teachers, events


def event_json(event, teachers, period, school_id):
    teacher = teachers.get(event.teacher_id)
    return {"id": str(event.id), "studentId": str(event.student_id),
        "classId": str(event.class_id), "academicYearId": str(event.academic_year_id),
        "periodId": str(period.id), "period": period.name, "schoolId": school_id,
        "teacherId": str(event.teacher_id),
        "teacher": f"{teacher.last_name} {teacher.first_name}" if teacher else None,
        "date": event.event_date.isoformat(), "score": int(event.category.split(":")[1]),
        "comment": event.description, "status": event.status,
        "recordedBy": str(event.recorded_by) if event.recorded_by else None}


def list_events(current, session, class_id, period_id, year_id=None, student_id=None, school_id=None):
    if not class_id or not period_id:
        raise HTTPException(422, "Sélectionnez une classe et un trimestre")
    cl, period, year = context(current, session, class_id, period_id, school_id)
    if year_id and year_id != year.id:
        raise HTTPException(422, "L’année ne correspond pas à la classe")
    students, teachers, events = sources(session, cl, period, year)
    if current.role == "teacher" and not any(str(t.id) == current.teacher_id for t in teachers):
        raise HTTPException(403, "Vous n’êtes pas autorisé à remplir ce relevé")
    teacher_map = {t.id: t for t in teachers}
    public_id = m.public_school_id(session, cl.establishment_id)
    return [event_json(e, teacher_map, period, public_id) for e in events
            if (not student_id or e.student_id == student_id)
            and (current.role != "teacher" or str(e.teacher_id) == current.teacher_id)]


def save_sheet(current, session, body):
    cl, period, year = context(current, session, body.class_id, body.academic_period_id)
    lock_context(session, cl, period)
    session.refresh(cl)
    session.refresh(period)
    if cl.status != "active" or period.status != "active" or year.status != "active":
        raise HTTPException(409, "Ce contexte scolaire n’est plus ouvert à la saisie")
    students, teachers, events = sources(session, cl, period, year)
    teacher = next((t for t in teachers if str(t.id) == current.teacher_id
                    and str(t.user_id) == current.id), None)
    if not teacher:
        raise HTTPException(403, "Vous n’êtes pas autorisé à remplir ce relevé")
    own = [e for e in events if e.teacher_id == teacher.id]
    if any(e.status in ("locked", "active") for e in own):
        raise HTTPException(409, "Vous avez déjà envoyé ce relevé")
    expected = {s.id for s in students}
    supplied = [e.student_id for e in body.entries]
    if len(supplied) != len(set(supplied)):
        raise HTTPException(422, "Un élève apparaît plusieurs fois dans le relevé")
    if set(supplied) - expected:
        raise HTTPException(422, "Un élève n’appartient pas à la classe sélectionnée")
    if body.action == "submit" and (not expected or set(supplied) != expected):
        raise HTTPException(422, "Le relevé est incomplet. Renseignez tous les élèves avant de l’envoyer")
    by_student = {e.student_id: e for e in own}
    now = datetime.now(timezone.utc)
    saved = []
    for entry in body.entries:
        event = by_student.get(entry.student_id)
        if event is None:
            event = m.BehaviorEvent(establishment_id=cl.establishment_id,
                student_id=entry.student_id, class_id=cl.id, academic_year_id=year.id,
                academic_period_id=period.id, teacher_id=teacher.id,
                recorded_by=teacher.user_id, event_date=period.start_date or now.date())
            session.add(event)
        event.category = f"stars:{entry.stars}"
        event.event_type = "positive" if entry.stars >= 3 else "negative"
        event.severity = "normal"
        event.title = f"{entry.stars} étoiles"
        event.description = entry.comment.strip() if entry.comment else None
        event.status = "locked" if body.action == "submit" else "draft"
        event.updated_at = now
        saved.append(event)
    try:
        session.commit()
    except IntegrityError as exc:
        session.rollback()
        raise HTTPException(409, "Le relevé a déjà été envoyé ou son contexte a changé. Actualisez la page") from exc
    return [event_json(e, {teacher.id: teacher}, period,
            m.public_school_id(session, cl.establishment_id)) for e in saved]


def state(current, session, class_id, period_id, school_id=None):
    cl, period, year = context(current, session, class_id, period_id, school_id)
    students, teachers, events = sources(session, cl, period, year)
    expected = {s.id for s in students}
    valid = [e for e in events if e.status in ("locked", "active")
             and e.student_id in expected and re.fullmatch(r"stars:[1-5]", e.category)
             and any(t.id == e.teacher_id and t.user_id == e.recorded_by for t in teachers)]
    submissions = []
    for teacher in teachers:
        own = [e for e in valid if e.teacher_id == teacher.id]
        complete = bool(expected) and {e.student_id for e in own} == expected and len(own) == len(expected)
        submissions.append({"teacherId": str(teacher.id),
            "teacher": f"{teacher.last_name} {teacher.first_name}",
            "status": "submitted" if complete else "pending", "studentCount": len(own)})
    ready = (bool(submissions) and bool(expected) and all(t["status"] == "submitted" for t in submissions)
             and cl.status == "active" and period.status == "active" and year.status == "active")
    # Canonical sets detect removals/disablements too. A second subject for the same
    # teacher does not change a behavior contribution and deliberately does not stale it.
    fingerprint_data = {
        "class": [str(cl.id), str(cl.cycle_id), str(cl.school_level_id), cl.status, str(cl.updated_at)],
        "year": [str(year.id), year.status, str(year.start_date), str(year.end_date)],
        "period": [str(period.id), period.status, period.period_type, str(period.start_date), str(period.end_date)],
        "directions": sorted(str(x) for x in session.scalars(select(m.SchoolDirectionCycle.direction_id).where(
            m.SchoolDirectionCycle.cycle_id == cl.cycle_id))),
        "students": sorted(str(s.id) for s in students),
        "teachers": sorted((str(t.id), str(t.user_id)) for t in teachers),
        "events": sorted((str(e.id), str(e.teacher_id), str(e.student_id), e.category, e.description,
                           e.status, str(e.recorded_by), str(e.updated_at)) for e in events),
    }
    fingerprint = hashlib.sha256(json.dumps(fingerprint_data, sort_keys=True).encode()).hexdigest()
    snapshot = session.scalar(select(m.BehaviorCalculation).where(
        m.BehaviorCalculation.establishment_id == cl.establishment_id,
        m.BehaviorCalculation.class_id == cl.id, m.BehaviorCalculation.academic_period_id == period.id))
    status = ("stale" if snapshot and snapshot.source_fingerprint != fingerprint
              else "waiting" if not ready else "official" if snapshot else "ready")
    payload = {"classId": str(cl.id), "periodId": str(period.id), "academicYearId": str(year.id),
        "schoolId": m.public_school_id(session, cl.establishment_id),
        "expectedCount": len(teachers), "receivedCount": sum(t["status"] == "submitted" for t in submissions),
        "missingCount": sum(t["status"] != "submitted" for t in submissions),
        "teacherSubmissions": submissions, "readyForCalculation": ready,
        "calculationStatus": status, "students": (snapshot.payload["students"] if status == "official" else []),
        "calculatedAt": snapshot.calculated_at.isoformat() if snapshot else None}
    return payload, (cl, period, year, students, valid, fingerprint, snapshot)


def results(current, session, class_id, period_id, school_id=None):
    return state(current, session, class_id, period_id, school_id)[0]


def calculate(current, session, class_id, period_id, school_id=None):
    cl, period, _ = context(current, session, class_id, period_id, school_id)
    lock_context(session, cl, period)
    payload, data = state(current, session, class_id, period_id, school_id)
    cl, period, year, students, valid, fingerprint, snapshot = data
    if not payload["readyForCalculation"]:
        raise HTTPException(409, "Tous les relevés ne sont pas encore reçus")
    totals = {s.id: [0, 0] for s in students}
    for event in valid:
        totals[event.student_id][0] += int(event.category.split(":")[1])
        totals[event.student_id][1] += 1
    rows = [{"studentId": str(s.id), "student": f"{s.last_name} {s.first_name}",
             "sum": totals[s.id][0], "contributionCount": totals[s.id][1],
             "average": float(Decimal(totals[s.id][0]) / Decimal(totals[s.id][1]))}
            for s in students]
    if snapshot is None:
        snapshot = m.BehaviorCalculation(establishment_id=cl.establishment_id,
            academic_year_id=year.id, class_id=cl.id, academic_period_id=period.id)
        session.add(snapshot)
    snapshot.source_fingerprint = fingerprint
    snapshot.payload = {"students": rows}
    snapshot.calculated_by = uuid.UUID(current.id)
    snapshot.calculated_at = datetime.now(timezone.utc)
    try:
        session.commit()
    except IntegrityError as exc:
        session.rollback()
        raise HTTPException(409, "Le contexte a changé. Actualisez avant de recalculer") from exc
    return {**payload, "calculationStatus": "official", "students": rows,
            "calculatedAt": snapshot.calculated_at.isoformat()}


def global_contexts(session):
    rows = session.execute(select(m.SchoolClass, m.Establishment, m.AcademicYear,
        m.SchoolCycle.name, m.SchoolLevel.name).join(m.Establishment,
        m.Establishment.id == m.SchoolClass.establishment_id).join(m.AcademicYear,
        m.AcademicYear.id == m.SchoolClass.academic_year_id).outerjoin(m.SchoolCycle,
        m.SchoolCycle.id == m.SchoolClass.cycle_id).outerjoin(m.SchoolLevel,
        m.SchoolLevel.id == m.SchoolClass.school_level_id).order_by(m.Establishment.name,
        m.AcademicYear.name, m.SchoolClass.name)).all()
    periods = list(session.scalars(select(m.AcademicPeriod).where(
        m.AcademicPeriod.period_type == "trimester", m.AcademicPeriod.status == "active")))
    return [{"schoolId": str(school.id), "school": school.name, "classId": str(cl.id),
        "class": cl.name, "year": year.name, "academicYearId": str(year.id),
        "cycle": cycle or "", "level": level or "",
        "periods": [{"id": str(p.id), "name": p.name} for p in periods
                    if p.establishment_id == school.id and p.academic_year_id == year.id]}
        for cl, school, year, cycle, level in rows]

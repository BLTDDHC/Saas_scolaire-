"""Attendance sheets and immutable scheduled-session history."""
import uuid
from datetime import datetime, time, timezone

from fastapi import HTTPException
from sqlalchemy import select, text
from sqlalchemy.exc import IntegrityError

from . import main as m


def now_local():
    return datetime.now().astimezone()


def snapshot(session, schedule):
    cl = session.get(m.SchoolClass, schedule.class_id)
    teacher = session.get(m.Teacher, schedule.teacher_id)
    subject = session.get(m.Subject, schedule.subject_id)
    cycle = session.get(m.SchoolCycle, cl.cycle_id) if cl.cycle_id else None
    level = session.get(m.SchoolLevel, cl.school_level_id) if cl.school_level_id else None
    direction = session.scalar(select(m.SchoolDirection).join(m.SchoolDirectionCycle,
        m.SchoolDirectionCycle.direction_id == m.SchoolDirection.id).where(m.SchoolDirectionCycle.cycle_id == cl.cycle_id))
    return {"classId": str(cl.id), "class": cl.name, "cycleId": str(cl.cycle_id) if cl.cycle_id else None,
        "cycle":cycle.name if cycle else "", "level":level.name if level else "",
        "directionId": str(direction.id) if direction else None, "direction":direction.name if direction else "",
        "levelId": str(cl.school_level_id) if cl.school_level_id else None,
        "teacherId": str(teacher.id), "teacher": f"{teacher.last_name} {teacher.first_name}",
        "subjectId": str(subject.id), "subject": subject.name,
        "affectationId": str(schedule.affectation_id) if schedule.affectation_id else None,
        "startTime": schedule.start_time.isoformat(timespec="minutes"),
        "endTime": schedule.end_time.isoformat(timespec="minutes")}


def lock_schedule(session, schedule_id):
    if not session.scalar(text("SELECT pg_try_advisory_xact_lock(hashtextextended(:key,0))"),
                          {"key": f"attendance-schedule:{schedule_id}"}):
        raise HTTPException(409, "Une opération est déjà en cours sur cette séance. Réessayez")


def tenant_year(current, session, year_id, school_id=None):
    year = session.get(m.AcademicYear, year_id)
    if not year:
        raise HTTPException(404, "Année scolaire introuvable")
    requested = school_id
    if current.role == "superadmin" and not requested:
        requested = m.public_school_id(session, year.establishment_id)
    _, tenant = m.module_tenant_scope(current, session, requested)
    if year.establishment_id != tenant:
        raise HTTPException(403, "Cette année scolaire n’appartient pas à votre établissement")
    return tenant, year


def allowed_context(current, context):
    if current.role == "admin" and context.get("directionId"):
        return current.direction_id == context["directionId"]
    cycles = m.direction_cycle_scope(current)
    return cycles is None or context.get("cycleId") in {str(c) for c in cycles}


def profile(current, session, tenant):
    teacher = session.get(m.Teacher, uuid.UUID(current.teacher_id)) if current.teacher_id else None
    user = session.get(m.User, uuid.UUID(current.id))
    if (not teacher or teacher.establishment_id != tenant or teacher.status != "active"
            or not user or user.status != "active" or user.role != "teacher"
            or user.school_id != tenant or teacher.user_id != user.id):
        raise HTTPException(403, "Cette séance ne vous est pas attribuée")
    return teacher


def roster(session, schedule, day):
    registrations = session.execute(select(m.StudentAcademicRegistration, m.Student).join(
        m.Student, m.Student.id == m.StudentAcademicRegistration.student_id).where(
        m.StudentAcademicRegistration.establishment_id == schedule.establishment_id,
        m.StudentAcademicRegistration.academic_year_id == schedule.academic_year_id,
        m.StudentAcademicRegistration.registration_date <= day,
        m.StudentAcademicRegistration.status.in_(("pending", "validated", "active")),
        m.Student.establishment_id == schedule.establishment_id, m.Student.status == "active")).all()
    transfers = session.scalars(select(m.StudentClassTransfer).where(
        m.StudentClassTransfer.establishment_id == schedule.establishment_id,
        m.StudentClassTransfer.academic_year_id == schedule.academic_year_id,
        m.StudentClassTransfer.effective_date > day).order_by(
            m.StudentClassTransfer.effective_date, m.StudentClassTransfer.created_at)).all()
    original_classes = {}
    for transfer in transfers:
        original_classes.setdefault(transfer.registration_id, transfer.from_class_id)
    return sorted([{"id": str(student.id), "fullName": f"{student.last_name} {student.first_name}"}
        for reg, student in registrations if original_classes.get(reg.id, reg.class_id) == schedule.class_id],
        key=lambda item: (item["fullName"], item["id"]))


def sheet_for(session, schedule_id, day):
    return session.scalar(select(m.AttendanceSheet).where(
        m.AttendanceSheet.schedule_entry_id == schedule_id, m.AttendanceSheet.attendance_date == day))


def session_context(current, session, schedule_id, day, class_id=None, write=False):
    schedule = session.get(m.ScheduleEntry, schedule_id)
    if not schedule:
        raise HTTPException(404, "Séance introuvable")
    tenant, year = tenant_year(current, session, schedule.academic_year_id)
    if class_id and class_id != schedule.class_id:
        raise HTTPException(403, "Cette séance ne correspond pas à la classe sélectionnée")
    sheet = sheet_for(session, schedule.id, day)
    context = sheet.context_snapshot if sheet else {**snapshot(session, schedule), **(schedule.attendance_context or {})}
    if not allowed_context(current, context):
        raise HTTPException(403, "Cette séance ne relève pas de votre direction")
    if current.role == "teacher":
        teacher = profile(current, session, tenant)
        if teacher.id != schedule.teacher_id:
            raise HTTPException(403, "Cette séance ne vous est pas attribuée")
    if not year.start_date <= day <= year.end_date:
        raise HTTPException(422, "La date est en dehors de l’année scolaire")
    if write:
        if current.role != "teacher":
            raise HTTPException(403, "L’appel est réservé à l’enseignant de la séance")
        if sheet and sheet.status == "locked":
            raise HTTPException(409, "Vous avez déjà envoyé ce relevé")
        cl = session.get(m.SchoolClass, schedule.class_id)
        subject = session.get(m.Subject, schedule.subject_id)
        assignment = session.get(m.Affectation, schedule.affectation_id) if schedule.affectation_id else None
        if (not assignment or assignment.status != "active" or assignment.establishment_id != tenant
                or assignment.teacher_id != schedule.teacher_id or assignment.class_id != schedule.class_id
                or assignment.subject_id != schedule.subject_id or not subject or subject.status != "active"
                or subject.establishment_id != tenant or cl.establishment_id != tenant
                or cl.academic_year_id != year.id or cl.status != "active" or year.status != "active"):
            raise HTTPException(403, "Votre affectation ne permet plus de remplir cette séance")
        now = now_local()
        if schedule.status != "active":
            raise HTTPException(409, "Cette séance n’est plus active")
        # Ouverture à l'heure de début, jusqu'à la fin de la date locale.
        if day > now.date():
            raise HTTPException(409, "L’appel ne peut être effectué qu’à la date prévue de la séance.")
        if day < now.date():
            raise HTTPException(409, "La période de saisie de cette présence est terminée.")
        if now.time().replace(tzinfo=None) < schedule.start_time:
            raise HTTPException(409, "L’appel sera disponible à partir de l’heure de début de la séance.")
        if day.isoweekday() != schedule.weekday:
            raise HTTPException(422, "Cette séance n’est pas prévue ce jour")
        if (schedule.attendance_context or {}).get("cycleId") != (str(cl.cycle_id) if cl.cycle_id else None):
            raise HTTPException(409, "La classe a été réorganisée. Le planning doit être actualisé")
    elif day.isoweekday() != schedule.weekday:
        raise HTTPException(422, "Cette séance n’est pas prévue ce jour")
    return schedule, sheet, context


def record_json(record, sheet):
    context = sheet.context_snapshot
    # Keep historical/demo sheets readable even if an older producer used the
    # public ``studentId`` key instead of the canonical roster ``id`` key.
    student = next((s for s in sheet.expected_students
        if (s.get("id") or s.get("studentId")) == str(record.student_id)), {})
    return {**context, "id": str(record.id), "sheetId": str(sheet.id),
        "scheduleId": str(sheet.schedule_entry_id), "academicYearId": str(sheet.academic_year_id),
        "studentId": str(record.student_id),
        "student": student.get("fullName") or student.get("student") or "Élève",
        "date": sheet.attendance_date.isoformat(), "status": record.status,
        "note": record.note, "sheetStatus": sheet.status,
        "submittedAt": sheet.submitted_at.isoformat() if sheet.submitted_at else None}


def open_sheet(current, session, schedule_id, day, class_id=None):
    schedule, sheet, context = session_context(current, session, schedule_id, day, class_id)
    if not sheet and current.role == "teacher":
        session_context(current, session, schedule_id, day, class_id, write=True)
    students = sheet.expected_students if sheet else roster(session, schedule, day)
    records = [] if not sheet else list(session.scalars(select(m.AttendanceRecord).where(
        m.AttendanceRecord.sheet_id == sheet.id).order_by(m.AttendanceRecord.student_id)))
    return {**context, "scheduleId": str(schedule.id), "date": day.isoformat(),
        "sheetStatus": sheet.status if sheet else "draft", "students": students,
        "records": [record_json(r, sheet) for r in records]}


def save(current, session, body):
    lock_schedule(session, body.schedule_entry_id)
    schedule, sheet, context = session_context(current, session, body.schedule_entry_id,
        body.attendance_date, body.class_id, write=True)
    expected_students = roster(session, schedule, body.attendance_date)
    expected = {uuid.UUID(s["id"]) for s in expected_students}
    supplied = [entry.student_id for entry in body.entries]
    if len(supplied) != len(set(supplied)):
        raise HTTPException(422, "Un élève apparaît plusieurs fois dans le relevé")
    if set(supplied) - expected:
        raise HTTPException(422, "Un élève n’appartient pas à la classe pour cette séance")
    if body.action == "submit" and (not expected or set(supplied) != expected):
        raise HTTPException(422, "Le relevé est incomplet. Renseignez tous les élèves avant de l’envoyer")
    records = [] if not sheet else list(session.scalars(select(m.AttendanceRecord).where(
        m.AttendanceRecord.sheet_id == sheet.id)))
    if {r.student_id for r in records} - expected:
        raise HTTPException(409, "La liste des élèves a changé depuis le brouillon. Contactez l’administration")
    now = now_local()
    if not sheet:
        sheet = m.AttendanceSheet(establishment_id=schedule.establishment_id,
            academic_year_id=schedule.academic_year_id, schedule_entry_id=schedule.id,
            class_id=schedule.class_id, teacher_id=schedule.teacher_id, subject_id=schedule.subject_id,
            attendance_date=body.attendance_date, context_snapshot=context, expected_students=expected_students)
        session.add(sheet)
    sheet.expected_students = expected_students
    sheet.status = "locked" if body.action == "submit" else "draft"
    sheet.submitted_at = now if body.action == "submit" else None
    sheet.updated_at = now
    try:
        session.flush()
        by_student = {r.student_id: r for r in records}
        for entry in body.entries:
            record = by_student.get(entry.student_id)
            if record is None:
                record = m.AttendanceRecord(establishment_id=schedule.establishment_id,
                    academic_year_id=schedule.academic_year_id,class_id=schedule.class_id,
                    teacher_id=schedule.teacher_id,subject_id=schedule.subject_id,
                    schedule_entry_id=schedule.id,attendance_date=body.attendance_date,
                    student_id=entry.student_id,sheet_id=sheet.id)
                session.add(record)
            record.status=entry.status
            record.note=entry.note
            record.recorded_by=uuid.UUID(current.id)
            record.updated_at=now
        session.commit()
    except IntegrityError as exc:
        session.rollback()
        raise HTTPException(409, "Ce relevé existe déjà ou la séance a changé. Actualisez la page") from exc
    return open_sheet(current, session, schedule.id, body.attendance_date, body.class_id)


def matches(context, filters):
    return all(not value or str(context.get(key)) == str(value) for key, value in filters.items())


def report(current, session, year_id, day=None, school_id=None, period_id=None,
           class_id=None, subject_id=None, teacher_id=None, schedule_id=None,
           cycle_id=None, level_id=None, student_id=None, month=None, direction_id=None):
    tenant, year = tenant_year(current, session, year_id, school_id)
    if day and not year.start_date <= day <= year.end_date:
        raise HTTPException(422, "La date est en dehors de l’année scolaire")
    if month is not None and not 1 <= month <= 12:
        raise HTTPException(422, "Mois invalide")
    start, end = year.start_date, year.end_date
    if period_id:
        period = session.get(m.AcademicPeriod, period_id)
        if not period or period.establishment_id != tenant or period.academic_year_id != year.id:
            raise HTTPException(422, "La période ne correspond pas à l’année sélectionnée")
        start, end = period.start_date or start, period.end_date or end
    if current.role == "teacher":
        teacher = profile(current, session, tenant)
        if teacher_id and teacher_id != teacher.id:
            raise HTTPException(403, "Cette consultation ne vous est pas autorisée")
        teacher_id = teacher.id
    filters = {"classId": class_id,"subjectId": subject_id,"teacherId": teacher_id,
               "cycleId":cycle_id,"levelId":level_id,"directionId":direction_id}
    sheet_query = select(m.AttendanceSheet).where(m.AttendanceSheet.establishment_id==tenant,
        m.AttendanceSheet.academic_year_id==year.id,m.AttendanceSheet.attendance_date>=start,
        m.AttendanceSheet.attendance_date<=end)
    if day: sheet_query=sheet_query.where(m.AttendanceSheet.attendance_date==day)
    sheets = [s for s in session.scalars(sheet_query) if allowed_context(current,s.context_snapshot)
        and matches(s.context_snapshot,filters) and (not schedule_id or s.schedule_entry_id==schedule_id)
        and (not month or s.attendance_date.month==month)]
    by_id={s.id:s for s in sheets}
    records=[] if not by_id else list(session.scalars(select(m.AttendanceRecord).where(
        m.AttendanceRecord.sheet_id.in_(by_id))))
    records=[r for r in records if not student_id or r.student_id==student_id]
    official=[record_json(r,by_id[r.sheet_id]) for r in records if by_id[r.sheet_id].status=="locked"]
    expected={}
    if day and start <= day <= end and (not month or day.month == month):
        cycle_names={str(c.id):c.name for c in session.scalars(select(m.SchoolCycle).where(m.SchoolCycle.establishment_id==tenant))}
        level_names={str(l.id):l.name for l in session.scalars(select(m.SchoolLevel).where(m.SchoolLevel.establishment_id==tenant))}
        directions={str(link.cycle_id):direction for link,direction in session.execute(
            select(m.SchoolDirectionCycle,m.SchoolDirection).join(m.SchoolDirection,
                m.SchoolDirection.id==m.SchoolDirectionCycle.direction_id).where(m.SchoolDirection.establishment_id==tenant))}
        active_assignments={a.id:a for a in session.scalars(select(m.Affectation).where(m.Affectation.establishment_id==tenant,m.Affectation.status=='active'))}
        active_teachers=set(session.scalars(select(m.Teacher.id).join(m.User,m.User.id==m.Teacher.user_id).where(
            m.Teacher.establishment_id==tenant,m.Teacher.status=='active',m.User.school_id==tenant,
            m.User.status=='active',m.User.role=='teacher')))
        active_classes=set(session.scalars(select(m.SchoolClass.id).where(
            m.SchoolClass.establishment_id==tenant,m.SchoolClass.academic_year_id==year.id,m.SchoolClass.status=='active')))
        active_subjects=set(session.scalars(select(m.Subject.id).where(
            m.Subject.establishment_id==tenant,m.Subject.status=='active')))
        schedules=session.scalars(select(m.ScheduleEntry).where(m.ScheduleEntry.establishment_id==tenant,
            m.ScheduleEntry.academic_year_id==year.id,m.ScheduleEntry.weekday==day.isoweekday())).all()
        # Recurrence applies only while this planning version existed. Past
        # expectations are not regenerated from the current active planning alone.
        for schedule in schedules:
            context=dict(schedule.attendance_context or {})
            context.setdefault('cycle',cycle_names.get(context.get('cycleId'),''))
            context.setdefault('level',level_names.get(context.get('levelId'),''))
            direction=directions.get(context.get('cycleId'))
            if 'directionId' not in context and direction:
                context.update(directionId=str(direction.id),direction=direction.name)
            if day >= now_local().date():
                assignment=active_assignments.get(schedule.affectation_id)
                if (year.status!='active' or schedule.class_id not in active_classes
                        or schedule.subject_id not in active_subjects or schedule.teacher_id not in active_teachers or not assignment
                        or assignment.teacher_id!=schedule.teacher_id or assignment.class_id!=schedule.class_id
                        or assignment.subject_id!=schedule.subject_id): continue
            slot_start=datetime.combine(day,schedule.start_time,tzinfo=now_local().tzinfo)
            created=schedule.created_at
            if created.tzinfo is None: created=created.replace(tzinfo=timezone.utc)
            retired=schedule.retired_at
            if retired and retired.tzinfo is None: retired=retired.replace(tzinfo=timezone.utc)
            if created>slot_start or (retired and retired<=slot_start): continue
            if not allowed_context(current,context) or not matches(context,filters): continue
            if schedule_id and schedule.id!=schedule_id: continue
            expected[schedule.id]={**context,"scheduleId":str(schedule.id),"date":day.isoformat(),"status":"pending"}
    for sheet in sheets:
        if day:
            expected[sheet.schedule_entry_id]={**sheet.context_snapshot,"scheduleId":str(sheet.schedule_entry_id),
                "date":sheet.attendance_date.isoformat(),"status":"submitted" if sheet.status=="locked" else "draft"}
    rows=list(expected.values())
    received=sum(r["status"]=="submitted" for r in rows)
    teacher_groups={}
    for row in rows:
        group=teacher_groups.setdefault(row["teacherId"],{"teacherId":row["teacherId"],"teacher":row["teacher"],
            "expectedCount":0,"receivedCount":0})
        group["expectedCount"]+=1;group["receivedCount"]+=int(row["status"]=="submitted")
    counts={status:sum(r["status"]==status for r in official) for status in ("present","absent","justified")}
    return {"sessions":rows,"teacherSubmissions":list(teacher_groups.values()),"expectedCount":len(rows),
        "receivedCount":received,"missingCount":len(rows)-received,"allReceived":bool(rows) and received==len(rows),
        "records":sorted(official,key=lambda r:(r["date"],r["class"],r["student"])),
        "statistics":{**counts,"total":len(official),"attendanceRate":round(100*counts["present"]/len(official),2) if official else None}}


def contexts(current, session):
    statement=select(m.AcademicYear,m.Establishment.name).join(m.Establishment,
        m.Establishment.id==m.AcademicYear.establishment_id)
    if current.role!="superadmin":
        _,tenant=m.module_tenant_scope(current,session)
        statement=statement.where(m.AcademicYear.establishment_id==tenant)
    years=list(session.execute(statement))
    periods=list(session.scalars(select(m.AcademicPeriod).where(
        m.AcademicPeriod.academic_year_id.in_([year.id for year,school in years]))))
    return [{"academicYearId":str(year.id),"year":year.name,"school":school,
        "periods":[{"periodId":str(p.id),"period":p.name} for p in periods if p.academic_year_id==year.id],
        "schoolId":str(year.establishment_id),"startDate":year.start_date.isoformat(),
        "endDate":year.end_date.isoformat()} for year,school in years]

"""Create permanent, idempotent presentation data for non-Lycee cycles.

This command is deliberately explicit: importing or starting FastAPI never runs
it.  Existing records are reused, nothing is deleted, and every lookup is scoped
to Le cogito's active academic year.
"""
from __future__ import annotations

import uuid
from datetime import date, datetime, time, timezone

from sqlalchemy import select
from sqlalchemy.orm import Session

from app import behavior
from app.main import (
    AcademicPeriod,
    AcademicYear,
    Affectation,
    AttendanceRecord,
    AttendanceSheet,
    Evaluation,
    EvaluationStatusEvent,
    Grade,
    Principal,
    Resource,
    ScheduleEntry,
    SchoolClass,
    SchoolCycle,
    SchoolDirection,
    SchoolDirectionCycle,
    SchoolLevel,
    Student,
    StudentAcademicRegistration,
    Subject,
    SubjectLevelSetting,
    Teacher,
    User,
    calculate_school_results,
    engine,
    passwords,
    public_school_id,
    school_results,
)


YEAR_NAME = "2027-2028"
DEMO_PASSWORD = "Demo2027!Teacher"

CYCLE_SPECS = [
    {
        "cycle_code": "MATERNELLE",
        "direction_code": "MATERNELLE_PRIMAIRE",
        "level_code": "GS",
        "level_name": "Grande Section",
        "class_name": "Grande Section A",
        "scale": 10.0,
        "subjects": [
            ("Langage et communication", "MAT-LANG"),
            ("Premiers outils mathématiques", "MAT-MATH"),
            ("Explorer le monde", "MAT-MOND"),
            ("Activités artistiques", "MAT-ART"),
            ("Activité physique", "MAT-EPS"),
        ],
        "teachers": [
            ("MAVOUNGOU", "Alice", "alice.mavoungou.demo@lecogito.school"),
            ("NGOMA", "Brice", "brice.ngoma.demo@lecogito.school"),
        ],
        "students": [
            ("BISSILA", "Léa"), ("MBOUNGOU", "Noah"),
            ("MALONGA", "Inès"), ("KIMBEMBE", "Aaron"),
            ("MOUKOKO", "Emma"), ("BANZOUZI", "Maël"),
            ("LOUBAKI", "Sarah"), ("ONDONGO", "Liam"),
        ],
        "evaluations": (("Composition", "composition"),),
    },
    {
        "cycle_code": "PRIMAIRE",
        "direction_code": "MATERNELLE_PRIMAIRE",
        "level_code": "CM2",
        "level_name": "CM2",
        "class_name": "CM2 A",
        "scale": 10.0,
        "subjects": [
            ("Français", "FRA"), ("Mathématiques", "MAT"),
            ("Sciences", "SCI"), ("Histoire-Géographie", "HGE"),
            ("Éducation civique", "ECM"), ("Anglais", "ANG"),
            ("EPS", "EPS"),
        ],
        "teachers": [
            ("MASSAMBA", "Nadia", "nadia.massamba.demo@lecogito.school"),
            ("OKO", "Patrick", "patrick.oko.demo@lecogito.school"),
            ("MBOUSSI", "Clarisse", "clarisse.mboussi.demo@lecogito.school"),
        ],
        "students": [
            ("MAYIMA", "Junior"), ("NSONA", "Grâce"),
            ("BOUKA", "Daniel"), ("KOUKA", "Aïcha"),
            ("MABIALA", "Ethan"), ("MOUANDA", "Esther"),
            ("NGOLO", "Samuel"), ("TSIBA", "Naomie"),
        ],
        "evaluations": (("Composition", "composition"),),
    },
    {
        "cycle_code": "COLLEGE",
        "direction_code": "COLLEGE",
        "level_code": "3E",
        "level_name": "Troisième",
        "class_name": "3e A",
        "scale": 20.0,
        "subjects": [
            ("Français", "FRA"), ("Mathématiques", "MAT"),
            ("Physique-Chimie", "PCH"), ("SVT", "SVT"),
            ("Histoire-Géographie", "HGE"), ("Anglais", "ANG"),
            ("Éducation civique", "ECM"), ("EPS", "EPS"),
        ],
        "teachers": [
            ("MOUYABI", "Cédric", "cedric.mouyabi.demo@lecogito.school"),
            ("NKAYA", "Sonia", "sonia.nkaya.demo@lecogito.school"),
            ("BAKALA", "Thierry", "thierry.bakala.demo@lecogito.school"),
        ],
        "students": [
            ("MILONDO", "Chris"), ("MOUKASSA", "Diane"),
            ("KIBANGOU", "Prince"), ("MABOUNDA", "Ruth"),
            ("TATI", "Elie"), ("MPEMBA", "Divine"),
            ("BOUITY", "Jordan"), ("NDEKO", "Rachelle"),
        ],
        "evaluations": (
            ("Devoir 1", "devoir"),
            ("Devoir 2", "devoir"),
            ("Composition", "composition"),
        ),
    },
]


def one(session: Session, model, *criteria):
    return session.scalar(select(model).where(*criteria))


def ensure_periods(session: Session, establishment_id: uuid.UUID, year: AcademicYear):
    # This presentation year follows the requested October -> June calendar.
    year.start_date = date(2027, 10, 1)
    year.end_date = date(2028, 6, 30)
    period_specs = [
        ("T1", "1er trimestre", 10, date(2027, 10, 1), date(2027, 12, 31)),
        ("T2", "2e trimestre", 20, date(2028, 1, 1), date(2028, 3, 31)),
        ("T3", "3e trimestre", 30, date(2028, 4, 1), date(2028, 6, 30)),
    ]
    periods = []
    for code, name, order, start, end in period_specs:
        period = one(
            session,
            AcademicPeriod,
            AcademicPeriod.establishment_id == establishment_id,
            AcademicPeriod.academic_year_id == year.id,
            AcademicPeriod.period_type == "trimester",
            AcademicPeriod.code == code,
        )
        if period is None:
            period = AcademicPeriod(
                establishment_id=establishment_id,
                academic_year_id=year.id,
                code=code,
                name=name,
                period_type="trimester",
                sort_order=order,
                start_date=start,
                end_date=end,
                status="active",
            )
            session.add(period)
            session.flush()
        else:
            period.name = name
            period.sort_order = order
            period.start_date = start
            period.end_date = end
            period.status = "active"
        periods.append(period)
    return periods


def ensure_teacher(
    session: Session,
    establishment_id: uuid.UUID,
    direction: SchoolDirection,
    last_name: str,
    first_name: str,
    email: str,
) -> Teacher:
    user = one(session, User, User.email == email)
    if user is None:
        user = User(
            email=email,
            password_hash=passwords.hash(DEMO_PASSWORD),
            name=f"{first_name} {last_name}",
            role="teacher",
            school_id=establishment_id,
            direction_id=direction.id,
            status="active",
            password_set=True,
        )
        session.add(user)
        session.flush()
    teacher = one(
        session,
        Teacher,
        Teacher.establishment_id == establishment_id,
        Teacher.email == email,
    )
    if teacher is None:
        teacher = Teacher(
            establishment_id=establishment_id,
            created_direction_id=direction.id,
            user_id=user.id,
            first_name=first_name,
            last_name=last_name,
            employee_number=f"DEMO-{direction.code[:3]}-{email.split('@')[0].upper()}",
            specialization="Données permanentes de présentation",
            email=email,
            status="active",
        )
        session.add(teacher)
        session.flush()
    else:
        teacher.user_id = user.id
        teacher.created_direction_id = direction.id
        teacher.status = "active"
    return teacher


def ensure_student(
    session: Session,
    establishment_id: uuid.UUID,
    direction_id: uuid.UUID,
    school_class: SchoolClass,
    year: AcademicYear,
    cycle_code: str,
    index: int,
    last_name: str,
    first_name: str,
) -> Student:
    number = f"DEMO-{cycle_code[:3]}-{index:02d}"
    student = one(
        session,
        Student,
        Student.establishment_id == establishment_id,
        Student.registration_number == number,
    )
    if student is None:
        student = Student(
            establishment_id=establishment_id,
            created_direction_id=direction_id,
            first_name=first_name,
            last_name=last_name,
            registration_number=number,
            birth_date=date(2016 if cycle_code == "MATERNELLE" else 2012 if cycle_code == "PRIMAIRE" else 2009, 1 + index, 2 + index),
            nationality="Congolaise",
            gender="F" if index % 2 else "M",
            status="active",
        )
        session.add(student)
        session.flush()
    registration = one(
        session,
        StudentAcademicRegistration,
        StudentAcademicRegistration.establishment_id == establishment_id,
        StudentAcademicRegistration.student_id == student.id,
        StudentAcademicRegistration.academic_year_id == year.id,
    )
    if registration is None:
        registration = StudentAcademicRegistration(
            establishment_id=establishment_id,
            student_id=student.id,
            class_id=school_class.id,
            academic_year_id=year.id,
            registration_date=year.start_date,
            registration_number=number,
            school_regime="normal",
            has_td=False,
            options={"demoDataset": "multicycle-permanent"},
            status="validated",
        )
        session.add(registration)
    return student


def principal_for(
    session: Session,
    direction: SchoolDirection,
    cycle_ids: list[uuid.UUID],
) -> Principal:
    admin = one(
        session,
        User,
        User.school_id == direction.establishment_id,
        User.direction_id == direction.id,
        User.role == "admin",
        User.status == "active",
    )
    if admin is None:
        raise RuntimeError(f"Aucun administrateur actif pour {direction.name}")
    return Principal(
        id=str(admin.id),
        role="admin",
        school_id=public_school_id(session, direction.establishment_id),
        direction_id=str(direction.id),
        direction_name=direction.name,
        direction_cycle_ids=[str(item) for item in cycle_ids],
    )


def ensure_cycle_dataset(
    session: Session,
    establishment_id: uuid.UUID,
    year: AcademicYear,
    t1: AcademicPeriod,
    spec: dict,
) -> dict:
    cycle = one(session, SchoolCycle, SchoolCycle.establishment_id == establishment_id,
                SchoolCycle.code == spec["cycle_code"])
    direction = one(session, SchoolDirection,
                    SchoolDirection.establishment_id == establishment_id,
                    SchoolDirection.code == spec["direction_code"])
    if cycle is None or direction is None:
        raise RuntimeError(f"Cycle/direction introuvable: {spec['cycle_code']}")
    if one(session, SchoolDirectionCycle,
           SchoolDirectionCycle.direction_id == direction.id,
           SchoolDirectionCycle.cycle_id == cycle.id) is None:
        session.add(SchoolDirectionCycle(
            establishment_id=establishment_id,
            direction_id=direction.id,
            cycle_id=cycle.id,
        ))

    level = one(session, SchoolLevel, SchoolLevel.establishment_id == establishment_id,
                SchoolLevel.cycle_id == cycle.id, SchoolLevel.code == spec["level_code"])
    if level is None:
        level = SchoolLevel(
            establishment_id=establishment_id,
            cycle_id=cycle.id,
            code=spec["level_code"],
            name=spec["level_name"],
            status="active",
            sort_order=10,
        )
        session.add(level)
        session.flush()

    school_class = one(session, SchoolClass,
        SchoolClass.establishment_id == establishment_id,
        SchoolClass.academic_year_id == year.id,
        SchoolClass.name == spec["class_name"])
    if school_class is None:
        school_class = SchoolClass(
            establishment_id=establishment_id,
            academic_year_id=year.id,
            name=spec["class_name"],
            level=spec["level_name"],
            capacity=30,
            cycle_id=cycle.id,
            school_level_id=level.id,
            status="active",
        )
        session.add(school_class)
        session.flush()

    teachers = [ensure_teacher(session, establishment_id, direction, *row)
                for row in spec["teachers"]]
    subjects = []
    affectations = []
    for index, (name, code) in enumerate(spec["subjects"]):
        subject = one(session, Subject, Subject.establishment_id == establishment_id,
                      Subject.name == name)
        if subject is None:
            subject = Subject(establishment_id=establishment_id, name=name,
                              code=code, status="active")
            session.add(subject)
            session.flush()
        subjects.append(subject)
        setting = one(session, SubjectLevelSetting,
            SubjectLevelSetting.establishment_id == establishment_id,
            SubjectLevelSetting.subject_id == subject.id,
            SubjectLevelSetting.school_level_id == level.id,
            SubjectLevelSetting.academic_year_id == year.id,
            SubjectLevelSetting.series_id.is_(None))
        if setting is None:
            setting = SubjectLevelSetting(
                establishment_id=establishment_id,
                subject_id=subject.id,
                school_level_id=level.id,
                academic_year_id=year.id,
                series_id=None,
            )
            session.add(setting)
        # Non-Lycee cycles deliberately have no coefficient. The official
        # result engine gives every enabled subject an equal weight of 1.
        setting.coefficient = None
        setting.grading_scale = spec["scale"]
        setting.contributes_to_average = True
        setting.status = "active"
        teacher = teachers[index % len(teachers)]
        affectation = one(session, Affectation,
            Affectation.establishment_id == establishment_id,
            Affectation.class_id == school_class.id,
            Affectation.subject_id == subject.id,
            Affectation.status == "active")
        if affectation is None:
            affectation = Affectation(
                establishment_id=establishment_id,
                teacher_id=teacher.id,
                class_id=school_class.id,
                subject_id=subject.id,
                status="active",
            )
            session.add(affectation)
            session.flush()
        affectations.append(affectation)

    students = [ensure_student(session, establishment_id, direction.id,
        school_class, year, spec["cycle_code"], index, *row)
        for index, row in enumerate(spec["students"], 1)]
    session.flush()

    now = datetime.now(timezone.utc)
    for subject_index, (subject, affectation) in enumerate(zip(subjects, affectations)):
        assigned_teacher = session.get(Teacher, affectation.teacher_id)
        if assigned_teacher is None or assigned_teacher.user_id is None:
            raise RuntimeError(f"Enseignant incomplet pour {subject.name}")
        for evaluation_index, (name, evaluation_type) in enumerate(spec["evaluations"]):
            evaluation = one(session, Evaluation,
                Evaluation.establishment_id == establishment_id,
                Evaluation.class_id == school_class.id,
                Evaluation.subject_id == subject.id,
                Evaluation.academic_period_id == t1.id,
                Evaluation.name == name)
            if evaluation is None:
                evaluation = Evaluation(
                    establishment_id=establishment_id,
                    class_id=school_class.id,
                    subject_id=subject.id,
                    name=name,
                    type=evaluation_type,
                    period=t1.name,
                    date_scheduled=date(2027, 10 + min(evaluation_index, 2), 12),
                    max_value=spec["scale"],
                    status="validated",
                    description=("Évaluation de compétences sur 10, "
                                 "restituée en appréciations."
                                 if spec["cycle_code"] == "MATERNELLE" else
                                 "Donnée permanente de présentation"),
                    academic_year_id=year.id,
                    academic_period_id=t1.id,
                    affectation_id=affectation.id,
                    created_by=assigned_teacher.user_id,
                    submitted_at=now,
                    validated_at=now,
                    validated_by=assigned_teacher.user_id,
                )
                session.add(evaluation)
                session.flush()
                session.add(EvaluationStatusEvent(
                    establishment_id=establishment_id,
                    evaluation_id=evaluation.id,
                    actor_user_id=assigned_teacher.user_id,
                    from_status="draft",
                    to_status="validated",
                    reason="Jeu permanent de présentation",
                ))
            elif float(evaluation.max_value) != float(spec["scale"]):
                # Preserve the existing sheet and its pedagogical ratio while
                # aligning the configured cycle scale in place.
                evaluation.max_value = spec["scale"]
                if spec["cycle_code"] == "MATERNELLE":
                    evaluation.description = (
                        "Évaluation de compétences sur 10, restituée en appréciations."
                    )
            for student_index, student in enumerate(students):
                grade = one(session, Grade,
                    Grade.establishment_id == establishment_id,
                    Grade.student_id == student.id,
                    Grade.evaluation_id == evaluation.id)
                ratio = 0.88 - student_index * 0.045 + subject_index * 0.006 + evaluation_index * 0.01
                value = round(max(0.35, min(0.98, ratio)) * spec["scale"], 2)
                if spec["cycle_code"] == "MATERNELLE":
                    value = round(max(1.0, min(10.0, value)), 2)
                comment = ("Très bonne maîtrise" if ratio >= .8 else
                           "Maîtrise satisfaisante" if ratio >= .65 else
                           "Compétence à consolider")
                if grade is None:
                    grade = Grade(
                        establishment_id=establishment_id,
                        student_id=student.id,
                        evaluation_id=evaluation.id,
                        class_id=school_class.id,
                        subject_id=subject.id,
                        teacher_id=affectation.teacher_id,
                        affectation_id=affectation.id,
                        value=value,
                        max_value=spec["scale"],
                        presence="present",
                        entered_by=assigned_teacher.user_id,
                        comment=comment,
                        status="validated",
                    )
                    session.add(grade)
                elif float(grade.max_value) != float(spec["scale"]):
                    old_scale = float(grade.max_value)
                    if grade.value is not None and old_scale > 0:
                        grade.value = round(
                            float(grade.value) * float(spec["scale"]) / old_scale,
                            2,
                        )
                    grade.max_value = spec["scale"]

    schedule_rows = []
    for index, (subject, affectation) in enumerate(zip(subjects, affectations)):
        schedule_teacher = session.get(Teacher, affectation.teacher_id)
        if schedule_teacher is None or schedule_teacher.user_id is None:
            raise RuntimeError(f"Compte enseignant incomplet pour {subject.name}")
        weekday = 1 + (index % 5)
        start = time(8 + (index // 5) * 2, 0)
        end = time(start.hour + 1, 0)
        schedule = one(session, ScheduleEntry,
            ScheduleEntry.establishment_id == establishment_id,
            ScheduleEntry.academic_year_id == year.id,
            ScheduleEntry.class_id == school_class.id,
            ScheduleEntry.subject_id == subject.id,
            ScheduleEntry.weekday == weekday,
            ScheduleEntry.start_time == start)
        context = {
            "cycleId": str(cycle.id), "cycle": cycle.name,
            "levelId": str(level.id), "level": level.name,
            "directionId": str(direction.id), "direction": direction.name,
            "classId": str(school_class.id), "class": school_class.name,
            "subjectId": str(subject.id), "subject": subject.name,
            "teacherId": str(affectation.teacher_id),
        }
        if schedule is None:
            schedule = ScheduleEntry(
                establishment_id=establishment_id,
                academic_year_id=year.id,
                class_id=school_class.id,
                subject_id=subject.id,
                teacher_id=affectation.teacher_id,
                affectation_id=affectation.id,
                weekday=weekday,
                start_time=start,
                end_time=end,
                room=school_class.name,
                status="active",
                attendance_context=context,
                created_by=schedule_teacher.user_id,
            )
            session.add(schedule)
            session.flush()
        schedule_rows.append(schedule)

    # One official attendance sheet, attached to a real Friday schedule.
    attendance_schedule = schedule_rows[4] if len(schedule_rows) > 4 else schedule_rows[0]
    attendance_teacher = session.get(Teacher, attendance_schedule.teacher_id)
    if attendance_teacher is None or attendance_teacher.user_id is None:
        raise RuntimeError("Enseignant d'appel incomplet")
    attendance_day = date(2027, 10, 1) if attendance_schedule.weekday == 5 else date(2027, 10, 4)
    sheet = one(session, AttendanceSheet,
        AttendanceSheet.establishment_id == establishment_id,
        AttendanceSheet.schedule_entry_id == attendance_schedule.id,
        AttendanceSheet.attendance_date == attendance_day)
    expected = [{"id": str(student.id),
                 "fullName": f"{student.last_name} {student.first_name}"}
                for student in students]
    if sheet is None:
        sheet = AttendanceSheet(
            establishment_id=establishment_id,
            academic_year_id=year.id,
            schedule_entry_id=attendance_schedule.id,
            class_id=school_class.id,
            teacher_id=attendance_schedule.teacher_id,
            subject_id=attendance_schedule.subject_id,
            attendance_date=attendance_day,
            status="locked",
            context_snapshot=dict(attendance_schedule.attendance_context or {}),
            expected_students=expected,
            submitted_at=now,
        )
        session.add(sheet)
        session.flush()
    else:
        # Normalize rows created by an older version of this explicit seed.
        sheet.context_snapshot = dict(attendance_schedule.attendance_context or {})
        sheet.expected_students = expected
    for index, student in enumerate(students):
        record = one(session, AttendanceRecord,
            AttendanceRecord.establishment_id == establishment_id,
            AttendanceRecord.sheet_id == sheet.id,
            AttendanceRecord.student_id == student.id)
        if record is None:
            session.add(AttendanceRecord(
                establishment_id=establishment_id,
                student_id=student.id,
                class_id=school_class.id,
                academic_year_id=year.id,
                schedule_entry_id=attendance_schedule.id,
                teacher_id=attendance_schedule.teacher_id,
                subject_id=attendance_schedule.subject_id,
                attendance_date=attendance_day,
                status="absent" if index == len(students) - 1 else "present",
                note="Absence de démonstration" if index == len(students) - 1 else None,
                sheet_id=sheet.id,
                recorded_by=attendance_teacher.user_id,
            ))
    session.commit()

    # Every assigned teacher contributes a complete locked behavior sheet.
    for teacher_index, teacher in enumerate(teachers):
        for student_index, student in enumerate(students):
            event = one(session, behavior.m.BehaviorEvent,
                behavior.m.BehaviorEvent.establishment_id == establishment_id,
                behavior.m.BehaviorEvent.class_id == school_class.id,
                behavior.m.BehaviorEvent.academic_period_id == t1.id,
                behavior.m.BehaviorEvent.teacher_id == teacher.id,
                behavior.m.BehaviorEvent.student_id == student.id)
            stars = max(2, min(5, 5 - student_index // 3 + teacher_index % 2))
            if event is None:
                session.add(behavior.m.BehaviorEvent(
                    establishment_id=establishment_id,
                    student_id=student.id,
                    class_id=school_class.id,
                    academic_year_id=year.id,
                    academic_period_id=t1.id,
                    event_date=t1.start_date,
                    category=f"stars:{stars}",
                    event_type="positive" if stars >= 3 else "negative",
                    severity="normal",
                    title=f"{stars} étoiles",
                    description="Participation et attitude en classe",
                    recorded_by=teacher.user_id,
                    teacher_id=teacher.id,
                    status="locked",
                ))
    session.commit()

    direction_cycles = list(session.scalars(select(SchoolDirectionCycle.cycle_id).where(
        SchoolDirectionCycle.direction_id == direction.id)))
    principal = principal_for(session, direction, direction_cycles)
    behavior_result = behavior.calculate(principal, session, school_class.id, t1.id)
    result = calculate_school_results(school_class.id, t1.id, principal, session)
    persisted = school_results(school_class.id, t1.id, principal, session)

    for student in students:
        document_id = f"DEMO-BULLETIN-{school_class.id.hex[:8]}-{student.id.hex[:8]}"
        key = {"kind": "documents", "id": document_id}
        payload = {
            "id": document_id,
            "title": f"Bulletin {t1.name} - {student.last_name} {student.first_name}",
            "type": "official_results",
            "entityId": str(school_class.id),
            "academicYearId": str(year.id),
            "metadata": {
                "documentKind": "bulletin",
                "studentId": str(student.id),
                "periodId": str(t1.id),
                "resultStatus": "official",
                "calculatedAt": persisted.get("calculatedAt"),
                "colorTheme": "auto",
            },
            "date": datetime.combine(t1.end_date, time(12), tzinfo=timezone.utc).isoformat(),
            "createdBy": principal.id,
            "status": "generated",
            "schoolId": principal.school_id,
        }
        document = session.get(Resource, key)
        if document is None:
            session.add(Resource(
                id=document_id,
                kind="documents",
                school_id=principal.school_id,
                establishment_id=establishment_id,
                cycle_id=cycle.id,
                school_level_id=level.id,
                academic_year_id=year.id,
                payload=payload,
            ))
        else:
            # Recalculation refreshes calculatedAt even when the source values
            # are identical. Keep the permanent document tied to that official
            # snapshot instead of letting an idempotent rerun mark it stale.
            document.payload = payload
    session.commit()
    return {
        "cycle": cycle.name,
        "direction": direction.name,
        "class": school_class.name,
        "students": len(students),
        "teachers": len(teachers),
        "subjects": len(subjects),
        "affectations": len(affectations),
        "schedule": len(schedule_rows),
        "evaluations": result["evaluationCount"],
        "results": len(persisted["students"]),
        "result_status": persisted["calculationStatus"],
        "behavior": len(behavior_result["students"]),
    }


def main() -> None:
    with Session(engine) as session:
        year = one(session, AcademicYear, AcademicYear.name == YEAR_NAME,
                   AcademicYear.is_active.is_(True))
        if year is None:
            raise RuntimeError(f"Année active {YEAR_NAME} introuvable")
        establishment_id = year.establishment_id
        periods = ensure_periods(session, establishment_id, year)
        session.commit()
        results = [ensure_cycle_dataset(session, establishment_id, year, periods[0], spec)
                   for spec in CYCLE_SPECS]
        print(f"establishment={establishment_id}")
        print(f"year={year.name}:{year.start_date}:{year.end_date}")
        print("periods=" + ",".join(period.code for period in periods))
        for row in results:
            print(" | ".join(f"{key}={value}" for key, value in row.items()))


if __name__ == "__main__":
    main()

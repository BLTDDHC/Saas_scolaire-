"""Create or complete the permanent Terminale C2 presentation dataset.

The script is deliberately idempotent and scoped to the existing active
Terminale C2 managed by the Lycée direction. It never creates admin accounts,
deletes records, or touches another class.
"""
from __future__ import annotations

import uuid
from datetime import date, datetime, time, timezone

from sqlalchemy import select
from sqlalchemy.orm import Session

from app import behavior
from app.main import (
    AcademicPeriod, AcademicYear, Affectation, Evaluation, EvaluationStatusEvent,
    Grade, Principal, ResultCalculation, ScheduleEntry, SchoolClass, SchoolCycle,
    SchoolDirection, SchoolLevel, SchoolSeries, Student, StudentAcademicRegistration,
    Subject, SubjectLevelSetting, Teacher, User, calculate_school_results, engine,
    public_school_id, school_results,
)


SUBJECTS = [
    ("Français", "FRA", 3),
    ("Philosophie", "PHI", 3),
    ("Histoire-Géographie", "HGE", 3),
    ("Anglais", "ANG", 3),
    ("Mathématiques", "MAT", 5),
    ("Physique-Chimie", "PCH", 5),
    ("SVT", "SVT", 4),
    ("EPS", "EPS", 2),
]

STUDENTS = [
    ("BOUAKO", "Leader"),
    ("MBONGA", "Evan"),
    ("KIM", "Marlène"),
    ("MADO", "Grâce"),
    ("OKO", "Éric"),
    ("NZINGA", "Paul"),
    ("MOUKALA", "Aïcha"),
    ("MAKOSSO", "Junior"),
]

PROFILE_BASE = [17.1, 15.3, 13.9, 12.8, 11.7, 10.4, 9.1, 7.8]


def one(session, model, *criteria):
    return session.scalar(select(model).where(*criteria))


def main() -> None:
    with Session(engine) as session:
        admin = one(session, User, User.email == "try@gmail.com", User.role == "admin")
        if not admin or not admin.school_id or not admin.direction_id:
            raise RuntimeError("Le compte BOUAKO try lié à une direction Lycée est introuvable")
        direction = session.get(SchoolDirection, admin.direction_id)
        if not direction or direction.code != "LYCEE":
            raise RuntimeError("BOUAKO try n'est pas rattaché à la Direction Lycée")
        year = one(session, AcademicYear,
                   AcademicYear.establishment_id == admin.school_id,
                   AcademicYear.is_active.is_(True))
        if not year:
            raise RuntimeError("Aucune année scolaire active")
        school_class = one(session, SchoolClass,
                           SchoolClass.establishment_id == admin.school_id,
                           SchoolClass.academic_year_id == year.id,
                           SchoolClass.name == "Terminale C2")
        if not school_class:
            raise RuntimeError("Terminale C2 n'existe pas dans l'année active")
        cycle = session.get(SchoolCycle, school_class.cycle_id)
        series = session.get(SchoolSeries, school_class.series_id)
        level = session.get(SchoolLevel, school_class.school_level_id)
        if not cycle or cycle.code != "LYCEE" or not series or series.code != "C" or not level:
            raise RuntimeError("Terminale C2 n'est pas correctement liée à Lycée / Série C")

        periods = []
        period_specs = [
            ("T1", "1er trimestre", 10, date(2027, 10, 1), date(2027, 12, 31)),
            ("T2", "2e trimestre", 20, date(2028, 1, 1), date(2028, 3, 31)),
            ("T3", "3e trimestre", 30, date(2028, 4, 1), date(2028, 6, 30)),
        ]
        for code, name, order, start, end in period_specs:
            period = one(session, AcademicPeriod,
                         AcademicPeriod.establishment_id == admin.school_id,
                         AcademicPeriod.academic_year_id == year.id,
                         AcademicPeriod.period_type == "trimester",
                         AcademicPeriod.code == code)
            if period is None:
                period = AcademicPeriod(establishment_id=admin.school_id,
                    academic_year_id=year.id, code=code, name=name,
                    period_type="trimester", sort_order=order,
                    start_date=start, end_date=end, status="active")
                session.add(period)
                session.flush()
            periods.append(period)
        t1 = periods[0]

        subject_by_name = {}
        for name, code, coefficient in SUBJECTS:
            subject = one(session, Subject,
                          Subject.establishment_id == admin.school_id,
                          Subject.name == name)
            if subject is None:
                subject = Subject(establishment_id=admin.school_id, name=name,
                                  code=code, status="active")
                session.add(subject)
                session.flush()
            subject_by_name[name] = subject
            setting = one(session, SubjectLevelSetting,
                          SubjectLevelSetting.establishment_id == admin.school_id,
                          SubjectLevelSetting.subject_id == subject.id,
                          SubjectLevelSetting.school_level_id == level.id,
                          SubjectLevelSetting.series_id == series.id,
                          SubjectLevelSetting.academic_year_id == year.id)
            if setting is None:
                setting = SubjectLevelSetting(establishment_id=admin.school_id,
                    subject_id=subject.id, school_level_id=level.id,
                    academic_year_id=year.id, series_id=series.id,
                    coefficient=coefficient, grading_scale=20,
                    contributes_to_average=True, status="active")
                session.add(setting)
            else:
                setting.coefficient = coefficient
                setting.grading_scale = 20
                setting.contributes_to_average = True
                setting.status = "active"

        teachers = list(session.scalars(select(Teacher).where(
            Teacher.establishment_id == admin.school_id,
            Teacher.created_direction_id == direction.id,
            Teacher.status == "active",
            Teacher.user_id.is_not(None)).order_by(Teacher.last_name)))
        if len(teachers) < 3:
            raise RuntimeError("Au moins trois enseignants Lycée liés à des comptes sont requis")
        teacher_for = {
            "Français": teachers[1], "Philosophie": teachers[1],
            "Anglais": teachers[1], "Mathématiques": teachers[2],
            "EPS": teachers[2], "Physique-Chimie": teachers[0],
            "Histoire-Géographie": teachers[0], "SVT": teachers[0],
        }
        affectation_by_subject = {}
        for name, _, _ in SUBJECTS:
            subject = subject_by_name[name]
            teacher = teacher_for[name]
            affectation = one(session, Affectation,
                              Affectation.establishment_id == admin.school_id,
                              Affectation.class_id == school_class.id,
                              Affectation.subject_id == subject.id,
                              Affectation.status == "active")
            if affectation is None:
                affectation = Affectation(establishment_id=admin.school_id,
                    teacher_id=teacher.id, class_id=school_class.id,
                    subject_id=subject.id, status="active")
                session.add(affectation)
                session.flush()
            affectation_by_subject[name] = affectation

        student_rows = []
        existing_regs = list(session.scalars(select(StudentAcademicRegistration).where(
            StudentAcademicRegistration.establishment_id == admin.school_id,
            StudentAcademicRegistration.class_id == school_class.id,
            StudentAcademicRegistration.academic_year_id == year.id,
            StudentAcademicRegistration.status.in_(("pending", "validated", "active")))))
        regs_by_name = {}
        for registration in existing_regs:
            student = session.get(Student, registration.student_id)
            if student:
                regs_by_name[(student.last_name.upper(), student.first_name.lower())] = (student, registration)
        for index, (last_name, first_name) in enumerate(STUDENTS, 1):
            pair = regs_by_name.get((last_name.upper(), first_name.lower()))
            if pair:
                student, registration = pair
            else:
                student = Student(establishment_id=admin.school_id,
                    created_direction_id=direction.id, last_name=last_name,
                    first_name=first_name, registration_number=f"DEMO-C2-{index:02d}",
                    nationality="Congolaise", status="active")
                session.add(student)
                session.flush()
                registration = StudentAcademicRegistration(
                    establishment_id=admin.school_id, student_id=student.id,
                    class_id=school_class.id, academic_year_id=year.id,
                    registration_date=year.start_date,
                    registration_number=f"DEMO-C2-{index:02d}",
                    school_regime="normal", has_td=False,
                    options={"demoDataset": "terminale-c2"}, status="validated")
                session.add(registration)
            student_rows.append(student)
        if len(student_rows) != 8:
            raise RuntimeError("Le jeu de démonstration doit contenir exactement huit élèves")

        session.flush()
        now = datetime.now(timezone.utc)
        evaluation_offsets = {"Devoir 1": -0.4, "Devoir 2": 0.4, "Composition": 0.0}
        subject_offsets = {name: (index % 4 - 1.5) * 0.25 for index, (name, _, _) in enumerate(SUBJECTS)}
        for subject_index, (name, _, _) in enumerate(SUBJECTS):
            subject = subject_by_name[name]
            affectation = affectation_by_subject[name]
            for eval_index, (evaluation_name, offset) in enumerate(evaluation_offsets.items()):
                evaluation = one(session, Evaluation,
                    Evaluation.establishment_id == admin.school_id,
                    Evaluation.class_id == school_class.id,
                    Evaluation.subject_id == subject.id,
                    Evaluation.academic_period_id == t1.id,
                    Evaluation.name == evaluation_name)
                if evaluation is None:
                    evaluation = Evaluation(establishment_id=admin.school_id,
                        class_id=school_class.id, subject_id=subject.id,
                        name=evaluation_name,
                        type="composition" if evaluation_name == "Composition" else "devoir",
                        period=t1.name, date_scheduled=date(2027, 10 + min(eval_index, 2), 10),
                        max_value=20, status="validated", academic_year_id=year.id,
                        academic_period_id=t1.id, affectation_id=affectation.id,
                        created_by=admin.id, submitted_at=now,
                        validated_at=now, validated_by=admin.id)
                    session.add(evaluation)
                    session.flush()
                    session.add(EvaluationStatusEvent(establishment_id=admin.school_id,
                        evaluation_id=evaluation.id, actor_user_id=admin.id,
                        from_status="draft", to_status="submitted",
                        reason="Jeu permanent de présentation"))
                    session.add(EvaluationStatusEvent(establishment_id=admin.school_id,
                        evaluation_id=evaluation.id, actor_user_id=admin.id,
                        from_status="submitted", to_status="validated",
                        reason="Jeu permanent de présentation"))
                for student_index, student in enumerate(student_rows):
                    grade = one(session, Grade,
                                Grade.establishment_id == admin.school_id,
                                Grade.student_id == student.id,
                                Grade.evaluation_id == evaluation.id)
                    value = max(0.0, min(20.0, round(PROFILE_BASE[student_index]
                        + subject_offsets[name] + offset, 2)))
                    if grade is None:
                        grade = Grade(establishment_id=admin.school_id,
                            student_id=student.id, evaluation_id=evaluation.id,
                            class_id=school_class.id, subject_id=subject.id,
                            teacher_id=affectation.teacher_id,
                            affectation_id=affectation.id, value=value, max_value=20,
                            presence="present", entered_by=admin.id,
                            comment="Donnée permanente de présentation",
                            status="validated")
                        session.add(grade)
                    else:
                        grade.value = value
                        grade.max_value = 20
                        grade.presence = "present"
                        grade.status = "validated"

        slots = [
            (1, time(8), time(9)), (1, time(10), time(11)),
            (2, time(8), time(9)), (3, time(9), time(10)),
            (4, time(8), time(9)), (4, time(10), time(11)),
            (5, time(8), time(9)), (5, time(11), time(12)),
        ]
        for (name, _, _), (weekday, start, end) in zip(SUBJECTS, slots):
            subject = subject_by_name[name]
            affectation = affectation_by_subject[name]
            entry = one(session, ScheduleEntry,
                        ScheduleEntry.establishment_id == admin.school_id,
                        ScheduleEntry.academic_year_id == year.id,
                        ScheduleEntry.class_id == school_class.id,
                        ScheduleEntry.subject_id == subject.id,
                        ScheduleEntry.weekday == weekday,
                        ScheduleEntry.start_time == start)
            if entry is None:
                session.add(ScheduleEntry(establishment_id=admin.school_id,
                    academic_year_id=year.id, class_id=school_class.id,
                    subject_id=subject.id, teacher_id=affectation.teacher_id,
                    affectation_id=affectation.id, weekday=weekday,
                    start_time=start, end_time=end, room="Terminale C2",
                    status="active", created_by=admin.id))

        session.commit()

        principal = Principal(id=str(admin.id), role="admin",
            school_id=public_school_id(session, admin.school_id), direction_id=str(direction.id),
            direction_name=direction.name, direction_cycle_ids=[str(cycle.id)])

        # One locked contribution per teacher and student, then the official server calculation.
        assigned_teachers = sorted({a.teacher_id for a in affectation_by_subject.values()}, key=str)
        for teacher_index, teacher_id in enumerate(assigned_teachers):
            teacher = session.get(Teacher, teacher_id)
            for student_index, student in enumerate(student_rows):
                event = one(session, behavior.m.BehaviorEvent,
                    behavior.m.BehaviorEvent.establishment_id == admin.school_id,
                    behavior.m.BehaviorEvent.class_id == school_class.id,
                    behavior.m.BehaviorEvent.academic_period_id == t1.id,
                    behavior.m.BehaviorEvent.teacher_id == teacher_id,
                    behavior.m.BehaviorEvent.student_id == student.id)
                stars = max(1, min(5, 5 - student_index // 2 + (teacher_index % 2)))
                if event is None:
                    event = behavior.m.BehaviorEvent(establishment_id=admin.school_id,
                        student_id=student.id, class_id=school_class.id,
                        academic_year_id=year.id, academic_period_id=t1.id,
                        event_date=t1.start_date, category=f"stars:{stars}",
                        event_type="positive" if stars >= 3 else "negative",
                        severity="normal", title=f"{stars} étoiles",
                        description="Participation et attitude en classe",
                        recorded_by=teacher.user_id, teacher_id=teacher_id,
                        status="locked")
                    session.add(event)
                else:
                    event.category = f"stars:{stars}"
                    event.event_type = "positive" if stars >= 3 else "negative"
                    event.description = "Participation et attitude en classe"
                    event.recorded_by = teacher.user_id
                    event.status = "locked"
        session.commit()
        behavior_result = behavior.calculate(principal, session, school_class.id, t1.id)
        result = calculate_school_results(school_class.id, t1.id, principal, session)
        persisted = school_results(school_class.id, t1.id, principal, session)
        print(f"establishment={admin.school_id}")
        print(f"direction={direction.name}")
        print(f"year={year.name}")
        print(f"class={school_class.name}")
        print(f"students={len(student_rows)}")
        print(f"subjects={len(subject_by_name)}")
        print(f"evaluations={result['evaluationCount']}")
        print(f"results={len(result['students'])}:{persisted['calculationStatus']}")
        print(f"behavior={len(behavior_result['students'])}:{behavior_result['calculationStatus']}")


if __name__ == "__main__":
    main()

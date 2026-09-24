"""School-registration projection for the existing finance ledger. No second roster."""
import calendar
import uuid
from datetime import date, datetime, timezone
from typing import Literal
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, ConfigDict, Field, model_validator
from sqlalchemy import select
from sqlalchemy.orm import Session
from . import main as m

router = APIRouter(prefix='/api/v1/school/finance')
guard = m.require_module_roles('finance', 'admin', 'superadmin')
receipt_guard = m.require_module_roles(
    'finance', 'admin', 'superadmin', 'student', 'parent'
)
KINDS = {'registration': 'Inscription', 'reenrollment': 'Réinscription',
         'tuition': 'Frais mensuels', 'td': 'TD', 'other': 'Autres frais'}
MONTHS = ('janvier', 'février', 'mars', 'avril', 'mai', 'juin', 'juillet',
          'août', 'septembre', 'octobre', 'novembre', 'décembre')


def enable_read_cache(session):
    """Enable request-local memoization for the read-only finance projections."""
    # Reset at each public projection entry point. Production creates one
    # Session per HTTP request, while direct unit tests intentionally reuse a
    # transaction and may mutate it between calls.
    session.info['finance_read_cache'] = {}
    session.info['finance_balance_cache'] = {}
    session.info['finance_registration_cache'] = {}
    session.info['finance_prior_registration_cache'] = {}
    session.info['finance_fee_cache'] = {}
    session.info['finance_other_fee_cache'] = {}
    session.info['finance_class_label_cache'] = {}


def context(current, session, school_id, year_id):
    school, tenant = m.module_tenant_scope(current, session, school_id)
    year = session.get(m.AcademicYear, year_id)
    if not year or year.establishment_id != tenant:
        raise HTTPException(403, 'Année scolaire hors établissement')
    return school, tenant, year


def month_key(value, year):
    try:
        day = date.fromisoformat(str(value) + '-01')
    except ValueError as exc:
        raise HTTPException(422, 'Choisissez un mois valide') from exc
    end = day.replace(day=calendar.monthrange(day.year, day.month)[1])
    if day > year.end_date or end < year.start_date:
        raise HTTPException(422, 'Le mois est en dehors de l’année scolaire')
    return day.strftime('%Y-%m')


def registration_context(session, current, registration_id, tenant):
    cache = session.info.get('finance_registration_cache')
    key = (str(registration_id), str(tenant), current.id, current.direction_id)
    if cache is not None and key in cache:
        return cache[key]
    reg = session.get(m.StudentAcademicRegistration, registration_id)
    if not reg or reg.establishment_id != tenant:
        raise HTTPException(403, 'Inscription scolaire hors établissement')
    cl = m.ensure_class_module_access(current, session.get(m.SchoolClass, reg.class_id), tenant, session)
    student = session.get(m.Student, reg.student_id)
    if not student or student.establishment_id != tenant:
        raise HTTPException(403, 'Élève hors établissement')
    result = (reg, cl, student)
    if cache is not None:
        cache[key] = result
    return result


def preload_registration_contexts(session, current, tenant, registrations, year):
    """Load the school roster context in sets instead of once per student."""
    if not registrations:
        return
    class_ids = {item.class_id for item in registrations}
    student_ids = {item.student_id for item in registrations}
    classes = {item.id: item for item in session.scalars(select(m.SchoolClass).where(
        m.SchoolClass.id.in_(class_ids),
        m.SchoolClass.establishment_id == tenant,
    )).all()}
    students = {item.id: item for item in session.scalars(select(m.Student).where(
        m.Student.id.in_(student_ids),
        m.Student.establishment_id == tenant,
    )).all()}
    levels = {item.id: item for item in session.scalars(select(m.SchoolLevel).where(
        m.SchoolLevel.id.in_({item.school_level_id for item in classes.values()
                              if item.school_level_id})
    )).all()}
    cycles = {item.id: item for item in session.scalars(select(m.SchoolCycle).where(
        m.SchoolCycle.id.in_({item.cycle_id for item in classes.values()
                              if item.cycle_id})
    )).all()}
    context_cache = session.info.setdefault('finance_registration_cache', {})
    label_cache = session.info.setdefault('finance_class_label_cache', {})
    for registration in registrations:
        school_class = classes.get(registration.class_id)
        student = students.get(registration.student_id)
        if school_class is None or student is None:
            raise HTTPException(403, 'Inscription scolaire incomplète')
        m.ensure_class_module_access(current, school_class, tenant, session)
        key = (str(registration.id), str(tenant), current.id, current.direction_id)
        context_cache[key] = (registration, school_class, student)
        level = levels.get(school_class.school_level_id)
        cycle = cycles.get(school_class.cycle_id)
        label_cache[str(school_class.id)] = (
            level.name if level else '', cycle.name if cycle else ''
        )
    prior_students = set(session.scalars(select(
        m.StudentAcademicRegistration.student_id
    ).join(m.AcademicYear,
           m.AcademicYear.id == m.StudentAcademicRegistration.academic_year_id).where(
        m.StudentAcademicRegistration.student_id.in_(student_ids),
        m.StudentAcademicRegistration.establishment_id == tenant,
        m.AcademicYear.start_date < year.start_date,
        m.StudentAcademicRegistration.status.in_(('validated', 'active')),
    )).all())
    prior_cache = session.info.setdefault('finance_prior_registration_cache', {})
    for student_id in student_ids:
        prior_cache[(str(student_id), str(tenant), str(year.id))] = (
            student_id if student_id in prior_students else None
        )


def prior_registration(session, reg, year):
    cache = session.info.get('finance_prior_registration_cache')
    key = (str(reg.student_id), str(reg.establishment_id), str(year.id))
    if cache is not None and key in cache:
        return cache[key]
    result = session.scalar(select(m.StudentAcademicRegistration.id).join(
        m.AcademicYear, m.AcademicYear.id == m.StudentAcademicRegistration.academic_year_id).where(
        m.StudentAcademicRegistration.student_id == reg.student_id,
        m.StudentAcademicRegistration.establishment_id == reg.establishment_id,
        m.AcademicYear.start_date < year.start_date,
        m.StudentAcademicRegistration.status.in_(('validated', 'active'))).limit(1))
    if cache is not None:
        cache[key] = result
    return result


def fee_for(session, current, school, reg, cl, kind, month=None, fee_id=None, name=None):
    cache = session.info.get('finance_fee_cache')
    cycle_code = m.class_cycle_code(cl, session)
    applicable_regime = (
        m.regime_for_month(reg, month)
        if kind == 'tuition' and cycle_code in {'MATERNELLE', 'PRIMAIRE'}
        else None
    )
    key = (str(reg.id), str(cl.id), kind, month, fee_id, name, applicable_regime)
    if cache is not None and key in cache:
        return cache[key]
    probe = m.Resource(payload={'classId': str(cl.id)})
    matches = []
    for fee in m.finance_rows(session, 'finance-fees', school, current):
        data = fee.payload
        if fee_id is not None and fee.id != fee_id:
            continue
        if name is not None and data.get('name', '').strip().casefold() != name:
            continue
        if (data.get('status', 'active') != 'active' or data.get('type', 'tuition') != kind
                or str(data.get('academicYearId')) != str(reg.academic_year_id)):
            continue
        fields = {key: data[key] for key in m.FinanceFeeInput.model_fields if key in data}
        body = m.FinanceFeeInput(**fields)
        if body.month is not None and body.month != month:
            continue
        if body.regime is not None:
            if applicable_regime is None or body.regime != applicable_regime:
                continue
        if m.finance_fee_matches_registration(body, probe, session, reg.establishment_id):
            rank = {'establishment': 0, 'cycle': 1, 'level': 2, 'class': 3}[body.scope]
            matches.append(((rank, body.month is not None, body.regime is not None), fee))
    if not matches:
        if cache is not None:
            cache[key] = None
        return None
    rank = max(item[0] for item in matches)
    selected = [fee for weight, fee in matches if weight == rank]
    if len(selected) != 1:
        raise HTTPException(409, 'Plusieurs tarifs couvrent le même contexte. Désactivez le tarif en doublon.')
    result = selected[0]
    if cache is not None:
        cache[key] = result
    return result


def other_fees(session, current, school, reg, cl):
    cache = session.info.get('finance_other_fee_cache')
    key = (str(reg.id), str(cl.id))
    if cache is not None and key in cache:
        return cache[key]
    names = {fee.payload.get('name', '').strip().casefold()
             for fee in m.finance_rows(session, 'finance-fees', school, current)
             if fee.payload.get('type') == 'other'}
    result = [fee for name in sorted(names)
              if (fee := fee_for(session, current, school, reg, cl, 'other', name=name))]
    if cache is not None:
        cache[key] = result
    return result


def registration_receipts(session, current, school, tenant, year):
    stmt = m.apply_class_direction_scope(select(m.StudentAcademicRegistration).join(
        m.SchoolClass, m.SchoolClass.id == m.StudentAcademicRegistration.class_id).where(
        m.StudentAcademicRegistration.establishment_id == tenant,
        m.StudentAcademicRegistration.academic_year_id == year.id,
        m.StudentAcademicRegistration.status.in_(('pre_enrolled', 'validated', 'active'))), current)
    registrations = session.scalars(stmt).all()
    preload_registration_contexts(session, current, tenant, registrations, year)
    result = []
    for reg in registrations:
        reg, cl, student = registration_context(session, current, reg.id, tenant)
        kind = 'reenrollment' if prior_registration(session, reg, year) else 'registration'
        row, _ = invoice(session, current, school, reg, cl, student, kind, None)
        if row['status'] != 'paid':
            continue
        rid = 'REGREC_' + uuid.uuid5(uuid.NAMESPACE_URL, f'{reg.id}:{kind}').hex
        result.append({'id': rid, 'paymentId': None, 'receiptNumber': rid,
            'registrationId': str(reg.id), 'schoolRegistrationId': str(reg.id),
            'studentId': str(student.id), 'studentName': row['studentName'],
            'classId': str(cl.id), 'className': row['className'],
            'matricule': row['matricule'], 'label': row['label'], 'type': kind,
            'amount': row['expected'], 'totalPaid': row['expected'], 'remaining': 0,
            'paymentMethod': 'registration', 'status': 'active', 'schoolId': school,
            'academicYearId': str(year.id), 'date': reg.registration_date.isoformat() if reg.registration_date else None,
            'source': 'school_registration'})
    return result


def assignment_key(session, reg, kind, month, fee_id=None):
    base = f'{reg.id}:{kind}:{month if kind == "tuition" else "once"}'
    legacy = 'INV_' + uuid.uuid5(uuid.NAMESPACE_URL, base).hex
    if kind != 'other' or not fee_id:
        return legacy
    old = session.get(m.Resource, {'kind': 'finance-fee-assignments', 'id': legacy})
    if old and old.payload.get('feeId') == fee_id:
        return legacy
    return 'INV_' + uuid.uuid5(uuid.NAMESPACE_URL, f'{base}:{fee_id}').hex


def invoice(session, current, school, reg, cl, student, kind, month, fee_id=None):
    year = session.get(m.AcademicYear, reg.academic_year_id)
    month = month_key(month, year) if kind == 'tuition' else None
    cycle_code = m.class_cycle_code(cl, session)
    applicable_regime = (
        m.regime_for_month(reg, month)
        if kind == 'tuition' and cycle_code in {'MATERNELLE', 'PRIMAIRE'}
        else None
    )
    prior = prior_registration(session, reg, year)
    eligible = (kind != 'td' or reg.has_td) and (kind != 'registration' or not prior) and (kind != 'reenrollment' or bool(prior))
    if kind == 'td' and eligible:
        try:
            m.validate_registration_academic_options(cl, True, session)
        except HTTPException:
            eligible = False
    fee = fee_for(session, current, school, reg, cl, kind, month, fee_id) if eligible else None
    identifier = assignment_key(session, reg, kind, month, fee.id if fee else None)
    projected_payload = {'id': identifier, 'registrationId': str(reg.id), 'schoolRegistrationId': str(reg.id),
            'studentId': str(student.id), 'academicYearId': str(reg.academic_year_id),
            'classId': str(cl.id),
            'feeId': fee.id if fee else None, 'amount': int(fee.payload['amount']) if fee else 0,
            'type': kind, 'month': month, 'regime': applicable_regime,
            'schoolId': school, 'status': 'assigned'}
    stored_assignment = session.get(m.Resource, {'kind': 'finance-fee-assignments', 'id': identifier})
    preserve_historical_assignment = bool(
        stored_assignment
        and stored_assignment.payload.get('classId') == str(cl.id)
    )
    assignment = stored_assignment if preserve_historical_assignment else m.Resource(
        id=identifier, kind='finance-fee-assignments', school_id=school,
        establishment_id=reg.establishment_id, academic_year_id=reg.academic_year_id,
        payload=projected_payload,
    )
    balance = m.finance_assignment_balance(session, school, assignment)
    # A validated school registration is itself the proof of settlement for
    # registration/re-enrollment. It is not a second cash payment and must not
    # create a duplicate ledger entry.
    if kind in ('registration', 'reenrollment') and fee and eligible:
        balance = {**balance, 'paid': balance['expected'], 'remaining': 0,
                   'status': 'paid'}
    label_cache = session.info.get('finance_class_label_cache')
    label_key = str(cl.id)
    if label_cache is not None and label_key in label_cache:
        level_name, cycle_name = label_cache[label_key]
    else:
        level = session.get(m.SchoolLevel, cl.school_level_id) if cl.school_level_id else None
        cycle = session.get(m.SchoolCycle, cl.cycle_id) if cl.cycle_id else None
        level_name = level.name if level else ''
        cycle_name = cycle.name if cycle else ''
        if label_cache is not None:
            label_cache[label_key] = (level_name, cycle_name)
    label = fee.payload['name'] if fee else KINDS[kind]
    if month and fee and not fee.payload.get('month'):
        label += f' — {MONTHS[int(month[5:])-1]} {month[:4]}'
    row = {'registrationId': str(reg.id), 'studentId': str(student.id),
        'lastName': student.last_name, 'firstName': student.first_name,
        'studentName': f'{student.last_name} {student.first_name}',
        'matricule': reg.registration_number or student.registration_number,
        'classId': str(cl.id), 'className': cl.name, 'level': level_name,
        'cycle': cycle_name, 'registrationStatus': reg.status,
        'academicYearId': str(reg.academic_year_id), 'schoolId': school,
        'type': kind, 'month': month, 'label': label, 'feeId': fee.id if fee else None,
        'eligible': eligible, 'hasTd': reg.has_td,
        'regime': assignment.payload.get('regime', applicable_regime), **balance,
        'credit': max(0, balance['paid']-balance['expected'])}
    if not eligible:
        row['status'] = 'not_applicable'
    elif not fee:
        row['status'] = 'no_tariff'
    return row, assignment


def billing_months(session, year):
    """Use dated academic monthly periods; otherwise the academic-year calendar."""
    periods = session.scalars(select(m.AcademicPeriod).where(
        m.AcademicPeriod.establishment_id == year.establishment_id,
        m.AcademicPeriod.academic_year_id == year.id,
        m.AcademicPeriod.period_type == 'month',
        m.AcademicPeriod.status == 'active')).all()
    if periods:
        if any(p.start_date is None for p in periods):
            raise HTTPException(409, 'Renseignez les dates des périodes mensuelles pour calculer le budget annuel')
        return sorted({month_key(p.start_date.strftime('%Y-%m'), year) for p in periods})
    result = []
    day = year.start_date.replace(day=1)
    while day <= year.end_date:
        result.append(day.strftime('%Y-%m'))
        day = date(day.year + (day.month == 12), day.month % 12 + 1, 1)
    return result


@router.get('/budget')
def budget(academic_year_id: uuid.UUID, school_id: str | None = None,
    current: m.Principal = Depends(guard), session: Session = Depends(m.db)):
    enable_read_cache(session)
    school, tenant, year = context(current, session, school_id, academic_year_id)
    months = billing_months(session, year)
    stmt = m.apply_class_direction_scope(select(m.StudentAcademicRegistration).join(
        m.SchoolClass, m.SchoolClass.id == m.StudentAcademicRegistration.class_id).where(
        m.StudentAcademicRegistration.establishment_id == tenant,
        m.StudentAcademicRegistration.academic_year_id == year.id,
        m.StudentAcademicRegistration.status.in_(('validated', 'active'))), current)
    totals = {kind: {'type': kind, 'label': label, 'expected': 0, 'paid': 0,
                    'remaining': 0, 'credit': 0, 'unconfiguredCount': 0}
              for kind, label in KINDS.items()}
    registrations = session.scalars(stmt).all()
    preload_registration_contexts(session, current, tenant, registrations, year)
    counts = {'students': len(registrations), 'paid': 0, 'partial': 0, 'unpaid': 0, 'unconfigured': 0}
    for registration in registrations:
        reg, cl, student = registration_context(session, current, registration.id, tenant)
        student_expected = student_paid = student_missing = 0
        for kind, total in totals.items():
            for month in months if kind == 'tuition' else [None]:
                fee_ids = [fee.id for fee in other_fees(session, current, school, reg, cl)] if kind == 'other' else [None]
                for fee_id in fee_ids:
                    row, _ = invoice(session, current, school, reg, cl, student, kind, month, fee_id)
                    for field in ('expected', 'paid', 'remaining', 'credit'):
                        total[field] += row[field]
                    total['unconfiguredCount'] += row['status'] == 'no_tariff'
                    student_expected += row['expected']
                    student_paid += row['paid']
                    student_missing += row['status'] == 'no_tariff'
        if student_missing or student_expected == 0:
            counts['unconfigured'] += 1
        elif student_paid >= student_expected:
            counts['paid'] += 1
        elif student_paid > 0:
            counts['partial'] += 1
        else:
            counts['unpaid'] += 1
    # Cash remains official even if its enrollment later becomes inactive.
    for total in totals.values():
        total['paid'] = 0
    # Registration/re-enrollment are settled by the school registration itself.
    for registration in registrations:
        reg, cl, student = registration_context(session, current, registration.id, tenant)
        for kind in ('registration', 'reenrollment'):
            row, _ = invoice(session, current, school, reg, cl, student, kind, None)
            totals[kind]['paid'] += row['paid']
    provisional_stmt = m.apply_class_direction_scope(
        select(m.StudentAcademicRegistration).join(
            m.SchoolClass,
            m.SchoolClass.id == m.StudentAcademicRegistration.class_id,
        ).where(
            m.StudentAcademicRegistration.establishment_id == tenant,
            m.StudentAcademicRegistration.academic_year_id == year.id,
            m.StudentAcademicRegistration.status == 'pre_enrolled',
        ),
        current,
    )
    provisional_registrations = list(session.scalars(provisional_stmt).all())
    preload_registration_contexts(
        session, current, tenant, provisional_registrations, year
    )
    for registration in provisional_registrations:
        reg, cl, student = registration_context(
            session, current, registration.id, tenant
        )
        kind = 'reenrollment' if prior_registration(session, reg, year) else 'registration'
        row, _ = invoice(session, current, school, reg, cl, student, kind, None)
        totals[kind]['expected'] += row['expected']
        totals[kind]['paid'] += row['paid']
    for payment in m.finance_rows(session, 'finance-payments', school, current):
        data = payment.payload
        if data.get('status', 'active') == 'cancelled' or str(data.get('academicYearId')) != str(year.id):
            continue
        kind = data.get('type')
        if kind not in totals:
            assignment = session.get(m.Resource, {'kind':'finance-fee-assignments', 'id':data.get('feeAssignmentId')})
            fee = session.get(m.Resource, {'kind':'finance-fees', 'id':assignment.payload.get('feeId')}) if assignment else None
            kind = fee.payload.get('type', 'other') if fee else 'other'
        totals.get(kind, totals['other'])['paid'] += int(data['amount'])
    for total in totals.values():
        total['remaining'] = max(0, total['expected'] - total['paid'])
        total['credit'] = max(0, total['paid'] - total['expected'])
    return {'academicYearId': str(year.id), 'registrationCount': len(registrations),
            'months': months, 'breakdown': list(totals.values()), 'counts': counts,
            'summary': {field: sum(row[field] for row in totals.values())
                        for field in ('expected', 'paid', 'remaining', 'credit', 'unconfiguredCount')}}


@router.get('/roster')
def roster(academic_year_id: uuid.UUID, kind: Literal['registration','reenrollment','tuition','td','other']='tuition',
    month: str | None=None, class_id: uuid.UUID | None=None, search: str='', school_id: str | None=None,
    current: m.Principal=Depends(guard), session: Session=Depends(m.db)):
    enable_read_cache(session)
    school, tenant, year = context(current, session, school_id, academic_year_id)
    if kind == 'tuition': month_key(month, year)
    if class_id:
        cl=m.ensure_class_module_access(current, session.get(m.SchoolClass,class_id), tenant, session)
        if cl.academic_year_id != year.id:
            raise HTTPException(422,'La classe ne correspond pas à l’année scolaire sélectionnée')
    stmt = select(m.StudentAcademicRegistration).join(m.SchoolClass,
        m.SchoolClass.id == m.StudentAcademicRegistration.class_id).where(
        m.StudentAcademicRegistration.establishment_id == tenant,
        m.StudentAcademicRegistration.academic_year_id == year.id,
        m.StudentAcademicRegistration.status.in_(('validated','active')))
    stmt = m.apply_class_direction_scope(stmt, current)
    if class_id: stmt = stmt.where(m.StudentAcademicRegistration.class_id == class_id)
    registrations = session.scalars(stmt).all()
    preload_registration_contexts(session, current, tenant, registrations, year)
    rows=[]
    for reg in registrations:
        reg, cl, student = registration_context(session,current,reg.id,tenant)
        if search.strip().casefold() not in f'{student.last_name} {student.first_name} {student.first_name} {student.last_name}'.casefold(): continue
        fee_ids = [fee.id for fee in other_fees(session,current,school,reg,cl)] if kind == 'other' else [None]
        for fee_id in fee_ids:
            rows.append(invoice(session,current,school,reg,cl,student,kind,month,fee_id)[0])
    rows.sort(key=lambda row:(row['lastName'].casefold(),row['firstName'].casefold()))
    classes_stmt=m.apply_class_direction_scope(select(m.SchoolClass).where(
        m.SchoolClass.establishment_id==tenant,m.SchoolClass.academic_year_id==year.id,
        m.SchoolClass.status=='active'),current)
    return {'students': rows,
        'budget': budget(year.id, school, current, session),
        'classes': [{'id':str(cl.id),'name':cl.name,'levelId':str(cl.school_level_id) if cl.school_level_id else None,
                     'levelName': session.get(m.SchoolLevel,cl.school_level_id).name if cl.school_level_id else None,
                     'cycleId':str(cl.cycle_id) if cl.cycle_id else None,
                     'cycleName': session.get(m.SchoolCycle,cl.cycle_id).name if cl.cycle_id else None}
                    for cl in session.scalars(classes_stmt.order_by(m.SchoolClass.name)).all()],
        'fees': [fee.payload for fee in m.finance_rows(session,'finance-fees',school,current)
                 if str(fee.payload.get('academicYearId'))==str(year.id)],
        'receipts': receipts(year.id,school,current,session),
        'summary': {
        'expected': sum(row['expected'] for row in rows), 'paid': sum(row['paid'] for row in rows),
        'remaining': sum(row['remaining'] for row in rows), 'credit': sum(row['credit'] for row in rows)},
        'unconfiguredCount': sum(row['status']=='no_tariff' for row in rows)}


@router.get('/monthly-situation/{registration_id}')
def monthly_situation(
    registration_id: uuid.UUID,
    academic_year_id: uuid.UUID,
    school_id: str | None = None,
    current: m.Principal = Depends(guard),
    session: Session = Depends(m.db),
):
    """Return every monthly balance for one student in a single request."""
    enable_read_cache(session)
    school, tenant, year = context(
        current, session, school_id, academic_year_id
    )
    reg, school_class, student = registration_context(
        session, current, registration_id, tenant
    )
    if reg.academic_year_id != year.id:
        raise HTTPException(422, 'L’inscription ne correspond pas à l’année scolaire')
    rows = [
        invoice(
            session, current, school, reg, school_class, student,
            'tuition', month,
        )[0]
        for month in billing_months(session, year)
    ]
    return {
        'registrationId': str(reg.id),
        'studentId': str(student.id),
        'studentName': f'{student.last_name} {student.first_name}',
        'firstName': student.first_name,
        'lastName': student.last_name,
        'matricule': reg.registration_number or student.registration_number,
        'classId': str(school_class.id),
        'className': school_class.name,
        'months': rows,
    }


@router.get('/parent-situation/{student_id}')
def parent_financial_situation(
    student_id: uuid.UUID,
    academic_year_id: uuid.UUID,
    current: m.Principal = Depends(receipt_guard),
    session: Session = Depends(m.db),
):
    if current.role != 'parent':
        raise HTTPException(403, 'Cet espace est réservé au parent')
    guardian = session.scalar(select(m.Guardian).where(
        m.Guardian.user_id == uuid.UUID(current.id),
        m.Guardian.status == 'active',
    ))
    if not guardian:
        raise HTTPException(403, 'Profil parent invalide')
    linked = session.scalar(select(m.StudentGuardian.id).where(
        m.StudentGuardian.guardian_id == guardian.id,
        m.StudentGuardian.student_id == student_id,
        m.StudentGuardian.establishment_id == guardian.establishment_id,
    ))
    if not linked:
        raise HTTPException(404, 'Enfant introuvable')
    registration = session.scalar(select(m.StudentAcademicRegistration).where(
        m.StudentAcademicRegistration.student_id == student_id,
        m.StudentAcademicRegistration.academic_year_id == academic_year_id,
        m.StudentAcademicRegistration.establishment_id == guardian.establishment_id,
        m.StudentAcademicRegistration.status.in_(('validated', 'active')),
    ))
    if not registration:
        raise HTTPException(404, 'Inscription annuelle introuvable')
    situation = monthly_situation(
        registration.id,
        academic_year_id,
        m.public_school_id(session, guardian.establishment_id),
        current,
        session,
    )
    months = situation['months']
    today_month = date.today().strftime('%Y-%m')
    paid_total = sum(int(row.get('paid') or 0) for row in months)
    remaining_total = sum(int(row.get('remaining') or 0) for row in months)
    expected_total = sum(int(row.get('expected') or 0) for row in months)
    credit_total = sum(int(row.get('credit') or 0) for row in months)
    overdue = [
        row for row in months
        if row.get('month') and row['month'] < today_month
        and row.get('remaining', 0) > 0
    ]
    unpaid = [
        row for row in months
        if row.get('status') in {'unpaid', 'partial'}
    ]
    advance = [
        row for row in months
        if row.get('month') and row['month'] > today_month
        and int(row.get('paid') or 0) > 0
    ]
    school_class = session.get(m.SchoolClass, registration.class_id)
    cycle_code = m.class_cycle_code(school_class, session) if school_class else ''
    return {
        **situation,
        'cycleCode': cycle_code,
        'currentRegime': (
            m.regime_for_month(registration, today_month)
            if cycle_code in {'MATERNELLE', 'PRIMAIRE'} else None
        ),
        'summary': {
            'expected': expected_total,
            'paid': paid_total,
            'remaining': remaining_total,
            'credit': credit_total,
            'unpaidMonths': len(unpaid),
            'overdueMonths': len(overdue),
        },
        'unpaidMonths': unpaid,
        'overdueMonths': overdue,
        'advanceMonths': advance,
    }


class SchoolPaymentInput(BaseModel):
    model_config = ConfigDict(extra='forbid')
    registrationId: uuid.UUID
    type: Literal['registration','reenrollment','tuition','td','other']
    month: str | None = None
    months: list[str] | None = Field(default=None, min_length=1, max_length=12)
    feeId: str | None = None
    amount: int = Field(gt=0, le=1_000_000_000)
    paymentMethod: Literal['cash','mobile','transfer','card','other']='cash'
    reference: str | None = Field(default=None,max_length=160)
    schoolId: str | None=None

    @model_validator(mode='after')
    def validate_month_selection(self):
        if self.months:
            if self.type != 'tuition':
                raise ValueError('Le paiement multi-mois concerne uniquement les frais mensuels')
            if self.month is not None:
                raise ValueError('Utilisez soit month, soit months, pas les deux')
            if len(self.months) != len(set(self.months)):
                raise ValueError('Un mois ne peut pas être sélectionné plusieurs fois')
        return self


def pay_multiple_months(body, current, session, school, tenant, reg, cl, student):
    year = session.get(m.AcademicYear, reg.academic_year_id)
    available_months = billing_months(session, year)
    selected = [month_key(value, year) for value in body.months or []]
    unknown = set(selected) - set(available_months)
    if unknown:
        raise HTTPException(422, 'Un mois sélectionné est hors de l’année scolaire')
    order = {value: index for index, value in enumerate(available_months)}
    selected.sort(key=order.__getitem__)

    projections = []
    for month in selected:
        key = assignment_key(session, reg, 'tuition', month)
        m.finance_lock(session, f'assignment:{key}')
        row, assignment = invoice(
            session, current, school, reg, cl, student, 'tuition', month
        )
        if row['status'] == 'no_tariff':
            raise HTTPException(409, f'Aucun tarif applicable pour {MONTHS[int(month[5:]) - 1]} {month[:4]}')
        if row['status'] == 'not_applicable':
            raise HTTPException(409, 'Un mois sélectionné n’est pas applicable à cette inscription')
        if row['remaining'] > 0:
            projections.append((month, row, assignment))
    if not projections:
        raise HTTPException(409, 'Tous les mois sélectionnés sont déjà entièrement payés')

    total_remaining = sum(row['remaining'] for _, row, _ in projections)
    if body.amount > total_remaining:
        raise HTTPException(409, 'Le montant dépasse le reste total des mois sélectionnés')

    allocations = []
    amount_left = body.amount
    for month, row, assignment in projections:
        stored = session.get(m.Resource, {'kind': assignment.kind, 'id': assignment.id})
        if stored:
            stored.payload = dict(assignment.payload)
        else:
            session.add(assignment)
        allocated = min(amount_left, row['remaining'])
        allocations.append({
            'feeAssignmentId': assignment.id,
            'month': month,
            'amount': allocated,
            'expected': row['expected'],
            'paidBefore': row['paid'],
            'remainingAfter': row['remaining'] - allocated,
            'status': (
                'paid' if row['remaining'] == allocated
                else 'partial' if allocated > 0
                else 'unpaid'
            ),
        })
        amount_left -= allocated

    now = datetime.now(timezone.utc)
    payment_id = f"PAY_{uuid.uuid4().hex[:16].upper()}"
    receipt_id = f"RC_{uuid.uuid4().hex[:16].upper()}"
    author = session.get(m.User, uuid.UUID(current.id))
    establishment = session.get(m.Establishment, tenant)
    direction = session.get(m.SchoolDirection, uuid.UUID(current.direction_id)) if current.direction_id else None
    month_labels = [f"{MONTHS[int(item['month'][5:]) - 1]} {item['month'][:4]}" for item in allocations]
    payment_payload = {
        'id': payment_id, 'registrationId': str(reg.id),
        'schoolRegistrationId': str(reg.id), 'feeAssignmentId': None,
        'studentId': str(student.id), 'studentName': f'{student.last_name} {student.first_name}',
        'classId': str(cl.id), 'className': cl.name,
        'matricule': reg.registration_number or student.registration_number,
        'type': 'tuition', 'months': [item['month'] for item in allocations],
        'allocations': allocations, 'amount': body.amount,
        'date': now.date().isoformat(), 'paymentMethod': body.paymentMethod,
        'reference': body.reference.strip() if body.reference else None,
        'receivedBy': current.id, 'schoolId': school,
        'institutionId': school, 'academicYearId': str(reg.academic_year_id),
        'status': 'active', 'createdAt': now.isoformat(),
    }
    receipt_payload = {
        'id': receipt_id, 'paymentId': payment_id,
        'receiptNumber': f"REC-{now:%Y%m%d}-{uuid.uuid4().hex[:6].upper()}",
        'registrationId': str(reg.id), 'schoolRegistrationId': str(reg.id),
        'studentId': str(student.id), 'studentName': payment_payload['studentName'],
        'classId': str(cl.id), 'className': cl.name,
        'matricule': payment_payload['matricule'],
        'label': f"Paiement mensuel — {', '.join(month_labels)}",
        'type': 'tuition', 'months': payment_payload['months'],
        'allocations': allocations, 'amount': body.amount,
        'totalPaid': sum(item['paidBefore'] + item['amount'] for item in allocations),
        'remaining': total_remaining - body.amount,
        'paymentMethod': body.paymentMethod, 'date': now.date().isoformat(),
        'schoolId': school, 'academicYearId': str(reg.academic_year_id),
        'schoolName': establishment.name, 'directionName': direction.name if direction else '',
        'authorName': author.name if author else '', 'status': 'active',
        'createdAt': now.isoformat(),
    }
    session.add_all((
        m.Resource(id=payment_id, kind='finance-payments', school_id=school,
            establishment_id=tenant, academic_year_id=reg.academic_year_id,
            payload=payment_payload),
        m.Resource(id=receipt_id, kind='finance-receipts', school_id=school,
            establishment_id=tenant, academic_year_id=reg.academic_year_id,
            payload=receipt_payload),
    ))
    try:
        session.commit()
    except Exception as exc:
        session.rollback()
        raise HTTPException(409, 'Le paiement multi-mois n’a pas pu être enregistré') from exc
    return {
        'payment': payment_payload,
        'receipt': receipt_payload,
        'allocations': allocations,
        'balance': {
            'expected': sum(row['expected'] for _, row, _ in projections),
            'paid': sum(row['paid'] for _, row, _ in projections) + body.amount,
            'remaining': total_remaining - body.amount,
            'status': 'paid' if body.amount == total_remaining else 'partial',
        },
    }


@router.post('/school-payments', status_code=201)
def pay(body: SchoolPaymentInput, current: m.Principal=Depends(guard),session: Session=Depends(m.db)):
    school, tenant = m.module_tenant_scope(current,session,body.schoolId)
    reg, cl, student = registration_context(session,current,body.registrationId,tenant)
    if reg.status not in ('validated','active'):
        raise HTTPException(409,'L’inscription scolaire n’est pas active')
    if body.months:
        return pay_multiple_months(
            body, current, session, school, tenant, reg, cl, student
        )
    # Same advisory assignment key as the existing payment endpoint.
    if body.type == 'other' and not body.feeId:
        raise HTTPException(422, 'Sélectionnez le frais à encaisser')
    if body.type != 'other' and body.feeId is not None:
        raise HTTPException(422, 'Le tarif est déterminé automatiquement pour ce type de paiement')
    key = assignment_key(session, reg, body.type, body.month, body.feeId)
    m.finance_lock(session,f'assignment:{key}')
    m.finance_lock(session,f'tariffs:{school}:{reg.academic_year_id}')
    if body.reference: m.finance_lock(session,f'reference:{school}:{body.reference.strip().casefold()}')
    row, assignment = invoice(session,current,school,reg,cl,student,body.type,body.month,body.feeId)
    if row['status'] in ('no_tariff','not_applicable'):
        raise HTTPException(409,'Aucun tarif applicable à ce paiement')
    if body.type in ('registration','reenrollment') and row['status'] == 'paid':
        receipt_id = 'REGREC_' + uuid.uuid5(uuid.NAMESPACE_URL, f'{reg.id}:{body.type}').hex
        receipt = {'id': receipt_id, 'paymentId': None, 'receiptNumber': receipt_id,
            'registrationId': str(reg.id), 'schoolRegistrationId': str(reg.id),
            'studentId': str(student.id), 'studentName': row['studentName'],
            'classId': str(cl.id), 'className': row['className'],
            'matricule': row['matricule'], 'label': row['label'], 'type': body.type,
            'month': None, 'amount': row['expected'], 'totalPaid': row['expected'],
            'remaining': 0, 'paymentMethod': 'registration', 'status': 'active',
            'schoolId': school, 'academicYearId': str(reg.academic_year_id),
            'date': reg.registration_date.isoformat() if reg.registration_date else None,
            'source': 'school_registration'}
        return {'payment': {'id': None, 'amount': row['expected'], 'status': 'paid',
                             'source': 'school_registration'}, 'receipt': receipt,
                'balance': {'expected': row['expected'], 'paid': row['expected'],
                            'remaining': 0, 'status': 'paid'}}
    if body.amount > row['remaining']:
        raise HTTPException(409,'Le montant dépasse le reste à payer. Aucun encaissement effectué.')
    # Transient projection: it is never inserted as a second student registration.
    projection=m.Resource(id=str(reg.id),academic_year_id=reg.academic_year_id,
        payload={'studentId':str(student.id),'studentName':row['studentName'],'academicYearId':str(reg.academic_year_id)})
    old=session.get(m.Resource,{'kind':assignment.kind,'id':assignment.id})
    if old: old.payload=dict(assignment.payload)
    else: session.add(assignment)
    legacy=m.FinancePaymentInput(registrationId=str(reg.id),feeAssignmentId=assignment.id,
        amount=body.amount,paymentMethod=body.paymentMethod,reference=body.reference,schoolId=school)
    result=m.persist_finance_payment(legacy,current,session,school,tenant,projection,assignment,row)
    session.flush()
    author=session.get(m.User,uuid.UUID(current.id))
    establishment=session.get(m.Establishment,tenant)
    direction=session.get(m.SchoolDirection,uuid.UUID(current.direction_id)) if current.direction_id else None
    for kind, keyname in [('finance-payments','payment'),('finance-receipts','receipt')]:
        record=session.get(m.Resource,{'kind':kind,'id':result[keyname]['id']})
        data={**record.payload,'schoolRegistrationId':str(reg.id),
            'classId':str(cl.id),'className':cl.name,
            'matricule':row['matricule'],'label':row['label'],'type':body.type,'month':row['month'],
            'schoolName':establishment.name,'directionName':direction.name if direction else '',
            'authorName':author.name if author else '', 'paymentMethod':body.paymentMethod,
            'totalPaid':result['balance']['paid'],'remaining':result['balance']['remaining']}
        record.payload=data
        result[keyname]=data
    session.commit()
    return result


@router.get('/receipts')
def receipts(academic_year_id: uuid.UUID,school_id: str | None=None,
    current: m.Principal=Depends(guard),session: Session=Depends(m.db)):
    enable_read_cache(session)
    school,tenant,year=context(current,session,school_id,academic_year_id)
    existing = [item.payload for item in m.finance_rows(session,'finance-receipts',school,current)
        if str(item.payload.get('academicYearId'))==str(year.id)]
    return registration_receipts(session,current,school,tenant,year) + existing


@router.get('/receipts/{receipt_id}')
def receipt(receipt_id: str,school_id: str | None=None,
    current: m.Principal=Depends(receipt_guard),session: Session=Depends(m.db)):
    school,tenant=m.module_tenant_scope(current,session,school_id)
    def can_read(payload):
        if current.role in {'admin', 'superadmin'}:
            return True
        student_id = str(payload.get('studentId') or '')
        if current.role == 'student':
            return bool(current.student_id) and student_id == str(current.student_id)
        if current.role == 'parent':
            try:
                guardian = session.scalar(select(m.Guardian).where(
                    m.Guardian.user_id == uuid.UUID(current.id),
                    m.Guardian.status == 'active',
                ))
            except ValueError:
                guardian = None
            if not guardian:
                return False
            child_ids = {str(value) for value in session.scalars(select(
                m.StudentGuardian.student_id
            ).where(
                m.StudentGuardian.guardian_id == guardian.id,
                m.StudentGuardian.establishment_id == tenant,
            )).all()}
            return student_id in child_ids
        return False
    if receipt_id.startswith('REGREC_'):
        for year in session.scalars(select(m.AcademicYear).where(m.AcademicYear.establishment_id==tenant)).all():
            for item in registration_receipts(session,current,school,tenant,year):
                if item['id'] == receipt_id:
                    if not can_read(item):
                        raise HTTPException(404, 'Reçu introuvable')
                    return item
    if current.role in {'admin', 'superadmin'}:
        return m.finance_resource(
            session, 'finance-receipts', receipt_id, school, current
        ).payload
    row = session.get(m.Resource, {'kind':'finance-receipts','id':receipt_id})
    if not row or row.school_id != school or not can_read(row.payload):
        raise HTTPException(404, 'Reçu introuvable')
    return row.payload


@router.put('/fees/{fee_id}')
def update_fee(fee_id: str, body: m.FinanceFeeInput,
    current: m.Principal=Depends(guard),session: Session=Depends(m.db)):
    try:
        year_id=uuid.UUID(body.academicYearId)
    except ValueError as exc:
        raise HTTPException(422,'Année scolaire invalide') from exc
    school,tenant,year=context(current,session,body.schoolId,year_id)
    fee=m.finance_resource(session,'finance-fees',fee_id,school,current)
    # Context cannot silently move a historical tariff to another class/year/type.
    for field in ('scope','cycle','levelId','classId','academicYearId','type','month','regime'):
        if fee.payload.get(field) != getattr(body,field):
            raise HTTPException(409,'Conservez le contexte du tarif ; seul le montant et le libellé sont modifiables')
    m.finance_lock(session,f'tariffs:{school}:{year.id}')
    if body.type == 'other':
        for other in m.finance_rows(session, 'finance-fees', school, current):
            if (other.id != fee.id and other.payload.get('status', 'active') == 'active'
                    and other.payload.get('name', '').strip().casefold() == body.name.strip().casefold()
                    and all(other.payload.get(field) == fee.payload.get(field)
                            for field in ('scope','cycle','levelId','classId','academicYearId','type'))):
                raise HTTPException(409, 'Un autre frais porte déjà ce libellé dans ce contexte')
    fee.payload={**fee.payload,'amount':body.amount,'name':body.name.strip(),'description':body.description}
    session.commit()
    return fee.payload

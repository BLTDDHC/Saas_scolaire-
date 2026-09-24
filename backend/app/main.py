"""EduPro API: tenant-safe JSON contracts matching the existing Flutter models."""
import os
import re
import json
import base64
import smtplib
import urllib.parse
import urllib.request
from email.message import EmailMessage
import secrets
import hashlib
import threading
import uuid
from collections import Counter
from datetime import date, datetime, time as dt_time, timedelta, timezone
from pathlib import Path
from time import monotonic
from typing import Any, Literal

import jwt
from dotenv import load_dotenv
from fastapi import Depends, FastAPI, HTTPException, Query, Request, Response, status
from fastapi.middleware.cors import CORSMiddleware
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from fastapi.staticfiles import StaticFiles
from passlib.context import CryptContext
from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator
from sqlalchemy import Boolean, Date, DateTime, Float, Integer, JSON, Numeric, String, Text, Time, create_engine, func, or_, select, text
from sqlalchemy.dialects.postgresql import JSONB, UUID
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import DeclarativeBase, Mapped, Session, mapped_column

# Always resolve the local configuration from backend/.env, regardless of the
# working directory used to launch Uvicorn.
load_dotenv(dotenv_path=Path(__file__).resolve().parents[1] / ".env")
DATABASE_URL = os.environ.get("DATABASE_URL")
JWT_SECRET = os.environ.get("JWT_SECRET")
if not DATABASE_URL or not JWT_SECRET:
    raise RuntimeError("DATABASE_URL and JWT_SECRET must be defined in the environment")

engine = create_engine(DATABASE_URL, pool_pre_ping=True)
passwords = CryptContext(schemes=["bcrypt"], deprecated="auto")
bearer = HTTPBearer()
KINDS = {"establishments", "subscriptions", "academic-years", "students", "teachers", "classes", "subjects", "evaluations", "grades", "affectations", "absences", "assignments", "documents", "announcements", "conversations", "notifications", "student-registrations", "finance-fees", "finance-registrations", "finance-fee-assignments", "finance-payments", "finance-receipts", "financial-accounts", "financial-lines", "financial-payment-records", "school-levels", "series", "annual-bulletins", "annual-decisions", "re-enrollment-requests", "behavior-assessments"}
PASSWORD_MIN_LENGTH = 8
RESULT_CALCULATION_RULE_VERSION = "mc-composition-v2"
STUDENT_PHOTO_ROOT = Path(__file__).resolve().parents[1] / "storage" / "student-photos"
USER_PROFILE_PHOTO_ROOT = Path(__file__).resolve().parents[1] / "storage" / "user-profile-photos"
STUDENT_PHOTO_MAX_BYTES = 5 * 1024 * 1024
STUDENT_PHOTO_TYPES = {
    "image/jpeg": ".jpg",
    "image/jpg": ".jpg",
    "image/png": ".png",
    "image/webp": ".webp",
    "image/gif": ".gif",
    "image/bmp": ".bmp",
    "image/x-ms-bmp": ".bmp",
    "image/heic": ".heic",
    "image/heif": ".heif",
}
TEMPORARY_ACCESS_TTL = timedelta(hours=24)
TEMPORARY_ACCESS_KIND = "password-reset-grants"
AUTH_RATE_LIMIT_ATTEMPTS = max(1, int(os.getenv("AUTH_RATE_LIMIT_ATTEMPTS", "8")))
AUTH_RATE_LIMIT_PEER_ATTEMPTS = max(
    AUTH_RATE_LIMIT_ATTEMPTS,
    int(os.getenv("AUTH_RATE_LIMIT_PEER_ATTEMPTS", "40")),
)
AUTH_RATE_LIMIT_WINDOW_SECONDS = max(
    60, int(os.getenv("AUTH_RATE_LIMIT_WINDOW_SECONDS", "900"))
)
_LOGIN_FAILURES: dict[str, list[float]] = {}
_LOGIN_FAILURES_LOCK = threading.Lock()
# A fixed bcrypt hash makes an unknown identifier cost roughly the same as a
# known one, reducing account-discovery through response timing.
_DUMMY_PASSWORD_HASH = passwords.hash(secrets.token_urlsafe(32))
MODULE_CATALOG = (
    ("students", "Élèves"),
    ("teachers", "Enseignants"),
    ("classes", "Classes"),
    ("subjects", "Matières"),
    ("affectations", "Affectations"),
    ("academic_years", "Années scolaires"),
    ("grades", "Notes & Évaluations"),
    ("attendance", "Absences & Retards"),
    ("behavior", "Comportement"),
    ("schedule", "Emploi du temps"),
    ("assignments", "Devoirs"),
    ("finance", "Finance"),
    ("documents", "Documents"),
    ("statistics", "Statistiques"),
)
MODULE_CATALOG = tuple(
    (module_id, 'Présences & Absences' if module_id == 'attendance' else label)
    for module_id, label in MODULE_CATALOG
)
MODULE_IDS = {module_id for module_id, _ in MODULE_CATALOG}
MODULE_GROUP_BY_ID = {
    **{module_id: "Scolarité" for module_id in (
        "students", "teachers", "classes", "subjects", "affectations",
        "academic_years", "schedule", "assignments",
    )},
    "grades": "Notes & résultats",
    "statistics": "Notes & résultats",
    "attendance": "Présence",
    "behavior": "Comportement",
    "finance": "Finance",
    "documents": "Documents",
}

# Fine-grained, user-facing capabilities are stored in the existing plan
# ``limits`` JSON. This keeps module activation backward-compatible and avoids
# a schema migration.
PLAN_CAPABILITY_GROUPS = {
    "Notes & résultats": (
        ("grades.publish_teacher", "Résultats visibles par les enseignants"),
        ("grades.publish_parent", "Résultats visibles par les parents"),
        ("grades.publish_student", "Résultats visibles par les élèves"),
    ),
    "Documents": (
        ("documents.advanced_search", "Historique et recherches avancées"),
    ),
    "Parents / Élèves": (
        ("parents.access", "Espace parent"),
        ("students.access", "Espace élève Collège/Lycée"),
    ),
}
PLAN_CAPABILITY_IDS = {
    capability_id
    for entries in PLAN_CAPABILITY_GROUPS.values()
    for capability_id, _ in entries
}
SUPERADMIN_RESTRICTED_MODULES = {"attendance", "behavior"}
RESOURCE_MODULE_BY_KIND = {
    "academic-years": "academic_years",
    "students": "students",
    "student-registrations": "students",
    "annual-decisions": "students",
    "re-enrollment-requests": "students",
    "teachers": "teachers",
    "classes": "classes",
    "school-levels": "classes",
    "series": "classes",
    "subjects": "subjects",
    "affectations": "affectations",
    "evaluations": "grades",
    "grades": "grades",
    "annual-bulletins": "grades",
    "absences": "attendance",
    "behavior-assessments": "behavior",
    "assignments": "assignments",
    "announcements": "messages",
    "conversations": "messages",
    # Internal, role-targeted workflow alerts are part of the platform shell.
    # They must remain available even though the former Communication module
    # (announcements/conversations/external broadcasts) is intentionally gone.
    "notifications": None,
    "documents": "documents",
    "finance-fees": "finance",
    "finance-registrations": "finance",
    "finance-fee-assignments": "finance",
    "finance-payments": "finance",
    "finance-receipts": "finance",
    "financial-accounts": "finance",
    "financial-lines": "finance",
    "financial-payment-records": "finance",
}
CYCLE_CATALOG = (
    ("MATERNELLE", "Maternelle", 10),
    ("PRIMAIRE", "Primaire", 20),
    ("COLLEGE", "Collège", 30),
    ("LYCEE", "Lycée", 40),
)
CYCLE_CATALOG_BY_CODE = {
    code: {"code": code, "name": name, "sortOrder": sort_order}
    for code, name, sort_order in CYCLE_CATALOG
}

BASE_LEVEL_CATALOG = {
    "MATERNELLE": (
        ("GARDERIE", "Garderie"), ("P1", "P1"), ("P2", "P2"), ("P3", "P3"),
    ),
    "PRIMAIRE": (
        ("CP1", "CP1"), ("CP2", "CP2"), ("CE1", "CE1"),
        ("CE2", "CE2"), ("CM1", "CM1"), ("CM2", "CM2"),
    ),
    "COLLEGE": (
        ("6E", "6e"), ("5E", "5e"), ("4E", "4e"), ("3E", "3e"),
    ),
    "LYCEE": (
        ("SECONDE", "Seconde"), ("PREMIERE", "Première"),
        ("TERMINALE", "Terminale"),
    ),
}
BASE_LYCEE_SERIES = (("A", "A"), ("C", "C"), ("D", "D"), ("G2", "G2"))
BASE_GENERAL_SUBJECTS = (
    ("FRANCAIS", "Français"), ("ANGLAIS", "Anglais"),
    ("MATHEMATIQUES", "Mathématiques"),
    ("HISTOIRE_GEOGRAPHIE", "Histoire-Géographie"),
    ("SVT", "Sciences de la Vie et de la Terre"),
    ("PHYSIQUE_CHIMIE", "Physique-Chimie"),
    ("EPS", "Éducation Physique et Sportive"),
    ("PHILOSOPHIE", "Philosophie"),
)
BASE_PRIMARY_SUBJECTS = (
    ("FRANCAIS", "Français"), ("MATHEMATIQUES", "Mathématiques"),
    ("SCIENCES", "Sciences"), ("HISTOIRE", "Histoire"),
    ("GEOGRAPHIE", "Géographie"),
    ("EDUCATION_CIVIQUE", "Éducation civique"),
    ("ANGLAIS", "Anglais"),
    ("EPS", "Éducation Physique et Sportive"),
)
BASE_PRESCHOOL_DOMAINS = (
    ("LANGAGE", "Langage"), ("COMMUNICATION", "Communication"),
    ("DEVELOPPEMENT_MOTEUR", "Développement moteur"),
    ("DECOUVERTE_MONDE", "Découverte du monde"),
    ("ACTIVITES_ARTISTIQUES", "Activités artistiques"),
    ("VIE_SOCIALE_AUTONOMIE", "Vie sociale / autonomie"),
)
BASE_SUBJECT_CATALOG = tuple(dict.fromkeys(
    (*BASE_GENERAL_SUBJECTS, *BASE_PRIMARY_SUBJECTS, *BASE_PRESCHOOL_DOMAINS)
))

def canonical_cycle_code(value: Any) -> str | None:
    normalized = str(value or "").strip().lower()
    return {
        "maternelle": "MATERNELLE",
        "preschool": "MATERNELLE",
        "kindergarten": "MATERNELLE",
        "primaire": "PRIMAIRE",
        "primary": "PRIMAIRE",
        "collège": "COLLEGE",
        "college": "COLLEGE",
        "lycée": "LYCEE",
        "lycee": "LYCEE",
        "high_school": "LYCEE",
    }.get(normalized)

def generate_initial_password() -> str:
    return secrets.token_urlsafe(18)

def validate_new_password(value: str) -> None:
    if not PASSWORD_MIN_LENGTH <= len(value) <= 128:
        raise HTTPException(
            422,
            f"Le mot de passe doit contenir entre {PASSWORD_MIN_LENGTH} et 128 caractères.",
        )
    checks = (
        re.search(r"[a-z]", value),
        re.search(r"[A-Z]", value),
        re.search(r"\d", value),
        re.search(r"[^A-Za-z0-9]", value),
    )
    if not all(checks):
        raise HTTPException(
            422,
            "Le mot de passe doit contenir une minuscule, une majuscule, un chiffre et un caractère spécial.",
        )

class Base(DeclarativeBase): pass
class User(Base):
    __tablename__ = "users"
    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    email: Mapped[str] = mapped_column(String, unique=True, index=True)
    password_hash: Mapped[str] = mapped_column(Text)
    name: Mapped[str] = mapped_column(String)
    role: Mapped[str] = mapped_column(String)
    school_id: Mapped[uuid.UUID | None] = mapped_column("establishment_id", UUID(as_uuid=True), index=True)
    direction_id: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True), index=True)
    status: Mapped[str] = mapped_column(String, default="active")
    password_set: Mapped[bool] = mapped_column(default=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))
class Establishment(Base):
    __tablename__ = "establishments"
    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    name: Mapped[str] = mapped_column(String)
    institution_type: Mapped[str] = mapped_column(String)
    type_label: Mapped[str | None] = mapped_column(String)
    address: Mapped[str | None] = mapped_column(Text)
    city: Mapped[str] = mapped_column(String)
    country: Mapped[str | None] = mapped_column(String)
    phone: Mapped[str | None] = mapped_column(String)
    email: Mapped[str | None] = mapped_column(String)
    status: Mapped[str] = mapped_column(String, default="active")
    enabled_modules: Mapped[list] = mapped_column(JSON, default=list)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))
class SchoolCycle(Base):
    __tablename__ = "school_cycles"
    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    establishment_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), index=True)
    code: Mapped[str] = mapped_column(String(32))
    name: Mapped[str] = mapped_column(String(80))
    status: Mapped[str] = mapped_column(String(16), default="active")
    sort_order: Mapped[int] = mapped_column(Integer, default=0)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))
class SchoolDirection(Base):
    __tablename__ = "school_directions"
    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    establishment_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), index=True)
    code: Mapped[str] = mapped_column(String(64))
    name: Mapped[str] = mapped_column(String(120))
    status: Mapped[str] = mapped_column(String(16), default="active")
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))
class SchoolDirectionCycle(Base):
    __tablename__ = "school_direction_cycles"
    direction_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True)
    establishment_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), index=True)
    cycle_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, index=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))
class SchoolLevel(Base):
    __tablename__ = "school_levels"
    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    establishment_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), index=True)
    cycle_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), index=True)
    code: Mapped[str] = mapped_column(String(40))
    name: Mapped[str] = mapped_column(String(80))
    status: Mapped[str] = mapped_column(String(16), default="active")
    sort_order: Mapped[int] = mapped_column(Integer, default=0)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))
class AcademicYear(Base):
    __tablename__ = "academic_years"
    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    establishment_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), index=True)
    name: Mapped[str] = mapped_column(String(100))
    start_date: Mapped[date] = mapped_column(Date)
    end_date: Mapped[date] = mapped_column(Date)
    is_active: Mapped[bool] = mapped_column(Boolean, default=False)
    status: Mapped[str] = mapped_column(String(50), default="inactive")
    created_at: Mapped[datetime] = mapped_column(DateTime, default=lambda: datetime.now(timezone.utc))
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=lambda: datetime.now(timezone.utc))
class SchoolSeries(Base):
    __tablename__ = 'school_series'
    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    establishment_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), index=True)
    cycle_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), index=True)
    code: Mapped[str] = mapped_column(String(32))
    name: Mapped[str] = mapped_column(String(100))
    description: Mapped[str | None] = mapped_column(Text)
    sort_order: Mapped[int] = mapped_column(Integer, default=0)
    status: Mapped[str] = mapped_column(String(20), default='active')
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))
class SchoolClass(Base):
    __tablename__ = "classes"
    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    establishment_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), index=True)
    academic_year_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), index=True)
    name: Mapped[str] = mapped_column(String(100))
    level: Mapped[str | None] = mapped_column(String(50))
    capacity: Mapped[int | None] = mapped_column(Integer)
    status: Mapped[str] = mapped_column(String(50), default="active")
    created_at: Mapped[datetime] = mapped_column(DateTime, default=lambda: datetime.now(timezone.utc))
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=lambda: datetime.now(timezone.utc))
    cycle_id: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True), index=True)
    school_level_id: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True), index=True)
    series_id: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True), index=True)
    main_teacher_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True), index=True
    )
class Teacher(Base):
    __tablename__ = "teachers"
    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    establishment_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), index=True)
    created_direction_id: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True), index=True)
    user_id: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True), index=True)
    first_name: Mapped[str] = mapped_column(String(100))
    last_name: Mapped[str] = mapped_column(String(100))
    employee_number: Mapped[str | None] = mapped_column(String(50))
    specialization: Mapped[str | None] = mapped_column(String(100))
    email: Mapped[str | None] = mapped_column(String(254))
    phone: Mapped[str | None] = mapped_column(String(32))
    gender: Mapped[str | None] = mapped_column(String(16))
    birth_date: Mapped[date | None] = mapped_column(Date)
    address: Mapped[str | None] = mapped_column(Text)
    diploma: Mapped[str | None] = mapped_column(String(150))
    hire_date: Mapped[date | None] = mapped_column(Date)
    status: Mapped[str] = mapped_column(String(50), default="active")
    created_at: Mapped[datetime] = mapped_column(DateTime, default=lambda: datetime.now(timezone.utc))
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=lambda: datetime.now(timezone.utc))
class Subject(Base):
    __tablename__ = "subjects"
    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    establishment_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), index=True)
    name: Mapped[str] = mapped_column(String(100))
    code: Mapped[str | None] = mapped_column(String(50))
    description: Mapped[str | None] = mapped_column(Text)
    status: Mapped[str] = mapped_column(String(50), default="active")
    created_at: Mapped[datetime] = mapped_column(DateTime, default=lambda: datetime.now(timezone.utc))
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=lambda: datetime.now(timezone.utc))
class Affectation(Base):
    __tablename__ = "affectations"
    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    establishment_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), index=True)
    teacher_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), index=True)
    class_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), index=True)
    subject_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), index=True)
    status: Mapped[str] = mapped_column(String(50), default="active")
    created_at: Mapped[datetime] = mapped_column(DateTime, default=lambda: datetime.now(timezone.utc))
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=lambda: datetime.now(timezone.utc))
class SubjectLevelSetting(Base):
    __tablename__ = "subject_level_settings"
    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    establishment_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), index=True)
    subject_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), index=True)
    school_level_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), index=True)
    academic_year_id: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True), index=True)
    series_id: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True), index=True)
    coefficient: Mapped[Any | None] = mapped_column(Numeric(6, 2))
    grading_scale: Mapped[Any] = mapped_column(Numeric(6, 2), default=20)
    contributes_to_average: Mapped[bool] = mapped_column(Boolean, default=True)
    status: Mapped[str] = mapped_column(String(20), default="active")
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))
class AcademicPeriod(Base):
    __tablename__ = "academic_periods"
    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    establishment_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), index=True)
    academic_year_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), index=True)
    parent_period_id: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True), index=True)
    code: Mapped[str] = mapped_column(String(32))
    name: Mapped[str] = mapped_column(String(80))
    period_type: Mapped[str] = mapped_column(String(20))
    sort_order: Mapped[int] = mapped_column(Integer, default=0)
    start_date: Mapped[date | None] = mapped_column(Date)
    end_date: Mapped[date | None] = mapped_column(Date)
    status: Mapped[str] = mapped_column(String(20), default="active")
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))
class EvaluationProgram(Base):
    __tablename__ = "evaluation_programs"
    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    establishment_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), index=True)
    academic_year_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), index=True)
    academic_period_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), index=True)
    name: Mapped[str] = mapped_column(String(100))
    type: Mapped[str] = mapped_column(String(50))
    exam_code: Mapped[str | None] = mapped_column(String(30))
    date_scheduled: Mapped[date | None] = mapped_column(Date)
    max_value: Mapped[float] = mapped_column(Float, default=20)
    description: Mapped[str | None] = mapped_column(Text)
    status: Mapped[str] = mapped_column(String(20), default="active")
    created_by: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))
class EvaluationProgramClass(Base):
    __tablename__ = "evaluation_program_classes"
    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    establishment_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), index=True)
    program_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), index=True)
    class_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), index=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))
class Evaluation(Base):
    __tablename__ = "evaluations"
    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    establishment_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), index=True)
    class_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), index=True)
    subject_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), index=True)
    name: Mapped[str] = mapped_column(String(100))
    type: Mapped[str] = mapped_column(String(50))
    exam_code: Mapped[str | None] = mapped_column(String(30))
    period: Mapped[str] = mapped_column(String(50))
    date_scheduled: Mapped[date | None] = mapped_column(Date)
    max_value: Mapped[float] = mapped_column(Float)
    status: Mapped[str] = mapped_column(String(50), default="draft")
    description: Mapped[str | None] = mapped_column(Text)
    academic_year_id: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True), index=True)
    academic_period_id: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True), index=True)
    affectation_id: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True), index=True)
    program_id: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True), index=True)
    created_by: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True))
    submitted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    validated_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    validated_by: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True))
    rejected_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    rejected_by: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True))
    rejection_reason: Mapped[str | None] = mapped_column(Text)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=lambda: datetime.now(timezone.utc))
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=lambda: datetime.now(timezone.utc))
class Grade(Base):
    __tablename__ = "grades"
    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    establishment_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), index=True)
    student_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), index=True)
    evaluation_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), index=True)
    class_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), index=True)
    subject_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), index=True)
    teacher_id: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True), index=True)
    affectation_id: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True), index=True)
    value: Mapped[float | None] = mapped_column(Float)
    max_value: Mapped[float] = mapped_column(Float)
    presence: Mapped[str] = mapped_column(String(20), default="present")
    entered_by: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True))
    comment: Mapped[str | None] = mapped_column(Text)
    status: Mapped[str] = mapped_column(String(50), default="draft")
    created_at: Mapped[datetime] = mapped_column(DateTime, default=lambda: datetime.now(timezone.utc))
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=lambda: datetime.now(timezone.utc))
class ResultCalculation(Base):
    __tablename__ = "result_calculations"
    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    establishment_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), index=True)
    academic_year_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), index=True)
    class_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), index=True)
    academic_period_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), index=True)
    status: Mapped[str] = mapped_column(String(20), default="official")
    payload: Mapped[dict[str, Any]] = mapped_column(JSONB)
    source_updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    calculated_by: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True))
    calculated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))
class EvaluationStatusEvent(Base):
    __tablename__ = "evaluation_status_events"
    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    establishment_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), index=True)
    evaluation_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), index=True)
    actor_user_id: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True))
    from_status: Mapped[str | None] = mapped_column(String(50))
    to_status: Mapped[str] = mapped_column(String(50))
    reason: Mapped[str | None] = mapped_column(Text)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))
class AttendanceRecord(Base):
    __tablename__ = "attendance_records"
    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    establishment_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), index=True)
    student_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), index=True)
    class_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), index=True)
    academic_year_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), index=True)
    schedule_entry_id: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True), index=True)
    teacher_id: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True), index=True)
    subject_id: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True), index=True)
    attendance_date: Mapped[date] = mapped_column(Date)
    status: Mapped[str] = mapped_column(String(20))
    note: Mapped[str | None] = mapped_column(Text)
    sheet_id: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True))
    recorded_by: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))
class AttendanceSheet(Base):
    __tablename__ = "attendance_sheets"
    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    establishment_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True))
    academic_year_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True))
    schedule_entry_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True))
    class_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True))
    teacher_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True))
    subject_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True))
    attendance_date: Mapped[date] = mapped_column(Date)
    status: Mapped[str] = mapped_column(String(16), default="draft")
    context_snapshot: Mapped[dict] = mapped_column(JSONB)
    expected_students: Mapped[list] = mapped_column(JSONB)
    submitted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))

class BehaviorEvent(Base):
    __tablename__ = "behavior_events"
    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    establishment_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), index=True)
    student_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), index=True)
    class_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), index=True)
    academic_year_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), index=True)
    academic_period_id: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True), index=True)
    event_date: Mapped[date] = mapped_column(Date)
    category: Mapped[str] = mapped_column(String(50))
    event_type: Mapped[str] = mapped_column(String(20))
    severity: Mapped[str] = mapped_column(String(20), default="normal")
    title: Mapped[str] = mapped_column(String(120))
    description: Mapped[str | None] = mapped_column(Text)
    recorded_by: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True))
    teacher_id: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True))
    status: Mapped[str] = mapped_column(String(20), default="active")
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))
class BehaviorCalculation(Base):
    __tablename__ = "behavior_calculations"
    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    establishment_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True))
    academic_year_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True))
    class_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True))
    academic_period_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True))
    source_fingerprint: Mapped[str] = mapped_column(String(64))
    payload: Mapped[dict[str, Any]] = mapped_column(JSONB)
    calculated_by: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True))
    calculated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))

class SchoolAssignment(Base):
    __tablename__ = "school_assignments"
    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    establishment_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), index=True)
    academic_year_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), index=True)
    class_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), index=True)
    subject_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), index=True)
    teacher_id: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True), index=True)
    affectation_id: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True), index=True)
    title: Mapped[str] = mapped_column(String(150))
    description: Mapped[str | None] = mapped_column(Text)
    assigned_date: Mapped[date] = mapped_column(Date)
    due_date: Mapped[date] = mapped_column(Date)
    max_score: Mapped[Any | None] = mapped_column(Numeric(8, 2))
    status: Mapped[str] = mapped_column(String(20), default="published")
    created_by: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))
class ScheduleEntry(Base):
    __tablename__ = "schedule_entries"
    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    establishment_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), index=True)
    academic_year_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), index=True)
    class_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), index=True)
    subject_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), index=True)
    teacher_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), index=True)
    affectation_id: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True), index=True)
    weekday: Mapped[int] = mapped_column(Integer)
    start_time: Mapped[dt_time] = mapped_column(Time)
    end_time: Mapped[dt_time] = mapped_column(Time)
    room: Mapped[str | None] = mapped_column(String(80))
    status: Mapped[str] = mapped_column(String(20), default="active")
    retired_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    attendance_context: Mapped[dict | None] = mapped_column(JSONB)
    created_by: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))
class Student(Base):
    __tablename__ = "students"
    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    establishment_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), index=True)
    created_direction_id: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True), index=True)
    user_id: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True), index=True)
    first_name: Mapped[str] = mapped_column(String(100))
    last_name: Mapped[str] = mapped_column(String(100))
    registration_number: Mapped[str | None] = mapped_column(String(50))
    birth_date: Mapped[date | None] = mapped_column(Date)
    nationality: Mapped[str | None] = mapped_column(String(100))
    gender: Mapped[str | None] = mapped_column(String(10))
    email: Mapped[str | None] = mapped_column(String(254))
    phone: Mapped[str | None] = mapped_column(String(32))
    address: Mapped[str | None] = mapped_column(Text)
    status: Mapped[str] = mapped_column(String(50), default="active")
    created_at: Mapped[datetime] = mapped_column(DateTime, default=lambda: datetime.now(timezone.utc))
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=lambda: datetime.now(timezone.utc))
class StudentAcademicRegistration(Base):
    __tablename__ = "student_academic_registrations"
    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    establishment_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), index=True)
    student_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), index=True)
    class_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), index=True)
    academic_year_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), index=True)
    registration_date: Mapped[date] = mapped_column(Date, default=date.today)
    registration_number: Mapped[str | None] = mapped_column(String(50))
    school_regime: Mapped[str] = mapped_column(String(20), default='normal')
    has_td: Mapped[bool] = mapped_column(Boolean, default=False)
    options: Mapped[dict[str, Any]] = mapped_column(JSONB, default=dict)
    status: Mapped[str] = mapped_column(String(50), default="validated")
    created_at: Mapped[datetime] = mapped_column(DateTime, default=lambda: datetime.now(timezone.utc))
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=lambda: datetime.now(timezone.utc))
class StudentRegimeHistory(Base):
    __tablename__ = "student_regime_history"
    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    establishment_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), index=True)
    registration_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), index=True)
    student_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), index=True)
    school_regime: Mapped[str] = mapped_column(String(20))
    effective_date: Mapped[date] = mapped_column(Date)
    end_date: Mapped[date | None] = mapped_column(Date)
    created_by: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))

class GuardianPerson(Base):
    __tablename__ = 'guardian_people'
    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True), index=True)
    first_name: Mapped[str] = mapped_column(String(100))
    last_name: Mapped[str] = mapped_column(String(100))
    phone: Mapped[str | None] = mapped_column(String(32))
    second_phone: Mapped[str | None] = mapped_column(String(32))
    email: Mapped[str | None] = mapped_column(String(254))
    address: Mapped[str | None] = mapped_column(Text)
    profession: Mapped[str | None] = mapped_column(String(150))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))
class Guardian(Base):
    __tablename__ = "guardians"
    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    establishment_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), index=True)
    created_direction_id: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True), index=True)
    user_id: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True), index=True)
    person_id: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True), index=True)
    first_name: Mapped[str] = mapped_column(String(100))
    last_name: Mapped[str] = mapped_column(String(100))
    phone: Mapped[str | None] = mapped_column(String(32))
    second_phone: Mapped[str | None] = mapped_column(String(32))
    email: Mapped[str | None] = mapped_column(String(254))
    address: Mapped[str | None] = mapped_column(Text)
    profession: Mapped[str | None] = mapped_column(String(150))
    status: Mapped[str] = mapped_column(String(20), default="active")
    created_at: Mapped[datetime] = mapped_column(DateTime, default=lambda: datetime.now(timezone.utc))
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=lambda: datetime.now(timezone.utc))
class StudentGuardian(Base):
    __tablename__ = "student_guardians"
    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    establishment_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), index=True)
    student_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), index=True)
    guardian_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), index=True)
    relationship: Mapped[str] = mapped_column(String(50))
    is_primary: Mapped[bool] = mapped_column(Boolean, default=False)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=lambda: datetime.now(timezone.utc))
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=lambda: datetime.now(timezone.utc))
class StudentClassTransfer(Base):
    __tablename__ = 'student_class_transfers'
    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    establishment_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), index=True)
    registration_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), index=True)
    student_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), index=True)
    academic_year_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), index=True)
    from_class_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True))
    to_class_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True))
    effective_date: Mapped[date] = mapped_column(Date)
    reason: Mapped[str | None] = mapped_column(Text)
    grade_handling_decision: Mapped[str | None] = mapped_column(String(30))
    created_by: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))
class StudentPreEnrollment(Base):
    __tablename__ = "student_pre_enrollments"
    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    establishment_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), index=True)
    student_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), index=True)
    academic_year_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), index=True)
    desired_class_id: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True), index=True)
    desired_school_regime: Mapped[str | None] = mapped_column(String(20))
    status: Mapped[str] = mapped_column(String(20), default="draft")
    submitted_at: Mapped[datetime | None] = mapped_column(DateTime)
    decided_at: Mapped[datetime | None] = mapped_column(DateTime)
    decision_note: Mapped[str | None] = mapped_column(Text)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=lambda: datetime.now(timezone.utc))
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=lambda: datetime.now(timezone.utc))
class SchoolCalendarSetting(Base):
    __tablename__ = 'school_calendar_settings'
    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    establishment_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), index=True)
    academic_year_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), index=True)
    teaching_days: Mapped[list[int]] = mapped_column(JSONB, default=lambda: [1, 2, 3, 4, 5])
    day_start: Mapped[dt_time] = mapped_column(Time, default=dt_time(7, 0))
    day_end: Mapped[dt_time] = mapped_column(Time, default=dt_time(17, 0))
    course_duration_minutes: Mapped[int] = mapped_column(Integer, default=60)
    pause_duration_minutes: Mapped[int] = mapped_column(Integer, default=15)
    pause_frequency: Mapped[int] = mapped_column(Integer, default=2)
    status: Mapped[str] = mapped_column(String(20), default='active')
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))
class SchoolCalendarEvent(Base):
    __tablename__ = 'school_calendar_events'
    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    establishment_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), index=True)
    academic_year_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), index=True)
    academic_period_id: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True), index=True)
    title: Mapped[str] = mapped_column(String(150))
    event_type: Mapped[str] = mapped_column(String(50))
    start_date: Mapped[date] = mapped_column(Date)
    end_date: Mapped[date] = mapped_column(Date)
    description: Mapped[str | None] = mapped_column(Text)
    status: Mapped[str] = mapped_column(String(20), default='active')
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))
class EvaluationRule(Base):
    __tablename__ = 'evaluation_rules'
    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    establishment_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), index=True)
    academic_year_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), index=True)
    cycle_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), index=True)
    school_level_id: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True), index=True)
    series_id: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True), index=True)
    evaluation_type: Mapped[str] = mapped_column(String(30))
    label: Mapped[str] = mapped_column(String(100))
    expected_count: Mapped[int | None] = mapped_column(Integer)
    contributes_to_average: Mapped[bool] = mapped_column(Boolean, default=True)
    is_required: Mapped[bool] = mapped_column(Boolean, default=False)
    sort_order: Mapped[int] = mapped_column(Integer, default=0)
    status: Mapped[str] = mapped_column(String(20), default='active')
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))
class StudentAnnualDecision(Base):
    __tablename__ = 'student_annual_decisions'
    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    establishment_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), index=True)
    student_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), index=True)
    academic_year_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), index=True)
    decision: Mapped[str] = mapped_column(String(20))
    reason: Mapped[str | None] = mapped_column(Text)
    decided_by: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True))
    decided_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))
class Resource(Base):
    __tablename__ = "api_resources"
    id: Mapped[str] = mapped_column(String, primary_key=True)
    kind: Mapped[str] = mapped_column(String, primary_key=True)
    school_id: Mapped[str | None] = mapped_column(String, index=True)
    establishment_id: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True), index=True)
    cycle_id: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True), index=True)
    school_level_id: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True), index=True)
    academic_year_id: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True), index=True)
    payload: Mapped[dict[str, Any]] = mapped_column(JSONB)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc), onupdate=lambda: datetime.now(timezone.utc))

class LoginInput(BaseModel):
    model_config = ConfigDict(extra="forbid")
    identifier: str | None = Field(default=None, min_length=1, max_length=254)
    email: str | None = Field(default=None, min_length=3, max_length=254)
    password: str = Field(min_length=1, max_length=128)

    @field_validator("identifier", "email", mode="before")
    @classmethod
    def normalize_identifier(cls, value):
        return value.strip().lower() if isinstance(value, str) else value

    @model_validator(mode="after")
    def require_one_identifier(self):
        if not (self.identifier or self.email):
            raise ValueError("Le matricule, le téléphone ou l’adresse e-mail est obligatoire")
        if self.identifier and self.email and self.identifier != self.email:
            raise ValueError("Utilisez un seul identifiant de connexion")
        self.identifier = self.identifier or self.email
        return self
class ChangePasswordInput(BaseModel):
    current_password: str | None = Field(default=None, min_length=1)
    new_password: str = Field(min_length=1, max_length=128)
    new_password_confirmation: str = Field(min_length=1, max_length=128)

class ProfileUpdateInput(BaseModel):
    model_config = ConfigDict(extra="forbid")
    name: str = Field(min_length=2, max_length=160)
    email: str = Field(min_length=3, max_length=254)

    @model_validator(mode="after")
    def normalize_profile(self):
        self.name = self.name.strip()
        self.email = self.email.strip().lower()
        if not re.fullmatch(r'[^\s@]+@[^\s@]+\.[^\s@]+', self.email):
            raise ValueError("Adresse e-mail invalide")
        return self
class ResourceInput(BaseModel): payload: dict[str, Any]
class FinanceFeeInput(BaseModel):
    model_config = ConfigDict(extra="forbid")
    name: str = Field(min_length=2, max_length=160)
    amount: int = Field(gt=0, le=1_000_000_000)
    scope: Literal["establishment", "cycle", "level", "class"] = "establishment"
    cycle: str | None = Field(default=None, max_length=80)
    levelId: str | None = None
    classId: str | None = None
    academicYearId: str
    description: str = Field(default="", max_length=1000)
    type: Literal["registration", "reenrollment", "tuition", "td", "other"] = "tuition"
    frequency: Literal["once", "monthly", "annual"] = "monthly"
    month: str | None = Field(default=None, pattern=r"^\d{4}-\d{2}$")
    schoolRegime: Literal["part_time", "full_time"] | None = None
    schoolId: str | None = None

    @model_validator(mode="after")
    def validate_school_regime_tariff(self):
        if self.schoolRegime is not None and self.type != "tuition":
            raise ValueError("Le régime ne peut être associé qu'aux frais mensuels")
        return self

class FinancePaymentInput(BaseModel):
    model_config = ConfigDict(extra="forbid")
    registrationId: str
    feeAssignmentId: str
    amount: int = Field(gt=0, le=1_000_000_000)
    paymentMethod: Literal["cash", "mobile", "transfer", "card", "other"] = "cash"
    reference: str | None = Field(default=None, max_length=160)
    note: str | None = Field(default=None, max_length=1000)
    schoolId: str | None = None

class FinanceCancelInput(BaseModel):
    model_config = ConfigDict(extra="forbid")
    reason: str = Field(min_length=3, max_length=1000)
    @field_validator('reason', mode='before')
    @classmethod
    def trim_reason(cls, value):
        return value.strip() if isinstance(value, str) else value
class DocumentCreateInput(BaseModel):
    model_config = ConfigDict(extra="forbid")
    title: str = Field(min_length=2, max_length=180)
    type: Literal[
        "student_record", "registration", "class_list", "teacher_record",
        "teacher_assignments", "schedule", "attendance", "behavior",
        "official_results", "financial_statement", "payment_receipt",
        "unpaid_report", "collection_report",
    ]
    entityId: str | None = None
    academicYearId: str | None = None
    metadata: dict[str, Any] = Field(default_factory=dict)
    schoolId: str | None = None
class AdminEstablishmentUpdateInput(BaseModel):
    model_config = ConfigDict(extra="forbid")
    address: str | None = Field(default=None, max_length=500)
    country: str | None = Field(default=None, max_length=120)
    phone: str | None = Field(default=None, max_length=32)
    email: str | None = Field(default=None, max_length=254)

    @field_validator("address", "country", "phone", "email", mode="before")
    @classmethod
    def trim_optional_fields(cls, value: Any) -> Any:
        if isinstance(value, str):
            value = value.strip()
            return value or None
        return value

    @field_validator("email")
    @classmethod
    def validate_email(cls, value: str | None) -> str | None:
        if value and not re.fullmatch(r"[^\s@]+@[^\s@]+\.[^\s@]+", value):
            raise ValueError("Adresse e-mail invalide")
        return value.lower() if value else None

    @field_validator("phone")
    @classmethod
    def validate_phone(cls, value: str | None) -> str | None:
        if value and not re.fullmatch(r"\+?[0-9][0-9 .()\-]{5,30}", value):
            raise ValueError("Numéro de téléphone invalide")
        return value
class ReactionInput(BaseModel): reaction: Literal["like", "acknowledge", "important"]
class UserCreateInput(BaseModel):
    name: str = Field(min_length=2, max_length=160)
    email: str = Field(min_length=3, max_length=254)
    role: Literal["admin", "teacher", "student", "parent"]
    establishment_id: str | None = None
    direction_id: uuid.UUID | None = None
class AdminAccountStatusInput(BaseModel):
    status: Literal["active", "suspended"]
class SchoolDirectionInput(BaseModel):
    model_config = ConfigDict(populate_by_name=True, extra="forbid")
    name: str = Field(min_length=2, max_length=120)
    code: str | None = Field(default=None, max_length=64)
    cycle_ids: list[uuid.UUID] = Field(alias="cycleIds", min_length=1)
    status: Literal["active", "inactive"] = "active"
class SchoolDirectionUpdateInput(BaseModel):
    model_config = ConfigDict(populate_by_name=True, extra="forbid")
    name: str | None = Field(default=None, min_length=2, max_length=120)
    cycle_ids: list[uuid.UUID] | None = Field(default=None, alias="cycleIds", min_length=1)
    status: Literal["active", "inactive"] | None = None
class DirectionAdministratorInput(BaseModel):
    model_config = ConfigDict(populate_by_name=True, extra="forbid")
    user_id: uuid.UUID | None = Field(default=None, alias="userId")
class PlanCreateInput(BaseModel):
    model_config = ConfigDict(extra="forbid")
    name: str = Field(min_length=2, max_length=80)
    description: str = Field(default="", max_length=1000)
    price: int = Field(ge=0, le=1_000_000_000)
    duration_days: int = Field(gt=0, le=3650)
    currency: Literal["FCFA"] = "FCFA"
    status: Literal["active", "inactive"] = "active"
    features: list[str] = Field(default_factory=list, max_length=len(MODULE_CATALOG))
    limits: dict[str, Any] = Field(default_factory=dict)

    @field_validator("name", "description", mode="before")
    @classmethod
    def trim_plan_text(cls, value: Any) -> Any:
        return value.strip() if isinstance(value, str) else value

    @model_validator(mode="before")
    @classmethod
    def accept_camel_duration(cls, value: Any) -> Any:
        if isinstance(value, dict) and "durationDays" in value:
            if "duration_days" in value:
                raise ValueError("La durée ne doit être fournie qu'une seule fois")
            value = {**value, "duration_days": value["durationDays"]}
            value.pop("durationDays", None)
        return value

    @field_validator("features")
    @classmethod
    def validate_plan_features(cls, values: list[str]) -> list[str]:
        if len(values) != len(set(values)):
            raise ValueError("Un module ne peut pas être sélectionné plusieurs fois")
        unknown = sorted(set(values) - MODULE_IDS)
        if unknown:
            raise ValueError(f"Modules inconnus: {', '.join(unknown)}")
        selected = set(values)
        return [module_id for module_id, _ in MODULE_CATALOG if module_id in selected]

    @field_validator("limits")
    @classmethod
    def validate_plan_limits(cls, value: dict[str, Any]) -> dict[str, Any]:
        capabilities = value.get("capabilities", [])
        if not isinstance(capabilities, list) or any(not isinstance(item, str) for item in capabilities):
            raise ValueError("Les capacités du plan sont invalides")
        unknown = sorted(set(capabilities) - PLAN_CAPABILITY_IDS)
        if unknown:
            raise ValueError(f"Capacités inconnues: {', '.join(unknown)}")
        if len(capabilities) != len(set(capabilities)):
            raise ValueError("Une capacité ne peut être sélectionnée plusieurs fois")
        return {**value, "capabilities": capabilities,
                "capabilitiesConfigured": bool(value.get("capabilitiesConfigured", False))}

class PlanUpdateInput(BaseModel):
    model_config = ConfigDict(extra="forbid")
    name: str | None = Field(default=None, min_length=2, max_length=80)
    description: str | None = Field(default=None, max_length=1000)
    price: int | None = Field(default=None, ge=0, le=1_000_000_000)
    duration_days: int | None = Field(default=None, gt=0, le=3650)
    currency: Literal["FCFA"] | None = None
    status: Literal["active", "inactive"] | None = None
    features: list[str] | None = Field(default=None, max_length=len(MODULE_CATALOG))
    limits: dict[str, Any] | None = None

    @field_validator("name", "description", mode="before")
    @classmethod
    def trim_plan_update_text(cls, value: Any) -> Any:
        return value.strip() if isinstance(value, str) else value

    @model_validator(mode="before")
    @classmethod
    def accept_camel_duration(cls, value: Any) -> Any:
        if isinstance(value, dict) and "durationDays" in value:
            if "duration_days" in value:
                raise ValueError("La durée ne doit être fournie qu'une seule fois")
            value = {**value, "duration_days": value["durationDays"]}
            value.pop("durationDays", None)
        return value

    @field_validator("features")
    @classmethod
    def validate_updated_features(cls, values: list[str] | None) -> list[str] | None:
        if values is None:
            return None
        if len(values) != len(set(values)):
            raise ValueError("Un module ne peut pas être sélectionné plusieurs fois")
        unknown = sorted(set(values) - MODULE_IDS)
        if unknown:
            raise ValueError(f"Modules inconnus: {', '.join(unknown)}")
        selected = set(values)
        return [module_id for module_id, _ in MODULE_CATALOG if module_id in selected]

    @field_validator("limits")
    @classmethod
    def validate_updated_plan_limits(cls, value: dict[str, Any] | None) -> dict[str, Any] | None:
        if value is None:
            return None
        return PlanCreateInput.validate_plan_limits(value)

class SubscriptionRenewInput(BaseModel):
    model_config = ConfigDict(populate_by_name=True, extra="forbid")
    plan: str = Field(min_length=2, max_length=80)
    start_date: date | None = Field(default=None, alias="startDate")

    @field_validator("plan", mode="before")
    @classmethod
    def trim_subscription_plan(cls, value: Any) -> Any:
        return value.strip() if isinstance(value, str) else value
class EstablishmentModulesInput(BaseModel):
    model_config = ConfigDict(extra="forbid")
    enabledModules: list[str] = Field(max_length=len(MODULE_CATALOG))

    @field_validator("enabledModules")
    @classmethod
    def validate_modules(cls, values: list[str]) -> list[str]:
        unknown = sorted(set(values) - MODULE_IDS)
        if unknown:
            raise ValueError(f"Modules inconnus: {', '.join(unknown)}")
        selected = set(values)
        return [module_id for module_id, _ in MODULE_CATALOG if module_id in selected]
class CycleCreateInput(BaseModel):
    model_config = ConfigDict(extra="forbid")
    school_id: str | None = None
    code: Literal["MATERNELLE", "PRIMAIRE", "COLLEGE", "LYCEE"]
    status: Literal["active", "inactive"] = "active"
    sort_order: int | None = Field(default=None, ge=0, le=1000)

    @model_validator(mode="before")
    @classmethod
    def accept_camel_fields(cls, value: Any) -> Any:
        if not isinstance(value, dict):
            return value
        value = dict(value)
        for source, target in (("schoolId", "school_id"), ("sortOrder", "sort_order")):
            if source in value:
                if target in value:
                    raise ValueError(f"Le champ {source} ne doit être fourni qu'une seule fois")
                value[target] = value.pop(source)
        return value

class CycleUpdateInput(BaseModel):
    model_config = ConfigDict(extra="forbid")
    status: Literal["active", "inactive"] | None = None
    sort_order: int | None = Field(default=None, ge=0, le=1000)

    @model_validator(mode="before")
    @classmethod
    def accept_camel_fields(cls, value: Any) -> Any:
        if isinstance(value, dict) and "sortOrder" in value:
            if "sort_order" in value:
                raise ValueError("Le champ sortOrder ne doit être fourni qu'une seule fois")
            value = {**value, "sort_order": value["sortOrder"]}
            value.pop("sortOrder", None)
        return value

class SchoolLevelCreateInput(BaseModel):
    model_config = ConfigDict(extra="forbid")
    school_id: str | None = None
    code: str = Field(min_length=1, max_length=40, pattern=r"^[A-Za-z0-9][A-Za-z0-9_-]*$")
    name: str = Field(min_length=1, max_length=80)
    status: Literal["active", "inactive"] = "active"
    sort_order: int = Field(default=0, ge=0, le=1000)

    @model_validator(mode="before")
    @classmethod
    def accept_camel_fields(cls, value: Any) -> Any:
        if not isinstance(value, dict):
            return value
        value = dict(value)
        for source, target in (("schoolId", "school_id"), ("sortOrder", "sort_order")):
            if source in value:
                if target in value:
                    raise ValueError(f"Le champ {source} ne doit être fourni qu'une seule fois")
                value[target] = value.pop(source)
        return value

    @field_validator("code", "name", mode="before")
    @classmethod
    def trim_level_text(cls, value: Any) -> Any:
        return value.strip() if isinstance(value, str) else value

    @field_validator("code")
    @classmethod
    def normalize_level_code(cls, value: str) -> str:
        return value.upper()

class SchoolLevelUpdateInput(BaseModel):
    model_config = ConfigDict(extra="forbid")
    code: str | None = Field(default=None, min_length=1, max_length=40, pattern=r"^[A-Za-z0-9][A-Za-z0-9_-]*$")
    name: str | None = Field(default=None, min_length=1, max_length=80)
    status: Literal["active", "inactive"] | None = None
    sort_order: int | None = Field(default=None, ge=0, le=1000)

    @model_validator(mode="before")
    @classmethod
    def accept_camel_fields(cls, value: Any) -> Any:
        if isinstance(value, dict) and "sortOrder" in value:
            if "sort_order" in value:
                raise ValueError("Le champ sortOrder ne doit être fourni qu'une seule fois")
            value = {**value, "sort_order": value["sortOrder"]}
            value.pop("sortOrder", None)
        return value

    @field_validator("code", "name", mode="before")
    @classmethod
    def trim_level_update_text(cls, value: Any) -> Any:
        return value.strip() if isinstance(value, str) else value

    @field_validator("code")
    @classmethod
    def normalize_updated_level_code(cls, value: str | None) -> str | None:
        return value.upper() if value else None
class AcademicYearCreateInput(BaseModel):
    model_config = ConfigDict(extra="forbid")
    school_id: str | None = None
    name: str = Field(min_length=1, max_length=100)
    start_date: date
    end_date: date

    @model_validator(mode="before")
    @classmethod
    def accept_camel_fields(cls, value: Any) -> Any:
        if not isinstance(value, dict):
            return value
        value = dict(value)
        for source, target in (("schoolId", "school_id"), ("start", "start_date"), ("end", "end_date")):
            if source in value:
                value[target] = value.pop(source)
        return value

    @model_validator(mode="after")
    def validate_dates(self):
        if self.end_date <= self.start_date:
            raise ValueError("La date de fin doit être postérieure à la date de début")
        self.name = self.name.strip()
        return self

class AcademicYearUpdateInput(AcademicYearCreateInput):
    school_id: str | None = None


class AcademicYearCopyConfigurationInput(BaseModel):
    model_config = ConfigDict(populate_by_name=True, extra="forbid")
    source_year_id: uuid.UUID = Field(alias="sourceYearId")


class SchoolClassInput(BaseModel):
    model_config = ConfigDict(extra="forbid")
    school_id: str | None = None
    academic_year_id: uuid.UUID
    cycle_id: uuid.UUID
    school_level_id: uuid.UUID
    name: str = Field(min_length=1, max_length=100)
    capacity: int | None = Field(default=None, ge=1, le=1000)
    status: Literal["active", "inactive"] = "active"

    @model_validator(mode="before")
    @classmethod
    def accept_camel_fields(cls, value: Any) -> Any:
        if not isinstance(value, dict):
            return value
        value = dict(value)
        for source, target in (
            ("schoolId", "school_id"),
            ("academicYearId", "academic_year_id"),
            ("cycleId", "cycle_id"),
            ("structuredLevelId", "school_level_id"),
            ("levelId", "school_level_id"),
        ):
            if source in value and target not in value:
                value[target] = value.pop(source)
            elif source in value:
                value.pop(source)
        return value

    @field_validator("name", mode="before")
    @classmethod
    def trim_name(cls, value: Any) -> Any:
        return value.strip() if isinstance(value, str) else value

class StudentIdentityInput(BaseModel):
    model_config = ConfigDict(populate_by_name=True, extra="forbid")
    first_name: str = Field(alias="firstName", min_length=1, max_length=100)
    last_name: str = Field(alias="lastName", min_length=1, max_length=100)
    birth_date: date | None = Field(default=None, alias="birthDate")
    gender: Literal["M", "F"] | None = None
    email: str | None = Field(default=None, max_length=254)
    phone: str | None = Field(default=None, max_length=32)
    address: str | None = Field(default=None, max_length=500)

    @field_validator("first_name", "last_name", "email", "phone", "address", mode="before")
    @classmethod
    def trim_student_fields(cls, value: Any) -> Any:
        if isinstance(value, str):
            value = value.strip()
            return value or None
        return value

    @field_validator("email")
    @classmethod
    def validate_student_email(cls, value: str | None) -> str | None:
        if value and not re.fullmatch(r"[^\s@]+@[^\s@]+\.[^\s@]+", value):
            raise ValueError("Adresse e-mail invalide")
        return value.lower() if value else None

    @field_validator("phone")
    @classmethod
    def validate_student_phone(cls, value: str | None) -> str | None:
        if value and not re.fullmatch(r"\+?[0-9][0-9 .()\-]{5,30}", value):
            raise ValueError("Numéro de téléphone invalide")
        return value

class StudentIdentityUpdateInput(BaseModel):
    model_config = ConfigDict(populate_by_name=True, extra="forbid")
    first_name: str | None = Field(default=None, alias="firstName", min_length=1, max_length=100)
    last_name: str | None = Field(default=None, alias="lastName", min_length=1, max_length=100)
    birth_date: date | None = Field(default=None, alias="birthDate")
    gender: Literal["M", "F"] | None = None
    email: str | None = Field(default=None, max_length=254)
    phone: str | None = Field(default=None, max_length=32)
    address: str | None = Field(default=None, max_length=500)
    status: Literal["active", "archived"] | None = None

    @field_validator("first_name", "last_name", "email", "phone", "address", mode="before")
    @classmethod
    def trim_student_update_fields(cls, value: Any) -> Any:
        if isinstance(value, str):
            value = value.strip()
            return value or None
        return value

class StudentRegistrationInput(BaseModel):
    model_config = ConfigDict(populate_by_name=True, extra="forbid")
    class_id: uuid.UUID = Field(alias="classId")
    registration_date: date = Field(default_factory=date.today, alias="registrationDate")

class StudentPreEnrollmentInput(BaseModel):
    model_config = ConfigDict(populate_by_name=True, extra="forbid")
    student_id: uuid.UUID | None = Field(default=None, alias="studentId")
    first_name: str | None = Field(default=None, alias="firstName", max_length=100)
    last_name: str | None = Field(default=None, alias="lastName", max_length=100)
    academic_year_id: uuid.UUID = Field(alias="academicYearId")
    desired_class_id: uuid.UUID = Field(alias="desiredClassId")
    registration_kind: Literal["registration", "reenrollment"] = Field(
        default="registration", alias="registrationKind"
    )
    school_regime: Literal['part_time', 'full_time'] | None = Field(
        default=None, alias='schoolRegime'
    )
    status: Literal["draft", "submitted"] = "draft"

    @model_validator(mode="after")
    def validate_candidate(self):
        if self.student_id is None:
            self.first_name = (self.first_name or "").strip()
            self.last_name = (self.last_name or "").strip()
            if not self.first_name or not self.last_name:
                raise ValueError("Le nom et le prénom sont obligatoires")
            if self.registration_kind == "reenrollment":
                raise ValueError("Sélectionnez l'ancien élève à réinscrire")
        return self

class StudentPreEnrollmentStatusInput(BaseModel):
    model_config = ConfigDict(populate_by_name=True, extra="forbid")
    status: Literal["draft", "submitted", "rejected", "cancelled"]
    decision_note: str | None = Field(default=None, alias="decisionNote", max_length=1000)

class StudentPreEnrollmentUpdateInput(BaseModel):
    model_config = ConfigDict(populate_by_name=True, extra="forbid")
    first_name: str = Field(alias="firstName", min_length=1, max_length=100)
    last_name: str = Field(alias="lastName", min_length=1, max_length=100)
    desired_class_id: uuid.UUID = Field(alias="desiredClassId")
    school_regime: Literal['part_time', 'full_time'] | None = Field(
        default=None, alias='schoolRegime'
    )

    @field_validator("first_name", "last_name", mode="before")
    @classmethod
    def trim_name(cls, value: Any) -> Any:
        return value.strip() if isinstance(value, str) else value

class StudentPreEnrollmentApprovalInput(BaseModel):
    school_regime: Literal['normal', 'part_time', 'full_time'] | None = Field(
        default=None, alias='schoolRegime'
    )
    has_td: bool = Field(default=False, alias='hasTd')
    options: dict[str, Any] = Field(default_factory=dict)
    model_config = ConfigDict(populate_by_name=True, extra="forbid")
    class_id: uuid.UUID | None = Field(default=None, alias="classId")
    registration_date: date = Field(default_factory=date.today, alias="registrationDate")

class GuardianInput(BaseModel):
    model_config = ConfigDict(populate_by_name=True, extra="forbid")
    first_name: str = Field(alias="firstName", min_length=1, max_length=100)
    last_name: str = Field(alias="lastName", min_length=1, max_length=100)
    phone: str | None = Field(default=None, max_length=32)
    email: str | None = Field(default=None, max_length=254)

    @model_validator(mode="after")
    def validate_contact(self):
        if not self.phone and not self.email:
            raise ValueError("Un téléphone ou un e-mail est obligatoire")
        if self.phone and not re.fullmatch(r"\+?[0-9][0-9 .()\-]{5,30}", self.phone):
            raise ValueError("Numéro de téléphone invalide")
        if self.email and not re.fullmatch(r"[^\s@]+@[^\s@]+\.[^\s@]+", self.email):
            raise ValueError("Adresse e-mail invalide")
        self.first_name = self.first_name.strip()
        self.last_name = self.last_name.strip()
        self.email = self.email.lower().strip() if self.email else None
        self.phone = self.phone.strip() if self.phone else None
        return self

class StudentGuardianLinkInput(BaseModel):
    model_config = ConfigDict(populate_by_name=True, extra="forbid")
    guardian_id: uuid.UUID = Field(alias="guardianId")
    relationship: str = Field(min_length=1, max_length=50)
    is_primary: bool = Field(default=False, alias="isPrimary")

class TeacherInput(BaseModel):
    model_config = ConfigDict(populate_by_name=True, extra="forbid")
    first_name: str = Field(alias="firstName", min_length=1, max_length=100)
    last_name: str = Field(alias="lastName", min_length=1, max_length=100)
    employee_number: str | None = Field(default=None, alias="employeeNumber", max_length=50)
    specialization: str | None = Field(default=None, max_length=100)
    email: str | None = Field(default=None, max_length=254)
    phone: str | None = Field(default=None, max_length=32)
    gender: Literal["M", "F", "X"] | None = None
    birth_date: date | None = Field(default=None, alias="birthDate")
    address: str | None = Field(default=None, max_length=500)
    diploma: str | None = Field(default=None, max_length=150)
    hire_date: date | None = Field(default=None, alias="hireDate")

    @field_validator("first_name", "last_name", "employee_number", "specialization", "email", "phone", "address", "diploma", mode="before")
    @classmethod
    def trim_teacher_fields(cls, value: Any) -> Any:
        if isinstance(value, str):
            value = value.strip()
            return value or None
        return value

    @field_validator("email")
    @classmethod
    def validate_teacher_email(cls, value: str | None) -> str | None:
        if value and not re.fullmatch(r"[^\s@]+@[^\s@]+\.[^\s@]+", value):
            raise ValueError("Adresse e-mail invalide")
        return value.lower() if value else None

    @field_validator("phone")
    @classmethod
    def validate_teacher_phone(cls, value: str | None) -> str | None:
        if value and not re.fullmatch(r"\+?[0-9][0-9 .()\-]{5,30}", value):
            raise ValueError("Numero de telephone invalide")
        return value

class TeacherUpdateInput(BaseModel):
    model_config = ConfigDict(populate_by_name=True, extra="forbid")
    first_name: str | None = Field(default=None, alias="firstName", min_length=1, max_length=100)
    last_name: str | None = Field(default=None, alias="lastName", min_length=1, max_length=100)
    employee_number: str | None = Field(default=None, alias="employeeNumber", max_length=50)
    specialization: str | None = Field(default=None, max_length=100)
    email: str | None = Field(default=None, max_length=254)
    phone: str | None = Field(default=None, max_length=32)
    gender: Literal["M", "F", "X"] | None = None
    birth_date: date | None = Field(default=None, alias="birthDate")
    address: str | None = Field(default=None, max_length=500)
    diploma: str | None = Field(default=None, max_length=150)
    hire_date: date | None = Field(default=None, alias="hireDate")
    status: Literal["active", "inactive", "archived"] | None = None

class SubjectInput(BaseModel):
    model_config = ConfigDict(populate_by_name=True, extra="forbid")
    name: str = Field(min_length=1, max_length=100)
    code: str | None = Field(default=None, max_length=50)
    description: str | None = Field(default=None, max_length=1000)

    @field_validator("name", "code", "description", mode="before")
    @classmethod
    def trim_subject_fields(cls, value: Any) -> Any:
        if isinstance(value, str):
            value = value.strip()
            return value or None
        return value

class SubjectUpdateInput(BaseModel):
    model_config = ConfigDict(populate_by_name=True, extra="forbid")
    name: str | None = Field(default=None, min_length=1, max_length=100)
    code: str | None = Field(default=None, max_length=50)
    description: str | None = Field(default=None, max_length=1000)
    status: Literal["active", "inactive", "archived"] | None = None

class SubjectLevelSettingInput(BaseModel):
    model_config = ConfigDict(populate_by_name=True, extra="forbid")
    school_level_id: uuid.UUID = Field(alias="schoolLevelId")
    coefficient: float | None = Field(default=None, gt=0)
    grading_scale: float = Field(default=20, alias="gradingScale", gt=0)

class AffectationInput(BaseModel):
    model_config = ConfigDict(populate_by_name=True, extra="forbid")
    teacher_id: uuid.UUID = Field(alias="teacherId")
    class_id: uuid.UUID = Field(alias="classId")
    subject_id: uuid.UUID = Field(alias="subjectId")

class MainTeacherInput(BaseModel):
    model_config = ConfigDict(populate_by_name=True, extra="forbid")
    teacher_id: uuid.UUID = Field(alias="teacherId")

class AcademicPeriodInput(BaseModel):
    model_config = ConfigDict(populate_by_name=True, extra="forbid")
    academic_year_id: uuid.UUID = Field(alias="academicYearId")
    code: str | None = Field(default=None, min_length=1, max_length=32)
    name: str = Field(min_length=1, max_length=80)
    period_type: Literal["trimester", "semester"] = Field(alias="periodType")
    sort_order: int = Field(default=0, alias="sortOrder", ge=0)
    start_date: date | None = Field(default=None, alias="startDate")
    end_date: date | None = Field(default=None, alias="endDate")

    @model_validator(mode="after")
    def validate_period_dates(self):
        if self.start_date and self.end_date and self.start_date > self.end_date:
            raise ValueError("La date de debut doit preceder la date de fin")
        self.code = self.code.strip().upper() if self.code else None
        self.name = self.name.strip()
        return self

class EvaluationInput(BaseModel):
    model_config = ConfigDict(populate_by_name=True, extra="forbid")
    title: str = Field(min_length=1, max_length=100)
    type: Literal["devoir", "composition", "quiz", "oral", "project"]
    class_id: uuid.UUID = Field(alias="classId")
    subject_id: uuid.UUID = Field(alias="subjectId")
    academic_period_id: uuid.UUID = Field(alias="periodId")
    date_scheduled: date | None = Field(default=None, alias="date")
    max_score: float = Field(default=20, alias="maxScore", gt=0, le=1000)
    description: str | None = Field(default=None, max_length=1000)

class EvaluationProgramInput(BaseModel):
    model_config = ConfigDict(populate_by_name=True, extra='forbid')
    title: str = Field(min_length=1, max_length=100)
    type: Literal['devoir', 'composition', 'test', 'exam', 'exam_blanc']
    exam_code: Literal[
        'devoir_1', 'devoir_2', 'composition',
        'cepe_test', 'cepe_blanc', 'bepc_test', 'bepc_blanc',
        'bac_test', 'bac_blanc'
    ] | None = Field(default=None, alias='examCode')
    class_ids: list[uuid.UUID] = Field(alias='classIds', min_length=1, max_length=100)
    academic_period_id: uuid.UUID = Field(alias='periodId')
    description: str | None = Field(default=None, max_length=1000)

    @model_validator(mode='after')
    def normalize_program(self):
        self.title = self.title.strip()
        if len(set(self.class_ids)) != len(self.class_ids):
            raise ValueError('Une classe ne peut être sélectionnée qu’une fois')
        return self

class EvaluationStatusInput(BaseModel):
    model_config = ConfigDict(populate_by_name=True, extra="forbid")
    status: Literal["draft", "submitted", "validated", "rejected", "locked"]
    reason: str | None = Field(default=None, max_length=1000)

class GradeEntryInput(BaseModel):
    model_config = ConfigDict(populate_by_name=True, extra="forbid")
    student_id: uuid.UUID = Field(alias="studentId")
    value: float | None = Field(default=None, ge=0)
    presence: Literal["present", "absent", "not_recorded"] = "present"
    comment: str | None = Field(default=None, max_length=500)

    @model_validator(mode="after")
    def validate_grade_presence(self):
        if self.presence == "present" and self.value is None:
            raise ValueError("Une note est obligatoire pour un eleve present")
        if self.presence == "absent":
            if self.value is not None:
                raise ValueError("Une absence ne doit pas contenir de note")
            self.value = None
        if self.presence == "not_recorded" and self.value is not None:
            raise ValueError("Une note non renseignee ne doit pas contenir de valeur")
        return self

class GradeBatchInput(BaseModel):
    model_config = ConfigDict(populate_by_name=True, extra='forbid')
    entries: list[GradeEntryInput] = Field(min_length=1, max_length=500)
    correction_reason: str | None = Field(
        default=None, alias='correctionReason', min_length=3, max_length=1000
    )

class AttendanceEntryInput(BaseModel):
    model_config = ConfigDict(populate_by_name=True, extra="forbid")
    student_id: uuid.UUID = Field(alias="studentId")
    status: Literal["present", "absent", "justified"]
    note: str | None = Field(default=None, max_length=500)

class AttendanceBatchInput(BaseModel):
    model_config = ConfigDict(populate_by_name=True, extra="forbid")
    class_id: uuid.UUID = Field(alias="classId")
    attendance_date: date = Field(alias="date")
    entries: list[AttendanceEntryInput] = Field(min_length=1, max_length=500)

class BehaviorEventInput(BaseModel):
    model_config = ConfigDict(populate_by_name=True, extra="forbid")
    student_id: uuid.UUID = Field(alias="studentId")
    class_id: uuid.UUID = Field(alias="classId")
    academic_period_id: uuid.UUID = Field(alias="periodId")
    category: str = Field(min_length=1, max_length=50)
    event_type: Literal["positive", "negative", "neutral"] = Field(alias="eventType")
    severity: Literal["low", "normal", "high", "critical"] = "normal"
    title: str = Field(min_length=1, max_length=120)
    description: str | None = Field(default=None, max_length=1000)

    @field_validator("category")
    @classmethod
    def validate_star_category(cls, value: str) -> str:
        normalized = value.strip().lower()
        if not re.fullmatch(r"stars:[1-5]", normalized):
            raise ValueError("Le comportement doit contenir entre 1 et 5 étoiles")
        return normalized

class BehaviorBatchEntryInput(BaseModel):
    model_config = ConfigDict(populate_by_name=True, extra="forbid")
    student_id: uuid.UUID = Field(alias="studentId")
    stars: int = Field(ge=1, le=5, strict=True)
    comment: str | None = Field(default=None, max_length=500)

class BehaviorBatchInput(BaseModel):
    model_config = ConfigDict(populate_by_name=True, extra="forbid")
    class_id: uuid.UUID = Field(alias="classId")
    academic_period_id: uuid.UUID = Field(alias="periodId")
    entries: list[BehaviorBatchEntryInput] = Field(min_length=1, max_length=500)
    action: Literal["draft", "submit"] = "submit"

class BehaviorCalculationInput(BaseModel):
    model_config = ConfigDict(populate_by_name=True, extra="forbid")
    class_id: uuid.UUID = Field(alias="classId")
    academic_period_id: uuid.UUID = Field(alias="periodId")
    school_id: str | None = Field(default=None, alias="schoolId")

class ExternalNotificationInput(BaseModel):
    model_config = ConfigDict(populate_by_name=True, extra='forbid')
    channel: Literal['email', 'sms', 'whatsapp']
    recipient: str = Field(min_length=3, max_length=254)
    subject: str | None = Field(default=None, max_length=160)
    message: str = Field(min_length=1, max_length=4000)
    confirmed: bool = False

    @model_validator(mode='after')
    def validate_notification(self):
        self.recipient = self.recipient.strip()
        self.message = self.message.strip()
        self.subject = self.subject.strip() if self.subject else None
        if not self.confirmed:
            raise ValueError('La confirmation explicite est obligatoire avant l’envoi')
        if self.channel == 'email':
            if not re.fullmatch(r'[^\s@]+@[^\s@]+\.[^\s@]+', self.recipient):
                raise ValueError('Adresse e-mail invalide')
        elif not re.fullmatch(r'\+?[0-9][0-9 .()\-]{5,30}', self.recipient):
            raise ValueError('Numéro de téléphone invalide')
        return self


class InAppTeacherNotificationInput(BaseModel):
    model_config = ConfigDict(populate_by_name=True, extra="forbid")
    title: str = Field(min_length=1, max_length=160)
    message: str = Field(min_length=1, max_length=4000)
    category: str = Field(default="administrative", min_length=1, max_length=80)
    teacher_ids: list[uuid.UUID] | None = Field(
        default=None, alias="teacherIds", max_length=500
    )

    @model_validator(mode="after")
    def normalize_in_app_teacher_notification(self):
        self.title = self.title.strip()
        self.message = self.message.strip()
        self.category = self.category.strip().lower()
        if self.teacher_ids is not None:
            self.teacher_ids = list(dict.fromkeys(self.teacher_ids))
            if not self.teacher_ids:
                self.teacher_ids = None
        return self


class TeacherBroadcastInput(BaseModel):
    model_config = ConfigDict(populate_by_name=True, extra="forbid")
    channel: Literal["email", "sms", "whatsapp"]
    subject: str | None = Field(default=None, max_length=160)
    message: str = Field(min_length=1, max_length=4000)
    confirmed: bool = False
    school_id: str | None = Field(default=None, alias="schoolId")

    @model_validator(mode="after")
    def validate_broadcast(self):
        self.message = self.message.strip()
        self.subject = self.subject.strip() if self.subject else None
        if not self.confirmed:
            raise ValueError("La confirmation explicite est obligatoire avant l’envoi")
        return self


class AssignmentInput(BaseModel):
    model_config = ConfigDict(populate_by_name=True, extra="forbid")
    class_id: uuid.UUID = Field(alias="classId")
    subject_id: uuid.UUID = Field(alias="subjectId")
    title: str = Field(min_length=1, max_length=150)
    description: str | None = Field(default=None, max_length=2000)
    assigned_date: date = Field(default_factory=date.today, alias="assignedDate")
    due_date: date = Field(alias="dueDate")
    max_score: float | None = Field(default=None, alias="maxScore", gt=0)

    @model_validator(mode="after")
    def validate_assignment_dates(self):
        if self.assigned_date > self.due_date:
            raise ValueError("La date limite doit suivre la date de publication")
        return self

class ScheduleEntryInput(BaseModel):
    model_config = ConfigDict(populate_by_name=True, extra="forbid")
    class_id: uuid.UUID = Field(alias="classId")
    subject_id: uuid.UUID = Field(alias="subjectId")
    teacher_id: uuid.UUID = Field(alias="teacherId")
    weekday: int = Field(ge=1, le=7)
    start_time: dt_time = Field(alias="startTime")
    end_time: dt_time = Field(alias="endTime")
    room: str | None = Field(default=None, max_length=80)

    @model_validator(mode="after")
    def validate_schedule_times(self):
        if self.start_time >= self.end_time:
            raise ValueError("L'heure de debut doit preceder l'heure de fin")
        return self

class SuperAdminEstablishmentCreateInput(BaseModel):
    model_config = ConfigDict(extra="forbid")
    id: str | None = Field(default=None, min_length=2, max_length=80)
    name: str = Field(min_length=2, max_length=200)
    code: str = Field(min_length=2, max_length=6)
    city: str = Field(min_length=2, max_length=120)
    country: str = Field(default="Congo", min_length=2, max_length=120)
    phone: str | None = None
    email: str | None = None
    plan: str = Field(default="basic", min_length=2, max_length=40)
    plan_price: str = "0"
    subscription_end_date: str | None = None
    admin_name: str = Field(min_length=2, max_length=160)
    admin_email: str = Field(min_length=3, max_length=254)
    admin_phone: str | None = None
    admin_direction_code: Literal["MATERNELLE_PRIMAIRE", "COLLEGE", "LYCEE"] | None = None
    use_base_configuration: bool = True
    initial_academic_year: str | None = Field(default=None, pattern=r"^\d{4}-\d{4}$")
    cycles: list[Literal["MATERNELLE", "PRIMAIRE", "COLLEGE", "LYCEE"]] = Field(
        default_factory=list,
        max_length=len(CYCLE_CATALOG),
    )

    @field_validator("code")
    @classmethod
    def normalize_code(cls, value: str) -> str:
        normalized = re.sub(r"[^A-Z0-9]", "", value.strip().upper())
        if not re.fullmatch(r"[A-Z][A-Z0-9]{1,5}", normalized):
            raise ValueError("Le code établissement doit contenir 2 à 6 lettres/chiffres et commencer par une lettre")
        return normalized

    @field_validator("email", "admin_email")
    @classmethod
    def validate_creation_email(cls, value: str | None) -> str | None:
        if value and not re.fullmatch(r"[^\s@]+@[^\s@]+\.[^\s@]+", value):
            raise ValueError("Adresse e-mail invalide")
        return value.lower().strip() if value else None

    @field_validator("cycles")
    @classmethod
    def validate_creation_cycles(cls, values: list[str]) -> list[str]:
        if len(values) != len(set(values)):
            raise ValueError("Un cycle ne peut pas être sélectionné plusieurs fois")
        selected = set(values)
        return [code for code, _, _ in CYCLE_CATALOG if code in selected]

    @model_validator(mode="after")
    def validate_creation_structure(self):
        if not self.cycles:
            raise ValueError("Au moins un cycle est obligatoire pour un établissement scolaire")
        if self.initial_academic_year:
            start, end = (int(value) for value in self.initial_academic_year.split("-"))
            if end != start + 1:
                raise ValueError("L’année scolaire doit suivre le format AAAA-AAAA+1")
        return self
class SchoolSeriesInput(BaseModel):
    model_config = ConfigDict(populate_by_name=True, extra='forbid')
    cycle_id: uuid.UUID = Field(alias='cycleId')
    code: str = Field(min_length=1, max_length=32)
    name: str = Field(min_length=1, max_length=100)
    description: str | None = Field(default=None, max_length=1000)
    sort_order: int = Field(default=0, alias='sortOrder', ge=0)
    status: Literal['active', 'inactive', 'archived'] = 'active'

    @model_validator(mode='after')
    def normalize_series(self):
        self.code = self.code.strip().upper()
        self.name = self.name.strip()
        return self

class SchoolClassInput(BaseModel):
    model_config = ConfigDict(populate_by_name=True, extra='forbid')
    school_id: str | None = Field(default=None, alias='schoolId')
    academic_year_id: uuid.UUID = Field(alias='academicYearId')
    cycle_id: uuid.UUID = Field(alias='cycleId')
    school_level_id: uuid.UUID = Field(alias='schoolLevelId')
    series_id: uuid.UUID | None = Field(default=None, alias='seriesId')
    name: str = Field(min_length=1, max_length=100)
    capacity: int | None = Field(default=None, ge=1, le=1000)
    status: Literal['active', 'inactive'] = 'active'

    @field_validator('name', mode='before')
    @classmethod
    def normalize_class_name(cls, value: Any) -> Any:
        return value.strip() if isinstance(value, str) else value

class StudentIdentityInput(BaseModel):
    model_config = ConfigDict(populate_by_name=True, extra='forbid')
    first_name: str = Field(alias='firstName', min_length=1, max_length=100)
    last_name: str = Field(alias='lastName', min_length=1, max_length=100)
    birth_date: date = Field(alias='birthDate')
    nationality: str = Field(min_length=1, max_length=100)
    gender: Literal['M', 'F'] | None = None
    email: str | None = Field(default=None, max_length=254)
    phone: str | None = Field(default=None, max_length=32)
    address: str = Field(min_length=1, max_length=500)

    @model_validator(mode='after')
    def normalize_student(self):
        self.first_name = self.first_name.strip()
        self.last_name = self.last_name.strip()
        self.nationality = self.nationality.strip()
        self.address = self.address.strip()
        self.email = self.email.lower().strip() if self.email else None
        self.phone = self.phone.strip() if self.phone else None
        if self.email and not re.fullmatch(r'[^\s@]+@[^\s@]+\.[^\s@]+', self.email):
            raise ValueError('Adresse e-mail invalide')
        if self.phone and not re.fullmatch(r'\+?[0-9][0-9 .()\-]{5,30}', self.phone):
            raise ValueError('Numéro de téléphone invalide')
        return self

class StudentIdentityUpdateInput(BaseModel):
    model_config = ConfigDict(populate_by_name=True, extra='forbid')
    first_name: str | None = Field(default=None, alias='firstName', min_length=1, max_length=100)
    last_name: str | None = Field(default=None, alias='lastName', min_length=1, max_length=100)
    birth_date: date | None = Field(default=None, alias='birthDate')
    nationality: str | None = Field(default=None, min_length=1, max_length=100)
    gender: Literal['M', 'F'] | None = None
    email: str | None = Field(default=None, max_length=254)
    phone: str | None = Field(default=None, max_length=32)
    address: str | None = Field(default=None, min_length=1, max_length=500)
    status: Literal['active', 'archived'] | None = None

class StudentRegistrationInput(BaseModel):
    model_config = ConfigDict(populate_by_name=True, extra='forbid')
    class_id: uuid.UUID = Field(alias='classId')
    registration_date: date = Field(default_factory=date.today, alias='registrationDate')
    school_regime: Literal['normal', 'part_time', 'full_time'] = Field(default='normal', alias='schoolRegime')
    has_td: bool = Field(default=False, alias='hasTd')
    options: dict[str, Any] = Field(default_factory=dict)

class StudentRegimeChangeInput(BaseModel):
    model_config = ConfigDict(populate_by_name=True, extra='forbid')
    school_regime: Literal['part_time', 'full_time'] = Field(alias='schoolRegime')
    effective_date: date = Field(alias='effectiveDate')

class StudentPhotoFileInput(BaseModel):
    model_config = ConfigDict(populate_by_name=True, extra="forbid")
    name: str = Field(min_length=1, max_length=180)
    mime_type: str = Field(alias="mimeType", max_length=80)
    content_base64: str = Field(alias="contentBase64", min_length=1)

class StudentPhotoImportInput(BaseModel):
    model_config = ConfigDict(populate_by_name=True, extra="forbid")
    academic_year_id: uuid.UUID = Field(alias="academicYearId")
    cycle_id: uuid.UUID = Field(alias="cycleId")
    files: list[StudentPhotoFileInput] = Field(min_length=1, max_length=500)

class StudentPhotoUpdateInput(BaseModel):
    model_config = ConfigDict(populate_by_name=True, extra="forbid")
    name: str = Field(min_length=1, max_length=180)
    mime_type: str = Field(alias="mimeType", max_length=80)
    content_base64: str = Field(alias="contentBase64", min_length=1)

class StudentClassTransferInput(BaseModel):
    model_config = ConfigDict(populate_by_name=True, extra='forbid')
    class_id: uuid.UUID = Field(alias='classId')
    effective_date: date = Field(default_factory=date.today, alias='effectiveDate')
    reason: str | None = Field(default=None, max_length=1000)
    grade_handling_decision: Literal['keep_origin', 'move_destination', 'admin_review'] | None = Field(
        default=None, alias='gradeHandlingDecision'
    )

class GuardianInput(BaseModel):
    model_config = ConfigDict(populate_by_name=True, extra='forbid')
    first_name: str = Field(alias='firstName', min_length=1, max_length=100)
    last_name: str = Field(alias='lastName', min_length=1, max_length=100)
    phone: str | None = Field(default=None, max_length=32)
    second_phone: str | None = Field(default=None, alias='secondPhone', max_length=32)
    email: str | None = Field(default=None, max_length=254)
    address: str = Field(min_length=1, max_length=500)
    profession: str = Field(min_length=1, max_length=150)

    @model_validator(mode='after')
    def normalize_guardian(self):
        if not self.phone and not self.email:
            raise ValueError('Un téléphone ou un e-mail est obligatoire')
        for value in (self.phone, self.second_phone):
            if value and not re.fullmatch(r'\+?[0-9][0-9 .()\-]{5,30}', value):
                raise ValueError('Numéro de téléphone invalide')
        if self.email and not re.fullmatch(r'[^\s@]+@[^\s@]+\.[^\s@]+', self.email):
            raise ValueError('Adresse e-mail invalide')
        self.first_name = self.first_name.strip()
        self.last_name = self.last_name.strip()
        self.phone = self.phone.strip() if self.phone else None
        self.second_phone = self.second_phone.strip() if self.second_phone else None
        self.email = self.email.lower().strip() if self.email else None
        self.address = self.address.strip()
        self.profession = self.profession.strip()
        return self

class SubjectLevelSettingInput(BaseModel):
    model_config = ConfigDict(populate_by_name=True, extra='forbid')
    school_level_id: uuid.UUID = Field(alias='schoolLevelId')
    academic_year_id: uuid.UUID = Field(alias='academicYearId')
    series_id: uuid.UUID | None = Field(default=None, alias='seriesId')
    coefficient: float | None = Field(default=None, gt=0)
    grading_scale: float = Field(default=20, alias='gradingScale', gt=0)
    contributes_to_average: bool = Field(default=True, alias='contributesToAverage')
    enabled: bool = True

class AcademicPeriodInput(BaseModel):
    model_config = ConfigDict(populate_by_name=True, extra='forbid')
    academic_year_id: uuid.UUID = Field(alias='academicYearId')
    parent_period_id: uuid.UUID | None = Field(default=None, alias='parentPeriodId')
    code: str | None = Field(default=None, min_length=1, max_length=32)
    name: str = Field(min_length=1, max_length=80)
    period_type: Literal['trimester', 'month', 'custom'] = Field(alias='periodType')
    sort_order: int = Field(default=0, alias='sortOrder', ge=0)
    start_date: date | None = Field(default=None, alias='startDate')
    end_date: date | None = Field(default=None, alias='endDate')

    @model_validator(mode='after')
    def normalize_period(self):
        if self.start_date and self.end_date and self.start_date > self.end_date:
            raise ValueError('La date de début doit précéder la date de fin')
        self.code = self.code.strip().upper() if self.code else None
        self.name = self.name.strip()
        return self

class EvaluationInput(BaseModel):
    model_config = ConfigDict(populate_by_name=True, extra='forbid')
    title: str = Field(min_length=1, max_length=100)
    type: Literal['devoir', 'composition', 'test', 'exam', 'exam_blanc']
    exam_code: Literal[
        'cepe_test', 'cepe_blanc', 'bepc_test', 'bepc_blanc',
        'bac_test', 'bac_blanc'
    ] | None = Field(default=None, alias='examCode')
    class_id: uuid.UUID = Field(alias='classId')
    subject_id: uuid.UUID = Field(alias='subjectId')
    academic_period_id: uuid.UUID = Field(alias='periodId')
    date_scheduled: date | None = Field(default=None, alias='date')
    max_score: float = Field(default=20, alias='maxScore', gt=0, le=1000)
    description: str | None = Field(default=None, max_length=1000)

class AttendanceEntryInput(BaseModel):
    model_config = ConfigDict(populate_by_name=True, extra='forbid')
    student_id: uuid.UUID = Field(alias='studentId')
    status: Literal['present', 'absent', 'justified']
    note: str | None = Field(default=None, max_length=500)

class AttendanceBatchInput(BaseModel):
    model_config = ConfigDict(populate_by_name=True, extra='forbid')
    class_id: uuid.UUID = Field(alias='classId')
    schedule_entry_id: uuid.UUID = Field(alias='scheduleId')
    attendance_date: date = Field(alias='date')
    entries: list[AttendanceEntryInput] = Field(min_length=1, max_length=500)
    action: Literal['draft', 'submit'] = 'draft'

class ScheduleEntryInput(BaseModel):
    model_config = ConfigDict(populate_by_name=True, extra='forbid')
    class_id: uuid.UUID = Field(alias='classId')
    subject_id: uuid.UUID = Field(alias='subjectId')
    teacher_id: uuid.UUID = Field(alias='teacherId')
    weekday: int = Field(ge=1, le=7)
    start_time: dt_time = Field(alias='startTime')
    end_time: dt_time = Field(alias='endTime')

    @model_validator(mode='after')
    def validate_times(self):
        if self.start_time >= self.end_time:
            raise ValueError('L heure de début doit précéder l heure de fin')
        return self

class CalendarSettingInput(BaseModel):
    model_config = ConfigDict(populate_by_name=True, extra='forbid')
    academic_year_id: uuid.UUID = Field(alias='academicYearId')
    teaching_days: list[int] = Field(alias='teachingDays', min_length=1, max_length=7)
    day_start: dt_time = Field(alias='dayStart')
    day_end: dt_time = Field(alias='dayEnd')
    course_duration_minutes: int = Field(alias='courseDurationMinutes', gt=0, le=480)
    pause_duration_minutes: int = Field(alias='pauseDurationMinutes', ge=0, le=180)
    pause_frequency: int = Field(alias='pauseFrequency', gt=0, le=20)

    @model_validator(mode='after')
    def validate_calendar(self):
        if len(set(self.teaching_days)) != len(self.teaching_days) or any(day < 1 or day > 7 for day in self.teaching_days):
            raise ValueError('Jours de cours invalides')
        if self.day_start >= self.day_end:
            raise ValueError('La journée doit avoir une heure de fin postérieure')
        return self

class CalendarEventInput(BaseModel):
    model_config = ConfigDict(populate_by_name=True, extra='forbid')
    academic_year_id: uuid.UUID = Field(alias='academicYearId')
    academic_period_id: uuid.UUID | None = Field(default=None, alias='periodId')
    title: str = Field(min_length=1, max_length=150)
    event_type: str = Field(alias='eventType', min_length=1, max_length=50)
    start_date: date = Field(alias='startDate')
    end_date: date = Field(alias='endDate')
    description: str | None = Field(default=None, max_length=1000)

class EvaluationRuleInput(BaseModel):
    model_config = ConfigDict(populate_by_name=True, extra='forbid')
    academic_year_id: uuid.UUID = Field(alias='academicYearId')
    cycle_id: uuid.UUID = Field(alias='cycleId')
    school_level_id: uuid.UUID | None = Field(default=None, alias='schoolLevelId')
    series_id: uuid.UUID | None = Field(default=None, alias='seriesId')
    evaluation_type: Literal['devoir', 'composition', 'test', 'exam', 'exam_blanc'] = Field(alias='evaluationType')
    label: str = Field(min_length=1, max_length=100)
    expected_count: int | None = Field(default=None, alias='expectedCount', gt=0)
    contributes_to_average: bool = Field(default=True, alias='contributesToAverage')
    is_required: bool = Field(default=False, alias='isRequired')
    sort_order: int = Field(default=0, alias='sortOrder', ge=0)

class AnnualDecisionInput(BaseModel):
    model_config = ConfigDict(populate_by_name=True, extra='forbid')
    academic_year_id: uuid.UUID = Field(alias='academicYearId')
    decision: Literal['admitted', 'repeat', 'excluded']
    reason: str | None = Field(default=None, max_length=1000)

    @model_validator(mode='after')
    def validate_decision(self):
        if self.decision == 'excluded' and not (self.reason and self.reason.strip()):
            raise ValueError('La raison de l exclusion est obligatoire')
        return self

class Principal(BaseModel):
    id: str
    role: str
    school_id: str | None = None
    teacher_id: str | None = None
    student_id: str | None = None
    direction_id: str | None = None
    direction_name: str | None = None
    direction_cycle_ids: list[str] = Field(default_factory=list)
    legacy_direction_scope: bool = False

def db():
    with Session(engine) as session: yield session

def password_policy_available(session: Session) -> bool:
    return bool(session.scalar(text("""
        SELECT EXISTS (
          SELECT 1 FROM information_schema.columns
          WHERE table_schema = current_schema()
            AND table_name = 'users'
            AND column_name = 'must_change_password'
        )
    """)))

def must_change_password(session: Session, user: User) -> bool:
    if not password_policy_available(session):
        return False
    return bool(session.scalar(text("SELECT must_change_password FROM users WHERE id = :id"), {"id": user.id}))

def temporary_access(session: Session, user: User) -> Resource | None:
    return session.get(
        Resource,
        {"kind": TEMPORARY_ACCESS_KIND, "id": str(user.id)},
    )

def issue_temporary_access(session: Session, user: User, reason: str) -> str:
    """Replace the credential without duplicating the user or role profile."""
    now = datetime.now(timezone.utc)
    temporary_password = generate_initial_password()
    user.password_hash = passwords.hash(temporary_password)
    user.password_set = False
    user.updated_at = now
    if password_policy_available(session):
        session.execute(
            text("UPDATE users SET must_change_password = TRUE WHERE id = :id"),
            {"id": user.id},
        )
    payload = {
        "userId": str(user.id),
        "issuedAt": now.isoformat(),
        "expiresAt": (now + TEMPORARY_ACCESS_TTL).isoformat(),
        "consumedAt": None,
        "reason": reason,
    }
    grant = temporary_access(session, user)
    if grant:
        grant.school_id = str(user.school_id) if user.school_id else None
        grant.establishment_id = user.school_id
        grant.payload = payload
        grant.updated_at = now
    else:
        session.add(Resource(
            id=str(user.id),
            kind=TEMPORARY_ACCESS_KIND,
            school_id=str(user.school_id) if user.school_id else None,
            establishment_id=user.school_id,
            payload=payload,
        ))
    return temporary_password

def consume_temporary_access(session: Session, user: User) -> None:
    """Make a generated temporary password usable for exactly one login."""
    if not must_change_password(session, user):
        return
    grant = temporary_access(session, user)
    if not grant:
        # Backward compatibility for credentials created before this safeguard.
        return
    now = datetime.now(timezone.utc)
    expires_at = datetime.fromisoformat(str(grant.payload["expiresAt"]))
    if expires_at <= now:
        raise HTTPException(
            401,
            "Ce mot de passe temporaire a expiré. Demandez une nouvelle réinitialisation.",
        )
    if grant.payload.get("consumedAt"):
        raise HTTPException(
            401,
            "Ce mot de passe temporaire a déjà été utilisé. Demandez une nouvelle réinitialisation.",
        )
    grant.payload = {**grant.payload, "consumedAt": now.isoformat()}
    grant.updated_at = now
    session.commit()

def password_revision(user: User) -> str:
    # Never expose the bcrypt hash itself in a JWT. Its SHA-256 fingerprint is
    # enough to invalidate every older token after a password replacement.
    return hashlib.sha256(user.password_hash.encode("utf-8")).hexdigest()

def establishment_is_active(session: Session, school_id: uuid.UUID | None) -> bool:
    if school_id is None:
        return True
    establishment = session.get(Establishment, school_id)
    return bool(establishment and establishment.status == "active")

def subscription_allows_access(session: Session, school_id: uuid.UUID | None) -> bool:
    if school_id is None:
        return True
    subscription = session.scalar(select(Resource).where(
        Resource.kind == "subscriptions",
        Resource.establishment_id == school_id,
    ).order_by(Resource.created_at.desc()))
    return subscription is None or canonical_subscription_status(subscription.payload) == "active"

def ensure_user_role_profile(user: User, session: Session) -> None:
    profile_exists = True
    if user.role == "teacher":
        profile_exists = session.scalar(select(Teacher.id).where(
            Teacher.user_id == user.id,
            Teacher.establishment_id == user.school_id,
            Teacher.status != "archived",
        )) is not None
    elif user.role == "student":
        profile_exists = session.scalar(select(Student.id).where(
            Student.user_id == user.id,
            Student.establishment_id == user.school_id,
            Student.status != "archived",
        )) is not None
    elif user.role == "parent":
        profile_exists = session.scalar(select(Guardian.id).where(
            Guardian.user_id == user.id,
            Guardian.establishment_id == user.school_id,
            Guardian.status != "archived",
        )) is not None
    if not profile_exists:
        raise HTTPException(403, "Ce compte n'est pas rattache a un profil actif")

def user_json(user: User, session: Session | None = None) -> dict[str, Any]:
    direction = session.get(SchoolDirection, user.direction_id) if session and user.direction_id else None
    direction_cycles = list(session.scalars(select(SchoolCycle).join(
        SchoolDirectionCycle, SchoolDirectionCycle.cycle_id == SchoolCycle.id
    ).where(
        SchoolDirectionCycle.direction_id == direction.id
    ).order_by(SchoolCycle.sort_order, SchoolCycle.name)).all()) if session and direction else []
    return {"id": str(user.id), "name": user.name, "email": user.email, "role": user.role,
            "roleName": user.role, "initials": "SA" if user.role == "superadmin" else None,
            "schoolId": public_school_id(session, user.school_id) if session else str(user.school_id) if user.school_id else None, "status": user.status, "passwordSet": user.password_set,
            "mustChangePassword": must_change_password(session, user) if session else False,
            "directionId": str(direction.id) if direction else None,
            "direction": ({"id": str(direction.id), "name": direction.name,
                "status": direction.status,
                "cycles": [cycle_json(cycle, session) for cycle in direction_cycles]}
                if direction else None),
            "legacyDirectionScope": False}

def create_user_record(body: UserCreateInput, current: Principal, session: Session) -> tuple[User, str]:
    if current.role != "superadmin" and body.role == "admin":
        raise HTTPException(403, "Seul le superadmin peut créer un administrateur")
    if current.role not in {"superadmin", "admin"}:
        raise HTTPException(403, "Permission insuffisante")
    if not body.establishment_id:
        raise HTTPException(422, "Un établissement est requis")
    school_resource = session.get(Resource, {"kind": "establishments", "id": body.establishment_id})
    database_id = school_resource.payload.get("databaseId") if school_resource else body.establishment_id
    try: school_id = uuid.UUID(str(database_id))
    except ValueError as exc: raise HTTPException(422, "Identifiant établissement invalide") from exc
    if not session.get(Establishment, school_id): raise HTTPException(404, "Établissement introuvable")
    public_school_id = school_resource.id if school_resource else str(school_id)
    if current.role == "admin" and public_school_id != current.school_id:
        raise HTTPException(403, "Accès inter-établissement interdit")
    if session.scalar(select(User).where(User.email == body.email.lower())):
        raise HTTPException(409, "Cette adresse e-mail est déjà utilisée")
    direction = None
    if body.role == "admin" and body.direction_id is None:
        raise HTTPException(
            422,
            "Choisissez la direction scolaire de cet administrateur.",
        )
    if body.direction_id is not None:
        if current.role != "superadmin" or body.role != "admin":
            raise HTTPException(403, "Seul le Super Admin peut attribuer une direction")
        direction = session.get(SchoolDirection, body.direction_id)
        if not direction or direction.establishment_id != school_id:
            raise HTTPException(422, "Direction scolaire invalide pour cet établissement")
        if direction.status != "active":
            raise HTTPException(409, "Cette direction scolaire est inactive")
        if session.scalar(select(User.id).where(
            User.direction_id == direction.id,
            User.role == "admin",
        )):
            raise HTTPException(409, "Cette direction possède déjà un administrateur")
    user = User(email=body.email.lower(), password_hash="", name=body.name, role=body.role, school_id=school_id, direction_id=direction.id if direction else None, status="active", password_set=False)
    session.add(user); session.flush()
    initial_password = issue_temporary_access(session, user, "initial-account")
    session.commit(); session.refresh(user)
    return user, initial_password

def public_school_id(session: Session, school_id: uuid.UUID | None) -> str | None:
    if not school_id: return None
    database_key = str(school_id)
    cache = session.info.get("public_school_ids")
    if cache is None:
        cache = {
            str(resource.payload.get("databaseId")): resource.id
            for resource in session.scalars(select(Resource).where(
                Resource.kind == "establishments"
            ))
            if resource.payload.get("databaseId")
        }
        session.info["public_school_ids"] = cache
    if database_key not in cache:
        # An establishment can be created in the current transaction after the
        # cache was first populated. Refresh only the missing key so the same
        # authenticated session immediately sees the new public identifier.
        for resource in session.scalars(select(Resource).where(
            Resource.kind == "establishments"
        )):
            resource_database_id = resource.payload.get("databaseId")
            if resource_database_id:
                cache[str(resource_database_id)] = resource.id
    return cache.get(database_key, database_key)

def issue_access_token(user: User, session: Session) -> str:
    now = datetime.now(timezone.utc)
    return jwt.encode({
        "sub": str(user.id),
        "role": user.role,
        "school_id": public_school_id(session, user.school_id),
        "pwd": password_revision(user),
        "iat": now,
        "exp": now + timedelta(hours=8),
    }, JWT_SECRET, algorithm="HS256")

def resolve_establishment_id(session: Session, school_reference: str | None) -> uuid.UUID | None:
    if not school_reference:
        return None
    resource = session.get(Resource, {"kind": "establishments", "id": school_reference})
    database_id = resource.payload.get("databaseId") if resource else school_reference
    try:
        candidate = uuid.UUID(str(database_id))
    except (TypeError, ValueError):
        return None
    return candidate if session.get(Establishment, candidate) else None

def school_scope(
    current: Principal,
    session: Session,
    requested_school_id: str | None,
    *,
    required: bool,
) -> tuple[str | None, uuid.UUID | None]:
    if current.role == "admin":
        if requested_school_id and requested_school_id != current.school_id:
            raise HTTPException(403, "Accès inter-établissement interdit")
        requested_school_id = current.school_id
    elif current.role != "superadmin":
        raise HTTPException(403, "Permission insuffisante")
    if required and not requested_school_id:
        raise HTTPException(422, "Un établissement est requis")
    database_id = resolve_establishment_id(session, requested_school_id)
    if requested_school_id and not database_id:
        raise HTTPException(404, "Établissement introuvable")
    return requested_school_id, database_id

def direction_cycle_scope(current: Principal) -> set[uuid.UUID] | None:
    if current.role != "admin":
        return None
    if not current.direction_id or not current.direction_cycle_ids:
        raise HTTPException(
            403,
            "Votre compte administratif doit être rattaché à une direction scolaire avant de pouvoir accéder à cet espace.",
        )
    return {uuid.UUID(value) for value in current.direction_cycle_ids}

def ensure_direction_cycle_access(
    current: Principal,
    cycle_id: uuid.UUID | None,
) -> None:
    allowed = direction_cycle_scope(current)
    if allowed is not None and (cycle_id is None or cycle_id not in allowed):
        raise HTTPException(403, "Vous n'avez pas acces a ces donnees dans votre direction")

def apply_class_direction_scope(statement: Any, current: Principal) -> Any:
    allowed = direction_cycle_scope(current)
    return statement.where(SchoolClass.cycle_id.in_(allowed)) if allowed is not None else statement

def direction_json(item: SchoolDirection, session: Session) -> dict[str, Any]:
    cycles = list(session.scalars(select(SchoolCycle).join(
        SchoolDirectionCycle, SchoolDirectionCycle.cycle_id == SchoolCycle.id
    ).where(
        SchoolDirectionCycle.direction_id == item.id
    ).order_by(SchoolCycle.sort_order, SchoolCycle.name)).all())
    administrator = session.scalar(select(User).where(
        User.direction_id == item.id,
        User.role == "admin",
    ).order_by(User.created_at))
    cycle_ids = {cycle.id for cycle in cycles}
    class_ids = set(session.scalars(select(SchoolClass.id).where(
        SchoolClass.establishment_id == item.establishment_id,
        SchoolClass.cycle_id.in_(cycle_ids),
        SchoolClass.status == "active",
    )).all()) if cycle_ids else set()
    student_count = session.scalar(select(
        func.count(func.distinct(StudentAcademicRegistration.student_id))
    ).where(
        StudentAcademicRegistration.class_id.in_(class_ids),
        StudentAcademicRegistration.status.in_(("pending", "validated", "active")),
    )) if class_ids else 0
    teacher_count = session.scalar(select(
        func.count(func.distinct(Affectation.teacher_id))
    ).where(
        Affectation.class_id.in_(class_ids),
        Affectation.status == "active",
    )) if class_ids else 0
    return {
        "id": str(item.id),
        "schoolId": public_school_id(session, item.establishment_id),
        "code": item.code,
        "name": item.name,
        "status": item.status,
        "cycles": [cycle_json(cycle, session) for cycle in cycles],
        "administrator": user_json(administrator, session) if administrator else None,
        "statistics": {
            "classes": len(class_ids),
            "students": student_count or 0,
            "teachers": teacher_count or 0,
        },
        "createdAt": item.created_at.isoformat(),
        "updatedAt": item.updated_at.isoformat(),
    }

def cycle_json(cycle: SchoolCycle, session: Session) -> dict[str, Any]:
    return {
        "id": str(cycle.id),
        "schoolId": public_school_id(session, cycle.establishment_id),
        "code": cycle.code,
        "name": cycle.name,
        "status": cycle.status,
        "sortOrder": cycle.sort_order,
        "createdAt": cycle.created_at.isoformat(),
        "updatedAt": cycle.updated_at.isoformat(),
    }

def level_json(level: SchoolLevel, session: Session, cycle: SchoolCycle | None = None) -> dict[str, Any]:
    cycle = cycle or session.get(SchoolCycle, level.cycle_id)
    return {
        "id": str(level.id),
        "schoolId": public_school_id(session, level.establishment_id),
        "cycleId": str(level.cycle_id),
        "cycle": cycle.name if cycle else None,
        "code": level.code,
        "name": level.name,
        "status": level.status,
        "sortOrder": level.sort_order,
        "createdAt": level.created_at.isoformat(),
        "updatedAt": level.updated_at.isoformat(),
    }

def scoped_cycle(cycle_id: uuid.UUID, current: Principal, session: Session) -> SchoolCycle:
    cycle = session.get(SchoolCycle, cycle_id)
    if not cycle:
        raise HTTPException(404, "Cycle introuvable")
    if current.role != "superadmin" and public_school_id(session, cycle.establishment_id) != current.school_id:
        raise HTTPException(403, "Accès inter-établissement interdit")
    ensure_direction_cycle_access(current, cycle.id)
    return cycle

def scoped_level(level_id: uuid.UUID, current: Principal, session: Session) -> SchoolLevel:
    level = session.get(SchoolLevel, level_id)
    if not level:
        raise HTTPException(404, "Niveau introuvable")
    if current.role != "superadmin" and public_school_id(session, level.establishment_id) != current.school_id:
        raise HTTPException(403, "Accès inter-établissement interdit")
    ensure_direction_cycle_access(current, level.cycle_id)
    return level

def academic_year_json(year: AcademicYear, session: Session) -> dict[str, Any]:
    return {
        "id": str(year.id),
        "schoolId": public_school_id(session, year.establishment_id),
        "name": year.name,
        "start": year.start_date.isoformat(),
        "end": year.end_date.isoformat(),
        "status": year.status,
        "isActive": year.is_active,
        "createdAt": year.created_at.isoformat(),
        "updatedAt": year.updated_at.isoformat(),
    }

def class_json(item: SchoolClass, session: Session) -> dict[str, Any]:
    year = session.get(AcademicYear, item.academic_year_id)
    cycle = session.get(SchoolCycle, item.cycle_id) if item.cycle_id else None
    level = session.get(SchoolLevel, item.school_level_id) if item.school_level_id else None
    main_teacher = (
        session.get(Teacher, item.main_teacher_id)
        if item.main_teacher_id else None
    )
    return {
        "id": str(item.id),
        "schoolId": public_school_id(session, item.establishment_id),
        "name": item.name,
        "academicYearId": str(item.academic_year_id),
        "academicYearName": year.name if year else None,
        "cycleId": str(item.cycle_id) if item.cycle_id else None,
        "cycle": cycle.name if cycle else None,
        "structuredLevelId": str(item.school_level_id) if item.school_level_id else None,
        "levelId": str(item.school_level_id) if item.school_level_id else None,
        "level": level.name if level else item.level,
        "capacity": item.capacity,
        "status": item.status,
        "students": 0,
        "createdAt": item.created_at.isoformat(),
        "updatedAt": item.updated_at.isoformat(),
    }

def class_json(item: SchoolClass, session: Session) -> dict[str, Any]:
    year = session.get(AcademicYear, item.academic_year_id)
    cycle = session.get(SchoolCycle, item.cycle_id) if item.cycle_id else None
    level = session.get(SchoolLevel, item.school_level_id) if item.school_level_id else None
    series = session.get(SchoolSeries, item.series_id) if item.series_id else None
    main_teacher = (
        session.get(Teacher, item.main_teacher_id)
        if item.main_teacher_id else None
    )
    return {
        'id': str(item.id),
        'schoolId': public_school_id(session, item.establishment_id),
        'name': item.name,
        'academicYearId': str(item.academic_year_id),
        'academicYearName': year.name if year else None,
        'cycleId': str(item.cycle_id) if item.cycle_id else None,
        'cycle': cycle.name if cycle else None,
        'cycleCode': cycle.code.upper() if cycle else None,
        'schoolLevelId': str(item.school_level_id) if item.school_level_id else None,
        'structuredLevelId': str(item.school_level_id) if item.school_level_id else None,
        'levelId': str(item.school_level_id) if item.school_level_id else None,
        'level': level.name if level else item.level,
        'seriesId': str(item.series_id) if item.series_id else None,
        'series': series.name if series else None,
        'capacity': item.capacity,
        'status': item.status,
        'mainTeacherId': str(main_teacher.id) if main_teacher else None,
        'mainTeacher': (
            f"{main_teacher.last_name} {main_teacher.first_name}"
            if main_teacher else None
        ),
        'createdAt': item.created_at.isoformat(),
        'updatedAt': item.updated_at.isoformat(),
    }

def generate_student_registration_number(session: Session) -> str:
    sequence_value = int(session.scalar(text("SELECT nextval('student_registration_number_seq')")))
    return f"EDU-{datetime.now(timezone.utc).year}-{sequence_value:08d}"

def student_login_matricule(student: Student, session: Session) -> str | None:
    if student.registration_number and student.registration_number.strip():
        return student.registration_number.strip()
    registration = session.scalar(
        select(StudentAcademicRegistration)
        .join(AcademicYear, AcademicYear.id == StudentAcademicRegistration.academic_year_id)
        .where(
            StudentAcademicRegistration.student_id == student.id,
            StudentAcademicRegistration.registration_number.is_not(None),
            StudentAcademicRegistration.status.in_(("pending", "validated", "active")),
        )
        .order_by(
            AcademicYear.is_active.desc(),
            StudentAcademicRegistration.registration_date.desc(),
            StudentAcademicRegistration.created_at.desc(),
        )
    )
    if registration and registration.registration_number:
        return registration.registration_number.strip()
    return None

def normalized_establishment_code(value: Any) -> str:
    normalized = re.sub(r"[^A-Z0-9]", "", str(value or "").strip().upper())
    if not re.fullmatch(r"[A-Z][A-Z0-9]{1,5}", normalized):
        raise HTTPException(
            422,
            "Le code établissement doit contenir 2 à 6 lettres/chiffres et commencer par une lettre",
        )
    return normalized

def lock_establishment_code(session: Session, code: str) -> None:
    session.execute(
        text("SELECT pg_advisory_xact_lock(hashtextextended(:key, 0))"),
        {"key": f"establishment-code:{code}"},
    )

def ensure_establishment_code_available(
    session: Session,
    code: str,
    *,
    exclude_resource_id: str | None = None,
) -> None:
    for resource in session.scalars(
        select(Resource).where(Resource.kind == "establishments")
    ).all():
        if exclude_resource_id and resource.id == exclude_resource_id:
            continue
        existing = re.sub(
            r"[^A-Z0-9]", "", str((resource.payload or {}).get("code") or "").upper()
        )
        if existing == code:
            raise HTTPException(409, "Ce code établissement est déjà utilisé")

def establishment_registration_code(
    session: Session, establishment_id: uuid.UUID
) -> str:
    resource = session.scalar(
        select(Resource).where(
            Resource.kind == "establishments",
            Resource.establishment_id == establishment_id,
        )
    )
    if not resource or not (resource.payload or {}).get("code"):
        raise HTTPException(
            409,
            "Le Super Admin doit renseigner le code de cet établissement avant la première inscription.",
        )
    return normalized_establishment_code(resource.payload.get("code"))

def generate_annual_registration_number(
    session: Session,
    establishment_id: uuid.UUID,
    academic_year_id: uuid.UUID,
) -> str:
    year = session.get(AcademicYear, academic_year_id)
    if not year:
        raise HTTPException(422, 'Année scolaire introuvable')
    school_code = establishment_registration_code(session, establishment_id)
    next_value = session.scalar(text(
        'INSERT INTO annual_registration_counters '
        '(establishment_id, academic_year_id, last_value) VALUES (:school, :year, 1) '
        'ON CONFLICT (establishment_id, academic_year_id) DO UPDATE '
        'SET last_value = annual_registration_counters.last_value + 1, updated_at = now() '
        'RETURNING last_value'
    ), {'school': establishment_id, 'year': academic_year_id})
    first_year = year.start_date.year if year.start_date else date.today().year
    year_token = str(first_year)[-2:]
    return f'{school_code}{year_token}-{int(next_value):03d}'

def ensure_student_permanent_matricule(
    session: Session,
    student: Student,
    academic_year_id: uuid.UUID,
) -> str:
    session.execute(
        text("SELECT pg_advisory_xact_lock(hashtextextended(:key, 0))"),
        {"key": f"student-matricule:{student.id}"},
    )
    session.refresh(student)
    existing = student_login_matricule(student, session)
    if existing:
        if not student.registration_number:
            student.registration_number = existing
        return existing
    matricule = generate_annual_registration_number(
        session, student.establishment_id, academic_year_id
    )
    student.registration_number = matricule
    return matricule

def validate_series_scope(
    series_id: uuid.UUID | None,
    establishment_id: uuid.UUID,
    cycle_id: uuid.UUID,
    session: Session,
) -> SchoolSeries | None:
    if not series_id:
        return None
    series = session.get(SchoolSeries, series_id)
    if not series:
        raise HTTPException(422, 'Série introuvable')
    if series.establishment_id != establishment_id:
        raise HTTPException(403, 'Série inter-établissement interdite')
    if series.cycle_id != cycle_id:
        raise HTTPException(422, 'La série n appartient pas au cycle sélectionné')
    if series.status != 'active':
        raise HTTPException(409, 'La série sélectionnée est inactive')
    return series

def validate_class_series_requirement(
    cycle: SchoolCycle,
    series_id: uuid.UUID | None,
) -> None:
    if canonical_cycle_code(cycle.code) == "LYCEE" and series_id is None:
        raise HTTPException(422, "Veuillez sélectionner une série.")

def registration_json(item: StudentAcademicRegistration, session: Session) -> dict[str, Any]:
    school_class = session.get(SchoolClass, item.class_id)
    year = session.get(AcademicYear, item.academic_year_id)
    cycle = session.get(SchoolCycle, school_class.cycle_id) if school_class and school_class.cycle_id else None
    level = session.get(SchoolLevel, school_class.school_level_id) if school_class and school_class.school_level_id else None
    return {
        "id": str(item.id),
        "schoolId": public_school_id(session, item.establishment_id),
        "studentId": str(item.student_id),
        "academicYearId": str(item.academic_year_id),
        "academicYearName": year.name if year else None,
        "classId": str(item.class_id),
        "className": school_class.name if school_class else None,
        "cycleId": str(school_class.cycle_id) if school_class and school_class.cycle_id else None,
        "cycle": cycle.name if cycle else None,
        "levelId": str(school_class.school_level_id) if school_class and school_class.school_level_id else None,
        "level": level.name if level else school_class.level if school_class else None,
        "registrationDate": item.registration_date.isoformat(),
        "status": item.status,
        "createdAt": item.created_at.isoformat(),
        "updatedAt": item.updated_at.isoformat(),
    }

def guardian_json(item: Guardian, session: Session) -> dict[str, Any]:
    child_count = session.scalar(select(func.count()).select_from(StudentGuardian).where(StudentGuardian.guardian_id == item.id))
    return {
        "id": str(item.id),
        "schoolId": public_school_id(session, item.establishment_id),
        "userId": str(item.user_id) if item.user_id else None,
        "firstName": item.first_name,
        "lastName": item.last_name,
        "fullName": f"{item.last_name} {item.first_name}",
        "phone": item.phone,
        "email": item.email,
        "status": item.status,
        "childCount": child_count,
    }

def student_json(item: Student, session: Session, academic_year_id: uuid.UUID | None = None) -> dict[str, Any]:
    registration = None
    if academic_year_id:
        registration = session.scalar(select(StudentAcademicRegistration).where(
            StudentAcademicRegistration.student_id == item.id,
            StudentAcademicRegistration.academic_year_id == academic_year_id,
            StudentAcademicRegistration.status.in_(("pending", "validated", "active")),
        ))
    links = session.scalars(select(StudentGuardian).where(StudentGuardian.student_id == item.id)).all()
    guardians = []
    for link in links:
        guardian = session.get(Guardian, link.guardian_id)
        if guardian:
            guardians.append({**guardian_json(guardian, session), "relationship": link.relationship, "isPrimary": link.is_primary})
    registration_data = registration_json(registration, session) if registration else None
    primary_guardian = next((value for value in guardians if value["isPrimary"]), guardians[0] if guardians else None)
    photo = _student_photo_row(session, item.id)
    return {
        "id": str(item.id),
        "schoolId": public_school_id(session, item.establishment_id),
        "userId": str(item.user_id) if item.user_id else None,
        "firstName": item.first_name,
        "lastName": item.last_name,
        "fullName": f"{item.last_name} {item.first_name}",
        "matricule": item.registration_number,
        "birthDate": item.birth_date.isoformat() if item.birth_date else None,
        "sex": item.gender,
        "email": item.email,
        "phone": item.phone,
        "address": item.address,
        "status": item.status,
        "registration": registration_data,
        "academicYearId": registration_data["academicYearId"] if registration_data else None,
        "classId": registration_data["classId"] if registration_data else None,
        "class": registration_data["className"] if registration_data else None,
        "cycle": registration_data["cycle"] if registration_data else None,
        "levelId": registration_data["levelId"] if registration_data else None,
        "level": registration_data["level"] if registration_data else None,
        "guardians": guardians,
        "parent": primary_guardian["fullName"] if primary_guardian else None,
        "parentPhone": primary_guardian["phone"] if primary_guardian else None,
        "parentEmail": primary_guardian["email"] if primary_guardian else None,
        "createdAt": item.created_at.isoformat(),
        "updatedAt": item.updated_at.isoformat(),
    }

def registration_json(item: StudentAcademicRegistration, session: Session) -> dict[str, Any]:
    school_class = session.get(SchoolClass, item.class_id)
    year = session.get(AcademicYear, item.academic_year_id)
    cycle = session.get(SchoolCycle, school_class.cycle_id) if school_class and school_class.cycle_id else None
    level = session.get(SchoolLevel, school_class.school_level_id) if school_class and school_class.school_level_id else None
    series = session.get(SchoolSeries, school_class.series_id) if school_class and school_class.series_id else None
    transfers = session.scalars(select(StudentClassTransfer).where(
        StudentClassTransfer.registration_id == item.id
    ).order_by(StudentClassTransfer.effective_date)).all()
    return {
        'id': str(item.id),
        'schoolId': public_school_id(session, item.establishment_id),
        'studentId': str(item.student_id),
        'academicYearId': str(item.academic_year_id),
        'academicYearName': year.name if year else None,
        'classId': str(item.class_id),
        'className': school_class.name if school_class else None,
        'cycleId': str(school_class.cycle_id) if school_class and school_class.cycle_id else None,
        'cycle': cycle.name if cycle else None,
        'cycleCode': cycle.code.upper() if cycle else None,
        'levelId': str(school_class.school_level_id) if school_class and school_class.school_level_id else None,
        'level': level.name if level else school_class.level if school_class else None,
        'seriesId': str(school_class.series_id) if school_class and school_class.series_id else None,
        'series': series.name if series else None,
        'matricule': item.registration_number,
        'schoolRegime': (
            school_regime_on_date(item, date.today(), session)
            if school_class and school_regime_supported(school_class, session)
            else None
        ),
        'schoolRegimeHistory': student_regime_history_json(item, session),
        'hasTd': item.has_td,
        'options': item.options or {},
        'registrationDate': item.registration_date.isoformat(),
        'status': item.status,
        'transfers': [{
            'id': str(transfer.id),
            'fromClassId': str(transfer.from_class_id),
            'toClassId': str(transfer.to_class_id),
            'effectiveDate': transfer.effective_date.isoformat(),
            'reason': transfer.reason,
            'gradeHandlingDecision': transfer.grade_handling_decision,
        } for transfer in transfers],
        'createdAt': item.created_at.isoformat(),
        'updatedAt': item.updated_at.isoformat(),
    }

def guardian_json(item: Guardian, session: Session) -> dict[str, Any]:
    child_count = session.scalar(select(func.count()).select_from(StudentGuardian).where(
        StudentGuardian.guardian_id == item.id
    ))
    return {
        'id': str(item.id),
        'personId': str(item.person_id) if item.person_id else None,
        'schoolId': public_school_id(session, item.establishment_id),
        'userId': str(item.user_id) if item.user_id else None,
        'firstName': item.first_name,
        'lastName': item.last_name,
        'fullName': f'{item.last_name} {item.first_name}',
        'phone': item.phone,
        'secondPhone': item.second_phone,
        'email': item.email,
        'address': item.address,
        'profession': item.profession,
        'status': item.status,
        'childCount': child_count,
    }

def student_json(item: Student, session: Session, academic_year_id: uuid.UUID | None = None) -> dict[str, Any]:
    registration = None
    if academic_year_id:
        registration = session.scalar(select(StudentAcademicRegistration).where(
            StudentAcademicRegistration.student_id == item.id,
            StudentAcademicRegistration.academic_year_id == academic_year_id,
            StudentAcademicRegistration.status.in_(('pending', 'validated', 'active')),
        ))
    links = session.scalars(select(StudentGuardian).where(StudentGuardian.student_id == item.id)).all()
    guardians = []
    for link in links:
        guardian = session.get(Guardian, link.guardian_id)
        if guardian:
            guardians.append({
                **guardian_json(guardian, session),
                'relationship': link.relationship,
                'isPrimary': link.is_primary,
            })
    registration_data = registration_json(registration, session) if registration else None
    primary_guardian = next((value for value in guardians if value['isPrimary']), None)
    photo = _student_photo_row(session, item.id)
    return {
        'id': str(item.id),
        'schoolId': public_school_id(session, item.establishment_id),
        'userId': str(item.user_id) if item.user_id else None,
        'firstName': item.first_name,
        'lastName': item.last_name,
        'fullName': f'{item.last_name} {item.first_name}',
        'photoUrl': (f'/api/v1/school/students/{item.id}/photo' if photo else None),
        'matricule': registration_data['matricule'] if registration_data else None,
        'birthDate': item.birth_date.isoformat() if item.birth_date else None,
        'nationality': item.nationality,
        'sex': item.gender,
        'email': item.email,
        'phone': item.phone,
        'address': item.address,
        'status': item.status,
        'registration': registration_data,
        'academicYearId': registration_data['academicYearId'] if registration_data else None,
        'classId': registration_data['classId'] if registration_data else None,
        'class': registration_data['className'] if registration_data else None,
        'cycle': registration_data['cycle'] if registration_data else None,
        'levelId': registration_data['levelId'] if registration_data else None,
        'level': registration_data['level'] if registration_data else None,
        'guardians': guardians,
        'parent': primary_guardian['fullName'] if primary_guardian else None,
        'parentPhone': primary_guardian['phone'] if primary_guardian else None,
        'parentEmail': primary_guardian['email'] if primary_guardian else None,
        'createdAt': item.created_at.isoformat(),
        'updatedAt': item.updated_at.isoformat(),
    }

def pre_enrollment_json(item: StudentPreEnrollment, session: Session) -> dict[str, Any]:
    student = session.get(Student, item.student_id)
    year = session.get(AcademicYear, item.academic_year_id)
    school_class = session.get(SchoolClass, item.desired_class_id) if item.desired_class_id else None
    provisional = session.scalar(select(StudentAcademicRegistration).where(
        StudentAcademicRegistration.student_id == item.student_id,
        StudentAcademicRegistration.academic_year_id == item.academic_year_id,
        StudentAcademicRegistration.status == "pre_enrolled",
    ))
    return {
        "id": str(item.id),
        "schoolId": public_school_id(session, item.establishment_id),
        "studentId": str(item.student_id),
        "studentName": f"{student.last_name} {student.first_name}" if student else None,
        "firstName": student.first_name if student else None,
        "lastName": student.last_name if student else None,
        "academicYearId": str(item.academic_year_id),
        "academicYearName": year.name if year else None,
        "desiredClassId": str(item.desired_class_id) if item.desired_class_id else None,
        "desiredClassName": school_class.name if school_class else None,
        "schoolRegime": item.desired_school_regime,
        "provisionalRegistrationId": str(provisional.id) if provisional else None,
        "registrationKind": (provisional.options or {}).get("registrationKind") if provisional else None,
        "status": item.status,
        "submittedAt": item.submitted_at.isoformat() if item.submitted_at else None,
        "decidedAt": item.decided_at.isoformat() if item.decided_at else None,
        "decisionNote": item.decision_note,
        "createdAt": item.created_at.isoformat(),
        "updatedAt": item.updated_at.isoformat(),
    }

def ensure_student_scope(student_id: uuid.UUID, current: Principal, session: Session) -> Student:
    student = session.get(Student, student_id)
    if not student:
        raise HTTPException(404, "Élève introuvable")
    if current.role != "superadmin" and public_school_id(session, student.establishment_id) != current.school_id:
        raise HTTPException(403, "Accès inter-établissement interdit")
    allowed = direction_cycle_scope(current)
    if allowed is not None:
        visible_registration = session.scalar(select(StudentAcademicRegistration.id).join(
            SchoolClass, SchoolClass.id == StudentAcademicRegistration.class_id
        ).where(
            StudentAcademicRegistration.student_id == student.id,
            StudentAcademicRegistration.status.in_(("pending", "validated", "active")),
            SchoolClass.cycle_id.in_(allowed),
        ).limit(1))
        created_here = (
            current.direction_id is not None
            and student.created_direction_id == uuid.UUID(current.direction_id)
        )
        if not visible_registration and not created_here:
            raise HTTPException(403, "Vous n'avez pas acces a cet eleve dans votre direction")
    return student

def ensure_guardian_scope(
    guardian_id: uuid.UUID,
    current: Principal,
    session: Session,
) -> Guardian:
    guardian = session.get(Guardian, guardian_id)
    if not guardian:
        raise HTTPException(404, "Responsable introuvable")
    if current.role != "superadmin" and public_school_id(
        session, guardian.establishment_id
    ) != current.school_id:
        raise HTTPException(403, "Accès inter-établissement interdit")
    allowed = direction_cycle_scope(current)
    if allowed is not None:
        linked_here = session.scalar(
            select(StudentGuardian.id)
            .join(
                StudentAcademicRegistration,
                StudentAcademicRegistration.student_id == StudentGuardian.student_id,
            )
            .join(SchoolClass, SchoolClass.id == StudentAcademicRegistration.class_id)
            .where(
                StudentGuardian.guardian_id == guardian.id,
                StudentAcademicRegistration.status.in_(("pending", "validated", "active")),
                SchoolClass.cycle_id.in_(allowed),
            )
            .limit(1)
        )
        created_here = (
            current.direction_id is not None
            and guardian.created_direction_id == uuid.UUID(current.direction_id)
        )
        if not linked_here and not created_here:
            raise HTTPException(
                403, "Vous n'avez pas accès à ce responsable dans votre direction"
            )
    return guardian

def validate_registration_class(
    establishment_id: uuid.UUID,
    class_id: uuid.UUID,
    session: Session,
    academic_year_id: uuid.UUID | None = None,
    current: Principal | None = None,
) -> SchoolClass:
    school_class = session.get(SchoolClass, class_id)
    if not school_class:
        raise HTTPException(422, "Classe introuvable")
    if school_class.establishment_id != establishment_id:
        raise HTTPException(403, "Classe inter-établissement interdite")
    if academic_year_id and school_class.academic_year_id != academic_year_id:
        raise HTTPException(422, "La classe n'appartient pas à l'année scolaire sélectionnée")
    if school_class.status != "active":
        raise HTTPException(409, "La classe sélectionnée est inactive")
    if current is not None:
        ensure_direction_cycle_access(current, school_class.cycle_id)
    return school_class

def validate_registration_academic_options(
    school_class: SchoolClass,
    has_td: bool,
    session: Session,
) -> None:
    if not has_td:
        return
    level = session.get(SchoolLevel, school_class.school_level_id)
    level_code = (level.code if level else school_class.level or '').strip().upper()
    if level_code not in {'CM2', '3E', 'TERMINALE'}:
        raise HTTPException(
            422,
            "L'option TD est réservée aux niveaux CM2, 3e et Terminale",
        )

def school_regime_supported(school_class: SchoolClass, session: Session) -> bool:
    cycle = session.get(SchoolCycle, school_class.cycle_id) if school_class.cycle_id else None
    return bool(cycle and cycle.code.strip().upper() in {'MATERNELLE', 'PRIMAIRE'})

def validate_school_regime(
    school_class: SchoolClass,
    school_regime: str,
    session: Session,
) -> str:
    if school_regime_supported(school_class, session):
        if school_regime not in {'part_time', 'full_time'}:
            raise HTTPException(
                422,
                "Le régime Mi-temps ou Plein temps est obligatoire en Maternelle et Primaire",
            )
        return school_regime
    if school_regime != 'normal':
        raise HTTPException(
            422,
            "Le régime ne s'applique pas aux cycles Collège et Lycée",
        )
    return 'normal'

def student_regime_history_json(
    registration: StudentAcademicRegistration,
    session: Session,
) -> list[dict[str, Any]]:
    school_class = session.get(SchoolClass, registration.class_id)
    if not school_class or not school_regime_supported(school_class, session):
        return []
    rows = session.scalars(select(StudentRegimeHistory).where(
        StudentRegimeHistory.registration_id == registration.id,
    ).order_by(StudentRegimeHistory.effective_date, StudentRegimeHistory.created_at)).all()
    return [{
        'id': str(item.id),
        'schoolRegime': item.school_regime,
        'effectiveDate': item.effective_date.isoformat(),
        'endDate': item.end_date.isoformat() if item.end_date else None,
        'createdBy': str(item.created_by) if item.created_by else None,
        'createdAt': item.created_at.isoformat(),
    } for item in rows]

def school_regime_on_date(
    registration: StudentAcademicRegistration,
    target_date: date,
    session: Session,
) -> str | None:
    school_class = session.get(SchoolClass, registration.class_id)
    if not school_class or not school_regime_supported(school_class, session):
        return None
    row = session.scalar(select(StudentRegimeHistory).where(
        StudentRegimeHistory.registration_id == registration.id,
        StudentRegimeHistory.effective_date <= target_date,
        (StudentRegimeHistory.end_date.is_(None)) |
        (StudentRegimeHistory.end_date >= target_date),
    ).order_by(StudentRegimeHistory.effective_date.desc()).limit(1))
    if row:
        return row.school_regime
    if registration.school_regime in {'part_time', 'full_time'}:
        return registration.school_regime
    return None

def validate_class_structure(
    establishment_id: uuid.UUID,
    academic_year_id: uuid.UUID,
    cycle_id: uuid.UUID,
    school_level_id: uuid.UUID,
    session: Session,
) -> tuple[AcademicYear, SchoolCycle, SchoolLevel]:
    year = session.get(AcademicYear, academic_year_id)
    if not year:
        raise HTTPException(422, "Année scolaire introuvable")
    if year.establishment_id != establishment_id:
        raise HTTPException(403, "Année scolaire inter-établissement interdite")
    cycle = session.get(SchoolCycle, cycle_id)
    if not cycle:
        raise HTTPException(422, "Cycle introuvable")
    if cycle.establishment_id != establishment_id:
        raise HTTPException(403, "Cycle inter-établissement interdit")
    if cycle.status != "active":
        raise HTTPException(409, "Le cycle sélectionné est inactif")
    level = session.get(SchoolLevel, school_level_id)
    if not level:
        raise HTTPException(422, "Niveau introuvable")
    if level.establishment_id != establishment_id:
        raise HTTPException(403, "Niveau inter-établissement interdit")
    if level.cycle_id != cycle.id:
        raise HTTPException(422, "Le niveau n'appartient pas au cycle sélectionné")
    if level.status != "active":
        raise HTTPException(409, "Le niveau sélectionné est inactif")
    return year, cycle, level
def principal(request: Request, credentials: HTTPAuthorizationCredentials = Depends(bearer), session: Session = Depends(db)) -> Principal:
    try:
        claim = jwt.decode(credentials.credentials, JWT_SECRET, algorithms=["HS256"])
        user_id = uuid.UUID(claim["sub"])
        user = session.get(User, user_id)
        if not user or user.status != "active":
            raise HTTPException(401, "Session invalide ou compte désactivé")
        if not secrets.compare_digest(str(claim["pwd"]), password_revision(user)):
            raise HTTPException(401, "Votre session a expiré. Veuillez vous reconnecter.")
        if not establishment_is_active(session, user.school_id):
            raise HTTPException(403, "Cet établissement est désactivé")
        if not subscription_allows_access(session, user.school_id):
            raise HTTPException(403, "L’abonnement de cet établissement a expiré")
        auth_transition_paths = {"/api/v1/auth/me", "/api/v1/auth/change-password"}
        if must_change_password(session, user) and request.url.path not in auth_transition_paths:
            raise HTTPException(403, "Vous devez d’abord modifier votre mot de passe temporaire")
        teacher_resource = next((resource for resource in session.scalars(select(Resource).where(Resource.kind == "teachers")) if str(resource.payload.get("userId")) == claim["sub"]), None)
        student_resource = next((resource for resource in session.scalars(select(Resource).where(Resource.kind == "students")) if str(resource.payload.get("userId")) == claim["sub"]), None)
        teacher = session.scalar(select(Teacher).where(Teacher.user_id == user_id))
        student = session.scalar(select(Student).where(Student.user_id == user_id))
        ensure_user_role_profile(user, session)
        direction = session.get(SchoolDirection, user.direction_id) if user.direction_id else None
        if user.role == "admin" and not user.direction_id:
            raise HTTPException(
                403,
                "Votre compte administratif doit être rattaché à une direction scolaire avant de pouvoir accéder à cet espace.",
            )
        if user.role == "admin" and user.direction_id and (
            not direction or direction.status != "active"
        ):
            raise HTTPException(403, "Cette direction est inactive")
        direction_cycles = list(session.scalars(select(SchoolDirectionCycle.cycle_id).where(
            SchoolDirectionCycle.direction_id == user.direction_id
        )).all()) if direction else []
        return Principal(id=str(user.id), role=user.role,
            school_id=public_school_id(session, user.school_id),
            teacher_id=str(teacher.id) if teacher else teacher_resource.id if teacher_resource else None,
            student_id=str(student.id) if student else student_resource.id if student_resource else None,
            direction_id=str(direction.id) if direction else None,
            direction_name=direction.name if direction else None,
            direction_cycle_ids=[str(value) for value in direction_cycles],
            legacy_direction_scope=False)
    except (jwt.PyJWTError, KeyError, ValueError) as exc: raise HTTPException(401, "Session invalide ou expirée") from exc
def require(*roles: str):
    def checker(me: Principal = Depends(principal)):
        if me.role not in roles: raise HTTPException(403, "Permission insuffisante")
        return me
    return checker

def require_module(module_id: str):
    def checker(
        me: Principal = Depends(require("superadmin", "admin")),
        session: Session = Depends(db),
    ) -> Principal:
        if module_id == "messages":
            raise HTTPException(410, "Le module Communication est retiré de cette version")
        if me.role == "superadmin" and module_id in SUPERADMIN_RESTRICTED_MODULES:
            raise HTTPException(403, "Ce module n’est pas accessible au Super Admin")
        if me.role == "superadmin":
            return me
        user = session.get(User, uuid.UUID(me.id))
        if not user or not user.school_id:
            raise HTTPException(403, "Aucun établissement associé à cet utilisateur")
        establishment = session.get(Establishment, user.school_id)
        if not establishment:
            raise HTTPException(403, "Établissement associé introuvable")
        if module_id not in set(establishment.enabled_modules or []):
            raise HTTPException(403, f"Module '{module_id}' désactivé pour cet établissement")
        return me
    return checker

def require_module_roles(module_id: str, *roles: str):
    def checker(
        me: Principal = Depends(principal),
        session: Session = Depends(db),
    ) -> Principal:
        if module_id == "messages":
            raise HTTPException(410, "Le module Communication est retiré de cette version")
        if me.role not in roles:
            raise HTTPException(403, "Permission insuffisante")
        if me.role == "superadmin" and module_id in SUPERADMIN_RESTRICTED_MODULES:
            raise HTTPException(403, "Ce module n’est pas accessible au Super Admin")
        if me.role == "superadmin":
            return me
        user = session.get(User, uuid.UUID(me.id))
        if not user or not user.school_id:
            raise HTTPException(403, "Aucun etablissement associe")
        establishment = session.get(Establishment, user.school_id)
        if not establishment or module_id not in set(establishment.enabled_modules or []):
            raise HTTPException(403, f"Module '{module_id}' desactive pour cet etablissement")
        return me
    return checker

def ensure_generic_resource_module_access(
    kind: str,
    current: Principal,
    session: Session,
) -> None:
    module_id = RESOURCE_MODULE_BY_KIND.get(kind)
    if module_id == "messages":
        raise HTTPException(410, "Le module Communication est retiré de cette version")
    if current.role == "superadmin" and module_id in SUPERADMIN_RESTRICTED_MODULES:
        raise HTTPException(403, "Ce module n’est pas accessible au Super Admin")
    if module_id is None or current.role == "superadmin":
        return
    user = session.get(User, uuid.UUID(current.id))
    establishment = (
        session.get(Establishment, user.school_id)
        if user and user.school_id else None
    )
    if not establishment or module_id not in set(establishment.enabled_modules or []):
        raise HTTPException(
            403,
            f"Module '{module_id}' desactive pour cet etablissement",
        )

def tenant_for(kind: str, payload: dict[str, Any], me: Principal) -> str | None:
    school_id = payload.get("schoolId") or payload.get("institutionId")
    if kind == "establishments": return payload.get("id")
    if me.role == "superadmin": return school_id
    if not me.school_id or school_id != me.school_id: raise HTTPException(403, "Accès inter-établissement interdit")
    return school_id

TENANT_REFERENCE_KINDS = {
    "studentId": "students",
    "classId": "classes",
    "teacherId": "teachers",
    "subjectId": "subjects",
    "academicYearId": "academic-years",
    "schoolYearId": "academic-years",
    "evaluationId": "evaluations",
    "affectationId": "affectations",
}

def validate_tenant_references(payload: dict[str, Any], tenant_id: str | None, session: Session) -> None:
    if not tenant_id:
        raise HTTPException(422, "L'établissement est obligatoire")
    for field, reference_kind in TENANT_REFERENCE_KINDS.items():
        reference_id = payload.get(field)
        if reference_id in (None, ""):
            continue
        reference = session.get(Resource, {"kind": reference_kind, "id": str(reference_id)})
        if not reference:
            raise HTTPException(422, f"Référence {field} introuvable")
        if reference.school_id != tenant_id:
            raise HTTPException(403, f"Référence {field} inter-établissement interdite")
    for field, reference_kind in {
        "studentIds": "students", "classIds": "classes", "teacherIds": "teachers", "subjectIds": "subjects",
    }.items():
        values = payload.get(field)
        if values is None:
            continue
        if not isinstance(values, list):
            raise HTTPException(422, f"La référence {field} doit être une liste")
        for reference_id in values:
            reference = session.get(Resource, {"kind": reference_kind, "id": str(reference_id)})
            if not reference:
                raise HTTPException(422, f"Référence {field} introuvable")
            if reference.school_id != tenant_id:
                raise HTTPException(403, f"Référence {field} inter-établissement interdite")
    for field in ("parentUserId", "studentUserId", "teacherUserId", "userId"):
        reference_id = payload.get(field)
        if reference_id in (None, ""):
            continue
        try:
            user = session.get(User, uuid.UUID(str(reference_id)))
        except ValueError:
            user = None
        if not user:
            raise HTTPException(422, f"Référence {field} introuvable")
        if public_school_id(session, user.school_id) != tenant_id:
            raise HTTPException(403, f"Référence {field} inter-établissement interdite")

def structured_resource_columns(
    kind: str,
    payload: dict[str, Any],
    tenant_id: str | None,
    session: Session,
    existing: Resource | None = None,
) -> tuple[uuid.UUID | None, uuid.UUID | None, uuid.UUID | None, uuid.UUID | None]:
    establishment_id = resolve_establishment_id(session, tenant_id)
    cycle_id = existing.cycle_id if existing else None
    school_level_id = existing.school_level_id if existing else None
    academic_year_id = existing.academic_year_id if existing else None
    if kind != "classes":
        return establishment_id, cycle_id, school_level_id, academic_year_id

    has_structured_cycle = "cycleId" in payload or "structuredLevelId" in payload
    if not has_structured_cycle and existing and existing.cycle_id:
        payload["cycleId"] = str(existing.cycle_id)
        if existing.school_level_id:
            payload["structuredLevelId"] = str(existing.school_level_id)
    if has_structured_cycle:
        if not establishment_id:
            raise HTTPException(409, "Relation établissement invalide")
        if not payload.get("cycleId") or not payload.get("structuredLevelId"):
            raise HTTPException(422, "Le cycle et le niveau structurés sont obligatoires")
        if not payload.get("academicYearId") and not payload.get("schoolYearId"):
            raise HTTPException(422, "L'année scolaire est obligatoire")
        try:
            cycle_id = uuid.UUID(str(payload["cycleId"]))
            school_level_id = uuid.UUID(str(payload["structuredLevelId"]))
        except ValueError as exc:
            raise HTTPException(422, "Référence cycle ou niveau invalide") from exc
        cycle = session.get(SchoolCycle, cycle_id)
        if not cycle:
            raise HTTPException(422, "Cycle introuvable")
        if cycle.establishment_id != establishment_id:
            raise HTTPException(403, "Cycle inter-établissement interdit")
        if cycle.status != "active":
            raise HTTPException(409, "Le cycle sélectionné est inactif")
        level = session.get(SchoolLevel, school_level_id)
        if not level:
            raise HTTPException(422, "Niveau introuvable")
        if level.establishment_id != establishment_id:
            raise HTTPException(403, "Niveau inter-établissement interdit")
        if level.cycle_id != cycle.id:
            raise HTTPException(422, "Le niveau n'appartient pas au cycle sélectionné")
        if level.status != "active":
            raise HTTPException(409, "Le niveau sélectionné est inactif")
        payload["cycle"] = cycle.name
        payload["level"] = level.name

    year_reference = payload.get("academicYearId") or payload.get("schoolYearId")
    if year_reference and establishment_id:
        try:
            candidate_year = uuid.UUID(str(year_reference))
        except ValueError:
            candidate_year = None
        if candidate_year and session.scalar(text(
            "SELECT EXISTS(SELECT 1 FROM academic_years WHERE id=:id AND establishment_id=:school_id)"
        ), {"id": candidate_year, "school_id": establishment_id}):
            academic_year_id = candidate_year
    return establishment_id, cycle_id, school_level_id, academic_year_id

def validate_registration_class_consistency(
    kind: str,
    payload: dict[str, Any],
    tenant_id: str | None,
    session: Session,
) -> None:
    if kind != "student-registrations":
        return
    required_fields = ("studentId", "classId", "academicYearId")
    missing = [field for field in required_fields if not payload.get(field)]
    if missing:
        raise HTTPException(422, f"Champs obligatoires manquants: {', '.join(missing)}")
    class_row = session.get(Resource, {"kind": "classes", "id": str(payload["classId"])})
    if not class_row:
        raise HTTPException(422, "Classe introuvable")
    if class_row.school_id != tenant_id:
        raise HTTPException(403, "Classe inter-établissement interdite")
    class_year = class_row.payload.get("academicYearId") or class_row.payload.get("schoolYearId")
    if class_year and str(class_year) != str(payload["academicYearId"]):
        raise HTTPException(422, "La classe n'appartient pas à l'année scolaire sélectionnée")

def teacher_has_class_access(class_id: str | None, me: Principal, session: Session | None) -> bool:
    if not class_id or not me.teacher_id or session is None:
        return False
    for affectation in session.scalars(select(Resource).where(Resource.kind == "affectations")):
        payload = affectation.payload
        if str(payload.get("classId")) == str(class_id) and (
            str(payload.get("teacherId")) == me.teacher_id or str(payload.get("teacherUserId")) == me.id
        ):
            return True
    return False

def announcement_audience_matches(payload: dict[str, Any], me: Principal, session: Session | None) -> bool:
    target_role = payload.get("targetRole")
    if target_role and target_role != me.role:
        return False
    class_id = payload.get("classId")
    cycle = payload.get("cycle")
    level_id = payload.get("levelId")
    if not class_id and not cycle and not level_id:
        return True
    if me.role == "teacher":
        return teacher_has_class_access(str(class_id), me, session)
    if session is None:
        return False
    for student in session.scalars(select(Resource).where(Resource.kind == "students")):
        data = student.payload
        if class_id and str(data.get("classId")) != str(class_id):
            continue
        if cycle and str(data.get("cycle", "")).lower() != str(cycle).lower():
            continue
        if level_id and str(data.get("levelId")) != str(level_id):
            continue
        if me.role == "student" and str(data.get("userId")) == me.id:
            return True
        if me.role == "parent" and str(data.get("parentUserId")) == me.id:
            return True
    return False

def visible(row: Resource, me: Principal, session: Session | None = None) -> bool:
    if me.role == "superadmin":
        return RESOURCE_MODULE_BY_KIND.get(row.kind) not in SUPERADMIN_RESTRICTED_MODULES
    if row.school_id != me.school_id:
        return False
    module_id = RESOURCE_MODULE_BY_KIND.get(row.kind)
    if module_id is not None:
        if session is None:
            return False
        database_id = resolve_establishment_id(session, me.school_id)
        establishment = session.get(Establishment, database_id) if database_id else None
        if not establishment or module_id not in set(establishment.enabled_modules or []):
            return False
    if me.role == "admin":
        if session is not None and direction_cycle_scope(me) is not None:
            direction_scoped_kinds = {
                "students", "teachers", "classes", "subjects", "evaluations",
                "grades", "affectations", "absences", "assignments",
                "documents", "student-registrations", "finance-fees",
                "finance-registrations", "finance-fee-assignments",
                "finance-payments", "finance-receipts", "annual-bulletins",
                "annual-decisions", "re-enrollment-requests",
                "behavior-assessments",
            }
            if row.kind in direction_scoped_kinds:
                return direction_resource_allowed(me, row, session)
        return True
    # Non-admin roles must be explicitly linked in the resource payload.  This
    # fails closed until the account-to-person association exists, preventing a
    # student, parent or teacher from receiving another user's tenant data.
    payload = row.payload
    if me.role == "teacher":
        if row.kind == "announcements":
            return announcement_audience_matches(payload, me, session) or str(payload.get("authorUserId")) == me.id
        if row.kind == "classes":
            return teacher_has_class_access(payload.get("id"), me, session)
        if row.kind == "students":
            return teacher_has_class_access(payload.get("classId"), me, session)
        if row.kind == "behavior-assessments":
            return teacher_has_class_access(payload.get("classId"), me, session)
        return me.teacher_id is not None and (me.teacher_id in {str(payload.get("teacherId")), str(payload.get("enteredBy"))} or me.teacher_id in {str(value) for value in payload.get("teacherIds", [])} or me.id == str(payload.get("createdBy")))
    if me.role == "student":
        if row.kind == "announcements":
            return announcement_audience_matches(payload, me, session)
        return me.id in {str(payload.get("userId")), str(payload.get("studentUserId"))} or me.student_id == str(payload.get("studentId"))
    if me.role == "parent":
        if row.kind == "announcements":
            return announcement_audience_matches(payload, me, session)
        return me.id == str(payload.get("parentUserId")) or me.id in {str(value) for value in payload.get("parentUserIds", [])}
    return False

app = FastAPI(title="EduPro API", version="1.0.0")
origins = [
    value.strip()
    for value in os.getenv("CORS_ORIGINS", "http://localhost:3000").split(",")
    if value.strip()
]
app.add_middleware(
    CORSMiddleware,
    allow_origins=origins,
    allow_origin_regex=r"^https?://(localhost|127\.0\.0\.1)(:\d+)?$",
    allow_credentials=True,
    allow_methods=["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
    allow_headers=[
        "Authorization",
        "Content-Type",
        "Accept",
        "ngrok-skip-browser-warning",
    ],
)

@app.middleware("http")
async def add_security_headers(request: Request, call_next):
    response = await call_next(request)
    response.headers.setdefault("X-Content-Type-Options", "nosniff")
    response.headers.setdefault("X-Frame-Options", "DENY")
    response.headers.setdefault("Referrer-Policy", "no-referrer")
    response.headers.setdefault("Permissions-Policy", "camera=(), microphone=(), geolocation=()")
    if request.url.path.startswith("/api/v1/auth"):
        response.headers.setdefault("Cache-Control", "no-store")
    return response

@app.on_event("startup")
def startup():
    # Startup prepares the schema only. Privileged identities and business
    # data must be restored or provisioned through an explicit operation.
    Base.metadata.create_all(engine)

@app.get("/health")
@app.get("/api/v1/health")
def health(session: Session = Depends(db)): session.execute(select(User.id).limit(1)); return {"status":"ok"}

@app.api_route("/api/v1/auth/activate", methods=["GET", "POST"], include_in_schema=False)
def removed_activation_endpoint():
    raise HTTPException(404, "Not Found")

def normalize_login_phone(value: str | None) -> str | None:
    """Return an E.164-like canonical phone used only for authentication matching.

    Congolese local numbers (9 digits, usually beginning with 0) are normalized
    to +242. International numbers must include their country prefix (or 00).
    Formatting spaces, dashes and parentheses are ignored.
    """
    if not value:
        return None
    raw = value.strip()
    digits = re.sub(r"\D", "", raw)
    if not digits:
        return None
    if raw.startswith("00") and digits.startswith("00"):
        digits = digits[2:]
    if digits.startswith("242"):
        return f"+{digits}"
    if len(digits) == 9:
        return f"+242{digits}"
    if raw.startswith("+") and 8 <= len(digits) <= 15:
        return f"+{digits}"
    return None

def login_candidates(identifier: str, session: Session) -> list[User]:
    """Resolve email, official matricule or phone for an authenticated profile.

    Phone login is supported for teacher, student and parent profiles. Ambiguous
    identifiers fail closed later unless exactly one password-valid account is
    found.
    """
    normalized = identifier.strip().lower()
    if "@" in normalized:
        user = session.scalar(select(User).where(func.lower(User.email) == normalized))
        # A phone-number login complements the regular e-mail identifier; it
        # must not make the e-mail accounts of teachers or students unusable.
        # ``users.email`` is unique, so this lookup stays unambiguous.
        return [user] if user else []

    candidates: dict[uuid.UUID, User] = {}
    normalized_phone = normalize_login_phone(identifier)
    if normalized_phone:
        for profile in session.scalars(select(Teacher).where(Teacher.status == "active", Teacher.user_id.is_not(None))).all():
            if normalize_login_phone(profile.phone) == normalized_phone:
                user = session.get(User, profile.user_id)
                if user and user.role == "teacher":
                    candidates[user.id] = user
        for profile in session.scalars(select(Student).where(Student.status == "active", Student.user_id.is_not(None))).all():
            if normalize_login_phone(profile.phone) == normalized_phone:
                user = session.get(User, profile.user_id)
                if user and user.role == "student":
                    candidates[user.id] = user
        for profile in session.scalars(select(Guardian).where(Guardian.status == "active", Guardian.user_id.is_not(None))).all():
            if normalized_phone in {normalize_login_phone(profile.phone), normalize_login_phone(profile.second_phone)}:
                user = session.get(User, profile.user_id)
                if user and user.role == "parent":
                    candidates[user.id] = user
        if candidates:
            return list(candidates.values())
    teacher_users = session.scalars(
        select(User)
        .join(Teacher, Teacher.user_id == User.id)
        .where(
            User.role == "teacher",
            func.lower(func.coalesce(Teacher.employee_number, "")) == normalized,
            Teacher.status == "active",
        )
    ).all()
    for user in teacher_users:
        candidates[user.id] = user

    student_users = session.scalars(
        select(User)
        .join(Student, Student.user_id == User.id)
        .outerjoin(
            StudentAcademicRegistration,
            StudentAcademicRegistration.student_id == Student.id,
        )
        .where(
            User.role == "student",
            Student.status == "active",
            or_(
                func.lower(func.coalesce(Student.registration_number, "")) == normalized,
                (
                    func.lower(func.coalesce(
                        StudentAcademicRegistration.registration_number, ""
                    )) == normalized
                )
                & StudentAcademicRegistration.status.in_(("pending", "validated", "active")),
            ),
        )
        .distinct()
    ).all()
    for user in student_users:
        candidates[user.id] = user
    return list(candidates.values())

def password_matches(user: User, password: str) -> bool:
    try:
        return bool(user.password_hash and passwords.verify(password, user.password_hash))
    except (TypeError, ValueError):
        return False

def authentication_request_key(request: Request) -> str:
    """Use the socket peer only; forwarded headers are intentionally untrusted."""
    return request.client.host if request.client else "unknown"

def login_rate_limit_keys(identifier: str, request_key: str) -> tuple[str, str]:
    identifier_fingerprint = hashlib.sha256(
        identifier.strip().lower().encode("utf-8")
    ).hexdigest()
    return (
        f"peer:{request_key}",
        f"peer-identity:{request_key}:{identifier_fingerprint}",
    )

def prune_login_failures(now: float) -> None:
    cutoff = now - AUTH_RATE_LIMIT_WINDOW_SECONDS
    for key, timestamps in list(_LOGIN_FAILURES.items()):
        active = [timestamp for timestamp in timestamps if timestamp > cutoff]
        if active:
            _LOGIN_FAILURES[key] = active
        else:
            _LOGIN_FAILURES.pop(key, None)

def enforce_login_rate_limit(identifier: str, request_key: str | None) -> None:
    if not request_key:
        return
    now = monotonic()
    with _LOGIN_FAILURES_LOCK:
        prune_login_failures(now)
        peer_key, identity_key = login_rate_limit_keys(identifier, request_key)
        if (
            len(_LOGIN_FAILURES.get(identity_key, ())) >= AUTH_RATE_LIMIT_ATTEMPTS
            or len(_LOGIN_FAILURES.get(peer_key, ())) >= AUTH_RATE_LIMIT_PEER_ATTEMPTS
        ):
            raise HTTPException(
                status.HTTP_429_TOO_MANY_REQUESTS,
                "Trop de tentatives de connexion. Réessayez dans quelques minutes.",
                headers={"Retry-After": str(AUTH_RATE_LIMIT_WINDOW_SECONDS)},
            )

def record_login_failure(identifier: str, request_key: str | None) -> None:
    if not request_key:
        return
    now = monotonic()
    with _LOGIN_FAILURES_LOCK:
        prune_login_failures(now)
        for key in login_rate_limit_keys(identifier, request_key):
            _LOGIN_FAILURES.setdefault(key, []).append(now)

def clear_login_failures(identifier: str, request_key: str | None) -> None:
    if not request_key:
        return
    with _LOGIN_FAILURES_LOCK:
        _, identity_key = login_rate_limit_keys(identifier, request_key)
        _LOGIN_FAILURES.pop(identity_key, None)

@app.post("/api/v1/auth/login")
def login(
    body: LoginInput,
    session: Session = Depends(db),
    rate_key: str | None = Depends(authentication_request_key),
):
    # Unit-level callers pass the session positionally and therefore leave the
    # FastAPI dependency marker in place. Only an injected string is a real
    # network peer key.
    request_key = rate_key if isinstance(rate_key, str) else None
    identifier = str(body.identifier)
    enforce_login_rate_limit(identifier, request_key)
    candidates = login_candidates(identifier, session)
    if not candidates:
        passwords.verify(body.password, _DUMMY_PASSWORD_HASH)
    matching = [
        user for user in candidates
        if user.status == "active" and password_matches(user, body.password)
    ]
    if len(matching) != 1:
        record_login_failure(identifier, request_key)
        raise HTTPException(401, "Identifiant ou mot de passe incorrect.")
    user = matching[0]
    if not establishment_is_active(session, user.school_id):
        raise HTTPException(403, "Cet établissement est désactivé")
    if not subscription_allows_access(session, user.school_id):
        raise HTTPException(403, "L’abonnement de cet établissement a expiré")
    ensure_user_role_profile(user, session)
    if user.role == "admin" and not user.direction_id:
        raise HTTPException(
            403,
            "Votre compte administratif doit être rattaché à une direction scolaire avant de pouvoir accéder à cet espace.",
        )
    consume_temporary_access(session, user)
    token = issue_access_token(user, session)
    clear_login_failures(identifier, request_key)
    return {"accessToken":token,"user":user_json(user, session)}
@app.get("/api/v1/auth/me")
def me(current: Principal = Depends(principal), session: Session = Depends(db)):
    user = session.get(User, uuid.UUID(current.id)); return user_json(user, session)
@app.put("/api/v1/auth/profile")
def update_own_profile(
    body: ProfileUpdateInput,
    current: Principal = Depends(principal),
    session: Session = Depends(db),
):
    if current.role not in {"admin", "superadmin"}:
        raise HTTPException(403, "La modification du profil est réservée aux administrateurs")
    user = session.get(User, uuid.UUID(current.id))
    if not user:
        raise HTTPException(404, "Utilisateur introuvable")
    duplicate = session.scalar(select(User.id).where(
        func.lower(User.email) == body.email,
        User.id != user.id,
    ))
    if duplicate:
        raise HTTPException(409, "Cette adresse e-mail est déjà utilisée")
    user.name = body.name
    user.email = body.email
    user.updated_at = datetime.now(timezone.utc)
    session.commit()
    session.refresh(user)
    return user_json(user, session)

def _user_profile_photo_row(
    session: Session, user_id: uuid.UUID
) -> Resource | None:
    return session.get(
        Resource, {"kind": "user-profile-photos", "id": str(user_id)}
    )

@app.get("/api/v1/auth/profile/photo")
def get_own_profile_photo(
    current: Principal = Depends(principal),
    session: Session = Depends(db),
):
    row = _user_profile_photo_row(session, uuid.UUID(current.id))
    path = Path(str(row.payload.get("path"))) if row and row.payload.get("path") else None
    if not row or not path or not path.is_file():
        raise HTTPException(404, "Photo de profil introuvable")
    return Response(
        content=path.read_bytes(),
        media_type=row.payload.get("mimeType") or "image/jpeg",
        headers={"Cache-Control": "private, max-age=300"},
    )

@app.put("/api/v1/auth/profile/photo")
def update_own_profile_photo(
    body: StudentPhotoUpdateInput,
    current: Principal = Depends(principal),
    session: Session = Depends(db),
):
    if current.role not in {"admin", "superadmin"}:
        raise HTTPException(403, "La photo de profil est gérée par l’administration")
    user_id = uuid.UUID(current.id)
    content, extension = _decode_student_photo(body)
    target_dir = USER_PROFILE_PHOTO_ROOT / str(user_id)
    target_dir.mkdir(parents=True, exist_ok=True)
    target = target_dir / f"profile{extension}"
    temporary = target_dir / f".profile-{uuid.uuid4().hex}.tmp"
    temporary.write_bytes(content)
    temporary.replace(target)
    row = _user_profile_photo_row(session, user_id)
    old_path = Path(str(row.payload.get("path"))) if row and row.payload.get("path") else None
    payload = {
        "userId": str(user_id),
        "path": str(target),
        "mimeType": body.mime_type.lower(),
        "originalName": body.name,
        "size": len(content),
        "updatedAt": datetime.now(timezone.utc).isoformat(),
    }
    if row:
        row.payload = payload
        row.updated_at = datetime.now(timezone.utc)
    else:
        session.add(Resource(
            id=str(user_id),
            kind="user-profile-photos",
            school_id=current.school_id,
            establishment_id=resolve_establishment_id(session, current.school_id),
            payload=payload,
        ))
    if old_path and old_path != target and old_path.is_file() and old_path.parent == target_dir:
        old_path.unlink(missing_ok=True)
    session.commit()
    return {"updatedAt": payload["updatedAt"]}

@app.post("/api/v1/auth/change-password")
def change_password(body: ChangePasswordInput, current: Principal = Depends(principal), session: Session = Depends(db)):
    user = session.get(User, uuid.UUID(current.id))
    forced_change = bool(user and must_change_password(session, user))
    if not user or (not forced_change and (not body.current_password or not passwords.verify(body.current_password, user.password_hash))):
        raise HTTPException(401, "Mot de passe actuel invalide")
    if body.new_password != body.new_password_confirmation:
        raise HTTPException(422, "Les mots de passe ne correspondent pas.")
    validate_new_password(body.new_password)
    if passwords.verify(body.new_password, user.password_hash):
        raise HTTPException(409, "Le nouveau mot de passe doit être différent du mot de passe actuel.")
    user.password_hash = passwords.hash(body.new_password)
    user.password_set = True
    user.updated_at = datetime.now(timezone.utc)
    if password_policy_available(session):
        session.execute(text("UPDATE users SET must_change_password = FALSE WHERE id = :id"), {"id": user.id})
    grant = temporary_access(session, user)
    if grant:
        session.delete(grant)
    session.commit()
    session.refresh(user)
    return {"accessToken": issue_access_token(user, session), "user": user_json(user, session)}
@app.get("/api/v1/bootstrap")
def bootstrap(current: Principal = Depends(principal), session: Session = Depends(db)):
    rows = session.scalars(select(Resource)).all(); data = {kind: [] for kind in KINDS}
    for row in rows:
        if row.kind in data and visible(row, current, session):
            if row.kind == "notifications":
                payload = dict(row.payload)
                read_by = {str(value) for value in payload.get("readByUserIds", [])}
                payload["read"] = bool(payload.get("read")) or current.id in read_by
                data[row.kind].append(payload)
            else:
                data[row.kind].append(row.payload)
    cycles = session.scalars(select(SchoolCycle).order_by(SchoolCycle.sort_order, SchoolCycle.name)).all()
    if current.role != "superadmin":
        database_id = resolve_establishment_id(session, current.school_id)
        cycles = [cycle for cycle in cycles if cycle.establishment_id == database_id]
        establishment = session.get(Establishment, database_id) if database_id else None
        if not establishment or "classes" not in set(establishment.enabled_modules or []):
            cycles = []
    allowed = direction_cycle_scope(current)
    if allowed is not None:
        cycles = [cycle for cycle in cycles if cycle.id in allowed]
    cycle_ids = {cycle.id for cycle in cycles}
    levels = session.scalars(select(SchoolLevel).order_by(SchoolLevel.sort_order, SchoolLevel.name)).all()
    data["cycles"] = [cycle_json(cycle, session) for cycle in cycles]
    data["school-levels"] = [
        level_json(level, session) for level in levels if level.cycle_id in cycle_ids
    ]
    return data

@app.get("/api/v1/school/cycles/catalog")
def school_cycle_catalog(_: Principal = Depends(require_module("classes"))):
    return list(CYCLE_CATALOG_BY_CODE.values())

@app.get("/api/v1/school/cycles")
def list_school_cycles(
    school_id: str | None = None,
    current: Principal = Depends(require_module("classes")),
    session: Session = Depends(db),
):
    _, database_id = school_scope(current, session, school_id, required=False)
    statement = select(SchoolCycle).order_by(SchoolCycle.sort_order, SchoolCycle.name)
    if database_id:
        statement = statement.where(SchoolCycle.establishment_id == database_id)
    allowed = direction_cycle_scope(current)
    if allowed is not None:
        statement = statement.where(SchoolCycle.id.in_(allowed))
    return [cycle_json(cycle, session) for cycle in session.scalars(statement).all()]

@app.get("/api/v1/school/cycles/{cycle_id}")
def get_school_cycle(
    cycle_id: uuid.UUID,
    current: Principal = Depends(require_module("classes")),
    session: Session = Depends(db),
):
    return cycle_json(scoped_cycle(cycle_id, current, session), session)

@app.post("/api/v1/school/cycles", status_code=201)
def create_school_cycle(
    body: CycleCreateInput,
    current: Principal = Depends(require("superadmin")),
    session: Session = Depends(db),
):
    _, database_id = school_scope(current, session, body.school_id, required=True)
    catalog = CYCLE_CATALOG_BY_CODE[body.code]
    cycle = SchoolCycle(
        establishment_id=database_id,
        code=body.code,
        name=catalog["name"],
        status=body.status,
        sort_order=body.sort_order if body.sort_order is not None else catalog["sortOrder"],
    )
    session.add(cycle)
    try:
        session.commit()
    except IntegrityError as exc:
        session.rollback()
        raise HTTPException(409, "Ce cycle existe déjà pour cet établissement") from exc
    session.refresh(cycle)
    return cycle_json(cycle, session)

@app.put("/api/v1/school/cycles/{cycle_id}")
def update_school_cycle(
    cycle_id: uuid.UUID,
    body: CycleUpdateInput,
    current: Principal = Depends(require_module("classes")),
    session: Session = Depends(db),
):
    if not body.model_fields_set:
        raise HTTPException(422, "Aucun champ à modifier")
    cycle = scoped_cycle(cycle_id, current, session)
    for field, value in body.model_dump(include=body.model_fields_set).items():
        setattr(cycle, field, value)
    cycle.updated_at = datetime.now(timezone.utc)
    session.commit()
    session.refresh(cycle)
    return cycle_json(cycle, session)

@app.get("/api/v1/school/cycles/{cycle_id}/levels")
def list_school_levels(
    cycle_id: uuid.UUID,
    current: Principal = Depends(require_module("classes")),
    session: Session = Depends(db),
):
    cycle = scoped_cycle(cycle_id, current, session)
    levels = session.scalars(
        select(SchoolLevel)
        .where(SchoolLevel.cycle_id == cycle.id)
        .order_by(SchoolLevel.sort_order, SchoolLevel.name)
    ).all()
    return [level_json(level, session, cycle) for level in levels]

@app.post("/api/v1/school/cycles/{cycle_id}/levels", status_code=201)
def create_school_level(
    cycle_id: uuid.UUID,
    body: SchoolLevelCreateInput,
    current: Principal = Depends(require_module("classes")),
    session: Session = Depends(db),
):
    _, database_id = school_scope(current, session, body.school_id, required=True)
    cycle = scoped_cycle(cycle_id, current, session)
    if cycle.establishment_id != database_id:
        raise HTTPException(403, "Cycle inter-établissement interdit")
    level = SchoolLevel(
        establishment_id=database_id,
        cycle_id=cycle.id,
        code=body.code,
        name=body.name,
        status=body.status,
        sort_order=body.sort_order,
    )
    session.add(level)
    try:
        session.commit()
    except IntegrityError as exc:
        session.rollback()
        raise HTTPException(409, "Ce niveau existe déjà dans ce cycle") from exc
    session.refresh(level)
    return level_json(level, session, cycle)

@app.get("/api/v1/school/levels/{level_id}")
def get_school_level(
    level_id: uuid.UUID,
    current: Principal = Depends(require_module("classes")),
    session: Session = Depends(db),
):
    return level_json(scoped_level(level_id, current, session), session)

@app.put("/api/v1/school/levels/{level_id}")
def update_school_level(
    level_id: uuid.UUID,
    body: SchoolLevelUpdateInput,
    current: Principal = Depends(require_module("classes")),
    session: Session = Depends(db),
):
    if not body.model_fields_set:
        raise HTTPException(422, "Aucun champ à modifier")
    level = scoped_level(level_id, current, session)
    for field, value in body.model_dump(include=body.model_fields_set).items():
        setattr(level, field, value)
    level.updated_at = datetime.now(timezone.utc)
    try:
        session.commit()
    except IntegrityError as exc:
        session.rollback()
        raise HTTPException(409, "Ce niveau existe déjà dans ce cycle") from exc
    session.refresh(level)
    return level_json(level, session)

@app.get("/api/v1/school/academic-years")
def list_academic_years(
    school_id: str | None = None,
    current: Principal = Depends(require_module("academic_years")),
    session: Session = Depends(db),
):
    _, database_id = school_scope(current, session, school_id, required=True)
    statement = (
        select(AcademicYear)
        .where(AcademicYear.establishment_id == database_id)
        .order_by(AcademicYear.start_date.desc(), AcademicYear.name.desc())
    )
    return [academic_year_json(year, session) for year in session.scalars(statement).all()]

@app.post("/api/v1/school/academic-years", status_code=201)
def create_academic_year(
    body: AcademicYearCreateInput,
    current: Principal = Depends(require_module("academic_years")),
    session: Session = Depends(db),
):
    _, database_id = school_scope(current, session, body.school_id, required=True)
    duplicate = session.scalar(
        select(AcademicYear).where(
            AcademicYear.establishment_id == database_id,
            func.lower(AcademicYear.name) == body.name.lower(),
        )
    )
    if duplicate:
        raise HTTPException(409, "Cette année scolaire existe déjà")
    has_year = session.scalar(
        select(func.count()).select_from(AcademicYear).where(
            AcademicYear.establishment_id == database_id
        )
    ) > 0
    year = AcademicYear(
        establishment_id=database_id,
        name=body.name,
        start_date=body.start_date,
        end_date=body.end_date,
        is_active=not has_year,
        status="inactive" if has_year else "active",
    )
    session.add(year)
    try:
        session.commit()
    except IntegrityError as exc:
        session.rollback()
        raise HTTPException(409, "Impossible de créer cette année scolaire") from exc
    session.refresh(year)
    return academic_year_json(year, session)

@app.put("/api/v1/school/academic-years/{year_id}")
def update_academic_year(
    year_id: uuid.UUID,
    body: AcademicYearUpdateInput,
    current: Principal = Depends(require_module("academic_years")),
    session: Session = Depends(db),
):
    year = session.get(AcademicYear, year_id)
    if not year:
        raise HTTPException(404, "Année scolaire introuvable")
    if current.role != "superadmin" and public_school_id(session, year.establishment_id) != current.school_id:
        raise HTTPException(403, "Accès inter-établissement interdit")
    duplicate = session.scalar(select(AcademicYear).where(
        AcademicYear.establishment_id == year.establishment_id,
        func.lower(AcademicYear.name) == body.name.lower(),
        AcademicYear.id != year.id,
    ))
    if duplicate:
        raise HTTPException(409, "Cette année scolaire existe déjà")
    year.name, year.start_date, year.end_date = body.name, body.start_date, body.end_date
    year.updated_at = datetime.now(timezone.utc)
    session.commit(); session.refresh(year)
    return academic_year_json(year, session)

@app.put("/api/v1/school/academic-years/{year_id}")
def update_academic_year(
    year_id: uuid.UUID,
    body: AcademicYearUpdateInput,
    current: Principal = Depends(require_module("academic_years")),
    session: Session = Depends(db),
):
    year = session.get(AcademicYear, year_id)
    if not year:
        raise HTTPException(404, "Année scolaire introuvable")
    if current.role != "superadmin" and public_school_id(session, year.establishment_id) != current.school_id:
        raise HTTPException(403, "Accès inter-établissement interdit")
    duplicate = session.scalar(select(AcademicYear).where(
        AcademicYear.establishment_id == year.establishment_id,
        func.lower(AcademicYear.name) == body.name.lower(),
        AcademicYear.id != year.id,
    ))
    if duplicate:
        raise HTTPException(409, "Cette année scolaire existe déjà")
    year.name, year.start_date, year.end_date = body.name, body.start_date, body.end_date
    year.updated_at = datetime.now(timezone.utc)
    session.commit(); session.refresh(year)
    return academic_year_json(year, session)

@app.post("/api/v1/school/academic-years/{year_id}/copy-configuration")
def copy_academic_year_configuration(
    year_id: uuid.UUID,
    body: AcademicYearCopyConfigurationInput,
    current: Principal = Depends(require_module_roles("academic_years", "superadmin", "admin")),
    session: Session = Depends(db),
):
    """Copy non-personal structural configuration into an existing year.

    The operation is additive/idempotent: it never deletes or overwrites
    existing target configuration. Teacher identities are not duplicated; their
    class/subject affectations are reproduced on the corresponding target-year
    classes. Students, schedules, finance, grades and documents are excluded.
    """
    target = session.get(AcademicYear, year_id)
    source = session.get(AcademicYear, body.source_year_id)
    if not target or not source:
        raise HTTPException(404, "Année scolaire introuvable")
    if source.id == target.id:
        raise HTTPException(422, "L’année source et l’année cible doivent être différentes")
    if source.establishment_id != target.establishment_id:
        raise HTTPException(403, "Copie inter-établissement interdite")
    if current.role != "superadmin":
        _, database_id = module_tenant_scope(current, session)
        if target.establishment_id != database_id:
            raise HTTPException(403, "Accès inter-établissement interdit")

    allowed_cycles = direction_cycle_scope(current)
    counts = {"classes": 0, "teacherAffectations": 0, "subjectSettings": 0, "evaluationRules": 0, "calendarSettings": 0}
    class_map: dict[uuid.UUID, SchoolClass] = {}

    source_classes = session.scalars(select(SchoolClass).where(
        SchoolClass.establishment_id == source.establishment_id,
        SchoolClass.academic_year_id == source.id,
        SchoolClass.status != "archived",
    )).all()
    for item in source_classes:
        if allowed_cycles is not None and item.cycle_id not in allowed_cycles:
            continue
        existing = session.scalar(select(SchoolClass).where(
            SchoolClass.establishment_id == target.establishment_id,
            SchoolClass.academic_year_id == target.id,
            func.lower(SchoolClass.name) == item.name.lower(),
            SchoolClass.school_level_id == item.school_level_id,
            SchoolClass.series_id == item.series_id,
        ))
        if existing:
            class_map[item.id] = existing
            continue
        cloned = SchoolClass(
            establishment_id=target.establishment_id,
            academic_year_id=target.id,
            name=item.name,
            level=item.level,
            capacity=item.capacity,
            status=item.status,
            cycle_id=item.cycle_id,
            school_level_id=item.school_level_id,
            series_id=item.series_id,
            main_teacher_id=item.main_teacher_id,
        )
        session.add(cloned)
        session.flush()
        class_map[item.id] = cloned
        counts["classes"] += 1

    # Teachers are permanent people, not year-specific rows. Reuse those same
    # teacher identities and copy only their pedagogical affectations.
    source_affectations = session.scalars(select(Affectation).where(
        Affectation.establishment_id == source.establishment_id,
        Affectation.class_id.in_(list(class_map.keys())),
        Affectation.status == "active",
    )).all() if class_map else []
    for item in source_affectations:
        target_class = class_map.get(item.class_id)
        if not target_class:
            continue
        existing = session.scalar(select(Affectation).where(
            Affectation.establishment_id == target.establishment_id,
            Affectation.teacher_id == item.teacher_id,
            Affectation.class_id == target_class.id,
            Affectation.subject_id == item.subject_id,
            Affectation.status == "active",
        ))
        if existing:
            continue
        session.add(Affectation(
            establishment_id=target.establishment_id,
            teacher_id=item.teacher_id,
            class_id=target_class.id,
            subject_id=item.subject_id,
            status="active",
        ))
        counts["teacherAffectations"] += 1

    source_settings = session.scalars(select(SubjectLevelSetting).where(
        SubjectLevelSetting.establishment_id == source.establishment_id,
        SubjectLevelSetting.academic_year_id == source.id,
        SubjectLevelSetting.status != "archived",
    )).all()
    for item in source_settings:
        level = session.get(SchoolLevel, item.school_level_id)
        if allowed_cycles is not None and (not level or level.cycle_id not in allowed_cycles):
            continue
        existing = session.scalar(select(SubjectLevelSetting).where(
            SubjectLevelSetting.establishment_id == target.establishment_id,
            SubjectLevelSetting.academic_year_id == target.id,
            SubjectLevelSetting.school_level_id == item.school_level_id,
            SubjectLevelSetting.subject_id == item.subject_id,
            SubjectLevelSetting.series_id == item.series_id,
        ))
        if existing:
            continue
        session.add(SubjectLevelSetting(
            establishment_id=target.establishment_id,
            subject_id=item.subject_id,
            school_level_id=item.school_level_id,
            academic_year_id=target.id,
            series_id=item.series_id,
            coefficient=item.coefficient,
            grading_scale=item.grading_scale,
            contributes_to_average=item.contributes_to_average,
            status=item.status,
        ))
        counts["subjectSettings"] += 1

    source_rules = session.scalars(select(EvaluationRule).where(
        EvaluationRule.establishment_id == source.establishment_id,
        EvaluationRule.academic_year_id == source.id,
        EvaluationRule.status != "archived",
    )).all()
    for item in source_rules:
        if allowed_cycles is not None and item.cycle_id not in allowed_cycles:
            continue
        existing = session.scalar(select(EvaluationRule).where(
            EvaluationRule.establishment_id == target.establishment_id,
            EvaluationRule.academic_year_id == target.id,
            EvaluationRule.cycle_id == item.cycle_id,
            EvaluationRule.school_level_id == item.school_level_id,
            EvaluationRule.series_id == item.series_id,
            EvaluationRule.evaluation_type == item.evaluation_type,
            EvaluationRule.label == item.label,
        ))
        if existing:
            continue
        session.add(EvaluationRule(
            establishment_id=target.establishment_id,
            academic_year_id=target.id,
            cycle_id=item.cycle_id,
            school_level_id=item.school_level_id,
            series_id=item.series_id,
            evaluation_type=item.evaluation_type,
            label=item.label,
            expected_count=item.expected_count,
            contributes_to_average=item.contributes_to_average,
            is_required=item.is_required,
            sort_order=item.sort_order,
            status=item.status,
        ))
        counts["evaluationRules"] += 1

    source_calendar = session.scalar(select(SchoolCalendarSetting).where(
        SchoolCalendarSetting.establishment_id == source.establishment_id,
        SchoolCalendarSetting.academic_year_id == source.id,
    ))
    target_calendar = session.scalar(select(SchoolCalendarSetting).where(
        SchoolCalendarSetting.establishment_id == target.establishment_id,
        SchoolCalendarSetting.academic_year_id == target.id,
    ))
    if source_calendar and not target_calendar:
        session.add(SchoolCalendarSetting(
            establishment_id=target.establishment_id,
            academic_year_id=target.id,
            teaching_days=list(source_calendar.teaching_days or []),
            day_start=source_calendar.day_start,
            day_end=source_calendar.day_end,
            course_duration_minutes=source_calendar.course_duration_minutes,
            pause_duration_minutes=source_calendar.pause_duration_minutes,
            pause_frequency=source_calendar.pause_frequency,
            status=source_calendar.status,
        ))
        counts["calendarSettings"] = 1

    session.commit()
    return {
        "sourceYearId": str(source.id),
        "targetYearId": str(target.id),
        "created": counts,
        "message": "Configuration copiée avec classes, matières/barèmes/coefficient et affectations des enseignants, sans élèves ni historiques métier.",
    }


@app.put("/api/v1/school/academic-years/{year_id}/activate")
def activate_academic_year(
    year_id: uuid.UUID,
    current: Principal = Depends(require_module("academic_years")),
    session: Session = Depends(db),
):
    year = session.get(AcademicYear, year_id)
    if not year:
        raise HTTPException(404, "Année scolaire introuvable")
    if current.role != "superadmin" and public_school_id(session, year.establishment_id) != current.school_id:
        raise HTTPException(403, "Accès inter-établissement interdit")
    session.scalars(
        select(AcademicYear)
        .where(AcademicYear.establishment_id == year.establishment_id)
        .with_for_update()
    ).all()
    session.execute(
        text(
            "UPDATE academic_years "
            "SET is_active = FALSE, status = 'inactive', updated_at = :updated_at "
            "WHERE establishment_id = :establishment_id"
        ),
        {"updated_at": datetime.now(timezone.utc), "establishment_id": year.establishment_id},
    )
    session.execute(
        text(
            "UPDATE academic_years "
            "SET is_active = TRUE, status = 'active', updated_at = :updated_at "
            "WHERE id = :year_id AND establishment_id = :establishment_id"
        ),
        {
            "updated_at": datetime.now(timezone.utc),
            "year_id": year.id,
            "establishment_id": year.establishment_id,
        },
    )
    try:
        session.commit()
    except IntegrityError as exc:
        session.rollback()
        raise HTTPException(409, "Une autre année scolaire est déjà active") from exc
    session.refresh(year)
    return academic_year_json(year, session)

@app.delete("/api/v1/school/academic-years/{year_id}", status_code=204)
def delete_academic_year(
    year_id: uuid.UUID,
    current: Principal = Depends(require_module("academic_years")),
    session: Session = Depends(db),
):
    year = session.get(AcademicYear, year_id)
    if not year:
        raise HTTPException(404, "Année scolaire introuvable")
    if current.role != "superadmin" and public_school_id(session, year.establishment_id) != current.school_id:
        raise HTTPException(403, "Accès inter-établissement interdit")
    if year.is_active:
        raise HTTPException(409, "L'année scolaire active ne peut pas être supprimée")
    used = session.scalar(
        select(func.count()).select_from(SchoolClass).where(
            SchoolClass.academic_year_id == year.id,
            SchoolClass.establishment_id == year.establishment_id,
        )
    ) > 0
    if used:
        raise HTTPException(409, "Cette année scolaire contient des classes")
    session.delete(year)
    session.commit()
    return Response(status_code=status.HTTP_204_NO_CONTENT)

@app.get("/api/v1/school/classes")
def list_school_classes(
    school_id: str | None = None,
    academic_year_id: uuid.UUID | None = None,
    cycle_id: uuid.UUID | None = None,
    level_id: uuid.UUID | None = None,
    current: Principal = Depends(require_module("classes")),
    session: Session = Depends(db),
):
    _, database_id = school_scope(current, session, school_id, required=True)
    statement = select(SchoolClass).where(SchoolClass.establishment_id == database_id)
    statement = apply_class_direction_scope(statement, current)
    if academic_year_id:
        statement = statement.where(SchoolClass.academic_year_id == academic_year_id)
    if cycle_id:
        statement = statement.where(SchoolClass.cycle_id == cycle_id)
    if level_id:
        statement = statement.where(SchoolClass.school_level_id == level_id)
    statement = statement.order_by(SchoolClass.name)
    return [class_json(item, session) for item in session.scalars(statement).all()]

@app.post("/api/v1/school/classes", status_code=201)
def create_school_class(
    body: SchoolClassInput,
    current: Principal = Depends(require_module("classes")),
    session: Session = Depends(db),
):
    _, database_id = school_scope(current, session, body.school_id, required=True)
    ensure_direction_cycle_access(current, body.cycle_id)
    _, cycle, level = validate_class_structure(
        database_id, body.academic_year_id, body.cycle_id, body.school_level_id, session
    )
    validate_class_series_requirement(cycle, body.series_id)
    validate_series_scope(body.series_id, database_id, body.cycle_id, session)
    item = SchoolClass(
        establishment_id=database_id,
        academic_year_id=body.academic_year_id,
        cycle_id=body.cycle_id,
        school_level_id=body.school_level_id,
        series_id=body.series_id,
        name=body.name,
        level=level.name,
        capacity=body.capacity,
        status=body.status,
    )
    session.add(item)
    try:
        session.commit()
    except IntegrityError as exc:
        session.rollback()
        raise HTTPException(409, "Une classe de ce nom existe déjà pour cette année") from exc
    session.refresh(item)
    return class_json(item, session)

@app.put("/api/v1/school/classes/{class_id}")
def update_school_class(
    class_id: uuid.UUID,
    body: SchoolClassInput,
    current: Principal = Depends(require_module("classes")),
    session: Session = Depends(db),
):
    item = session.get(SchoolClass, class_id)
    if not item:
        raise HTTPException(404, "Classe introuvable")
    if current.role != "superadmin" and public_school_id(session, item.establishment_id) != current.school_id:
        raise HTTPException(403, "Accès inter-établissement interdit")
    ensure_direction_cycle_access(current, item.cycle_id)
    ensure_direction_cycle_access(current, body.cycle_id)
    if body.school_id and resolve_establishment_id(session, body.school_id) != item.establishment_id:
        raise HTTPException(403, "Accès inter-établissement interdit")
    _, cycle, level = validate_class_structure(
        item.establishment_id,
        body.academic_year_id,
        body.cycle_id,
        body.school_level_id,
        session,
    )
    validate_class_series_requirement(cycle, body.series_id)
    validate_series_scope(body.series_id, item.establishment_id, body.cycle_id, session)
    item.academic_year_id = body.academic_year_id
    item.cycle_id = body.cycle_id
    item.school_level_id = body.school_level_id
    item.series_id = body.series_id
    item.level = level.name
    item.name = body.name
    item.capacity = body.capacity
    item.status = body.status
    item.updated_at = datetime.now(timezone.utc)
    try:
        session.commit()
    except IntegrityError as exc:
        session.rollback()
        raise HTTPException(409, "Une classe de ce nom existe déjà pour cette année") from exc
    session.refresh(item)
    return class_json(item, session)

@app.put("/api/v1/school/classes/{class_id}/main-teacher")
def set_class_main_teacher(
    class_id: uuid.UUID,
    body: MainTeacherInput,
    current: Principal = Depends(require_module("classes")),
    session: Session = Depends(db),
):
    item = session.get(SchoolClass, class_id)
    teacher = session.get(Teacher, body.teacher_id)
    if not item or not teacher:
        raise HTTPException(404, "Classe ou enseignant introuvable")
    _, database_id = school_scope(current, session, None, required=True)
    ensure_class_module_access(current, item, database_id, session)
    if teacher.establishment_id != item.establishment_id:
        raise HTTPException(403, "Cet enseignant appartient à un autre établissement")
    if teacher.status != "active":
        raise HTTPException(409, "Cet enseignant n'est pas actif")
    teaches_class = session.scalar(select(Affectation.id).where(
        Affectation.establishment_id == item.establishment_id,
        Affectation.teacher_id == teacher.id,
        Affectation.class_id == item.id,
        Affectation.status == "active",
    ))
    if not teaches_class:
        raise HTTPException(
            409,
            "Affectez d'abord cet enseignant à une matière de cette classe",
        )
    item.main_teacher_id = teacher.id
    item.updated_at = datetime.now(timezone.utc)
    session.commit()
    session.refresh(item)
    return class_json(item, session)

@app.delete("/api/v1/school/classes/{class_id}/main-teacher", status_code=204)
def clear_class_main_teacher(
    class_id: uuid.UUID,
    current: Principal = Depends(require_module("classes")),
    session: Session = Depends(db),
):
    item = session.get(SchoolClass, class_id)
    if not item:
        raise HTTPException(404, "Classe introuvable")
    _, database_id = school_scope(current, session, None, required=True)
    ensure_class_module_access(current, item, database_id, session)
    item.main_teacher_id = None
    item.updated_at = datetime.now(timezone.utc)
    session.commit()
    return Response(status_code=status.HTTP_204_NO_CONTENT)

@app.delete("/api/v1/school/classes/{class_id}", status_code=204)
def delete_school_class(
    class_id: uuid.UUID,
    current: Principal = Depends(require_module("classes")),
    session: Session = Depends(db),
):
    item = session.get(SchoolClass, class_id)
    if not item:
        raise HTTPException(404, "Classe introuvable")
    if current.role != "superadmin" and public_school_id(session, item.establishment_id) != current.school_id:
        raise HTTPException(403, "Accès inter-établissement interdit")
    ensure_direction_cycle_access(current, item.cycle_id)
    session.delete(item)
    try:
        session.commit()
    except IntegrityError as exc:
        session.rollback()
        raise HTTPException(409, "Cette classe contient des dépendances") from exc
    return Response(status_code=status.HTTP_204_NO_CONTENT)

@app.get("/api/v1/school/students")
def list_relational_students(
    academic_year_id: uuid.UUID | None = None,
    cycle_id: uuid.UUID | None = None,
    level_id: uuid.UUID | None = None,
    class_id: uuid.UUID | None = None,
    search: str | None = None,
    status_filter: Literal["active", "archived"] | None = None,
    school_id: str | None = None,
    current: Principal = Depends(require_module("students")),
    session: Session = Depends(db),
):
    _, database_id = school_scope(current, session, school_id, required=True)
    statement = select(Student).where(Student.establishment_id == database_id)
    allowed = direction_cycle_scope(current)
    direction_joined = False
    if allowed is not None:
        statement = statement.outerjoin(
            StudentAcademicRegistration,
            StudentAcademicRegistration.student_id == Student.id,
        ).outerjoin(SchoolClass, SchoolClass.id == StudentAcademicRegistration.class_id).where(
            or_(
                (
                    StudentAcademicRegistration.status.in_(("pending", "validated", "active"))
                    & SchoolClass.cycle_id.in_(allowed)
                ),
                Student.created_direction_id == uuid.UUID(current.direction_id),
            ),
        )
        direction_joined = True
    if status_filter:
        statement = statement.where(Student.status == status_filter)
    else:
        statement = statement.where(Student.status == "active")
    if search and search.strip():
        query = f"%{search.strip().lower()}%"
        statement = statement.where(
            func.lower(Student.first_name).like(query)
            | func.lower(Student.last_name).like(query)
            | Student.id.in_(select(StudentAcademicRegistration.student_id).where(
                StudentAcademicRegistration.establishment_id == database_id,
                func.lower(StudentAcademicRegistration.registration_number).like(query),
            ))
        )
    if any((academic_year_id, cycle_id, level_id, class_id)) and not direction_joined:
        statement = statement.join(StudentAcademicRegistration, StudentAcademicRegistration.student_id == Student.id).join(
            SchoolClass, SchoolClass.id == StudentAcademicRegistration.class_id
        ).where(StudentAcademicRegistration.status.in_(("pending", "validated", "active")))
    if any((academic_year_id, cycle_id, level_id, class_id)):
        if academic_year_id:
            statement = statement.where(StudentAcademicRegistration.academic_year_id == academic_year_id)
        if cycle_id:
            statement = statement.where(SchoolClass.cycle_id == cycle_id)
        if level_id:
            statement = statement.where(SchoolClass.school_level_id == level_id)
        if class_id:
            statement = statement.where(SchoolClass.id == class_id)
    students = session.scalars(statement.distinct().order_by(Student.last_name, Student.first_name)).all()
    return [student_json(student, session, academic_year_id) for student in students]

@app.get("/api/v1/school/students/re-enrollment-candidates")
def re_enrollment_candidates(
    target_academic_year_id: uuid.UUID,
    class_id: uuid.UUID | None = None,
    last_name: str | None = None,
    first_name: str | None = None,
    matricule: str | None = None,
    limit: int = Query(50, ge=1, le=100),
    school_id: str | None = None,
    current: Principal = Depends(require_module_roles("students", "superadmin", "admin")),
    session: Session = Depends(db),
):
    """Search eligible pupils from the immediately preceding academic year.

    The endpoint deliberately returns a bounded, purpose-built projection: the
    picker never downloads the whole pupil directory and an existing target-year
    registration is excluded at the database level.
    """
    _, database_id = school_scope(current, session, school_id, required=True)
    target_year = session.get(AcademicYear, target_academic_year_id)
    if not target_year or target_year.establishment_id != database_id:
        raise HTTPException(404, "Année scolaire cible introuvable")

    previous_year = session.scalar(
        select(AcademicYear)
        .where(
            AcademicYear.establishment_id == database_id,
            AcademicYear.start_date < target_year.start_date,
        )
        .order_by(AcademicYear.start_date.desc())
        .limit(1)
    )
    if not previous_year:
        return {
            "previousAcademicYear": None,
            "classes": [],
            "items": [],
            "total": 0,
        }

    previous_registration = StudentAcademicRegistration
    statement = (
        select(Student, previous_registration, SchoolClass)
        .join(previous_registration, previous_registration.student_id == Student.id)
        .join(SchoolClass, SchoolClass.id == previous_registration.class_id)
        .where(
            Student.establishment_id == database_id,
            Student.status == "active",
            previous_registration.academic_year_id == previous_year.id,
            previous_registration.status.in_(("pending", "validated", "active")),
            ~Student.id.in_(
                select(StudentAcademicRegistration.student_id).where(
                    StudentAcademicRegistration.establishment_id == database_id,
                    StudentAcademicRegistration.academic_year_id == target_year.id,
                    StudentAcademicRegistration.status.in_(("pending", "validated", "active")),
                )
            ),
        )
    )
    allowed = direction_cycle_scope(current)
    if allowed is not None:
        statement = statement.where(SchoolClass.cycle_id.in_(allowed))
    if class_id:
        statement = statement.where(SchoolClass.id == class_id)
    if last_name and last_name.strip():
        statement = statement.where(
            func.lower(Student.last_name).like(f"%{last_name.strip().lower()}%")
        )
    if first_name and first_name.strip():
        statement = statement.where(
            func.lower(Student.first_name).like(f"%{first_name.strip().lower()}%")
        )
    if matricule and matricule.strip():
        value = f"%{matricule.strip().lower()}%"
        statement = statement.where(
            or_(
                func.lower(Student.registration_number).like(value),
                func.lower(previous_registration.registration_number).like(value),
            )
        )

    count_statement = select(func.count()).select_from(statement.order_by(None).subquery())
    total = int(session.scalar(count_statement) or 0)
    rows = session.execute(
        statement.order_by(Student.last_name, Student.first_name).limit(limit)
    ).all()

    class_statement = (
        select(SchoolClass)
        .join(previous_registration, previous_registration.class_id == SchoolClass.id)
        .where(
            previous_registration.establishment_id == database_id,
            previous_registration.academic_year_id == previous_year.id,
            previous_registration.status.in_(("pending", "validated", "active")),
        )
    )
    if allowed is not None:
        class_statement = class_statement.where(SchoolClass.cycle_id.in_(allowed))
    previous_classes = session.scalars(
        class_statement.distinct().order_by(SchoolClass.name)
    ).all()

    row_classes = [row[2] for row in rows]
    level_ids = {item.school_level_id for item in row_classes if item.school_level_id}
    cycle_ids = {item.cycle_id for item in row_classes if item.cycle_id}
    series_ids = {item.series_id for item in row_classes if item.series_id}
    levels_by_id = {item.id: item for item in session.scalars(
        select(SchoolLevel).where(SchoolLevel.id.in_(level_ids))).all()
    } if level_ids else {}
    cycles_by_id = {item.id: item for item in session.scalars(
        select(SchoolCycle).where(SchoolCycle.id.in_(cycle_ids))).all()
    } if cycle_ids else {}
    series_by_id = {item.id: item for item in session.scalars(
        select(SchoolSeries).where(SchoolSeries.id.in_(series_ids))).all()
    } if series_ids else {}
    items = []
    for student, registration, school_class in rows:
        level = levels_by_id.get(school_class.school_level_id)
        cycle = cycles_by_id.get(school_class.cycle_id)
        series = series_by_id.get(school_class.series_id)
        items.append({
            "id": str(student.id),
            "schoolId": public_school_id(session, student.establishment_id),
            "firstName": student.first_name,
            "lastName": student.last_name,
            "matricule": student.registration_number or registration.registration_number,
            "birthDate": student.birth_date.isoformat() if student.birth_date else None,
            "sex": student.gender,
            "email": student.email,
            "phone": student.phone,
            "address": student.address,
            "status": student.status,
            "academicYearId": str(previous_year.id),
            "classId": str(school_class.id),
            "class": school_class.name,
            "cycle": cycle.name if cycle else None,
            "levelId": str(level.id) if level else None,
            "level": level.name if level else school_class.level,
            "seriesId": str(series.id) if series else None,
            "series": series.name if series else None,
        })
    return {
        "previousAcademicYear": {
            "id": str(previous_year.id),
            "name": previous_year.name,
        },
        "classes": [
            {"id": str(item.id), "name": item.name}
            for item in previous_classes
        ],
        "items": items,
        "total": total,
    }

@app.post("/api/v1/school/students", status_code=201)
def create_relational_student(
    body: StudentIdentityInput,
    school_id: str | None = None,
    current: Principal = Depends(require_module("students")),
    session: Session = Depends(db),
):
    _, database_id = school_scope(current, session, school_id, required=True)
    student = Student(
        establishment_id=database_id,
        created_direction_id=(uuid.UUID(current.direction_id) if current.direction_id else None),
        first_name=body.first_name,
        last_name=body.last_name,
        registration_number=None,
        birth_date=body.birth_date,
        nationality=body.nationality,
        gender=body.gender,
        email=body.email,
        phone=body.phone,
        address=body.address,
        status="active",
    )
    session.add(student)
    try:
        session.commit()
    except IntegrityError as exc:
        session.rollback()
        raise HTTPException(409, "Impossible de générer un matricule unique") from exc
    session.refresh(student)
    return student_json(student, session)

def _student_photo_row(session: Session, student_id: uuid.UUID) -> Resource | None:
    return session.get(Resource, {"kind": "student-photos", "id": str(student_id)})

def _student_photo_document_data(session: Session, student_id: uuid.UUID) -> dict[str, Any] | None:
    row = _student_photo_row(session, student_id)
    path = Path(str(row.payload.get("path"))) if row and row.payload.get("path") else None
    if not row or not path or not path.is_file():
        return None
    return {
        "mimeType": row.payload.get("mimeType") or "image/jpeg",
        "contentBase64": base64.b64encode(path.read_bytes()).decode("ascii"),
    }

def _decode_student_photo(file: StudentPhotoFileInput | StudentPhotoUpdateInput) -> tuple[bytes, str]:
    mime_type = file.mime_type.lower().strip()
    extension = STUDENT_PHOTO_TYPES.get(mime_type)
    if not extension:
        raise HTTPException(
            422,
            "Format de photo non pris en charge par le système",
        )
    try:
        content = base64.b64decode(file.content_base64, validate=True)
    except Exception as exc:
        raise HTTPException(422, "Le contenu de la photo est invalide") from exc
    if not content:
        raise HTTPException(422, "La photo est vide")
    if len(content) > STUDENT_PHOTO_MAX_BYTES:
        raise HTTPException(422, "La photo doit peser au maximum 5 Mo")
    signatures = {
        ".jpg": (b"\xff\xd8\xff",),
        ".png": (b"\x89PNG\r\n\x1a\n",),
        ".webp": (b"RIFF",),
        ".gif": (b"GIF87a", b"GIF89a"),
        ".bmp": (b"BM",),
        ".heic": (b"\x00\x00\x00",),
        ".heif": (b"\x00\x00\x00",),
    }
    if not any(content.startswith(signature) for signature in signatures[extension]):
        raise HTTPException(422, "Le fichier ne correspond pas au format annoncé")
    if extension == ".webp" and content[8:12] != b"WEBP":
        raise HTTPException(422, "Le fichier WEBP est invalide")
    if extension in {".heic", ".heif"}:
        header = content[:32]
        if b"ftypheic" not in header and b"ftypheix" not in header and b"ftyphevc" not in header and b"ftyphevx" not in header and b"ftypmif1" not in header:
            raise HTTPException(422, "Le fichier HEIC/HEIF est invalide")
    return content, extension

def _save_student_photo(
    session: Session,
    student: Student,
    file: StudentPhotoFileInput | StudentPhotoUpdateInput,
    current: Principal,
) -> dict[str, Any]:
    content, extension = _decode_student_photo(file)
    tenant_directory = STUDENT_PHOTO_ROOT / str(student.establishment_id)
    tenant_directory.mkdir(parents=True, exist_ok=True)
    target = tenant_directory / f"{student.id}{extension}"
    temporary = tenant_directory / f".{student.id}-{uuid.uuid4().hex}.tmp"
    temporary.write_bytes(content)
    temporary.replace(target)
    row = _student_photo_row(session, student.id)
    old_path = Path(str(row.payload.get("path"))) if row and row.payload.get("path") else None
    payload = {
        "studentId": str(student.id),
        "path": str(target),
        "mimeType": file.mime_type.lower(),
        "originalName": file.name,
        "size": len(content),
        "updatedBy": current.id,
        "updatedAt": datetime.now(timezone.utc).isoformat(),
    }
    if row:
        row.payload = payload
        row.updated_at = datetime.now(timezone.utc)
    else:
        session.add(Resource(
            id=str(student.id), kind="student-photos",
            school_id=public_school_id(session, student.establishment_id),
            establishment_id=student.establishment_id,
            payload=payload,
        ))
    if old_path and old_path != target and old_path.is_file() and old_path.parent == tenant_directory:
        old_path.unlink(missing_ok=True)
    return payload

def _can_read_student_photo(current: Principal, student: Student, session: Session) -> bool:
    if current.role == "superadmin":
        return True
    if public_school_id(session, student.establishment_id) != current.school_id:
        return False
    if current.role == "admin":
        try:
            ensure_student_scope(student.id, current, session)
            return True
        except HTTPException:
            return False
    if current.role == "student":
        return str(student.id) == str(current.student_id)
    if current.role == "teacher" and current.teacher_id:
        try:
            teacher_id = uuid.UUID(current.teacher_id)
        except ValueError:
            return False
        return session.scalar(select(StudentAcademicRegistration.id).join(
            Affectation,
            Affectation.class_id == StudentAcademicRegistration.class_id,
        ).where(
            StudentAcademicRegistration.student_id == student.id,
            StudentAcademicRegistration.status.in_(("pending", "validated", "active")),
            Affectation.teacher_id == teacher_id,
            Affectation.status == "active",
        ).limit(1)) is not None
    if current.role == "parent":
        guardian = session.scalar(select(Guardian).where(Guardian.user_id == uuid.UUID(current.id)))
        return bool(guardian and session.scalar(select(StudentGuardian.student_id).where(
            StudentGuardian.student_id == student.id,
            StudentGuardian.guardian_id == guardian.id,
        )))
    return False

@app.post("/api/v1/school/students/photos/import")
def import_student_photos(
    body: StudentPhotoImportInput,
    current: Principal = Depends(require_module_roles("students", "admin")),
    session: Session = Depends(db),
):
    _, database_id = school_scope(current, session, None, required=True)
    year = ensure_year_tenant(body.academic_year_id, database_id, session)
    cycle = session.get(SchoolCycle, body.cycle_id)
    if not cycle or cycle.establishment_id != database_id or cycle.status != "active":
        raise HTTPException(404, "Cycle introuvable")
    ensure_direction_cycle_access(current, cycle.id)
    rows = session.execute(select(Student, StudentAcademicRegistration).join(
        StudentAcademicRegistration, StudentAcademicRegistration.student_id == Student.id
    ).join(SchoolClass, SchoolClass.id == StudentAcademicRegistration.class_id).where(
        Student.establishment_id == database_id,
        Student.status == "active",
        StudentAcademicRegistration.academic_year_id == year.id,
        StudentAcademicRegistration.status.in_(("pending", "validated", "active")),
        SchoolClass.cycle_id == cycle.id,
    )).all()
    suffixes: dict[int, list[Student]] = {}
    for student, registration in rows:
        matricule = registration.registration_number or student.registration_number or ""
        match = re.search(r"(\d+)$", matricule.strip())
        if match:
            suffixes.setdefault(int(match.group(1)), []).append(student)
    existing = {
        row.id for row in session.scalars(select(Resource).where(
            Resource.kind == "student-photos",
            Resource.id.in_([str(student.id) for student, _ in rows]),
        )).all()
    } if rows else set()
    items = []
    for file in body.files:
        match = re.fullmatch(r"(\d+)", Path(file.name).stem.strip())
        candidates = suffixes.get(int(match.group(1)), []) if match else []
        if not candidates:
            items.append({"name": file.name, "status": "not_found"})
            continue
        if len(candidates) > 1:
            items.append({
                "name": file.name,
                "status": "error",
                "message": "Plusieurs matricules correspondent à ce suffixe ; aucune photo n’a été associée",
            })
            continue
        student = candidates[0]
        if str(student.id) in existing:
            items.append({"name": file.name, "status": "already_present",
                          "studentId": str(student.id),
                          "studentName": f"{student.last_name} {student.first_name}"})
            continue
        try:
            _save_student_photo(session, student, file, current)
            existing.add(str(student.id))
            items.append({"name": file.name, "status": "associated",
                          "studentId": str(student.id),
                          "studentName": f"{student.last_name} {student.first_name}"})
        except HTTPException as exc:
            items.append({"name": file.name, "status": "error", "message": exc.detail})
    session.commit()
    return {"processed": len(items), "items": items}

@app.get("/api/v1/school/students/{student_id}/photo")
def get_student_photo(
    student_id: uuid.UUID,
    current: Principal = Depends(principal),
    session: Session = Depends(db),
):
    student = session.get(Student, student_id)
    if not student or not _can_read_student_photo(current, student, session):
        raise HTTPException(404, "Photo introuvable")
    row = _student_photo_row(session, student.id)
    path = Path(str(row.payload.get("path"))) if row else None
    if not row or not path or not path.is_file():
        raise HTTPException(404, "Photo introuvable")
    return Response(content=path.read_bytes(), media_type=row.payload.get("mimeType") or "image/jpeg",
                    headers={"Cache-Control": "private, max-age=300"})

@app.put("/api/v1/school/students/{student_id}/photo")
def update_student_photo(
    student_id: uuid.UUID,
    body: StudentPhotoUpdateInput,
    current: Principal = Depends(principal),
    session: Session = Depends(db),
):
    student = session.get(Student, student_id)
    if not student:
        raise HTTPException(404, "Élève introuvable")
    if current.role == "admin":
        student = ensure_student_scope(student_id, current, session)
    else:
        raise HTTPException(403, "La photo de l’élève est gérée par l’administration")
    payload = _save_student_photo(session, student, body, current)
    session.commit()
    return {"studentId": str(student.id), "photoUrl": f"/api/v1/school/students/{student.id}/photo",
            "updatedAt": payload["updatedAt"]}

@app.get("/api/v1/school/students/{student_id}")
def get_relational_student(
    student_id: uuid.UUID,
    academic_year_id: uuid.UUID | None = None,
    current: Principal = Depends(require_module("students")),
    session: Session = Depends(db),
):
    return student_json(ensure_student_scope(student_id, current, session), session, academic_year_id)

@app.put("/api/v1/school/students/{student_id}")
def update_relational_student(
    student_id: uuid.UUID,
    body: StudentIdentityUpdateInput,
    current: Principal = Depends(require_module("students")),
    session: Session = Depends(db),
):
    student = ensure_student_scope(student_id, current, session)
    for field, value in body.model_dump(exclude_unset=True).items():
        setattr(student, field, value)
    student.updated_at = datetime.now(timezone.utc)
    session.commit()
    session.refresh(student)
    return student_json(student, session)

@app.post("/api/v1/school/students/{student_id}/access")
def provision_student_access(
    student_id: uuid.UUID,
    current: Principal = Depends(require_module_roles("students", "superadmin", "admin")),
    session: Session = Depends(db),
):
    student = ensure_student_scope(student_id, current, session)
    if student.status != "active":
        raise HTTPException(409, "Le profil élève doit être actif")
    latest_registration = session.scalar(select(StudentAcademicRegistration).where(
        StudentAcademicRegistration.student_id == student.id,
        StudentAcademicRegistration.status.in_(("pending", "validated", "active")),
    ).order_by(StudentAcademicRegistration.registration_date.desc()))
    school_class = session.get(SchoolClass, latest_registration.class_id) if latest_registration else None
    cycle = session.get(SchoolCycle, school_class.cycle_id) if school_class and school_class.cycle_id else None
    if cycle and cycle.code.upper() in {"MATERNELLE", "PRIMAIRE"}:
        raise HTTPException(
            409,
            "Les élèves de maternelle et primaire utilisent le compte parent ; un accès élève autonome n’est pas autorisé.",
        )
    ensure_plan_capability(current, session, "students.access")
    matricule = student_login_matricule(student, session)
    if not matricule:
        raise HTTPException(
            409,
            "L’élève doit avoir une inscription scolaire avec un matricule avant la création de son accès.",
        )

    user = session.get(User, student.user_id) if student.user_id else None
    if student.user_id and not user:
        raise HTTPException(409, "Le compte élève associé est introuvable")
    if user and (user.role != "student" or user.school_id != student.establishment_id):
        raise HTTPException(409, "Le compte associé au profil élève est incohérent")
    if not user:
        internal_email = f"student-{student.id}@accounts.edupro.local"
        user = User(
            email=internal_email,
            password_hash="",
            name=f"{student.last_name} {student.first_name}".strip(),
            role="student",
            school_id=student.establishment_id,
            status="active",
            password_set=False,
        )
        session.add(user)
        session.flush()
        student.user_id = user.id

    user.name = f"{student.last_name} {student.first_name}".strip()
    user.status = "active"
    student.updated_at = datetime.now(timezone.utc)
    temporary_password = issue_temporary_access(session, user, "student-access")
    session.commit()
    session.refresh(student)
    return {
        "student": student_json(student, session),
        "matricule": matricule,
        "temporaryPassword": temporary_password,
    }

@app.delete("/api/v1/school/students/{student_id}", status_code=204)
def archive_relational_student(
    student_id: uuid.UUID,
    current: Principal = Depends(require_module("students")),
    session: Session = Depends(db),
):
    student = ensure_student_scope(student_id, current, session)
    student.status = "archived"
    student.updated_at = datetime.now(timezone.utc)
    session.commit()
    return Response(status_code=status.HTTP_204_NO_CONTENT)

@app.get("/api/v1/school/students/{student_id}/registrations")
def student_registration_history(
    student_id: uuid.UUID,
    current: Principal = Depends(require_module("students")),
    session: Session = Depends(db),
):
    ensure_student_scope(student_id, current, session)
    statement = select(StudentAcademicRegistration).where(
        StudentAcademicRegistration.student_id == student_id
    )
    allowed = direction_cycle_scope(current)
    if allowed is not None:
        statement = statement.join(
            SchoolClass, SchoolClass.id == StudentAcademicRegistration.class_id
        ).where(SchoolClass.cycle_id.in_(allowed))
    items = session.scalars(
        statement.order_by(StudentAcademicRegistration.registration_date.desc())
    ).all()
    return [registration_json(item, session) for item in items]

@app.post("/api/v1/school/students/{student_id}/registrations", status_code=201)
def create_student_registration(
    student_id: uuid.UUID,
    body: StudentRegistrationInput,
    current: Principal = Depends(require_module("students")),
    session: Session = Depends(db),
):
    student = ensure_student_scope(student_id, current, session)
    school_class = validate_registration_class(
        student.establishment_id, body.class_id, session, current=current
    )
    validate_registration_academic_options(school_class, body.has_td, session)
    approval_regime = body.school_regime or item.desired_school_regime or 'normal'
    validate_school_regime(school_class, approval_regime, session)
    matricule = ensure_student_permanent_matricule(
        session, student, school_class.academic_year_id
    )
    item = StudentAcademicRegistration(
        establishment_id=student.establishment_id,
        student_id=student.id,
        class_id=school_class.id,
        academic_year_id=school_class.academic_year_id,
        registration_date=body.registration_date,
        registration_number=matricule,
        school_regime=body.school_regime,
        has_td=body.has_td,
        options=body.options,
        status="validated",
    )
    session.add(item)
    session.flush()
    if school_regime_supported(school_class, session):
        session.add(StudentRegimeHistory(
            establishment_id=item.establishment_id,
            registration_id=item.id,
            student_id=item.student_id,
            school_regime=item.school_regime,
            effective_date=item.registration_date,
            created_by=uuid.UUID(current.id),
        ))
    # The temporary creator scope is useful only until the first academic
    # registration. From here, class/cycle registrations are authoritative.
    student.created_direction_id = None
    try:
        session.commit()
    except IntegrityError as exc:
        session.rollback()
        raise HTTPException(409, "Cet élève possède déjà une inscription active pour cette année") from exc
    session.refresh(item)
    return registration_json(item, session)

@app.put("/api/v1/school/student-registrations/{registration_id}")
def change_student_registration_class(
    registration_id: uuid.UUID,
    body: StudentClassTransferInput,
    current: Principal = Depends(require_module("students")),
    session: Session = Depends(db),
):
    item = session.get(StudentAcademicRegistration, registration_id)
    if not item:
        raise HTTPException(404, "Inscription introuvable")
    student = ensure_student_scope(item.student_id, current, session)
    school_class = validate_registration_class(
        student.establishment_id, body.class_id, session,
        item.academic_year_id, current
    )
    old_class = session.get(SchoolClass, item.class_id)
    if old_class and old_class.cycle_id != school_class.cycle_id:
        raise HTTPException(409, 'Un changement de cycle en cours d année est interdit')
    if item.class_id == school_class.id:
        raise HTTPException(409, 'L élève appartient déjà à cette classe')
    transfer = StudentClassTransfer(
        establishment_id=item.establishment_id,
        registration_id=item.id,
        student_id=item.student_id,
        academic_year_id=item.academic_year_id,
        from_class_id=item.class_id,
        to_class_id=school_class.id,
        effective_date=body.effective_date,
        reason=body.reason,
        grade_handling_decision=body.grade_handling_decision,
        created_by=uuid.UUID(current.id),
    )
    session.add(transfer)
    item.class_id = school_class.id
    item.updated_at = datetime.now(timezone.utc)
    session.commit()
    session.refresh(item)
    return registration_json(item, session)

@app.put("/api/v1/school/student-registrations/{registration_id}/regime")
def change_student_registration_regime(
    registration_id: uuid.UUID,
    body: StudentRegimeChangeInput,
    current: Principal = Depends(require_module_roles("students", "admin")),
    session: Session = Depends(db),
):
    registration = session.get(StudentAcademicRegistration, registration_id)
    if not registration:
        raise HTTPException(404, "Inscription introuvable")
    student = ensure_student_scope(registration.student_id, current, session)
    school_class = validate_registration_class(
        student.establishment_id,
        registration.class_id,
        session,
        registration.academic_year_id,
        current,
    )
    validate_school_regime(school_class, body.school_regime, session)
    year = session.get(AcademicYear, registration.academic_year_id)
    if not year:
        raise HTTPException(404, "Année scolaire introuvable")
    if body.effective_date.day != 1:
        raise HTTPException(422, "Le changement de régime doit prendre effet au premier jour d'un mois")
    if body.effective_date < registration.registration_date or body.effective_date > year.end_date:
        raise HTTPException(422, "La date d'effet est hors de la période d'inscription")
    effective_month = body.effective_date.strftime('%Y-%m')
    paid_rows = finance_rows(session, "finance-payments", current.school_id, current)
    for payment in paid_rows:
        payload = payment.payload or {}
        if payload.get("status", "active") != "active":
            continue
        if str(payload.get("registrationId") or payload.get("schoolRegistrationId")) != str(registration.id):
            continue
        months = list(payload.get("months") or [])
        if payload.get("month"):
            months.append(payload.get("month"))
        months.extend(
            allocation.get("month")
            for allocation in (payload.get("allocations") or [])
            if allocation.get("month")
        )
        if any(str(month) >= effective_month for month in months):
            raise HTTPException(
                409,
                "Un paiement validé existe déjà à partir de cette date. Choisissez un mois ultérieur.",
            )

    latest = session.scalar(select(StudentRegimeHistory).where(
        StudentRegimeHistory.registration_id == registration.id,
    ).order_by(StudentRegimeHistory.effective_date.desc()).limit(1))
    if latest and latest.school_regime == body.school_regime:
        raise HTTPException(409, "Ce régime est déjà applicable")
    if latest and body.effective_date <= latest.effective_date:
        raise HTTPException(409, "La date d'effet doit être postérieure au dernier changement de régime")
    if latest:
        latest.end_date = body.effective_date - timedelta(days=1)
    session.add(StudentRegimeHistory(
        establishment_id=registration.establishment_id,
        registration_id=registration.id,
        student_id=registration.student_id,
        school_regime=body.school_regime,
        effective_date=body.effective_date,
        created_by=uuid.UUID(current.id),
    ))
    registration.school_regime = body.school_regime
    registration.updated_at = datetime.now(timezone.utc)
    session.commit()
    session.refresh(registration)
    return registration_json(registration, session)

@app.get("/api/v1/school/pre-enrollments")
def list_student_pre_enrollments(
    academic_year_id: uuid.UUID | None = None,
    status_filter: Literal["draft", "submitted", "approved", "rejected", "cancelled"] | None = None,
    school_id: str | None = None,
    current: Principal = Depends(require_module("students")),
    session: Session = Depends(db),
):
    _, database_id = school_scope(current, session, school_id, required=True)
    statement = select(StudentPreEnrollment).where(StudentPreEnrollment.establishment_id == database_id)
    allowed = direction_cycle_scope(current)
    if allowed is not None:
        statement = statement.where(StudentPreEnrollment.desired_class_id.in_(
            select(SchoolClass.id).where(SchoolClass.cycle_id.in_(allowed))
        ))
    if academic_year_id:
        statement = statement.where(StudentPreEnrollment.academic_year_id == academic_year_id)
    if status_filter:
        statement = statement.where(StudentPreEnrollment.status == status_filter)
    items = session.scalars(statement.order_by(StudentPreEnrollment.created_at.desc())).all()
    return [pre_enrollment_json(item, session) for item in items]

@app.post("/api/v1/school/pre-enrollments", status_code=201)
def create_student_pre_enrollment(
    body: StudentPreEnrollmentInput,
    current: Principal = Depends(require_module("students")),
    session: Session = Depends(db),
):
    year = session.get(AcademicYear, body.academic_year_id)
    if not year:
        raise HTTPException(422, "Année scolaire introuvable")
    if body.student_id:
        student = ensure_student_scope(body.student_id, current, session)
    else:
        if current.role == "superadmin":
            database_id = year.establishment_id
        else:
            _, database_id = school_scope(current, session, None, required=True)
        student = Student(
            establishment_id=database_id,
            created_direction_id=(uuid.UUID(current.direction_id) if current.direction_id else None),
            first_name=body.first_name or "",
            last_name=body.last_name or "",
            status="pre_enrolled",
        )
        session.add(student)
        session.flush()
    if year.establishment_id != student.establishment_id:
        raise HTTPException(403, "Année scolaire inter-établissement interdite")
    desired_class = validate_registration_class(
        student.establishment_id, body.desired_class_id, session,
        year.id, current
    )
    effective_regime = body.school_regime or 'normal'
    validate_school_regime(desired_class, effective_regime, session)
    prior_registration_exists = bool(session.scalar(
        select(StudentAcademicRegistration.id).join(
            AcademicYear,
            AcademicYear.id == StudentAcademicRegistration.academic_year_id,
        ).where(
            StudentAcademicRegistration.student_id == student.id,
            StudentAcademicRegistration.establishment_id == student.establishment_id,
            AcademicYear.start_date < year.start_date,
            StudentAcademicRegistration.status.in_(("validated", "active")),
        ).limit(1)
    ))
    expected_kind = "reenrollment" if prior_registration_exists else "registration"
    if body.registration_kind != expected_kind:
        raise HTTPException(
            422,
            "Le type d'inscription ne correspond pas à l'historique de l'élève",
        )
    item = StudentPreEnrollment(
        establishment_id=student.establishment_id,
        student_id=student.id,
        academic_year_id=year.id,
        desired_class_id=body.desired_class_id,
        desired_school_regime=(
            body.school_regime
            if school_regime_supported(desired_class, session)
            else None
        ),
        status=body.status,
        submitted_at=datetime.now(timezone.utc) if body.status == "submitted" else None,
    )
    session.add(item)
    session.flush()
    # A provisional annual registration gives Finance one canonical source for
    # the paid registration fee and its receipt, without making the pupil part
    # of the definitive class roster yet.
    provisional = StudentAcademicRegistration(
        establishment_id=student.establishment_id,
        student_id=student.id,
        class_id=body.desired_class_id,
        academic_year_id=year.id,
        registration_date=date.today(),
        registration_number=student.registration_number,
        school_regime=effective_regime,
        options={
            "preEnrollmentId": str(item.id),
            "registrationKind": expected_kind,
        },
        status="pre_enrolled",
    )
    session.add(provisional)
    from .finance import registration_receipts
    school_public_id = public_school_id(session, student.establishment_id)
    receipts = registration_receipts(
        session, current, school_public_id, student.establishment_id, year
    )
    receipt = next((row for row in receipts
                    if row.get("schoolRegistrationId") == str(provisional.id)), None)
    if receipt is None:
        session.rollback()
        raise HTTPException(
            409,
            "Configurez d'abord le tarif d'inscription applicable à cette classe",
        )
    try:
        session.commit()
    except IntegrityError as exc:
        session.rollback()
        raise HTTPException(409, "Une préinscription existe déjà pour cet élève et cette année") from exc
    session.refresh(item)
    return {**pre_enrollment_json(item, session), "receipt": receipt}

@app.put("/api/v1/school/pre-enrollments/{pre_enrollment_id}/status")
def update_student_pre_enrollment_status(
    pre_enrollment_id: uuid.UUID,
    body: StudentPreEnrollmentStatusInput,
    current: Principal = Depends(require_module("students")),
    session: Session = Depends(db),
):
    item = session.get(StudentPreEnrollment, pre_enrollment_id)
    if not item:
        raise HTTPException(404, "Préinscription introuvable")
    ensure_student_scope(item.student_id, current, session)
    allowed = {
        "draft": {"submitted", "cancelled"},
        "submitted": {"draft", "rejected", "cancelled"},
        "rejected": {"draft"},
        "cancelled": {"draft"},
        "approved": set(),
    }
    if body.status not in allowed[item.status]:
        raise HTTPException(409, "Transition de préinscription invalide")
    student = session.get(Student, item.student_id)
    provisional = session.scalar(select(StudentAcademicRegistration).where(
        StudentAcademicRegistration.student_id == item.student_id,
        StudentAcademicRegistration.academic_year_id == item.academic_year_id,
        StudentAcademicRegistration.status.in_(["pre_enrolled", "cancelled"]),
    ))
    if not provisional:
        raise HTTPException(409, "L'inscription provisoire associée est introuvable")
    if body.status in {"rejected", "cancelled"}:
        provisional.status = "cancelled"
        if student and student.status == "pre_enrolled":
            student.status = "archived"
    elif body.status in {"draft", "submitted"}:
        provisional.status = "pre_enrolled"
        if student and student.status == "archived" and not student.registration_number:
            student.status = "pre_enrolled"
    provisional.updated_at = datetime.now(timezone.utc)
    item.status = body.status
    item.decision_note = body.decision_note
    item.submitted_at = datetime.now(timezone.utc) if body.status == "submitted" else item.submitted_at
    item.decided_at = datetime.now(timezone.utc) if body.status in {"rejected", "cancelled"} else None
    item.updated_at = datetime.now(timezone.utc)
    session.commit()
    session.refresh(item)
    return pre_enrollment_json(item, session)

@app.put("/api/v1/school/pre-enrollments/{pre_enrollment_id}")
def update_student_pre_enrollment(
    pre_enrollment_id: uuid.UUID,
    body: StudentPreEnrollmentUpdateInput,
    current: Principal = Depends(require_module("students")),
    session: Session = Depends(db),
):
    item = session.get(StudentPreEnrollment, pre_enrollment_id)
    if not item:
        raise HTTPException(404, "Préinscription introuvable")
    if item.status not in {"draft", "submitted"}:
        raise HTTPException(409, "Cette préinscription ne peut plus être modifiée")
    student = ensure_student_scope(item.student_id, current, session)
    school_class = validate_registration_class(
        item.establishment_id, body.desired_class_id, session,
        item.academic_year_id, current,
    )
    effective_regime = body.school_regime or 'normal'
    validate_school_regime(school_class, effective_regime, session)
    provisional = session.scalar(select(StudentAcademicRegistration).where(
        StudentAcademicRegistration.student_id == student.id,
        StudentAcademicRegistration.academic_year_id == item.academic_year_id,
        StudentAcademicRegistration.status == "pre_enrolled",
    ))
    if not provisional:
        raise HTTPException(409, "L'inscription provisoire associée est introuvable")
    if (provisional.options or {}).get("registrationKind") == "reenrollment" and (
        body.first_name != student.first_name or body.last_name != student.last_name
    ):
        raise HTTPException(
            409,
            "Les informations personnelles ne peuvent pas être modifiées pendant la réinscription",
        )
    student.first_name = body.first_name
    student.last_name = body.last_name
    student.updated_at = datetime.now(timezone.utc)
    item.desired_class_id = school_class.id
    item.desired_school_regime = (
        body.school_regime if school_regime_supported(school_class, session) else None
    )
    item.updated_at = datetime.now(timezone.utc)
    provisional.class_id = school_class.id
    provisional.school_regime = effective_regime
    provisional.updated_at = datetime.now(timezone.utc)
    session.commit()
    return pre_enrollment_json(item, session)

@app.post("/api/v1/school/pre-enrollments/{pre_enrollment_id}/approve", status_code=201)
def approve_student_pre_enrollment(
    pre_enrollment_id: uuid.UUID,
    body: StudentPreEnrollmentApprovalInput,
    current: Principal = Depends(require_module("students")),
    session: Session = Depends(db),
):
    item = session.get(StudentPreEnrollment, pre_enrollment_id)
    if not item:
        raise HTTPException(404, "Préinscription introuvable")
    student = ensure_student_scope(item.student_id, current, session)
    if item.status != "submitted":
        raise HTTPException(409, "Seule une préinscription soumise peut être approuvée")
    class_id = body.class_id or item.desired_class_id
    if not class_id:
        raise HTTPException(422, "Une classe est obligatoire pour approuver la préinscription")
    school_class = validate_registration_class(
        student.establishment_id, class_id, session,
        item.academic_year_id, current
    )
    validate_registration_academic_options(school_class, body.has_td, session)
    validate_school_regime(school_class, body.school_regime, session)
    matricule = ensure_student_permanent_matricule(
        session, student, item.academic_year_id
    )
    registration = session.scalar(select(StudentAcademicRegistration).where(
        StudentAcademicRegistration.student_id == student.id,
        StudentAcademicRegistration.academic_year_id == item.academic_year_id,
        StudentAcademicRegistration.status == "pre_enrolled",
    ))
    if registration is None:
        raise HTTPException(409, "L'inscription provisoire associée est introuvable")
    registration.class_id = school_class.id
    registration.registration_date = body.registration_date
    registration.registration_number = matricule
    registration.school_regime = approval_regime
    registration.has_td = body.has_td
    registration.options = {**(registration.options or {}), **body.options}
    registration.status = "validated"
    registration.updated_at = datetime.now(timezone.utc)
    existing_regime_history = session.scalar(select(StudentRegimeHistory.id).where(
        StudentRegimeHistory.registration_id == registration.id,
    ).limit(1))
    if school_regime_supported(school_class, session) and not existing_regime_history:
        session.add(StudentRegimeHistory(
            establishment_id=registration.establishment_id,
            registration_id=registration.id,
            student_id=registration.student_id,
            school_regime=registration.school_regime,
            effective_date=registration.registration_date,
            created_by=uuid.UUID(current.id),
        ))
    student.status = "active"
    student.updated_at = datetime.now(timezone.utc)
    item.status = "approved"
    item.desired_class_id = school_class.id
    item.decided_at = datetime.now(timezone.utc)
    item.updated_at = datetime.now(timezone.utc)
    try:
        session.commit()
    except IntegrityError as exc:
        session.rollback()
        raise HTTPException(409, "Une inscription active existe déjà pour cet élève et cette année") from exc
    session.refresh(registration)
    return {"preEnrollment": pre_enrollment_json(item, session), "registration": registration_json(registration, session)}

@app.get("/api/v1/school/guardians")
def list_guardians(
    search: str | None = None,
    school_id: str | None = None,
    current: Principal = Depends(require_module("students")),
    session: Session = Depends(db),
):
    _, database_id = school_scope(current, session, school_id, required=True)
    statement = select(Guardian).where(Guardian.establishment_id == database_id, Guardian.status == "active")
    allowed = direction_cycle_scope(current)
    if allowed is not None:
        visible_guardians = (
            select(StudentGuardian.guardian_id)
            .join(
                StudentAcademicRegistration,
                StudentAcademicRegistration.student_id == StudentGuardian.student_id,
            )
            .join(SchoolClass, SchoolClass.id == StudentAcademicRegistration.class_id)
            .where(
                StudentAcademicRegistration.status.in_(("pending", "validated", "active")),
                SchoolClass.cycle_id.in_(allowed),
            )
        )
        statement = statement.where(or_(
            Guardian.id.in_(visible_guardians),
            Guardian.created_direction_id == uuid.UUID(current.direction_id),
        ))
    if search and search.strip():
        query = f"%{search.strip().lower()}%"
        statement = statement.where(
            func.lower(Guardian.first_name).like(query)
            | func.lower(Guardian.last_name).like(query)
            | func.lower(func.coalesce(Guardian.phone, "")).like(query)
            | func.lower(func.coalesce(Guardian.email, "")).like(query)
        )
    return [guardian_json(item, session) for item in session.scalars(statement.order_by(Guardian.last_name, Guardian.first_name)).all()]

@app.post("/api/v1/school/guardians", status_code=201)
def create_guardian(
    body: GuardianInput,
    school_id: str | None = None,
    current: Principal = Depends(require_module("students")),
    session: Session = Depends(db),
):
    _, database_id = school_scope(current, session, school_id, required=True)
    person_filters = []
    if body.phone:
        normalized_phone = re.sub(r'[^0-9+]', '', body.phone)
        person_filters.append(func.regexp_replace(GuardianPerson.phone, r'[^0-9+]', '', 'g') == normalized_phone)
    if body.email:
        person_filters.append(func.lower(GuardianPerson.email) == body.email)
    person = session.scalar(select(GuardianPerson).where(*[
        person_filters[0] if len(person_filters) == 1 else person_filters[0] | person_filters[1]
    ])) if person_filters else None
    if not person:
        person = GuardianPerson(**body.model_dump())
        session.add(person)
        session.flush()
    existing = session.scalar(select(Guardian).where(
        Guardian.establishment_id == database_id,
        Guardian.person_id == person.id,
    ))
    if existing:
        raise HTTPException(409, 'Ce responsable existe déjà dans cet établissement')
    item = Guardian(
        establishment_id=database_id,
        created_direction_id=(uuid.UUID(current.direction_id) if current.direction_id else None),
        person_id=person.id,
        **body.model_dump(),
    )
    session.add(item)
    session.commit()
    session.refresh(item)
    return guardian_json(item, session)

@app.put("/api/v1/school/guardians/{guardian_id}")
def update_guardian(
    guardian_id: uuid.UUID,
    body: GuardianInput,
    current: Principal = Depends(require_module("students")),
    session: Session = Depends(db),
):
    item = ensure_guardian_scope(guardian_id, current, session)
    for field, value in body.model_dump().items():
        setattr(item, field, value)
    if item.person_id:
        person = session.get(GuardianPerson, item.person_id)
        if person:
            for field, value in body.model_dump().items():
                setattr(person, field, value)
            person.updated_at = datetime.now(timezone.utc)
    if item.user_id:
        user = session.get(User, item.user_id)
        if not user or user.role != "parent" or user.school_id != item.establishment_id:
            raise HTTPException(409, "Le compte parent associé est incohérent")
        normalized_email = str(item.email or "").strip().lower()
        if not normalized_email:
            raise HTTPException(
                422,
                "Une adresse e-mail est obligatoire pour un responsable disposant d’un accès parent",
            )
        duplicate = session.scalar(select(User.id).where(
            func.lower(User.email) == normalized_email,
            User.id != user.id,
        ))
        if duplicate:
            raise HTTPException(409, "Cette adresse e-mail est déjà utilisée par un compte")
        user.email = normalized_email
        user.name = f"{item.last_name} {item.first_name}".strip()
        user.updated_at = datetime.now(timezone.utc)
    item.updated_at = datetime.now(timezone.utc)
    session.commit()
    session.refresh(item)
    return guardian_json(item, session)

@app.post("/api/v1/school/guardians/{guardian_id}/access")
def provision_parent_access(
    guardian_id: uuid.UUID,
    current: Principal = Depends(require_module_roles(
        "students", "superadmin", "admin"
    )),
    session: Session = Depends(db),
):
    guardian = ensure_guardian_scope(guardian_id, current, session)
    if guardian.status != "active":
        raise HTTPException(409, "Le profil responsable doit être actif")
    ensure_plan_capability(current, session, "parents.access")
    linked_student = session.scalar(select(StudentGuardian.id).join(
        Student, Student.id == StudentGuardian.student_id
    ).where(
        StudentGuardian.guardian_id == guardian.id,
        StudentGuardian.establishment_id == guardian.establishment_id,
        Student.establishment_id == guardian.establishment_id,
        Student.status == "active",
    ).limit(1))
    if not linked_student:
        raise HTTPException(
            409,
            "Ce responsable doit d’abord être rattaché à un élève actif",
        )
    normalized_email = str(guardian.email or "").strip().lower()
    if not normalized_email or not re.fullmatch(r"[^\s@]+@[^\s@]+\.[^\s@]+", normalized_email):
        raise HTTPException(
            422,
            "Une adresse e-mail valide est obligatoire pour créer l’accès parent",
        )
    user = session.get(User, guardian.user_id) if guardian.user_id else None
    if guardian.user_id and not user:
        raise HTTPException(409, "Le compte parent associé est introuvable")
    if user and (user.role != "parent" or user.school_id != guardian.establishment_id):
        raise HTTPException(409, "Le compte associé au responsable est incohérent")
    duplicate = session.scalar(select(User).where(
        func.lower(User.email) == normalized_email,
        User.id != user.id if user else True,
    ))
    if duplicate:
        raise HTTPException(409, "Cette adresse e-mail est déjà utilisée par un compte")
    if not user:
        user = User(
            email=normalized_email,
            password_hash="",
            name=f"{guardian.last_name} {guardian.first_name}".strip(),
            role="parent",
            school_id=guardian.establishment_id,
            status="active",
            password_set=False,
        )
        session.add(user)
        session.flush()
        guardian.user_id = user.id
    user.email = normalized_email
    user.name = f"{guardian.last_name} {guardian.first_name}".strip()
    user.status = "active"
    guardian.updated_at = datetime.now(timezone.utc)
    if guardian.person_id:
        person = session.get(GuardianPerson, guardian.person_id)
        if person:
            person.user_id = user.id
            person.updated_at = datetime.now(timezone.utc)
    temporary_password = issue_temporary_access(session, user, "parent-access")
    session.commit()
    session.refresh(guardian)
    return {
        "guardian": guardian_json(guardian, session),
        "email": normalized_email,
        "temporaryPassword": temporary_password,
    }

@app.post("/api/v1/school/students/{student_id}/guardians", status_code=201)
def link_student_guardian(
    student_id: uuid.UUID,
    body: StudentGuardianLinkInput,
    current: Principal = Depends(require_module("students")),
    session: Session = Depends(db),
):
    student = ensure_student_scope(student_id, current, session)
    guardian = ensure_guardian_scope(body.guardian_id, current, session)
    if guardian.establishment_id != student.establishment_id:
        raise HTTPException(403, "Responsable inter-établissement interdit")
    if body.is_primary:
        for link in session.scalars(select(StudentGuardian).where(StudentGuardian.student_id == student.id)).all():
            link.is_primary = False
    link = StudentGuardian(
        establishment_id=student.establishment_id,
        student_id=student.id,
        guardian_id=guardian.id,
        relationship=body.relationship.strip(),
        is_primary=body.is_primary,
    )
    session.add(link)
    guardian.created_direction_id = None
    try:
        session.commit()
    except IntegrityError as exc:
        session.rollback()
        raise HTTPException(409, "Ce responsable est déjà associé à cet élève") from exc
    return student_json(student, session)

@app.delete("/api/v1/school/students/{student_id}/guardians/{guardian_id}", status_code=204)
def unlink_student_guardian(
    student_id: uuid.UUID,
    guardian_id: uuid.UUID,
    current: Principal = Depends(require_module("students")),
    session: Session = Depends(db),
):
    ensure_student_scope(student_id, current, session)
    link = session.scalar(select(StudentGuardian).where(
        StudentGuardian.student_id == student_id,
        StudentGuardian.guardian_id == guardian_id,
    ))
    if not link:
        raise HTTPException(404, "Association responsable/élève introuvable")
    session.delete(link)
    session.commit()
    return Response(status_code=status.HTTP_204_NO_CONTENT)

def teacher_json(item: Teacher, session: Session) -> dict[str, Any]:
    return {
        "id": str(item.id),
        "schoolId": public_school_id(session, item.establishment_id),
        "directionId": str(item.created_direction_id) if item.created_direction_id else None,
        "userId": str(item.user_id) if item.user_id else None,
        "firstName": item.first_name,
        "lastName": item.last_name,
        "employeeNumber": item.employee_number,
        "subject": item.specialization,
        "specialization": item.specialization,
        "email": item.email,
        "phone": item.phone,
        "sex": item.gender,
        "birthDate": item.birth_date.isoformat() if item.birth_date else None,
        "address": item.address,
        "diploma": item.diploma,
        "hireDate": item.hire_date.isoformat() if item.hire_date else None,
        "status": item.status,
        "createdAt": item.created_at.isoformat(),
        "updatedAt": item.updated_at.isoformat(),
    }

def subject_json(item: Subject, session: Session) -> dict[str, Any]:
    settings = session.scalars(
        select(SubjectLevelSetting).where(
            SubjectLevelSetting.subject_id == item.id,
            SubjectLevelSetting.establishment_id == item.establishment_id,
        )
    ).all()
    return {
        "id": str(item.id),
        "schoolId": public_school_id(session, item.establishment_id),
        "name": item.name,
        "code": item.code,
        "description": item.description,
        "status": item.status,
        "coefficient": 1,
        "levelSettings": [
            {
                "id": str(setting.id),
                "schoolLevelId": str(setting.school_level_id),
                "coefficient": float(setting.coefficient) if setting.coefficient is not None else None,
                "gradingScale": float(setting.grading_scale),
                "status": setting.status,
            }
            for setting in settings
        ],
        "createdAt": item.created_at.isoformat(),
        "updatedAt": item.updated_at.isoformat(),
    }

def affectation_json(item: Affectation, session: Session) -> dict[str, Any]:
    teacher = session.get(Teacher, item.teacher_id)
    subject = session.get(Subject, item.subject_id)
    school_class = session.get(SchoolClass, item.class_id)
    return {
        "id": str(item.id),
        "schoolId": public_school_id(session, item.establishment_id),
        "teacherId": str(item.teacher_id),
        "teacherName": f"{teacher.last_name} {teacher.first_name}" if teacher else None,
        "subjectId": str(item.subject_id),
        "subject": subject.name if subject else None,
        "classId": str(item.class_id),
        "className": school_class.name if school_class else None,
        "academicYearId": str(school_class.academic_year_id) if school_class else None,
        "schoolYearId": str(school_class.academic_year_id) if school_class else None,
        "type": "teaching",
        "status": item.status,
        "createdAt": item.created_at.isoformat(),
        "updatedAt": item.updated_at.isoformat(),
    }

def subject_json(item: Subject, session: Session) -> dict[str, Any]:
    settings = session.scalars(select(SubjectLevelSetting).where(
        SubjectLevelSetting.subject_id == item.id,
        SubjectLevelSetting.establishment_id == item.establishment_id,
        SubjectLevelSetting.status != 'archived')).all()
    return {'id': str(item.id), 'schoolId': public_school_id(session, item.establishment_id),
        'name': item.name, 'code': item.code, 'description': item.description,
        'status': item.status, 'levelSettings': [{
            'id': str(setting.id), 'schoolLevelId': str(setting.school_level_id),
            'academicYearId': str(setting.academic_year_id) if setting.academic_year_id else None,
            'seriesId': str(setting.series_id) if setting.series_id else None,
            'coefficient': float(setting.coefficient) if setting.coefficient is not None else None,
            'gradingScale': float(setting.grading_scale),
            'contributesToAverage': setting.contributes_to_average,
            'status': setting.status} for setting in settings],
        'createdAt': item.created_at.isoformat(), 'updatedAt': item.updated_at.isoformat()}

def scoped_teacher(teacher_id: uuid.UUID, current: Principal, session: Session) -> Teacher:
    teacher = session.get(Teacher, teacher_id)
    if not teacher:
        raise HTTPException(404, "Enseignant introuvable")
    if current.role != "superadmin" and public_school_id(session, teacher.establishment_id) != current.school_id:
        raise HTTPException(403, "Acces inter-etablissement interdit")
    allowed = direction_cycle_scope(current)
    if allowed is not None:
        owned_by_direction = (
            current.direction_id is not None
            and str(teacher.created_direction_id or "") == current.direction_id
        )
        assigned_in_direction = session.scalar(select(Affectation.id).join(
            SchoolClass, SchoolClass.id == Affectation.class_id
        ).where(
            Affectation.teacher_id == teacher.id,
            Affectation.status == "active",
            SchoolClass.cycle_id.in_(allowed),
        ).limit(1))
        if not owned_by_direction and not assigned_in_direction:
            raise HTTPException(403, "Vous n'avez pas acces a cet enseignant dans votre direction")
    return teacher

def scoped_subject(subject_id: uuid.UUID, current: Principal, session: Session) -> Subject:
    subject = session.get(Subject, subject_id)
    if not subject:
        raise HTTPException(404, "Matiere introuvable")
    if current.role != "superadmin" and public_school_id(session, subject.establishment_id) != current.school_id:
        raise HTTPException(403, "Acces inter-etablissement interdit")
    allowed = direction_cycle_scope(current)
    if allowed is not None:
        configured = session.scalar(select(SubjectLevelSetting.id).join(
            SchoolLevel, SchoolLevel.id == SubjectLevelSetting.school_level_id
        ).where(
            SubjectLevelSetting.subject_id == subject.id,
            SubjectLevelSetting.status == "active",
            SchoolLevel.cycle_id.in_(allowed),
        ).limit(1))
        assigned = session.scalar(select(Affectation.id).join(
            SchoolClass, SchoolClass.id == Affectation.class_id
        ).where(
            Affectation.subject_id == subject.id,
            Affectation.status == "active",
            SchoolClass.cycle_id.in_(allowed),
        ).limit(1))
        if not configured and not assigned:
            raise HTTPException(403, "Cette matiere n'est pas disponible dans votre direction")
    return subject

def tenant_subject(subject_id: uuid.UUID, current: Principal, session: Session) -> Subject:
    """Resolve a shared subject catalog entry without granting cycle access."""
    subject = session.get(Subject, subject_id)
    if not subject:
        raise HTTPException(404, "Matiere introuvable")
    if (
        current.role != "superadmin"
        and public_school_id(session, subject.establishment_id) != current.school_id
    ):
        raise HTTPException(403, "Acces inter-etablissement interdit")
    return subject

def scoped_affectation(affectation_id: uuid.UUID, current: Principal, session: Session) -> Affectation:
    affectation = session.get(Affectation, affectation_id)
    if not affectation:
        raise HTTPException(404, "Affectation introuvable")
    if current.role != "superadmin" and public_school_id(session, affectation.establishment_id) != current.school_id:
        raise HTTPException(403, "Acces inter-etablissement interdit")
    school_class = session.get(SchoolClass, affectation.class_id)
    ensure_direction_cycle_access(current, school_class.cycle_id if school_class else None)
    return affectation

@app.get("/api/v1/school/teachers")
def list_teachers(
    school_id: str | None = None,
    search: str | None = None,
    status_filter: str | None = None,
    current: Principal = Depends(require_module("teachers")),
    session: Session = Depends(db),
):
    _, database_id = school_scope(current, session, school_id, required=True)
    statement = select(Teacher).where(Teacher.establishment_id == database_id)
    allowed = direction_cycle_scope(current)
    if allowed is not None:
        assigned_teacher_ids = select(Affectation.teacher_id).join(
            SchoolClass, SchoolClass.id == Affectation.class_id
        ).where(
            Affectation.status == "active",
            SchoolClass.cycle_id.in_(allowed),
        )
        statement = statement.where(or_(
            Teacher.created_direction_id == uuid.UUID(current.direction_id),
            Teacher.id.in_(assigned_teacher_ids),
        ))
    if status_filter:
        statement = statement.where(Teacher.status == status_filter)
    else:
        # Archived profiles remain available to historical relations, but are
        # excluded from the operational teacher directory.
        statement = statement.where(Teacher.status != "archived")
    if search:
        pattern = f"%{search.strip().lower()}%"
        statement = statement.where(
            func.lower(Teacher.first_name + " " + Teacher.last_name).like(pattern)
            | func.lower(func.coalesce(Teacher.employee_number, "")).like(pattern)
        )
    return [teacher_json(item, session) for item in session.scalars(
        statement.distinct().order_by(Teacher.last_name, Teacher.first_name)
    ).all()]

@app.post("/api/v1/school/teachers", status_code=201)
def create_teacher(
    body: TeacherInput,
    school_id: str | None = None,
    current: Principal = Depends(require_module("teachers")),
    session: Session = Depends(db),
):
    _, database_id = school_scope(current, session, school_id, required=True)
    employee_number = body.employee_number or f"ENS-{datetime.now().year}-{uuid.uuid4().hex[:8].upper()}"
    teacher = Teacher(
        establishment_id=database_id,
        created_direction_id=(
            uuid.UUID(current.direction_id)
            if current.role == "admin" and current.direction_id
            else None
        ),
        first_name=body.first_name,
        last_name=body.last_name,
        employee_number=employee_number,
        specialization=body.specialization,
        email=body.email,
        phone=body.phone,
        gender=body.gender,
        birth_date=body.birth_date,
        address=body.address,
        diploma=body.diploma,
        hire_date=body.hire_date,
        status="active",
    )
    session.add(teacher)
    try:
        session.commit()
    except IntegrityError as exc:
        session.rollback()
        raise HTTPException(409, "Ce matricule enseignant existe deja") from exc
    session.refresh(teacher)
    return teacher_json(teacher, session)

@app.put("/api/v1/school/teachers/{teacher_id}")
def update_teacher(
    teacher_id: uuid.UUID,
    body: TeacherUpdateInput,
    current: Principal = Depends(require_module("teachers")),
    session: Session = Depends(db),
):
    teacher = scoped_teacher(teacher_id, current, session)
    if not body.model_fields_set:
        raise HTTPException(422, "Aucun champ a modifier")
    for field, value in body.model_dump(include=body.model_fields_set).items():
        setattr(teacher, field, value.strip() if isinstance(value, str) else value)
    if teacher.user_id:
        user = session.get(User, teacher.user_id)
        if not user or user.role != "teacher":
            raise HTTPException(409, "Le compte enseignant associé est incohérent")
        if "email" in body.model_fields_set:
            normalized_email = str(teacher.email or "").strip().lower()
            if not normalized_email or "@" not in normalized_email:
                raise HTTPException(422, "Une adresse e-mail enseignant valide est requise")
            duplicate = session.scalar(select(User).where(
                User.email == normalized_email,
                User.id != user.id,
            ))
            if duplicate:
                raise HTTPException(409, "Cette adresse e-mail est déjà utilisée par un compte")
            user.email = normalized_email
        user.name = f"{teacher.last_name} {teacher.first_name}".strip()
        user.updated_at = datetime.now(timezone.utc)
    teacher.updated_at = datetime.now(timezone.utc)
    try:
        session.commit()
    except IntegrityError as exc:
        session.rollback()
        raise HTTPException(409, "Ce matricule enseignant existe deja") from exc
    session.refresh(teacher)
    return teacher_json(teacher, session)

@app.get("/api/v1/school/teachers/{teacher_id}")
def get_teacher(
    teacher_id: uuid.UUID,
    current: Principal = Depends(require_module("teachers")),
    session: Session = Depends(db),
):
    return teacher_json(scoped_teacher(teacher_id, current, session), session)

@app.post("/api/v1/school/teachers/{teacher_id}/access")
def provision_teacher_access(
    teacher_id: uuid.UUID,
    current: Principal = Depends(require_module_roles("teachers", "superadmin", "admin")),
    session: Session = Depends(db),
):
    teacher = scoped_teacher(teacher_id, current, session)
    if teacher.status != "active":
        raise HTTPException(409, "Le profil enseignant doit être actif")
    matricule = str(teacher.employee_number or "").strip()
    if not matricule:
        raise HTTPException(409, "Un matricule enseignant est requis pour créer l’accès")

    user = session.get(User, teacher.user_id) if teacher.user_id else None
    if teacher.user_id and not user:
        raise HTTPException(409, "Le compte enseignant associé est introuvable")
    if user and (user.role != "teacher" or user.school_id != teacher.establishment_id):
        raise HTTPException(409, "Le compte associé au profil enseignant est incohérent")
    if not user:
        internal_email = f"teacher-{teacher.id}@accounts.edupro.local"
        user = User(
            email=internal_email,
            password_hash="",
            name=f"{teacher.last_name} {teacher.first_name}".strip(),
            role="teacher",
            school_id=teacher.establishment_id,
            status="active",
            password_set=False,
        )
        session.add(user)
        session.flush()
        teacher.user_id = user.id

    user.name = f"{teacher.last_name} {teacher.first_name}".strip()
    user.status = "active"
    teacher.updated_at = datetime.now(timezone.utc)
    temporary_password = issue_temporary_access(session, user, "teacher-access")
    session.commit()
    session.refresh(teacher)
    return {
        "teacher": teacher_json(teacher, session),
        "matricule": matricule,
        "temporaryPassword": temporary_password,
    }

@app.get("/api/v1/school/teacher/workspace")
def teacher_workspace(
    current: Principal = Depends(require("teacher")),
    session: Session = Depends(db),
):
    if not current.teacher_id:
        raise HTTPException(403, "Profil enseignant non associé")
    try:
        teacher_id = uuid.UUID(current.teacher_id)
    except ValueError as exc:
        raise HTTPException(403, "Profil enseignant invalide") from exc
    teacher = session.get(Teacher, teacher_id)
    if (
        not teacher
        or teacher.user_id != uuid.UUID(current.id)
        or teacher.status != "active"
        or public_school_id(session, teacher.establishment_id) != current.school_id
    ):
        raise HTTPException(403, "Profil enseignant invalide")

    candidate_affectations = session.scalars(
        select(Affectation).where(
            Affectation.teacher_id == teacher.id,
            Affectation.establishment_id == teacher.establishment_id,
            Affectation.status == "active",
        ).order_by(Affectation.created_at)
    ).all()
    affectations = []
    for affectation in candidate_affectations:
        school_class = session.get(SchoolClass, affectation.class_id)
        subject = session.get(Subject, affectation.subject_id)
        if (
            school_class
            and subject
            and school_class.status == "active"
            and subject.status == "active"
            and subject_is_enabled_for_class(
                session, school_class, affectation.subject_id
            )
        ):
            affectations.append(affectation)
    class_ids = {item.class_id for item in affectations}
    subject_ids = {item.subject_id for item in affectations}
    classes = session.scalars(
        select(SchoolClass).where(
            SchoolClass.id.in_(class_ids),
            SchoolClass.status == "active",
        ).order_by(SchoolClass.name)
    ).all() if class_ids else []
    cycle_ids = {item.cycle_id for item in classes if item.cycle_id}
    level_ids = {item.school_level_id for item in classes if item.school_level_id}
    cycles = session.scalars(
        select(SchoolCycle).where(
            SchoolCycle.establishment_id == teacher.establishment_id,
            SchoolCycle.id.in_(cycle_ids),
            SchoolCycle.status == "active",
        ).order_by(SchoolCycle.sort_order, SchoolCycle.name)
    ).all() if cycle_ids else []
    levels = session.scalars(
        select(SchoolLevel).where(
            SchoolLevel.establishment_id == teacher.establishment_id,
            SchoolLevel.id.in_(level_ids),
            SchoolLevel.status == "active",
        ).order_by(SchoolLevel.sort_order, SchoolLevel.name)
    ).all() if level_ids else []
    subjects = session.scalars(
        select(Subject).where(
            Subject.id.in_(subject_ids),
            Subject.status == "active",
        ).order_by(Subject.name)
    ).all() if subject_ids else []
    years = session.scalars(
        select(AcademicYear).where(
            AcademicYear.establishment_id == teacher.establishment_id
        ).order_by(AcademicYear.start_date.desc())
    ).all()
    active_year = next((year for year in years if year.is_active), None)
    registrations = session.scalars(
        select(StudentAcademicRegistration).where(
            StudentAcademicRegistration.class_id.in_(class_ids),
            StudentAcademicRegistration.establishment_id == teacher.establishment_id,
            StudentAcademicRegistration.status.in_(("pending", "validated", "active")),
        ).order_by(StudentAcademicRegistration.registration_date.desc())
    ).all() if class_ids else []
    registration_by_student: dict[uuid.UUID, StudentAcademicRegistration] = {}
    for registration in registrations:
        previous = registration_by_student.get(registration.student_id)
        if previous is None or (
            active_year
            and registration.academic_year_id == active_year.id
            and previous.academic_year_id != active_year.id
        ):
            registration_by_student[registration.student_id] = registration
    students = []
    for registration in registration_by_student.values():
        student = session.get(Student, registration.student_id)
        if student and student.status != "archived":
            students.append(student_json(student, session, registration.academic_year_id))
    establishment_row, establishment = admin_establishment_record(current, session)

    return {
        "establishment": admin_establishment_json(
            establishment_row, establishment, session
        ),
        "teacher": teacher_json(teacher, session),
        "academicYears": [academic_year_json(year, session) for year in years],
        "cycles": [cycle_json(item, session) for item in cycles],
        "schoolLevels": [level_json(item, session) for item in levels],
        "classes": [class_json(item, session) for item in classes],
        "subjects": [subject_json(item, session) for item in subjects],
        "affectations": [affectation_json(item, session) for item in affectations],
        "students": students,
    }

@app.get("/api/v1/school/student/workspace")
def student_workspace(
    current: Principal = Depends(require("student")),
    session: Session = Depends(db),
):
    if not current.student_id:
        raise HTTPException(403, "Profil élève non associé")
    try:
        student_id = uuid.UUID(current.student_id)
    except ValueError as exc:
        raise HTTPException(403, "Profil élève invalide") from exc
    student = session.get(Student, student_id)
    if (
        not student
        or student.user_id != uuid.UUID(current.id)
        or student.status != "active"
        or public_school_id(session, student.establishment_id) != current.school_id
    ):
        raise HTTPException(403, "Profil élève invalide")

    registrations = list(session.scalars(
        select(StudentAcademicRegistration).where(
            StudentAcademicRegistration.student_id == student.id,
            StudentAcademicRegistration.establishment_id == student.establishment_id,
            StudentAcademicRegistration.status.in_(("pending", "validated", "active")),
        ).order_by(StudentAcademicRegistration.registration_date.desc())
    ).all())
    class_ids = {registration.class_id for registration in registrations}
    classes = list(session.scalars(
        select(SchoolClass).where(SchoolClass.id.in_(class_ids)).order_by(SchoolClass.name)
    ).all()) if class_ids else []
    year_ids = {registration.academic_year_id for registration in registrations}
    years = list(session.scalars(
        select(AcademicYear).where(AcademicYear.id.in_(year_ids)).order_by(AcademicYear.start_date.desc())
    ).all()) if year_ids else []
    cycle_ids = {item.cycle_id for item in classes if item.cycle_id}
    level_ids = {item.school_level_id for item in classes if item.school_level_id}
    cycles = list(session.scalars(
        select(SchoolCycle).where(SchoolCycle.id.in_(cycle_ids)).order_by(SchoolCycle.sort_order)
    ).all()) if cycle_ids else []
    levels = list(session.scalars(
        select(SchoolLevel).where(SchoolLevel.id.in_(level_ids)).order_by(SchoolLevel.sort_order)
    ).all()) if level_ids else []
    establishment_row, establishment = admin_establishment_record(current, session)
    selected_year_id = next((year.id for year in years if year.is_active), None)
    return {
        "establishment": admin_establishment_json(
            establishment_row, establishment, session
        ),
        "student": student_json(student, session, selected_year_id),
        "academicYears": [academic_year_json(year, session) for year in years],
        "classes": [class_json(item, session) for item in classes],
        "cycles": [cycle_json(item, session) for item in cycles],
        "schoolLevels": [level_json(item, session) for item in levels],
        "registrations": [registration_json(item, session) for item in registrations],
    }

@app.get("/api/v1/school/parent/workspace")
def parent_workspace(
    current: Principal = Depends(require("parent")),
    session: Session = Depends(db),
):
    """Return only the school context of children linked to this parent."""
    user_id = uuid.UUID(current.id)
    guardian = session.scalar(select(Guardian).where(
        Guardian.user_id == user_id,
        Guardian.status == "active",
    ))
    if (
        not guardian
        or public_school_id(session, guardian.establishment_id) != current.school_id
    ):
        raise HTTPException(403, "Profil parent invalide")

    linked_student_ids = select(StudentGuardian.student_id).where(
        StudentGuardian.guardian_id == guardian.id,
        StudentGuardian.establishment_id == guardian.establishment_id,
    )
    students = list(session.scalars(select(Student).where(
        Student.id.in_(linked_student_ids),
        Student.establishment_id == guardian.establishment_id,
        Student.status == "active",
    ).order_by(Student.last_name, Student.first_name)).all())
    student_ids = {student.id for student in students}
    registrations = list(session.scalars(select(StudentAcademicRegistration).where(
        StudentAcademicRegistration.student_id.in_(student_ids),
        StudentAcademicRegistration.establishment_id == guardian.establishment_id,
        StudentAcademicRegistration.status.in_(("pending", "validated", "active")),
    ).order_by(StudentAcademicRegistration.registration_date.desc())).all()) if student_ids else []
    class_ids = {registration.class_id for registration in registrations}
    year_ids = {registration.academic_year_id for registration in registrations}
    classes = list(session.scalars(select(SchoolClass).where(
        SchoolClass.id.in_(class_ids),
        SchoolClass.establishment_id == guardian.establishment_id,
        SchoolClass.status == "active",
    ).order_by(SchoolClass.name)).all()) if class_ids else []
    years = list(session.scalars(select(AcademicYear).where(
        AcademicYear.id.in_(year_ids),
        AcademicYear.establishment_id == guardian.establishment_id,
    ).order_by(AcademicYear.start_date.desc())).all()) if year_ids else []
    cycle_ids = {item.cycle_id for item in classes if item.cycle_id}
    level_ids = {item.school_level_id for item in classes if item.school_level_id}
    cycles = list(session.scalars(select(SchoolCycle).where(
        SchoolCycle.id.in_(cycle_ids),
        SchoolCycle.establishment_id == guardian.establishment_id,
        SchoolCycle.status == "active",
    ).order_by(SchoolCycle.sort_order, SchoolCycle.name)).all()) if cycle_ids else []
    levels = list(session.scalars(select(SchoolLevel).where(
        SchoolLevel.id.in_(level_ids),
        SchoolLevel.establishment_id == guardian.establishment_id,
        SchoolLevel.status == "active",
    ).order_by(SchoolLevel.sort_order, SchoolLevel.name)).all()) if level_ids else []
    registration_by_student: dict[uuid.UUID, StudentAcademicRegistration] = {}
    for registration in registrations:
        registration_by_student.setdefault(registration.student_id, registration)
    student_payloads = []
    for student in students:
        payload = student_json(
            student,
            session,
            registration_by_student.get(student.id).academic_year_id
            if student.id in registration_by_student else None,
        )
        # Another guardian's private contact data is not part of a parent's
        # workspace, even when both adults are linked to the same child.
        own_guardians = [
            item for item in payload.get("guardians", [])
            if item.get("id") == str(guardian.id)
        ]
        payload["guardians"] = own_guardians
        student_payloads.append(payload)
    establishment_row, establishment = admin_establishment_record(current, session)
    return {
        "establishment": admin_establishment_json(
            establishment_row, establishment, session
        ),
        "guardian": guardian_json(guardian, session),
        "students": student_payloads,
        "academicYears": [academic_year_json(year, session) for year in years],
        "classes": [class_json(item, session) for item in classes],
        "cycles": [cycle_json(item, session) for item in cycles],
        "schoolLevels": [level_json(item, session) for item in levels],
        "registrations": [registration_json(item, session) for item in registrations],
    }

@app.delete("/api/v1/school/teachers/{teacher_id}", status_code=204)
def archive_teacher(
    teacher_id: uuid.UUID,
    current: Principal = Depends(require_module("teachers")),
    session: Session = Depends(db),
):
    teacher = scoped_teacher(teacher_id, current, session)
    active_count = session.scalar(select(func.count()).select_from(Affectation).where(
        Affectation.teacher_id == teacher.id,
        Affectation.status == "active",
    ))
    if active_count:
        raise HTTPException(409, "Des affectations actives utilisent cet enseignant")
    teacher.status = "archived"
    if teacher.user_id:
        user = session.get(User, teacher.user_id)
        if user and user.role == "teacher":
            user.status = "suspended"
            user.updated_at = datetime.now(timezone.utc)
    teacher.updated_at = datetime.now(timezone.utc)
    session.commit()
    return Response(status_code=status.HTTP_204_NO_CONTENT)

@app.get("/api/v1/school/subjects")
def list_subjects(
    school_id: str | None = None,
    current: Principal = Depends(require_module("subjects")),
    session: Session = Depends(db),
):
    _, database_id = school_scope(current, session, school_id, required=True)
    statement = select(Subject).where(
        Subject.establishment_id == database_id,
        Subject.status != "archived",
    )
    rows = session.scalars(statement.order_by(Subject.name)).all()
    return [subject_json(item, session) for item in rows]

@app.post("/api/v1/school/subjects", status_code=201)
def create_subject(
    body: SubjectInput,
    school_id: str | None = None,
    current: Principal = Depends(require_module("subjects")),
    session: Session = Depends(db),
):
    _, database_id = school_scope(current, session, school_id, required=True)
    subject = Subject(
        establishment_id=database_id,
        name=body.name,
        code=body.code,
        description=body.description,
        status="active",
    )
    session.add(subject)
    try:
        session.commit()
    except IntegrityError as exc:
        session.rollback()
        raise HTTPException(409, "Cette matiere ou ce code existe deja") from exc
    session.refresh(subject)
    return subject_json(subject, session)

@app.put("/api/v1/school/subjects/{subject_id}")
def update_subject(
    subject_id: uuid.UUID,
    body: SubjectUpdateInput,
    current: Principal = Depends(require_module("subjects")),
    session: Session = Depends(db),
):
    subject = scoped_subject(subject_id, current, session)
    if not body.model_fields_set:
        raise HTTPException(422, "Aucun champ a modifier")
    for field, value in body.model_dump(include=body.model_fields_set).items():
        setattr(subject, field, value.strip() if isinstance(value, str) else value)
    subject.updated_at = datetime.now(timezone.utc)
    try:
        session.commit()
    except IntegrityError as exc:
        session.rollback()
        raise HTTPException(409, "Cette matiere ou ce code existe deja") from exc
    session.refresh(subject)
    return subject_json(subject, session)

@app.get("/api/v1/school/subjects/{subject_id}")
def get_subject(
    subject_id: uuid.UUID,
    current: Principal = Depends(require_module("subjects")),
    session: Session = Depends(db),
):
    return subject_json(scoped_subject(subject_id, current, session), session)

@app.put("/api/v1/school/subjects/{subject_id}/level-setting")
def upsert_subject_level_setting(
    subject_id: uuid.UUID,
    body: SubjectLevelSettingInput,
    current: Principal = Depends(require_module_roles("subjects", "superadmin", "admin")),
    session: Session = Depends(db),
):
    subject = tenant_subject(subject_id, current, session)
    level = session.get(SchoolLevel, body.school_level_id)
    if not level:
        raise HTTPException(422, "Niveau introuvable")
    if level.establishment_id != subject.establishment_id:
        raise HTTPException(403, "Niveau inter-etablissement interdit")
    ensure_direction_cycle_access(current, level.cycle_id)
    year = session.get(AcademicYear, body.academic_year_id)
    if not year:
        raise HTTPException(422, 'Annee scolaire introuvable')
    if year.establishment_id != subject.establishment_id:
        raise HTTPException(403, 'Annee scolaire inter-etablissement interdite')
    cycle = session.get(SchoolCycle, level.cycle_id)
    cycle_identity = (
        f"{cycle.code} {cycle.name}".upper().replace("É", "E")
        if cycle else ""
    )
    is_lycee = "LYCEE" in cycle_identity
    has_fixed_scale = is_lycee or "COLLEGE" in cycle_identity
    if has_fixed_scale and body.grading_scale != 20:
        raise HTTPException(
            422,
            "Le barème est fixé à 20 au collège et au lycée",
        )
    if not is_lycee and body.coefficient is not None:
        raise HTTPException(422, 'Les coefficients sont autorises uniquement au lycee')
    if is_lycee and body.coefficient is not None and body.series_id is None:
        raise HTTPException(
            422,
            "Sélectionnez une série pour configurer un coefficient",
        )
    validate_series_scope(body.series_id, subject.establishment_id, level.cycle_id, session)
    if body.series_id and not is_lycee:
        raise HTTPException(422, 'Une serie pedagogique est autorisee uniquement au lycee')
    setting = session.scalar(select(SubjectLevelSetting).where(
        SubjectLevelSetting.establishment_id == subject.establishment_id,
        SubjectLevelSetting.subject_id == subject.id,
        SubjectLevelSetting.school_level_id == level.id,
        SubjectLevelSetting.academic_year_id == year.id,
        SubjectLevelSetting.series_id == body.series_id,
    ))
    if not setting:
        setting = SubjectLevelSetting(
            establishment_id=subject.establishment_id,
            subject_id=subject.id,
            school_level_id=level.id,
            academic_year_id=year.id,
            series_id=body.series_id,
        )
        session.add(setting)
    setting.coefficient = body.coefficient
    setting.grading_scale = 20 if has_fixed_scale else body.grading_scale
    setting.contributes_to_average = body.contributes_to_average
    setting.status = "active" if body.enabled else "inactive"
    setting.updated_at = datetime.now(timezone.utc)
    if is_lycee and body.series_id is not None:
        series_rows = session.scalars(select(SubjectLevelSetting).where(
            SubjectLevelSetting.establishment_id == subject.establishment_id,
            SubjectLevelSetting.subject_id == subject.id,
            SubjectLevelSetting.academic_year_id == year.id,
            SubjectLevelSetting.series_id == body.series_id,
            SubjectLevelSetting.status != "archived",
        )).all()
        for series_row in series_rows:
            series_row.coefficient = body.coefficient
            series_row.updated_at = datetime.now(timezone.utc)
    session.commit()
    return subject_json(subject, session)


def subject_is_enabled_for_class(
    session: Session,
    school_class: SchoolClass,
    subject_id: uuid.UUID,
) -> bool:
    """Use contextual settings when configured, while preserving legacy contexts."""
    context_rows = session.scalars(select(SubjectLevelSetting).where(
        SubjectLevelSetting.establishment_id == school_class.establishment_id,
        SubjectLevelSetting.academic_year_id == school_class.academic_year_id,
        SubjectLevelSetting.school_level_id == school_class.school_level_id,
        SubjectLevelSetting.series_id == school_class.series_id,
        SubjectLevelSetting.status != 'archived',
    )).all()
    if not context_rows:
        return True
    return any(
        row.subject_id == subject_id and row.status == 'active'
        for row in context_rows
    )


def subject_grading_scale_for_class(
    session: Session,
    school_class: SchoolClass,
    subject_id: uuid.UUID,
) -> float:
    cycle = (
        session.get(SchoolCycle, school_class.cycle_id)
        if school_class.cycle_id else None
    )
    cycle_identity = (
        f"{cycle.code} {cycle.name}".upper().replace("É", "E")
        if cycle else ""
    )
    if "COLLEGE" in cycle_identity or "LYCEE" in cycle_identity:
        return 20.0
    setting = session.scalar(select(SubjectLevelSetting).where(
        SubjectLevelSetting.establishment_id == school_class.establishment_id,
        SubjectLevelSetting.academic_year_id == school_class.academic_year_id,
        SubjectLevelSetting.school_level_id == school_class.school_level_id,
        SubjectLevelSetting.subject_id == subject_id,
        SubjectLevelSetting.series_id == school_class.series_id,
        SubjectLevelSetting.status == "active",
    ))
    return float(setting.grading_scale) if setting else 20.0

@app.delete("/api/v1/school/subjects/{subject_id}", status_code=204)
def archive_subject(
    subject_id: uuid.UUID,
    current: Principal = Depends(require_module("subjects")),
    session: Session = Depends(db),
):
    subject = scoped_subject(subject_id, current, session)
    active_count = session.scalar(select(func.count()).select_from(Affectation).where(
        Affectation.subject_id == subject.id,
        Affectation.status == "active",
    ))
    if active_count:
        raise HTTPException(409, "Des affectations actives utilisent cette matiere")
    subject.status = "archived"
    subject.updated_at = datetime.now(timezone.utc)
    session.commit()
    return Response(status_code=status.HTTP_204_NO_CONTENT)

@app.get("/api/v1/school/affectations")
def list_affectations(
    school_id: str | None = None,
    academic_year_id: uuid.UUID | None = None,
    current: Principal = Depends(require_module("affectations")),
    session: Session = Depends(db),
):
    _, database_id = school_scope(current, session, school_id, required=True)
    statement = select(Affectation).where(Affectation.establishment_id == database_id)
    allowed = direction_cycle_scope(current)
    if allowed is not None:
        statement = statement.join(
            SchoolClass, SchoolClass.id == Affectation.class_id
        ).where(SchoolClass.cycle_id.in_(allowed))
    if academic_year_id:
        class_ids = select(SchoolClass.id).where(
            SchoolClass.establishment_id == database_id,
            SchoolClass.academic_year_id == academic_year_id,
        )
        statement = statement.where(Affectation.class_id.in_(class_ids))
    rows = session.scalars(statement.order_by(Affectation.created_at)).all()
    return [affectation_json(item, session) for item in rows]

@app.post("/api/v1/school/affectations", status_code=201)
def create_affectation(
    body: AffectationInput,
    current: Principal = Depends(require_module("affectations")),
    session: Session = Depends(db),
):
    _, database_id = school_scope(current, session, None, required=True)
    teacher = scoped_teacher(body.teacher_id, current, session)
    subject = session.get(Subject, body.subject_id)
    school_class = session.get(SchoolClass, body.class_id)
    if not teacher or not subject or not school_class:
        raise HTTPException(422, "Enseignant, matiere ou classe introuvable")
    if any(item.establishment_id != database_id for item in (teacher, subject, school_class)):
        raise HTTPException(403, "Reference inter-etablissement interdite")
    ensure_direction_cycle_access(current, school_class.cycle_id)
    if any(item.status != "active" for item in (teacher, subject, school_class)):
        raise HTTPException(409, "Enseignant, matiere et classe doivent etre actifs")
    if not subject_is_enabled_for_class(session, school_class, subject.id):
        raise HTTPException(
            409,
            "Cette matière n'est pas configurée pour le niveau ou la série de cette classe",
        )
    occupied = session.scalar(select(Affectation).where(
        Affectation.establishment_id == database_id,
        Affectation.class_id == school_class.id,
        Affectation.subject_id == subject.id,
        Affectation.status == "active",
    ))
    if occupied:
        occupied_teacher = session.get(Teacher, occupied.teacher_id)
        teacher_name = (
            f"{occupied_teacher.last_name} {occupied_teacher.first_name}".strip()
            if occupied_teacher else "un autre enseignant"
        )
        raise HTTPException(
            409,
            f"{subject.name} est déjà attribuée à {teacher_name} dans {school_class.name}.",
        )
    affectation = Affectation(
        establishment_id=database_id,
        teacher_id=teacher.id,
        subject_id=subject.id,
        class_id=school_class.id,
        status="active",
    )
    session.add(affectation)
    try:
        session.commit()
    except IntegrityError as exc:
        session.rollback()
        raise HTTPException(409, "Cette affectation existe deja") from exc
    session.refresh(affectation)
    return affectation_json(affectation, session)

@app.delete("/api/v1/school/affectations/{affectation_id}", status_code=204)
def archive_affectation(
    affectation_id: uuid.UUID,
    current: Principal = Depends(require_module("affectations")),
    session: Session = Depends(db),
):
    affectation = scoped_affectation(affectation_id, current, session)
    affectation.status = "inactive"
    affectation.updated_at = datetime.now(timezone.utc)
    session.commit()
    return Response(status_code=status.HTTP_204_NO_CONTENT)

@app.put("/api/v1/school/affectations/{affectation_id}")
def update_affectation(
    affectation_id: uuid.UUID,
    body: AffectationInput,
    current: Principal = Depends(require_module("affectations")),
    session: Session = Depends(db),
):
    affectation = scoped_affectation(affectation_id, current, session)
    teacher = scoped_teacher(body.teacher_id, current, session)
    subject = session.get(Subject, body.subject_id)
    school_class = session.get(SchoolClass, body.class_id)
    if not teacher or not subject or not school_class:
        raise HTTPException(422, "Enseignant, matiere ou classe introuvable")
    if any(item.establishment_id != affectation.establishment_id
           for item in (teacher, subject, school_class)):
        raise HTTPException(403, "Reference inter-etablissement interdite")
    ensure_direction_cycle_access(current, school_class.cycle_id)
    if not subject_is_enabled_for_class(session, school_class, subject.id):
        raise HTTPException(
            409,
            "Cette matière n'est pas configurée pour le niveau ou la série de cette classe",
        )
    occupied = session.scalar(select(Affectation).where(
        Affectation.establishment_id == affectation.establishment_id,
        Affectation.class_id == school_class.id,
        Affectation.subject_id == subject.id,
        Affectation.status == "active",
        Affectation.id != affectation.id,
    ))
    if occupied:
        occupied_teacher = session.get(Teacher, occupied.teacher_id)
        teacher_name = (
            f"{occupied_teacher.last_name} {occupied_teacher.first_name}".strip()
            if occupied_teacher else "un autre enseignant"
        )
        raise HTTPException(
            409,
            f"{subject.name} est déjà attribuée à {teacher_name} dans {school_class.name}.",
        )
    context_changed = any((
        affectation.teacher_id != teacher.id,
        affectation.subject_id != subject.id,
        affectation.class_id != school_class.id,
    ))
    has_history = context_changed and any((
        session.scalar(select(Evaluation.id).where(
            Evaluation.affectation_id == affectation.id).limit(1)),
        session.scalar(select(Grade.id).where(
            Grade.affectation_id == affectation.id).limit(1)),
        session.scalar(select(SchoolAssignment.id).where(
            SchoolAssignment.affectation_id == affectation.id).limit(1)),
        session.scalar(select(ScheduleEntry.id).where(
            ScheduleEntry.affectation_id == affectation.id).limit(1)),
    ))
    if has_history:
        # Affectations referenced by pedagogical history are append-only.  The
        # old row remains available to evaluations/grades while the corrected
        # context becomes the sole active assignment.
        affectation.status = "inactive"
        affectation.updated_at = datetime.now(timezone.utc)
        replacement = Affectation(
            establishment_id=affectation.establishment_id,
            teacher_id=teacher.id,
            subject_id=subject.id,
            class_id=school_class.id,
            status="active",
        )
        session.add(replacement)
        try:
            session.commit()
        except IntegrityError as exc:
            session.rollback()
            raise HTTPException(409, "Cette affectation existe deja") from exc
        session.refresh(replacement)
        return affectation_json(replacement, session)
    affectation.teacher_id = teacher.id
    affectation.subject_id = subject.id
    affectation.class_id = school_class.id
    affectation.status = "active"
    affectation.updated_at = datetime.now(timezone.utc)
    try:
        session.commit()
    except IntegrityError as exc:
        session.rollback()
        raise HTTPException(409, "Cette affectation existe deja") from exc
    session.refresh(affectation)
    return affectation_json(affectation, session)

def module_tenant_scope(
    current: Principal,
    session: Session,
    requested_school_id: str | None = None,
) -> tuple[str, uuid.UUID]:
    if current.role == "superadmin":
        if not requested_school_id:
            raise HTTPException(422, "Un etablissement est requis")
        public_id = requested_school_id
    else:
        if not current.school_id:
            raise HTTPException(403, "Aucun etablissement associe")
        if requested_school_id and requested_school_id != current.school_id:
            raise HTTPException(403, "Acces inter-etablissement interdit")
        public_id = current.school_id
    database_id = resolve_establishment_id(session, public_id)
    if not database_id:
        raise HTTPException(404, "Etablissement introuvable")
    return public_id, database_id

def academic_period_json(item: AcademicPeriod, session: Session) -> dict[str, Any]:
    return {
        "id": str(item.id),
        "schoolId": public_school_id(session, item.establishment_id),
        "academicYearId": str(item.academic_year_id),
        "parentPeriodId": str(item.parent_period_id) if item.parent_period_id else None,
        "code": item.code,
        "name": item.name,
        "periodType": item.period_type,
        "sortOrder": item.sort_order,
        "startDate": item.start_date.isoformat() if item.start_date else None,
        "endDate": item.end_date.isoformat() if item.end_date else None,
        "status": item.status,
    }

def evaluation_json(item: Evaluation, session: Session) -> dict[str, Any]:
    return {
        "id": str(item.id),
        "schoolId": public_school_id(session, item.establishment_id),
        "title": item.name,
        "type": item.type,
        "examCode": item.exam_code,
        "academicYearId": str(item.academic_year_id) if item.academic_year_id else "",
        "periodId": str(item.academic_period_id) if item.academic_period_id else None,
        "period": item.period,
        "classId": str(item.class_id),
        "subjectId": str(item.subject_id),
        "affectationId": str(item.affectation_id) if item.affectation_id else None,
        "programId": str(item.program_id) if item.program_id else None,
        "date": item.date_scheduled.isoformat() if item.date_scheduled else None,
        "status": item.status,
        "maxScore": item.max_value,
        "description": item.description,
        "createdBy": str(item.created_by) if item.created_by else "",
        "createdAt": item.created_at.isoformat(),
        "submittedAt": item.submitted_at.isoformat() if item.submitted_at else None,
        "validatedAt": item.validated_at.isoformat() if item.validated_at else None,
        "validatedBy": str(item.validated_by) if item.validated_by else None,
        "rejectedAt": item.rejected_at.isoformat() if item.rejected_at else None,
        "rejectedBy": str(item.rejected_by) if item.rejected_by else None,
        "rejectionReason": item.rejection_reason,
    }

def evaluation_program_json(item: EvaluationProgram, session: Session) -> dict[str, Any]:
    class_ids = session.scalars(select(EvaluationProgramClass.class_id).where(
        EvaluationProgramClass.program_id == item.id
    ).order_by(EvaluationProgramClass.created_at)).all()
    sheet_count = session.scalar(select(func.count(Evaluation.id)).where(
        Evaluation.program_id == item.id
    )) or 0
    return {
        "id": str(item.id),
        "schoolId": public_school_id(session, item.establishment_id),
        "academicYearId": str(item.academic_year_id),
        "periodId": str(item.academic_period_id),
        "title": item.name,
        "type": item.type,
        "examCode": item.exam_code,
        "classIds": [str(value) for value in class_ids],
        "date": item.date_scheduled.isoformat() if item.date_scheduled else None,
        "maxScore": item.max_value,
        "description": item.description,
        "status": item.status,
        "sheetCount": int(sheet_count),
        "createdAt": item.created_at.isoformat(),
    }

def validate_program_type_for_class(
    school_class: SchoolClass,
    evaluation_type: str,
    exam_code: str | None,
    session: Session,
) -> None:
    cycle = session.get(SchoolCycle, school_class.cycle_id)
    level = session.get(SchoolLevel, school_class.school_level_id)
    cycle_code = (cycle.code if cycle else "").upper()
    level_code = (level.code if level else "").upper()
    if exam_code in {None, 'devoir_1', 'devoir_2', 'composition'}:
        if exam_code in {'devoir_1', 'devoir_2'} and evaluation_type != 'devoir':
            raise HTTPException(422, "Le type ne correspond pas à l'évaluation sélectionnée")
        if exam_code == 'composition' and evaluation_type != 'composition':
            raise HTTPException(422, "Le type ne correspond pas à l'évaluation sélectionnée")
        allowed_types = (
            {"composition"}
            if cycle_code in {"MATERNELLE", "PRIMAIRE"}
            else {"devoir", "composition"}
            if cycle_code in {"COLLEGE", "LYCEE"}
            else set()
        )
        if evaluation_type not in allowed_types:
            raise HTTPException(
                422,
                f"Le type d'évaluation ne correspond pas à la classe {school_class.name}",
            )
        return
    expected_type = "test" if exam_code in {
        "cepe_test", "bepc_test", "bac_test"
    } else "exam_blanc"
    if evaluation_type != expected_type:
        raise HTTPException(422, "Le type ne correspond pas à l'examen sélectionné")
    expected_level = {
        "cepe_test": "CM2",
        "cepe_blanc": "CM2",
        "bepc_test": "3E",
        "bepc_blanc": "3E",
        "bac_test": "TERMINALE",
        "bac_blanc": "TERMINALE",
    }[exam_code]
    expected_cycle = (
        "PRIMAIRE" if exam_code.startswith("cepe_")
        else "COLLEGE" if exam_code.startswith("bepc_")
        else "LYCEE"
    )
    if cycle_code != expected_cycle or level_code != expected_level:
        raise HTTPException(
            422,
            f"{exam_code.upper()} ne correspond pas à la classe {school_class.name}",
        )

def materialize_evaluation_program(
    program: EvaluationProgram,
    session: Session,
) -> list[Evaluation]:
    period = session.get(AcademicPeriod, program.academic_period_id)
    targets = session.scalars(select(EvaluationProgramClass).where(
        EvaluationProgramClass.program_id == program.id
    )).all()
    created: list[Evaluation] = []
    for target in targets:
        affectations = session.scalars(select(Affectation).where(
            Affectation.establishment_id == program.establishment_id,
            Affectation.class_id == target.class_id,
            Affectation.status == "active",
        )).all()
        for affectation in affectations:
            school_class = session.get(SchoolClass, affectation.class_id)
            if (not school_class or not subject_is_enabled_for_class(
                    session, school_class, affectation.subject_id)):
                continue
            existing = session.scalar(select(Evaluation).where(
                Evaluation.program_id == program.id,
                Evaluation.affectation_id == affectation.id,
            ))
            if existing:
                continue
            evaluation = Evaluation(
                establishment_id=program.establishment_id,
                class_id=affectation.class_id,
                subject_id=affectation.subject_id,
                academic_year_id=program.academic_year_id,
                academic_period_id=program.academic_period_id,
                affectation_id=affectation.id,
                program_id=program.id,
                name=program.name,
                type=program.type,
                exam_code=program.exam_code,
                period=period.code if period else "",
                date_scheduled=program.date_scheduled,
                max_value=subject_grading_scale_for_class(
                    session, school_class, affectation.subject_id
                ),
                status="draft",
                description=program.description,
                created_by=program.created_by,
            )
            session.add(evaluation)
            session.flush()
            session.add(EvaluationStatusEvent(
                establishment_id=program.establishment_id,
                evaluation_id=evaluation.id,
                actor_user_id=program.created_by,
                from_status=None,
                to_status="draft",
            ))
            created.append(evaluation)
    return created

def effective_grade_value(item: Grade) -> float | None:
    # Une absence n'est pas une note zéro. Le moteur officiel ignore les notes
    # non renseignées/absences tant qu'une règle métier explicite ne les convertit
    # pas en valeur numérique.
    return float(item.value) if item.value is not None else None


def grade_json(item: Grade, evaluation: Evaluation | None = None) -> dict[str, Any]:
    return {
        "id": str(item.id),
        "studentId": str(item.student_id),
        "subjectId": str(item.subject_id),
        "evaluationId": str(item.evaluation_id),
        "eval": evaluation.name if evaluation else "",
        "grade": effective_grade_value(item),
        "maxScore": item.max_value,
        "presence": item.presence,
        "enteredBy": str(item.entered_by) if item.entered_by else None,
        "comment": item.comment,
        "date": item.updated_at.date().isoformat(),
        "academicYearId": str(evaluation.academic_year_id) if evaluation and evaluation.academic_year_id else None,
        "semesterId": str(evaluation.academic_period_id) if evaluation and evaluation.academic_period_id else None,
        "status": item.status,
    }

def ensure_evaluation_scope(
    evaluation_id: uuid.UUID,
    current: Principal,
    session: Session,
) -> Evaluation:
    evaluation = session.get(Evaluation, evaluation_id)
    if not evaluation:
        raise HTTPException(404, "Evaluation introuvable")
    if current.role != "superadmin" and public_school_id(session, evaluation.establishment_id) != current.school_id:
        raise HTTPException(403, "Acces inter-etablissement interdit")
    school_class = session.get(SchoolClass, evaluation.class_id)
    if not school_class:
        raise HTTPException(409, "La classe de cette evaluation est introuvable")
    ensure_direction_cycle_access(current, school_class.cycle_id)
    return evaluation

def teacher_evaluation_affectation(
    current: Principal,
    class_id: uuid.UUID,
    subject_id: uuid.UUID,
    session: Session,
) -> Affectation | None:
    if current.role != "teacher":
        return None
    if not current.teacher_id:
        raise HTTPException(403, "Profil enseignant non associe")
    try:
        teacher_id = uuid.UUID(current.teacher_id)
    except ValueError as exc:
        raise HTTPException(403, "Profil enseignant invalide") from exc
    affectation = session.scalar(select(Affectation).where(
        Affectation.teacher_id == teacher_id,
        Affectation.class_id == class_id,
        Affectation.subject_id == subject_id,
        Affectation.status == "active",
    ))
    if not affectation:
        raise HTTPException(403, "Affectation enseignant insuffisante")
    school_class = session.get(SchoolClass, class_id)
    if (
        not school_class
        or not subject_is_enabled_for_class(session, school_class, subject_id)
    ):
        raise HTTPException(
            403,
            "Cette matière n'est pas active pour cette classe",
        )
    return affectation


def submission_aggregation_principal(current: Principal) -> Principal:
    """Create an internal context after the caller's class access was checked.

    Readiness must include every teacher assigned to the class. This removes the
    per-teacher filter without impersonating an administrator, whose direction
    membership is an unrelated security requirement.
    """
    return current.model_copy(update={"role": "submission_aggregation"})


@app.get("/api/v1/school/academic-periods")
def list_academic_periods(
    academic_year_id: uuid.UUID,
    current: Principal = Depends(require_module_roles("grades", "superadmin", "admin", "teacher")),
    session: Session = Depends(db),
):
    _, database_id = module_tenant_scope(current, session)
    rows = session.scalars(select(AcademicPeriod).where(
        AcademicPeriod.establishment_id == database_id,
        AcademicPeriod.academic_year_id == academic_year_id,
        AcademicPeriod.status != 'archived',
    ).order_by(AcademicPeriod.sort_order, AcademicPeriod.code)).all()
    return [academic_period_json(item, session) for item in rows]

@app.post("/api/v1/school/academic-periods", status_code=201)
def create_academic_period(
    body: AcademicPeriodInput,
    current: Principal = Depends(require_module_roles("grades", "superadmin", "admin")),
    session: Session = Depends(db),
):
    _, database_id = module_tenant_scope(current, session)
    year = session.get(AcademicYear, body.academic_year_id)
    if not year:
        raise HTTPException(422, "Annee scolaire introuvable")
    if year.establishment_id != database_id:
        raise HTTPException(403, "Annee inter-etablissement interdite")
    if body.parent_period_id:
        parent = session.get(AcademicPeriod, body.parent_period_id)
        if (not parent or parent.establishment_id != database_id
                or parent.academic_year_id != year.id
                or parent.period_type != 'trimester'):
            raise HTTPException(422, 'Le trimestre parent est invalide')
        if body.period_type == 'trimester':
            raise HTTPException(422, 'Un trimestre ne peut pas avoir de trimestre parent')
    item = AcademicPeriod(
        establishment_id=database_id,
        academic_year_id=year.id,
        parent_period_id=body.parent_period_id,
        code=body.code or f"PER-{uuid.uuid4().hex[:12].upper()}",
        name=body.name,
        period_type=body.period_type,
        sort_order=body.sort_order,
        start_date=body.start_date,
        end_date=body.end_date,
        status="active",
    )
    session.add(item)
    try:
        session.commit()
    except IntegrityError as exc:
        session.rollback()
        raise HTTPException(409, "Cette periode existe deja") from exc
    session.refresh(item)
    return academic_period_json(item, session)

@app.get("/api/v1/school/evaluation-programs")
def list_evaluation_programs(
    academic_year_id: uuid.UUID | None = None,
    period_id: uuid.UUID | None = None,
    current: Principal = Depends(require_module_roles("grades", "superadmin", "admin")),
    session: Session = Depends(db),
):
    _, database_id = module_tenant_scope(current, session)
    statement = select(EvaluationProgram).where(
        EvaluationProgram.establishment_id == database_id,
        EvaluationProgram.status == "active",
    )
    allowed = direction_cycle_scope(current)
    if allowed is not None:
        statement = statement.join(
            EvaluationProgramClass,
            EvaluationProgramClass.program_id == EvaluationProgram.id,
        ).join(
            SchoolClass, SchoolClass.id == EvaluationProgramClass.class_id
        ).where(SchoolClass.cycle_id.in_(allowed)).distinct()
    if academic_year_id:
        statement = statement.where(EvaluationProgram.academic_year_id == academic_year_id)
    if period_id:
        statement = statement.where(EvaluationProgram.academic_period_id == period_id)
    return [
        evaluation_program_json(item, session)
        for item in session.scalars(statement.order_by(EvaluationProgram.created_at)).all()
    ]

@app.post("/api/v1/school/evaluation-programs", status_code=201)
def create_evaluation_program(
    body: EvaluationProgramInput,
    current: Principal = Depends(require_module_roles("grades", "superadmin", "admin")),
    session: Session = Depends(db),
):
    _, database_id = module_tenant_scope(current, session)
    period = session.get(AcademicPeriod, body.academic_period_id)
    if not period:
        raise HTTPException(422, "Période pédagogique introuvable")
    if period.establishment_id != database_id:
        raise HTTPException(403, "Période inter-établissement interdite")
    classes = [session.get(SchoolClass, class_id) for class_id in body.class_ids]
    if any(item is None for item in classes):
        raise HTTPException(422, "Une classe sélectionnée est introuvable")
    selected_classes = [item for item in classes if item is not None]
    for school_class in selected_classes:
        if school_class.establishment_id != database_id:
            raise HTTPException(403, "Classe inter-établissement interdite")
        ensure_direction_cycle_access(current, school_class.cycle_id)
        if school_class.academic_year_id != period.academic_year_id:
            raise HTTPException(422, "Toutes les classes doivent appartenir à l'année de la période")
        validate_program_type_for_class(
            school_class, body.type, body.exam_code, session
        )
    program_identity = body.exam_code or f"{body.type}:{body.title.lower()}"
    for class_id in sorted(body.class_ids, key=str):
        lock_key = (
            f"evaluation-program:{database_id}:{period.id}:"
            f"{class_id}:{program_identity}"
        )
        session.execute(
            text("SELECT pg_advisory_xact_lock(hashtextextended(:key, 0))"),
            {"key": lock_key},
        )
    same_event = (
        (EvaluationProgram.exam_code == body.exam_code)
        if body.exam_code
        else (
            (EvaluationProgram.exam_code.is_(None))
            & (func.lower(EvaluationProgram.name) == body.title.lower())
        )
    )
    duplicate = session.scalar(select(EvaluationProgramClass.id).join(
        EvaluationProgram,
        EvaluationProgram.id == EvaluationProgramClass.program_id,
    ).where(
        EvaluationProgram.establishment_id == database_id,
        EvaluationProgram.academic_period_id == period.id,
        EvaluationProgram.status == "active",
        same_event,
        EvaluationProgramClass.class_id.in_(body.class_ids),
    ).limit(1))
    if duplicate:
        raise HTTPException(
            409,
            "Cette évaluation est déjà programmée pour cette période et cette classe.",
        )
    if body.exam_code == "bac_blanc" and session.scalar(
        select(EvaluationProgramClass.id).join(
            EvaluationProgram,
            EvaluationProgram.id == EvaluationProgramClass.program_id,
        ).where(
            EvaluationProgram.establishment_id == database_id,
            EvaluationProgram.academic_year_id == period.academic_year_id,
            EvaluationProgram.exam_code == "bac_blanc",
            EvaluationProgram.status == "active",
            EvaluationProgramClass.class_id.in_(body.class_ids),
        ).limit(1)
    ):
        raise HTTPException(409, "Un BAC blanc existe déjà pour une classe sélectionnée")
    program = EvaluationProgram(
        establishment_id=database_id,
        academic_year_id=period.academic_year_id,
        academic_period_id=period.id,
        name=body.title,
        type=body.type,
        exam_code=body.exam_code,
        date_scheduled=None,
        max_value=20,
        description=body.description,
        status="active",
        created_by=uuid.UUID(current.id),
    )
    try:
        session.add(program)
        session.flush()
        for school_class in selected_classes:
            session.add(EvaluationProgramClass(
                establishment_id=database_id,
                program_id=program.id,
                class_id=school_class.id,
            ))
        session.flush()
        sheets = materialize_evaluation_program(program, session)
        school_public_id = public_school_id(session, database_id)
        teacher_ids = {
            affectation.teacher_id
            for sheet in sheets
            if sheet.affectation_id
            and (affectation := session.get(Affectation, sheet.affectation_id))
        }
        now = datetime.now(timezone.utc)
        for teacher_id in teacher_ids:
            notification_id = f"grade-entry-open-{program.id}-{teacher_id}"
            session.add(Resource(
                id=notification_id,
                kind="notifications",
                school_id=school_public_id,
                establishment_id=database_id,
                academic_year_id=period.academic_year_id,
                payload={
                    "id": notification_id,
                    "type": "grade_entry_open",
                    "title": "Saisie des notes ouverte",
                    "message": f"{body.title} — {period.name}. Vos relevés sont disponibles dans Notes.",
                    "teacherId": str(teacher_id),
                    "academicYearId": str(period.academic_year_id),
                    "periodId": str(period.id),
                    "read": False,
                    "time": now.isoformat(),
                    "schoolId": school_public_id,
                },
            ))
        session.commit()
    except IntegrityError as exc:
        session.rollback()
        raise HTTPException(
            409,
            "Cette évaluation ne peut pas être programmée deux fois pour le même contexte.",
        ) from exc
    session.refresh(program)
    return {
        "program": evaluation_program_json(program, session),
        "evaluations": [evaluation_json(item, session) for item in sheets],
    }

@app.get("/api/v1/school/evaluations")
def list_evaluations(
    academic_year_id: uuid.UUID | None = None,
    class_id: uuid.UUID | None = None,
    subject_id: uuid.UUID | None = None,
    period_id: uuid.UUID | None = None,
    current: Principal = Depends(require_module_roles("grades", "superadmin", "admin", "teacher")),
    session: Session = Depends(db),
):
    _, database_id = module_tenant_scope(current, session)
    statement = select(Evaluation).where(Evaluation.establishment_id == database_id)
    allowed = direction_cycle_scope(current)
    if allowed is not None:
        statement = statement.where(Evaluation.class_id.in_(
            select(SchoolClass.id).where(SchoolClass.cycle_id.in_(allowed))
        ))
    if academic_year_id:
        statement = statement.where(Evaluation.academic_year_id == academic_year_id)
    if class_id:
        ensure_class_module_access(
            current, session.get(SchoolClass, class_id), database_id, session
        )
        statement = statement.where(Evaluation.class_id == class_id)
    if subject_id:
        statement = statement.where(Evaluation.subject_id == subject_id)
    if period_id:
        statement = statement.where(Evaluation.academic_period_id == period_id)
    if current.role == "teacher":
        if not current.teacher_id:
            return []
        statement = statement.where(Evaluation.affectation_id.in_(
            select(Affectation.id).where(
                Affectation.teacher_id == uuid.UUID(current.teacher_id),
                Affectation.status == "active",
            )
        ))
    rows = session.scalars(statement.order_by(Evaluation.created_at)).all()
    if current.role == "teacher":
        rows = [
            item for item in rows
            if (
                (school_class := session.get(SchoolClass, item.class_id))
                and subject_is_enabled_for_class(
                    session, school_class, item.subject_id
                )
            )
        ]
    return [evaluation_json(item, session) for item in rows]

@app.post("/api/v1/school/evaluations", status_code=201)
def create_evaluation(
    body: EvaluationInput,
    current: Principal = Depends(require_module_roles("grades", "superadmin", "admin")),
    session: Session = Depends(db),
):
    _, database_id = module_tenant_scope(current, session)
    school_class = session.get(SchoolClass, body.class_id)
    subject = session.get(Subject, body.subject_id)
    period = session.get(AcademicPeriod, body.academic_period_id)
    if not school_class or not subject or not period:
        raise HTTPException(422, "Classe, matiere ou periode introuvable")
    if any(item.establishment_id != database_id for item in (school_class, subject, period)):
        raise HTTPException(403, "Reference inter-etablissement interdite")
    ensure_class_module_access(current, school_class, database_id, session)
    if period.academic_year_id != school_class.academic_year_id:
        raise HTTPException(422, "La periode et la classe ne sont pas dans la meme annee")
    cycle = session.get(SchoolCycle, school_class.cycle_id)
    level = session.get(SchoolLevel, school_class.school_level_id)
    cycle_code = (cycle.code if cycle else "").upper()
    if body.exam_code is None:
        allowed_types = (
            {"composition"}
            if cycle_code in {"MATERNELLE", "PRIMAIRE"}
            else {"devoir", "composition"}
            if cycle_code in {"COLLEGE", "LYCEE"}
            else set()
        )
        if body.type not in allowed_types:
            raise HTTPException(
                422,
                "Ce type d evaluation ne correspond pas au cycle de la classe",
            )
    duplicate = session.scalar(select(Evaluation.id).where(
        Evaluation.establishment_id == database_id,
        Evaluation.class_id == school_class.id,
        Evaluation.subject_id == subject.id,
        Evaluation.academic_period_id == period.id,
        func.lower(Evaluation.name) == body.title.strip().lower(),
        Evaluation.status != "rejected",
    ).limit(1))
    if duplicate:
        raise HTTPException(
            409,
            "Un element pedagogique portant ce libelle existe deja pour cette matiere",
        )
    if body.exam_code:
        expected_type = 'test' if body.exam_code in {
            'cepe_test', 'bepc_test', 'bac_test'
        } else 'exam_blanc'
        if body.type != expected_type:
            raise HTTPException(422, 'Le type ne correspond pas a l examen officiel selectionne')
        expected_level = {
            'cepe_test': 'CM2',
            'cepe_blanc': 'CM2',
            'bepc_test': '3E',
            'bepc_blanc': '3E',
            'bac_test': 'TERMINALE',
            'bac_blanc': 'TERMINALE',
        }[body.exam_code]
        expected_cycle = (
            'PRIMAIRE' if body.exam_code.startswith('cepe_')
            else 'COLLEGE' if body.exam_code.startswith('bepc_')
            else 'LYCEE'
        )
        if not cycle or cycle.code.upper() != expected_cycle:
            raise HTTPException(
                422,
                'Cet examen officiel ne correspond pas au cycle de la classe',
            )
        if not level or level.code.upper() != expected_level:
            raise HTTPException(422, 'Cet examen officiel ne correspond pas au niveau de la classe')
        if body.exam_code == 'bac_blanc' and session.scalar(select(Evaluation.id).where(
            Evaluation.establishment_id == database_id,
            Evaluation.academic_year_id == school_class.academic_year_id,
            Evaluation.class_id == school_class.id,
            Evaluation.exam_code == 'bac_blanc',
            Evaluation.status != 'rejected',
        ).limit(1)):
            raise HTTPException(409, 'Un BAC blanc existe deja pour cette classe et cette annee')
    teacher_affectation = teacher_evaluation_affectation(
        current, school_class.id, subject.id, session
    )
    affectation = teacher_affectation or session.scalar(select(Affectation).where(
        Affectation.establishment_id == database_id,
        Affectation.class_id == school_class.id,
        Affectation.subject_id == subject.id,
        Affectation.status == "active",
    ))
    if not affectation:
        raise HTTPException(
            409,
            "Une affectation active enseignant-matiere-classe est requise",
        )
    evaluation = Evaluation(
        establishment_id=database_id,
        class_id=school_class.id,
        subject_id=subject.id,
        academic_year_id=school_class.academic_year_id,
        academic_period_id=period.id,
        affectation_id=affectation.id if affectation else None,
        name=body.title.strip(),
        type=body.type,
        exam_code=body.exam_code,
        period=period.code,
        date_scheduled=body.date_scheduled,
        max_value=subject_grading_scale_for_class(
            session, school_class, subject.id
        ),
        status="draft",
        description=body.description,
        created_by=uuid.UUID(current.id),
    )
    session.add(evaluation)
    session.flush()
    session.add(EvaluationStatusEvent(
        establishment_id=database_id,
        evaluation_id=evaluation.id,
        actor_user_id=uuid.UUID(current.id),
        from_status=None,
        to_status="draft",
    ))
    session.commit()
    session.refresh(evaluation)
    return evaluation_json(evaluation, session)

@app.put("/api/v1/school/evaluations/{evaluation_id}/status")
def update_evaluation_status(
    evaluation_id: uuid.UUID,
    body: EvaluationStatusInput,
    current: Principal = Depends(require_module_roles("grades", "superadmin", "admin", "teacher")),
    session: Session = Depends(db),
):
    evaluation = ensure_evaluation_scope(evaluation_id, current, session)
    if current.role == "teacher":
        teacher_evaluation_affectation(
            current, evaluation.class_id, evaluation.subject_id, session
        )
    allowed = {
        "draft": {"submitted"},
        "submitted": {"validated", "rejected"},
        "rejected": {"draft", "submitted"},
        "validated": {"locked"},
        "locked": set(),
    }
    if body.status not in allowed.get(evaluation.status, set()):
        raise HTTPException(409, "Transition de statut invalide")
    if body.status == "submitted" and current.role != "teacher":
        raise HTTPException(403, "La soumission est reservee a l'enseignant")
    if body.status in {"validated", "rejected", "locked"} and current.role == "teacher":
        raise HTTPException(403, "Validation reservee a l'administration")
    if body.status == "rejected" and not body.reason:
        raise HTTPException(422, "Le motif de rejet est obligatoire")
    grade_rows = session.scalars(select(Grade).where(
        Grade.establishment_id == evaluation.establishment_id,
        Grade.evaluation_id == evaluation.id,
    )).all()
    if body.status == "submitted":
        expected_students = session.scalar(select(func.count()).select_from(
            StudentAcademicRegistration
        ).where(
            StudentAcademicRegistration.establishment_id == evaluation.establishment_id,
            StudentAcademicRegistration.class_id == evaluation.class_id,
            StudentAcademicRegistration.academic_year_id == evaluation.academic_year_id,
            StudentAcademicRegistration.status.in_(("pending", "validated", "active")),
        )) or 0
        if (expected_students == 0
                or len(grade_rows) != expected_students
                or any(item.presence == "not_recorded" for item in grade_rows)):
            raise HTTPException(
                409,
                "Le releve est incomplet pour les eleves inscrits dans cette classe",
            )
    old_status = evaluation.status
    now = datetime.now(timezone.utc)
    evaluation.status = body.status
    evaluation.updated_at = now
    if body.status == "submitted":
        evaluation.submitted_at = now
    elif body.status == "validated":
        evaluation.validated_at = now
        evaluation.validated_by = uuid.UUID(current.id)
    elif body.status == "rejected":
        evaluation.rejected_at = now
        evaluation.rejected_by = uuid.UUID(current.id)
        evaluation.rejection_reason = body.reason
    for grade in grade_rows:
        grade.status = body.status
        grade.updated_at = now
    session.add(EvaluationStatusEvent(
        establishment_id=evaluation.establishment_id,
        evaluation_id=evaluation.id,
        actor_user_id=uuid.UUID(current.id),
        from_status=old_status,
        to_status=body.status,
        reason=body.reason,
    ))
    if body.status == "submitted":
        affectation = session.get(Affectation, evaluation.affectation_id)
        teacher = session.get(Teacher, affectation.teacher_id) if affectation else None
        subject = session.get(Subject, evaluation.subject_id)
        school_class = session.get(SchoolClass, evaluation.class_id)
        teacher_name = (
            f"{teacher.last_name} {teacher.first_name}" if teacher else "Un enseignant"
        )
        subject_name = subject.name if subject else "une matiere"
        class_name = school_class.name if school_class else "une classe"
        notification_id = f"evaluation-submitted-{evaluation.id}-{uuid.uuid4().hex[:8]}"
        public_id = public_school_id(session, evaluation.establishment_id)
        session.add(Resource(
            id=notification_id,
            kind="notifications",
            school_id=public_id,
            establishment_id=evaluation.establishment_id,
            payload={
                "id": notification_id,
                "title": "Notes soumises",
                "message": (
                    f"{teacher_name} a soumis les notes de {subject_name} "
                    f"pour la classe {class_name}."
                ),
                "type": "evaluation_submitted",
                "icon": "assignment_turned_in",
                "schoolId": public_id,
                "teacherId": str(teacher.id) if teacher else None,
                "evaluationId": str(evaluation.id),
                "read": False,
                "time": now.isoformat(),
            },
        ))
        readiness_current = submission_aggregation_principal(current)
        readiness = school_submission_status(
            evaluation.class_id,
            evaluation.academic_period_id,
            readiness_current,
            session,
        )
        if readiness["readyForCalculation"]:
            period = session.get(AcademicPeriod, evaluation.academic_period_id)
            ready_id = (
                f"results-ready-{evaluation.class_id}-{evaluation.academic_period_id}"
            )
            ready_payload = {
                "id": ready_id,
                "title": "Tous les releves sont arrives",
                "message": (
                    f"{class_name} - {period.name if period else 'Periode'} : "
                    f"{len(readiness['submissions'])}/{len(readiness['submissions'])} "
                    "releves recus. Les resultats peuvent etre calcules."
                ),
                "type": "results_ready",
                "icon": "calculate",
                "schoolId": public_id,
                "classId": str(evaluation.class_id),
                "class": class_name,
                "academicYearId": str(evaluation.academic_year_id),
                "periodId": str(evaluation.academic_period_id),
                "period": period.name if period else None,
                "expected": len(readiness["submissions"]),
                "received": len(readiness["submissions"]),
                "missing": 0,
                "readyForCalculation": True,
                "read": False,
                "time": now.isoformat(),
            }
            ready_resource = session.get(
                Resource, {"kind": "notifications", "id": ready_id}
            )
            if ready_resource:
                ready_resource.payload = ready_payload
                ready_resource.updated_at = now
            else:
                session.add(Resource(
                    id=ready_id,
                    kind="notifications",
                    school_id=public_id,
                    establishment_id=evaluation.establishment_id,
                    payload=ready_payload,
                ))
    session.commit()
    return evaluation_json(evaluation, session)

@app.get("/api/v1/school/evaluations/{evaluation_id}/grades")
def list_evaluation_grades(
    evaluation_id: uuid.UUID,
    current: Principal = Depends(require_module_roles("grades", "superadmin", "admin", "teacher")),
    session: Session = Depends(db),
):
    evaluation = ensure_evaluation_scope(evaluation_id, current, session)
    if current.role == "teacher":
        teacher_evaluation_affectation(
            current, evaluation.class_id, evaluation.subject_id, session
        )
    rows = session.scalars(select(Grade).where(
        Grade.evaluation_id == evaluation.id,
        Grade.establishment_id == evaluation.establishment_id,
    ).order_by(Grade.student_id)).all()
    return [grade_json(item, evaluation) for item in rows]

@app.get("/api/v1/school/grades")
def list_school_grades(
    academic_year_id: uuid.UUID | None = None,
    class_id: uuid.UUID | None = None,
    current: Principal = Depends(require_module_roles("grades", "superadmin", "admin", "teacher")),
    session: Session = Depends(db),
):
    """Return a scoped grade batch so Flutter does not issue one request per sheet."""
    _, database_id = module_tenant_scope(current, session)
    statement = (
        select(Grade, Evaluation)
        .join(Evaluation, Evaluation.id == Grade.evaluation_id)
        .where(
            Grade.establishment_id == database_id,
            Evaluation.establishment_id == database_id,
        )
    )
    allowed = direction_cycle_scope(current)
    if allowed is not None:
        statement = statement.where(Evaluation.class_id.in_(
            select(SchoolClass.id).where(SchoolClass.cycle_id.in_(allowed))
        ))
    if academic_year_id:
        statement = statement.where(Evaluation.academic_year_id == academic_year_id)
    if class_id:
        ensure_class_module_access(
            current, session.get(SchoolClass, class_id), database_id, session
        )
        statement = statement.where(Evaluation.class_id == class_id)
    if current.role == "teacher":
        if not current.teacher_id:
            return []
        statement = statement.where(Evaluation.affectation_id.in_(
            select(Affectation.id).where(
                Affectation.teacher_id == uuid.UUID(current.teacher_id),
                Affectation.status == "active",
            )
        ))
    rows = session.execute(statement.order_by(Grade.evaluation_id, Grade.student_id)).all()
    return [grade_json(grade, evaluation) for grade, evaluation in rows]

@app.put("/api/v1/school/evaluations/{evaluation_id}/grades")
def save_evaluation_grades(
    evaluation_id: uuid.UUID,
    body: GradeBatchInput,
    current: Principal = Depends(require_module_roles("grades", "superadmin", "admin", "teacher")),
    session: Session = Depends(db),
):
    evaluation = ensure_evaluation_scope(evaluation_id, current, session)
    administrative_correction = (
        current.role in {'superadmin', 'admin'}
        and evaluation.status in {'submitted', 'validated'}
    )
    if evaluation.status not in {"draft", "rejected"} and not administrative_correction:
        raise HTTPException(409, "Les notes ne sont plus modifiables")
    if administrative_correction and not body.correction_reason:
        raise HTTPException(422, 'Le motif de la correction administrative est obligatoire')
    teacher_affectation = teacher_evaluation_affectation(
        current, evaluation.class_id, evaluation.subject_id, session
    )
    seen: set[uuid.UUID] = set()
    rows: list[Grade] = []
    for entry in body.entries:
        if entry.student_id in seen:
            raise HTTPException(422, "Un eleve apparait plusieurs fois")
        seen.add(entry.student_id)
        student = session.get(Student, entry.student_id)
        if not student:
            raise HTTPException(422, "Eleve introuvable")
        if student.establishment_id != evaluation.establishment_id:
            raise HTTPException(403, "Eleve inter-etablissement interdit")
        registration = session.scalar(select(StudentAcademicRegistration).where(
            StudentAcademicRegistration.establishment_id == evaluation.establishment_id,
            StudentAcademicRegistration.student_id == student.id,
            StudentAcademicRegistration.class_id == evaluation.class_id,
            StudentAcademicRegistration.academic_year_id == evaluation.academic_year_id,
            StudentAcademicRegistration.status.in_(("pending", "validated", "active")),
        ))
        if not registration:
            raise HTTPException(422, "Eleve non inscrit dans cette classe et cette annee")
        if entry.value is not None and entry.value > evaluation.max_value:
            raise HTTPException(
                422,
                f"La note doit être comprise entre 0 et {evaluation.max_value:g}",
            )
        grade = session.scalar(select(Grade).where(
            Grade.student_id == student.id,
            Grade.evaluation_id == evaluation.id,
        ))
        if not grade:
            grade = Grade(
                establishment_id=evaluation.establishment_id,
                student_id=student.id,
                evaluation_id=evaluation.id,
                class_id=evaluation.class_id,
                subject_id=evaluation.subject_id,
                teacher_id=teacher_affectation.teacher_id if teacher_affectation else None,
                affectation_id=evaluation.affectation_id,
                max_value=evaluation.max_value,
            )
            session.add(grade)
        grade.value = entry.value
        grade.presence = entry.presence
        grade.comment = entry.comment
        grade.entered_by = uuid.UUID(current.id)
        grade.status = evaluation.status if administrative_correction else "draft"
        grade.updated_at = datetime.now(timezone.utc)
        rows.append(grade)
    if administrative_correction:
        session.add(EvaluationStatusEvent(
            establishment_id=evaluation.establishment_id,
            evaluation_id=evaluation.id,
            actor_user_id=uuid.UUID(current.id),
            from_status=evaluation.status,
            to_status=evaluation.status,
            reason=f'Correction administrative : {body.correction_reason.strip()}',
        ))
        ready_id = (
            f"results-ready-{evaluation.class_id}-{evaluation.academic_period_id}"
        )
        ready_resource = session.get(
            Resource, {"kind": "notifications", "id": ready_id}
        )
        school_class = session.get(SchoolClass, evaluation.class_id)
        period = session.get(AcademicPeriod, evaluation.academic_period_id)
        now = datetime.now(timezone.utc)
        ready_payload = {
            "id": ready_id,
            "title": "Recalcul des resultats necessaire",
            "message": (
                f"{school_class.name if school_class else 'Classe'} - "
                f"{period.name if period else 'Periode'} : une note a ete "
                "corrigee. Le classement doit etre recalcule."
            ),
            "type": "results_ready",
            "icon": "calculate",
            "schoolId": public_school_id(session, evaluation.establishment_id),
            "classId": str(evaluation.class_id),
            "class": school_class.name if school_class else None,
            "academicYearId": str(evaluation.academic_year_id),
            "periodId": str(evaluation.academic_period_id),
            "period": period.name if period else None,
            "readyForCalculation": True,
            "requiresRecalculation": True,
            "read": False,
            "time": now.isoformat(),
        }
        if ready_resource:
            ready_resource.payload = ready_payload
            ready_resource.updated_at = now
        else:
            session.add(Resource(
                id=ready_id,
                kind="notifications",
                school_id=ready_payload["schoolId"],
                establishment_id=evaluation.establishment_id,
                payload=ready_payload,
            ))
    session.commit()
    return [grade_json(item, evaluation) for item in rows]

@app.get("/api/v1/school/results")
def school_results_route(
    class_id: uuid.UUID,
    period_id: uuid.UUID,
    current: Principal = Depends(require_module_roles(
        bytes((103, 114, 97, 100, 101, 115)).decode(),
        bytes((115, 117, 112, 101, 114, 97, 100, 109, 105, 110)).decode(),
        bytes((97, 100, 109, 105, 110)).decode(),
        bytes((116, 101, 97, 99, 104, 101, 114)).decode(),
    )),
    session: Session = Depends(db),
    event_code: str | None = None,
):
    if event_code:
        return school_event_results(
            class_id, period_id, event_code, current, session
        )
    return school_results(class_id, period_id, current, session)

@app.get('/api/v1/school/submissions')
def school_submission_status(
    class_id: uuid.UUID,
    period_id: uuid.UUID,
    current: Principal = Depends(require_module_roles(
        'grades', 'superadmin', 'admin', 'teacher')),
    session: Session = Depends(db),
    event_code: str | None = None,
):
    if event_code:
        return school_event_submission_status(
            class_id, period_id, event_code, current, session
        )
    school_class = session.get(SchoolClass, class_id)
    if not school_class:
        raise HTTPException(404, 'Classe introuvable')
    if current.role == 'superadmin':
        database_id = school_class.establishment_id
    else:
        _, database_id = module_tenant_scope(current, session)
    school_class = ensure_class_module_access(
        current, school_class, database_id, session
    )
    period = session.get(AcademicPeriod, period_id)
    if not period:
        raise HTTPException(404, 'Periode introuvable')
    if (period.establishment_id != database_id
            or period.academic_year_id != school_class.academic_year_id):
        raise HTTPException(403, 'Periode inter-etablissement interdite')
    period_ids = [period.id]
    if period.period_type == 'trimester':
        period_ids.extend(session.scalars(select(AcademicPeriod.id).where(
            AcademicPeriod.establishment_id == database_id,
            AcademicPeriod.academic_year_id == period.academic_year_id,
            AcademicPeriod.parent_period_id == period.id,
            AcademicPeriod.status == 'active',
        )).all())
    affectation_statement = select(Affectation).where(
        Affectation.establishment_id == database_id,
        Affectation.class_id == school_class.id,
        Affectation.status == 'active',
    )
    if current.role == 'teacher':
        affectation_statement = affectation_statement.where(
            Affectation.teacher_id == uuid.UUID(current.teacher_id)
        )
    affectations = session.scalars(affectation_statement).all()
    rows = []
    for affectation in affectations:
        if not subject_is_enabled_for_class(
                session, school_class, affectation.subject_id):
            continue
        evaluations = session.scalars(select(Evaluation).where(
            Evaluation.establishment_id == database_id,
            Evaluation.class_id == school_class.id,
            Evaluation.subject_id == affectation.subject_id,
            Evaluation.academic_period_id.in_(period_ids),
        )).all()
        submitted = [item for item in evaluations
                     if item.status in {'submitted', 'validated', 'locked'}]
        calculation_rows, missing = evaluation_policy_for_class(
            session, school_class, submitted, period
        )
        teacher = session.get(Teacher, affectation.teacher_id)
        subject = session.get(Subject, affectation.subject_id)
        # Tout élément préparé par l'ADMIN fait partie du relevé attendu,
        # même lorsqu'un examen complémentaire ne contribue pas à la moyenne.
        ready = (
            not missing
            and bool(calculation_rows)
            and bool(evaluations)
            and len(submitted) == len(evaluations)
        )
        submitted_at = max(
            (item.submitted_at for item in submitted if item.submitted_at),
            default=None,
        )
        rows.append({
            'affectationId': str(affectation.id),
            'teacherId': str(affectation.teacher_id),
            'teacher': f'{teacher.last_name} {teacher.first_name}' if teacher else None,
            'subjectId': str(affectation.subject_id),
            'subject': subject.name if subject else None,
            'classId': str(school_class.id),
            'class': school_class.name,
            'status': 'submitted' if ready else ('draft' if evaluations else 'pending'),
            'evaluationCount': len(evaluations),
            'submittedCount': len(submitted),
            'submittedAt': submitted_at.isoformat() if submitted_at else None,
            'missing': missing,
            'elements': [
                {
                    'id': str(item.id),
                    'name': item.name,
                    'type': item.type,
                    'examCode': item.exam_code,
                    'status': item.status,
                    'submittedAt': item.submitted_at.isoformat()
                    if item.submitted_at else None,
                }
                for item in evaluations
            ],
        })
    received_count = sum(row['status'] == 'submitted' for row in rows)
    teacher_groups: dict[str, dict[str, Any]] = {}
    for row in rows:
        teacher_id = row['teacherId']
        group = teacher_groups.setdefault(teacher_id, {
            'teacherId': teacher_id,
            'teacher': row['teacher'],
            'classId': row['classId'],
            'class': row['class'],
            'subjects': [],
            'submittedElements': [],
            'status': 'submitted',
            'submittedAt': None,
        })
        if row['subject'] and row['subject'] not in group['subjects']:
            group['subjects'].append(row['subject'])
        if row['status'] != 'submitted':
            group['status'] = 'pending'
        for element in row['elements']:
            if element['status'] not in {'submitted', 'validated', 'locked'}:
                continue
            label = element['name']
            if label not in group['submittedElements']:
                group['submittedElements'].append(label)
            submitted_at = element.get('submittedAt')
            if submitted_at and (
                    group['submittedAt'] is None
                    or submitted_at > group['submittedAt']):
                group['submittedAt'] = submitted_at
    return {
        'classId': str(school_class.id),
        'periodId': str(period.id),
        'expectedCount': len(rows),
        'receivedCount': received_count,
        'missingCount': len(rows) - received_count,
        'readyForCalculation': bool(rows) and all(
            row['status'] == 'submitted' for row in rows
        ),
        'submissions': rows,
        'teacherSubmissions': list(teacher_groups.values()),
    }


KNOWN_EVALUATION_EVENTS = {
    'devoir_1': 'Devoir 1',
    'devoir_2': 'Devoir 2',
    'composition': 'Composition',
    'cepe_test': 'CEPE test',
    'cepe_blanc': 'CEPE blanc',
    'bepc_test': 'BEPC test',
    'bepc_blanc': 'BEPC blanc',
    'bac_test': 'BAC test',
    'bac_blanc': 'BAC blanc',
}


def normalized_evaluation_event(item: Evaluation) -> str | None:
    if item.exam_code in KNOWN_EVALUATION_EVENTS:
        return item.exam_code
    normalized_name = re.sub(r'[^A-Z0-9]+', ' ', item.name.upper()).strip()
    if item.type == 'devoir':
        if re.search(r'\b2\b', normalized_name):
            return 'devoir_2'
        return 'devoir_1'
    if item.type == 'composition':
        return 'composition'
    return item.exam_code if item.exam_code in KNOWN_EVALUATION_EVENTS else None


def school_subject_average(
    cycle_code: str,
    values_by_event: list[tuple[str | None, float]],
) -> tuple[float, float | None, float | None]:
    """Return (subject average, MC, composition) on the cycle's general scale.

    Collège/Lycée use the official rule: MC is the mean of ordinary devoirs
    and the subject average is (MC + composition) / 2. Other cycles keep the
    average of their contributing evaluations (currently compositions by
    default).
    """
    if not values_by_event:
        raise ValueError('Aucune note contributive')
    normalized_cycle = cycle_code.upper()
    if normalized_cycle in {'COLLEGE', 'LYCEE'}:
        devoirs = [
            value for event, value in values_by_event
            if event in {'devoir_1', 'devoir_2'}
        ]
        compositions = [
            value for event, value in values_by_event
            if event == 'composition'
        ]
        mc = sum(devoirs) / len(devoirs) if devoirs else None
        composition = (
            sum(compositions) / len(compositions) if compositions else None
        )
        if mc is not None and composition is not None:
            return round((mc + composition) / 2, 2), round(mc, 2), round(composition, 2)
    average = round(
        sum(value for _, value in values_by_event) / len(values_by_event), 2
    )
    return average, None, None


def validate_evaluation_event_code(event_code: str) -> str:
    normalized = event_code.strip().lower()
    if normalized not in KNOWN_EVALUATION_EVENTS:
        raise HTTPException(422, "Cette évaluation n'est pas reconnue")
    return normalized


def event_period_ids(
    session: Session, database_id: uuid.UUID, period: AcademicPeriod
) -> list[uuid.UUID]:
    ids = [period.id]
    if period.period_type == 'trimester':
        ids.extend(session.scalars(select(AcademicPeriod.id).where(
            AcademicPeriod.establishment_id == database_id,
            AcademicPeriod.academic_year_id == period.academic_year_id,
            AcademicPeriod.parent_period_id == period.id,
            AcademicPeriod.status == 'active',
        )).all())
    return ids


def school_event_submission_status(
    class_id: uuid.UUID,
    period_id: uuid.UUID,
    event_code: str,
    current: Principal,
    session: Session,
) -> dict[str, Any]:
    code = validate_evaluation_event_code(event_code)
    school_class = session.get(SchoolClass, class_id)
    period = session.get(AcademicPeriod, period_id)
    if not school_class or not period:
        raise HTTPException(404, 'Classe ou période introuvable')
    if current.role == 'superadmin':
        database_id = school_class.establishment_id
    else:
        _, database_id = module_tenant_scope(current, session)
    school_class = ensure_class_module_access(
        current, school_class, database_id, session
    )
    if (period.establishment_id != database_id
            or period.academic_year_id != school_class.academic_year_id):
        raise HTTPException(403, 'Période non accessible')
    statement = select(Affectation).where(
        Affectation.establishment_id == database_id,
        Affectation.class_id == school_class.id,
        Affectation.status == 'active',
    )
    if current.role == 'teacher':
        statement = statement.where(
            Affectation.teacher_id == uuid.UUID(current.teacher_id)
        )
    rows = []
    for affectation in session.scalars(statement).all():
        if not subject_is_enabled_for_class(
                session, school_class, affectation.subject_id):
            continue
        evaluations = [
            item for item in session.scalars(select(Evaluation).where(
                Evaluation.establishment_id == database_id,
                Evaluation.class_id == school_class.id,
                Evaluation.subject_id == affectation.subject_id,
                Evaluation.academic_period_id.in_(
                    event_period_ids(session, database_id, period)
                ),
            )).all()
            if normalized_evaluation_event(item) == code
        ]
        submitted = [item for item in evaluations
                     if item.status in {'submitted', 'validated', 'locked'}]
        teacher = session.get(Teacher, affectation.teacher_id)
        subject = session.get(Subject, affectation.subject_id)
        ready = bool(evaluations) and len(submitted) == len(evaluations)
        submitted_at = max(
            (item.submitted_at for item in submitted if item.submitted_at),
            default=None,
        )
        rows.append({
            'affectationId': str(affectation.id),
            'teacherId': str(affectation.teacher_id),
            'teacher': f'{teacher.last_name} {teacher.first_name}' if teacher else None,
            'subjectId': str(affectation.subject_id),
            'subject': subject.name if subject else None,
            'classId': str(school_class.id),
            'class': school_class.name,
            'status': 'submitted' if ready else 'pending',
            'evaluationCount': len(evaluations),
            'submittedCount': len(submitted),
            'submittedAt': submitted_at.isoformat() if submitted_at else None,
            'elements': [{
                'id': str(item.id),
                'name': item.name,
                'examCode': normalized_evaluation_event(item),
                'status': item.status,
                'submittedAt': item.submitted_at.isoformat()
                if item.submitted_at else None,
            } for item in evaluations],
        })
    received = sum(row['status'] == 'submitted' for row in rows)
    return {
        'classId': str(school_class.id),
        'periodId': str(period.id),
        'eventCode': code,
        'event': KNOWN_EVALUATION_EVENTS[code],
        'expectedCount': len(rows),
        'receivedCount': received,
        'missingCount': len(rows) - received,
        'readyForCalculation': bool(rows) and received == len(rows),
        'submissions': rows,
    }


def subject_level_coefficient(
    session: Session,
    establishment_id: uuid.UUID,
    school_level_id: uuid.UUID,
    subject_id: uuid.UUID,
) -> float:
    setting = session.scalar(select(SubjectLevelSetting).where(
        SubjectLevelSetting.establishment_id == establishment_id,
        SubjectLevelSetting.school_level_id == school_level_id,
        SubjectLevelSetting.subject_id == subject_id,
        SubjectLevelSetting.status == bytes(
            (97, 99, 116, 105, 118, 101)
        ).decode(),
    ))
    if setting and setting.coefficient is not None:
        return float(setting.coefficient)
    return 1.0


def subject_context_weight(session: Session, school_class: SchoolClass, subject_id: uuid.UUID) -> float | None:
    if not subject_is_enabled_for_class(session, school_class, subject_id):
        return None
    cycle = session.get(SchoolCycle, school_class.cycle_id) if school_class.cycle_id else None
    is_lycee = bool(cycle and ('LYCEE' in cycle.code.upper() or 'LYCEE' in cycle.name.upper()))
    setting = session.scalar(select(SubjectLevelSetting).where(
        SubjectLevelSetting.establishment_id == school_class.establishment_id,
        SubjectLevelSetting.academic_year_id == school_class.academic_year_id,
        SubjectLevelSetting.school_level_id == school_class.school_level_id,
        SubjectLevelSetting.subject_id == subject_id,
        SubjectLevelSetting.series_id == school_class.series_id,
        SubjectLevelSetting.status == 'active'))
    if setting and not setting.contributes_to_average:
        return None
    if not is_lycee:
        return 1.0
    coefficient = setting.coefficient if setting else None
    if coefficient is None and school_class.series_id is not None:
        series_setting = session.scalar(select(SubjectLevelSetting).where(
            SubjectLevelSetting.establishment_id == school_class.establishment_id,
            SubjectLevelSetting.academic_year_id == school_class.academic_year_id,
            SubjectLevelSetting.subject_id == subject_id,
            SubjectLevelSetting.series_id == school_class.series_id,
            SubjectLevelSetting.status == 'active',
            SubjectLevelSetting.coefficient.is_not(None),
        ).order_by(SubjectLevelSetting.updated_at.desc()))
        coefficient = series_setting.coefficient if series_setting else None
    if coefficient is None:
        subject = session.get(Subject, subject_id)
        level = (
            session.get(SchoolLevel, school_class.school_level_id)
            if school_class.school_level_id else None
        )
        subject_name = subject.name if subject else 'la matière évaluée'
        level_name = level.name if level else 'ce niveau du lycée'
        raise HTTPException(
            409,
            f'Le coefficient de {subject_name} n’est pas configuré pour {level_name}.',
        )
    return float(coefficient)

def evaluation_policy_for_class(
    session: Session,
    school_class: SchoolClass,
    evaluations: list[Evaluation],
    target_period: AcademicPeriod | None = None,
) -> tuple[list[Evaluation], list[dict[str, Any]]]:
    rules = session.scalars(select(EvaluationRule).where(
        EvaluationRule.establishment_id == school_class.establishment_id,
        EvaluationRule.academic_year_id == school_class.academic_year_id,
        EvaluationRule.cycle_id == school_class.cycle_id,
        EvaluationRule.status == 'active',
    )).all()
    applicable = [
        rule for rule in rules
        if (rule.school_level_id is None
            or rule.school_level_id == school_class.school_level_id)
        and (rule.series_id is None or rule.series_id == school_class.series_id)
    ]
    if not applicable:
        cycle = session.get(SchoolCycle, school_class.cycle_id)
        level = session.get(SchoolLevel, school_class.school_level_id)
        cycle_code = (cycle.code if cycle else '').upper()
        level_code = (level.code if level else '').upper()
        required: dict[str, int] = {}
        contributing_types: set[str] = set()
        if cycle_code in {'MATERNELLE', 'PRIMAIRE'}:
            # Par défaut, les examens blancs restent complémentaires. Une
            # règle pédagogique explicite peut seule les rendre contributifs.
            contributing_types = {'composition'}
            if target_period and target_period.period_type == 'trimester':
                child_count = session.scalar(select(func.count(AcademicPeriod.id)).where(
                    AcademicPeriod.establishment_id == school_class.establishment_id,
                    AcademicPeriod.academic_year_id == school_class.academic_year_id,
                    AcademicPeriod.parent_period_id == target_period.id,
                    AcademicPeriod.status == 'active',
                )) or 0
                # Les examens officiels blancs sont complémentaires : ils ne
                # remplacent jamais les compositions normales du trimestre.
                required['composition'] = int(child_count) + 1
            else:
                required['composition'] = 1
        elif cycle_code in {'COLLEGE', 'LYCEE'}:
            contributing_types = {'devoir', 'composition'}
            if target_period is None or target_period.period_type == 'trimester':
                required = {'devoir': 2, 'composition': 1}
        missing = []
        for evaluation_type, expected in required.items():
            actual = sum(item.type == evaluation_type for item in evaluations)
            if actual < expected:
                missing.append({
                    'evaluationType': evaluation_type,
                    'expected': expected,
                    'actual': actual,
                    'labels': ['Règle métier automatique'],
                })
        if missing:
            return [], missing
        return [
            item for item in evaluations
            if not contributing_types or item.type in contributing_types
        ], []
    selected_by_type: dict[str, list[EvaluationRule]] = {}
    for evaluation_type in {rule.evaluation_type for rule in applicable}:
        candidates = [
            rule for rule in applicable
            if rule.evaluation_type == evaluation_type
        ]
        most_specific = max(
            (int(rule.school_level_id is not None)
             + int(rule.series_id is not None) for rule in candidates),
            default=0,
        )
        selected_by_type[evaluation_type] = [
            rule for rule in candidates
            if int(rule.school_level_id is not None)
            + int(rule.series_id is not None) == most_specific
        ]

    missing_rules = []
    contributing_types: set[str] = set()
    for evaluation_type, selected_rules in selected_by_type.items():
        if any(rule.contributes_to_average for rule in selected_rules):
            contributing_types.add(evaluation_type)
        expected = sum(
            rule.expected_count or 1
            for rule in selected_rules
            if rule.is_required
        )
        actual = sum(
            evaluation.type == evaluation_type for evaluation in evaluations
        )
        if expected > actual:
            missing_rules.append({
                'evaluationType': evaluation_type,
                'expected': expected,
                'actual': actual,
                'labels': [rule.label for rule in selected_rules if rule.is_required],
            })

    if missing_rules:
        return [], missing_rules
    if not selected_by_type:
        return evaluations, []
    return [
        evaluation for evaluation in evaluations
        if evaluation.type not in selected_by_type
        or evaluation.type in contributing_types
    ], []


def general_average_scale(session: Session, school_class: SchoolClass) -> float:
    """The class cycle determines the common scale, never the grade display."""
    cycle = session.get(SchoolCycle, school_class.cycle_id) if school_class.cycle_id else None
    if cycle and cycle.code.upper() in {"MATERNELLE", "PRIMAIRE"}:
        return 10.0
    return 20.0


def normalize_grade_for_general_average(value: float, max_value: float, scale: float) -> float:
    """Normalize only the calculation contribution; persisted/displayed grades stay intact."""
    if max_value <= 0:
        raise ValueError("Le barème doit être strictement positif")
    return float(value) * float(scale) / float(max_value)


def _compute_school_results(
    class_id: uuid.UUID,
    period_id: uuid.UUID,
    current: Principal = Depends(require_module_roles("grades", "superadmin", "admin", "teacher")),
    session: Session = Depends(db),
):
    school_class = session.get(SchoolClass, class_id)
    if not school_class:
        raise HTTPException(404, 'Classe introuvable')
    if current.role == 'superadmin':
        database_id = school_class.establishment_id
    else:
        _, database_id = module_tenant_scope(current, session)
    period = session.get(AcademicPeriod, period_id)
    if not school_class or not period:
        raise HTTPException(404, "Classe ou periode introuvable")
    if school_class.establishment_id != database_id or period.establishment_id != database_id:
        raise HTTPException(403, "Acces inter-etablissement interdit")
    if current.role == "teacher" and not session.scalar(select(Affectation).where(
        Affectation.teacher_id == uuid.UUID(current.teacher_id),
        Affectation.class_id == school_class.id,
        Affectation.status == "active",
    )):
        raise HTTPException(403, "Classe non affectee a cet enseignant")
    evaluations = session.scalars(select(Evaluation).where(
        Evaluation.establishment_id == database_id,
        Evaluation.class_id == school_class.id,
        Evaluation.academic_period_id.in_([
            period.id,
            *(
                session.scalars(select(AcademicPeriod.id).where(
                    AcademicPeriod.establishment_id == database_id,
                    AcademicPeriod.academic_year_id == period.academic_year_id,
                    AcademicPeriod.parent_period_id == period.id,
                    AcademicPeriod.status == 'active',
                )).all()
                if period.period_type == 'trimester' else []
            ),
        ]),
        Evaluation.status.in_(("submitted", "validated", "locked")),
    )).all()
    calculation_evaluations, _ = evaluation_policy_for_class(
        session, school_class, list(evaluations), period
    )
    evaluation_ids = [item.id for item in calculation_evaluations]
    grades = [] if not evaluation_ids else session.scalars(select(Grade).where(
        Grade.establishment_id == database_id,
        Grade.evaluation_id.in_(evaluation_ids),
        Grade.presence == "present",
        Grade.value.is_not(None),
    )).all()
    evaluation_by_id = {item.id: item for item in calculation_evaluations}
    average_scale = general_average_scale(session, school_class)
    cycle = session.get(SchoolCycle, school_class.cycle_id) if school_class.cycle_id else None
    cycle_code = (cycle.code if cycle else '').upper()
    scores: dict[uuid.UUID, dict[uuid.UUID, list[tuple[float, Grade]]]] = {}
    for grade in grades:
        normalized_value = normalize_grade_for_general_average(
            effective_grade_value(grade), float(grade.max_value), average_scale
        )
        scores.setdefault(grade.student_id, {}).setdefault(
            grade.subject_id, []
        ).append((normalized_value, grade))
    computed: list[tuple[uuid.UUID, float]] = []
    subject_details: dict[uuid.UUID, list[dict[str, Any]]] = {}
    for student_id, subject_scores in scores.items():
        weighted_total = 0.0
        coefficient_total = 0.0
        for subject_id, score_rows in subject_scores.items():
            official_grades = sorted(
                (grade for _, grade in score_rows),
                key=lambda grade: (
                    evaluation_by_id[grade.evaluation_id].date_scheduled or date.min,
                    evaluation_by_id[grade.evaluation_id].name,
                ),
            )
            normalized_by_grade = {grade.id: value for value, grade in score_rows}
            average, mc, composition = school_subject_average(
                cycle_code,
                [
                    (
                        normalized_evaluation_event(
                            evaluation_by_id[grade.evaluation_id]
                        ),
                        normalized_by_grade[grade.id],
                    )
                    for grade in official_grades
                ],
            )
            coefficient = subject_context_weight(session, school_class, subject_id)
            if coefficient is None:
                continue
            weighted_total += average * coefficient
            coefficient_total += coefficient
            subject = session.get(Subject, subject_id)
            grade_details = [{
                'evaluationId': str(grade.evaluation_id),
                'evaluation': evaluation_by_id[grade.evaluation_id].name,
                'type': evaluation_by_id[grade.evaluation_id].type,
                'examCode': evaluation_by_id[grade.evaluation_id].exam_code,
                'date': evaluation_by_id[grade.evaluation_id].date_scheduled.isoformat()
                    if evaluation_by_id[grade.evaluation_id].date_scheduled else None,
                'status': grade.status,
                'presence': grade.presence,
                'value': effective_grade_value(grade),
                'maxValue': float(grade.max_value),
                'comment': grade.comment,
            } for grade in official_grades]
            observations = list(dict.fromkeys(
                grade.comment.strip() for grade in official_grades
                if grade.comment and grade.comment.strip()
            ))
            subject_details.setdefault(student_id, []).append({
                'subjectId': str(subject_id),
                'subject': subject.name if subject else '',
                'average': average, 'coefficient': coefficient,
                'mc': round(mc, 2) if mc is not None else None,
                'composition': round(composition, 2) if composition is not None else None,
                'gradeCount': len(score_rows),
                'point': round(average * coefficient, 2),
                'grades': grade_details,
                'observation': ' / '.join(observations),
            })
        if coefficient_total == 0:
            continue
        general_average = round(weighted_total / coefficient_total, 2)
        computed.append((student_id, general_average))
    ranked = sorted(
        computed,
        key=lambda item: item[1],
        reverse=True,
    )
    result = []
    last_average = None
    last_rank = 0
    for index, (student_id, average) in enumerate(ranked, 1):
        if last_average != average:
            last_rank = index
            last_average = average
        student = session.get(Student, student_id)
        result.append({
            "studentId": str(student_id),
            "studentName": f"{student.last_name} {student.first_name}" if student else None,
            "lastName": student.last_name if student else None,
            "firstName": student.first_name if student else None,
            "average": average,
            "rank": last_rank,
            "subjects": sorted(subject_details.get(student_id, []),
                               key=lambda item: item['subject']),
        })
    return {
        "schoolId": public_school_id(session, database_id),
        "classId": str(school_class.id),
        "periodId": str(period.id),
        "evaluationCount": len(evaluations),
        "students": result,
    }


def _event_source_updated_at(
    session: Session,
    database_id: uuid.UUID,
    school_class: SchoolClass,
    period: AcademicPeriod,
    event_code: str,
) -> datetime:
    evaluations = [
        item for item in session.scalars(select(Evaluation).where(
            Evaluation.establishment_id == database_id,
            Evaluation.class_id == school_class.id,
            Evaluation.academic_period_id.in_(
                event_period_ids(session, database_id, period)
            ),
        )).all()
        if normalized_evaluation_event(item) == event_code
    ]
    ids = [item.id for item in evaluations]
    grades = [] if not ids else session.scalars(select(Grade).where(
        Grade.establishment_id == database_id,
        Grade.evaluation_id.in_(ids),
    )).all()
    settings = session.scalars(select(SubjectLevelSetting).where(
        SubjectLevelSetting.establishment_id == database_id,
        SubjectLevelSetting.academic_year_id == school_class.academic_year_id,
        SubjectLevelSetting.school_level_id == school_class.school_level_id,
        SubjectLevelSetting.series_id == school_class.series_id,
        SubjectLevelSetting.status == 'active',
    )).all()
    values = [
        value for value in [
            *(item.updated_at for item in evaluations),
            *(item.updated_at for item in grades),
            *(item.updated_at for item in settings),
        ] if value is not None
    ]
    if not values:
        return datetime(1970, 1, 1, tzinfo=timezone.utc)
    return max(
        value.replace(tzinfo=timezone.utc) if value.tzinfo is None
        else value.astimezone(timezone.utc)
        for value in values
    )


def _compute_school_event_results(
    school_class: SchoolClass,
    period: AcademicPeriod,
    event_code: str,
    session: Session,
) -> dict[str, Any]:
    evaluations = [
        item for item in session.scalars(select(Evaluation).where(
            Evaluation.establishment_id == school_class.establishment_id,
            Evaluation.class_id == school_class.id,
            Evaluation.academic_period_id.in_(event_period_ids(
                session, school_class.establishment_id, period
            )),
            Evaluation.status.in_(('submitted', 'validated', 'locked')),
        )).all()
        if normalized_evaluation_event(item) == event_code
    ]
    evaluation_by_id = {item.id: item for item in evaluations}
    grades = [] if not evaluation_by_id else session.scalars(select(Grade).where(
        Grade.establishment_id == school_class.establishment_id,
        Grade.evaluation_id.in_(list(evaluation_by_id)),
        Grade.presence == "present",
        Grade.value.is_not(None),
    )).all()
    average_scale = general_average_scale(session, school_class)
    cycle = session.get(SchoolCycle, school_class.cycle_id)
    is_lycee = bool(cycle and cycle.code.upper() == 'LYCEE')
    scores: dict[
        uuid.UUID,
        dict[uuid.UUID, list[tuple[float, Evaluation, float, float]]],
    ] = {}
    for grade in grades:
        scores.setdefault(grade.student_id, {}).setdefault(
            grade.subject_id, []
        ).append((
            normalize_grade_for_general_average(
                effective_grade_value(grade), float(grade.max_value), average_scale),
            evaluation_by_id[grade.evaluation_id],
            effective_grade_value(grade),
            float(grade.max_value),
        ))
    computed = []
    for student_id, subject_scores in scores.items():
        weighted_total = 0.0
        coefficient_total = 0.0
        details = []
        for subject_id, values in subject_scores.items():
            average = round(
                sum(value for value, _, _, _ in values) / len(values), 2
            )
            coefficient = subject_context_weight(session, school_class, subject_id)
            if coefficient is None:
                continue
            subject = session.get(Subject, subject_id)
            details.append({
                'subjectId': str(subject_id),
                'subject': subject.name if subject else None,
                'average': average,
                'coefficient': coefficient if is_lycee else None,
                'point': round(average * coefficient, 2),
                'grades': [{
                    'evaluationId': str(evaluation.id),
                    'evaluation': evaluation.name,
                    'value': round(raw_value, 2),
                    'maxValue': max_value,
                    'normalizedValue': round(value, 2),
                } for value, evaluation, raw_value, max_value in values],
            })
            weighted_total += average * coefficient
            coefficient_total += coefficient
        if coefficient_total:
            computed.append((
                student_id,
                round(weighted_total / coefficient_total, 2),
                sorted(details, key=lambda item: (item['subject'] or '').lower()),
            ))
    ranked = sorted(computed, key=lambda item: item[1], reverse=True)
    students = []
    last_average = None
    last_rank = 0
    for index, (student_id, average, subjects) in enumerate(ranked, 1):
        if average != last_average:
            last_average = average
            last_rank = index
        student = session.get(Student, student_id)
        students.append({
            'studentId': str(student_id),
            'studentName': f'{student.last_name} {student.first_name}' if student else None,
            'lastName': student.last_name if student else None,
            'firstName': student.first_name if student else None,
            'average': average,
            'rank': last_rank,
            'subjects': subjects,
        })
    return {
        'schoolId': public_school_id(session, school_class.establishment_id),
        'classId': str(school_class.id),
        'periodId': str(period.id),
        'eventCode': event_code,
        'event': KNOWN_EVALUATION_EVENTS[event_code],
        'evaluationCount': len(evaluations),
        'students': students,
    }


def school_event_results(
    class_id: uuid.UUID,
    period_id: uuid.UUID,
    event_code: str,
    current: Principal,
    session: Session,
) -> dict[str, Any]:
    code = validate_evaluation_event_code(event_code)
    readiness = school_event_submission_status(
        class_id, period_id, code, current, session
    )
    school_class = session.get(SchoolClass, class_id)
    period = session.get(AcademicPeriod, period_id)
    base = {
        'classId': str(class_id),
        'periodId': str(period_id),
        'eventCode': code,
        'event': KNOWN_EVALUATION_EVENTS[code],
        'readyForCalculation': readiness['readyForCalculation'],
        'submissions': readiness['submissions'],
        'students': [],
    }
    if not readiness['readyForCalculation']:
        return {**base, 'calculationStatus': 'waiting'}
    snapshot = session.scalar(select(ResultCalculation).where(
        ResultCalculation.establishment_id == school_class.establishment_id,
        ResultCalculation.class_id == class_id,
        ResultCalculation.academic_period_id == period_id,
    ))
    stored = ((snapshot.payload.get('eventResults') or {}).get(code)
              if snapshot else None)
    if not stored:
        return {**base, 'calculationStatus': 'ready'}
    source = _event_source_updated_at(
        session, school_class.establishment_id, school_class, period, code
    )
    stored_source = datetime.fromisoformat(stored['sourceUpdatedAt'])
    if stored_source.tzinfo is None:
        stored_source = stored_source.replace(tzinfo=timezone.utc)
    if source > stored_source:
        return {
            **base,
            'calculationStatus': 'stale',
            'calculatedAt': stored.get('calculatedAt'),
        }
    return {
        **stored,
        'readyForCalculation': True,
        'calculationStatus': 'official',
    }


def calculate_school_event_results(
    class_id: uuid.UUID,
    period_id: uuid.UUID,
    event_code: str,
    current: Principal,
    session: Session,
) -> dict[str, Any]:
    code = validate_evaluation_event_code(event_code)
    readiness = school_event_submission_status(
        class_id, period_id, code, current, session
    )
    if not readiness['readyForCalculation']:
        raise HTTPException(
            409,
            f"Calcul impossible : {readiness['missingCount']} relevé(s) restent à recevoir",
        )
    school_class = session.get(SchoolClass, class_id)
    period = session.get(AcademicPeriod, period_id)
    payload = _compute_school_event_results(
        school_class, period, code, session
    )
    now = datetime.now(timezone.utc)
    source = _event_source_updated_at(
        session, school_class.establishment_id, school_class, period, code
    )
    snapshot = session.scalar(select(ResultCalculation).where(
        ResultCalculation.establishment_id == school_class.establishment_id,
        ResultCalculation.class_id == class_id,
        ResultCalculation.academic_period_id == period_id,
    ))
    if not snapshot:
        snapshot = ResultCalculation(
            establishment_id=school_class.establishment_id,
            academic_year_id=school_class.academic_year_id,
            class_id=class_id,
            academic_period_id=period_id,
            status='archived',
            payload={},
            source_updated_at=datetime(1970, 1, 1, tzinfo=timezone.utc),
            calculated_by=uuid.UUID(current.id),
            calculated_at=now,
        )
        session.add(snapshot)
    stored_payload = dict(snapshot.payload or {})
    event_results = dict(stored_payload.get('eventResults') or {})
    event_results[code] = {
        **payload,
        'sourceUpdatedAt': source.isoformat(),
        'calculatedAt': now.isoformat(),
    }
    stored_payload['eventResults'] = event_results
    snapshot.payload = stored_payload
    snapshot.updated_at = now
    session.commit()
    return {
        **event_results[code],
        'readyForCalculation': True,
        'calculationStatus': 'official',
        'submissions': readiness['submissions'],
    }


def _result_source_updated_at(
    session: Session,
    database_id: uuid.UUID,
    school_class: SchoolClass,
    period: AcademicPeriod,
) -> datetime:
    period_ids = [period.id]
    if period.period_type == "trimester":
        period_ids.extend(session.scalars(select(AcademicPeriod.id).where(
            AcademicPeriod.establishment_id == database_id,
            AcademicPeriod.academic_year_id == period.academic_year_id,
            AcademicPeriod.parent_period_id == period.id,
            AcademicPeriod.status == "active",
        )).all())
    evaluation_rows = session.scalars(select(Evaluation).where(
        Evaluation.establishment_id == database_id,
        Evaluation.class_id == school_class.id,
        Evaluation.academic_period_id.in_(period_ids),
    )).all()
    evaluation_ids = [item.id for item in evaluation_rows]
    grade_rows = [] if not evaluation_ids else session.scalars(select(Grade).where(
        Grade.establishment_id == database_id,
        Grade.evaluation_id.in_(evaluation_ids),
    )).all()
    setting_rows = session.scalars(select(SubjectLevelSetting).where(
        SubjectLevelSetting.establishment_id == database_id,
        SubjectLevelSetting.academic_year_id == school_class.academic_year_id,
        SubjectLevelSetting.school_level_id == school_class.school_level_id,
        SubjectLevelSetting.status == "active",
    )).all()
    rule_rows = session.scalars(select(EvaluationRule).where(
        EvaluationRule.establishment_id == database_id,
        EvaluationRule.academic_year_id == school_class.academic_year_id,
        EvaluationRule.cycle_id == school_class.cycle_id,
        EvaluationRule.status == "active",
    )).all()
    values = [
        value for value in [
            *(item.updated_at for item in evaluation_rows),
            *(item.updated_at for item in grade_rows),
            *(item.updated_at for item in setting_rows),
            *(item.updated_at for item in rule_rows),
        ] if value is not None
    ]
    if not values:
        return datetime(1970, 1, 1, tzinfo=timezone.utc)
    normalized = [
        value.replace(tzinfo=timezone.utc) if value.tzinfo is None
        else value.astimezone(timezone.utc)
        for value in values
    ]
    return max(normalized)


def school_results(
    class_id: uuid.UUID,
    period_id: uuid.UUID,
    current: Principal,
    session: Session,
):
    if current.role == "teacher":
        ensure_plan_capability(current, session, "grades.publish_teacher")
    school_class = session.get(SchoolClass, class_id)
    period = session.get(AcademicPeriod, period_id)
    if not school_class or not period:
        raise HTTPException(404, "Classe ou periode introuvable")
    if current.role == "superadmin":
        database_id = school_class.establishment_id
    else:
        _, database_id = module_tenant_scope(current, session)
    if (school_class.establishment_id != database_id
            or period.establishment_id != database_id
            or period.academic_year_id != school_class.academic_year_id):
        raise HTTPException(403, "Acces inter-etablissement interdit")
    if current.role == "teacher" and not session.scalar(select(Affectation.id).where(
        Affectation.teacher_id == uuid.UUID(current.teacher_id),
        Affectation.class_id == school_class.id,
        Affectation.status == "active",
    )):
        raise HTTPException(403, "Classe non affectee a cet enseignant")

    readiness_principal = current
    if current.role not in {"admin", "superadmin"}:
        readiness_principal = submission_aggregation_principal(current)
    submission = school_submission_status(
        school_class.id, period.id, readiness_principal, session
    )
    base = {
        "schoolId": public_school_id(session, database_id),
        "classId": str(school_class.id),
        "periodId": str(period.id),
        "readyForCalculation": submission["readyForCalculation"],
        "submissions": submission["submissions"],
        "students": [],
    }
    if not submission["readyForCalculation"]:
        return {**base, "calculationStatus": "waiting"}

    snapshot = session.scalar(select(ResultCalculation).where(
        ResultCalculation.establishment_id == database_id,
        ResultCalculation.class_id == school_class.id,
        ResultCalculation.academic_period_id == period.id,
        ResultCalculation.status == "official",
    ))
    if not snapshot:
        return {**base, "calculationStatus": "ready"}
    source_updated_at = _result_source_updated_at(
        session, database_id, school_class, period
    )
    snapshot_source = snapshot.source_updated_at
    if snapshot_source.tzinfo is None:
        snapshot_source = snapshot_source.replace(tzinfo=timezone.utc)
    stored_rule_version = (snapshot.payload or {}).get("calculationRuleVersion")
    if (source_updated_at > snapshot_source
            or stored_rule_version != RESULT_CALCULATION_RULE_VERSION):
        return {
            **base,
            "calculationStatus": "stale",
            "calculatedAt": snapshot.calculated_at.isoformat(),
        }
    return {
        **dict(snapshot.payload),
        "readyForCalculation": True,
        "calculationStatus": "official",
        "calculatedAt": snapshot.calculated_at.isoformat(),
    }


def annual_trimester_periods(session, establishment_id, academic_year_id):
    # Codes are generated PER-...; use the canonical type, not guessed T1 codes.
    periods = session.scalars(select(AcademicPeriod).where(
        AcademicPeriod.establishment_id == establishment_id,
        AcademicPeriod.academic_year_id == academic_year_id,
        AcademicPeriod.period_type == "trimester",
        AcademicPeriod.status == "active",
    ).order_by(AcademicPeriod.sort_order, AcademicPeriod.code)).all()
    return list(periods) if len(periods) == 3 else []


def sync_automatic_annual_decisions_for_class(
    school_class: SchoolClass,
    current: Principal,
    session: Session,
    decided_at: datetime,
) -> int:
    periods = annual_trimester_periods(session, school_class.establishment_id, school_class.academic_year_id)
    if not periods:
        return 0

    period_ids = [period.id for period in periods]
    snapshots = session.scalars(select(ResultCalculation).where(
        ResultCalculation.establishment_id == school_class.establishment_id,
        ResultCalculation.class_id == school_class.id,
        ResultCalculation.academic_period_id.in_(period_ids),
        ResultCalculation.status == "official",
    )).all()
    snapshots_by_period = {
        snapshot.academic_period_id: snapshot for snapshot in snapshots
    }
    if len(snapshots_by_period) != len(periods):
        return 0

    for period in periods:
        snapshot = snapshots_by_period[period.id]
        stored_rule_version = (snapshot.payload or {}).get("calculationRuleVersion")
        # Backward compatibility: official snapshots created before rule-version
        # stamping remain valid. Only an explicit incompatible version blocks the
        # annual decision sync.
        if (stored_rule_version is not None
                and stored_rule_version != RESULT_CALCULATION_RULE_VERSION):
            return 0
        snapshot_source = snapshot.source_updated_at
        if snapshot_source.tzinfo is None:
            snapshot_source = snapshot_source.replace(tzinfo=timezone.utc)
        if _result_source_updated_at(
            session, school_class.establishment_id, school_class, period
        ) > snapshot_source:
            return 0

    registrations = session.scalars(select(StudentAcademicRegistration).where(
        StudentAcademicRegistration.establishment_id
        == school_class.establishment_id,
        StudentAcademicRegistration.class_id == school_class.id,
        StudentAcademicRegistration.academic_year_id
        == school_class.academic_year_id,
        StudentAcademicRegistration.status.in_(("pending", "validated", "active")),
    )).all()
    if not registrations:
        return 0

    student_ids = [registration.student_id for registration in registrations]
    decisions = session.scalars(select(StudentAnnualDecision).where(
        StudentAnnualDecision.establishment_id == school_class.establishment_id,
        StudentAnnualDecision.academic_year_id == school_class.academic_year_id,
        StudentAnnualDecision.student_id.in_(student_ids),
    )).all()
    decisions_by_student = {decision.student_id: decision for decision in decisions}
    actor_id = uuid.UUID(current.id)
    updated = 0

    for student_id in student_ids:
        averages: list[float] = []
        for period in periods:
            rows = (snapshots_by_period[period.id].payload or {}).get("students") or []
            student_result = next((
                row for row in rows
                if row.get("studentId") == str(student_id)
            ), None)
            average = student_result.get("average") if student_result else None
            if average is None:
                break
            averages.append(float(average))
        if len(averages) != len(periods):
            continue

        automatic_decision = (
            "admitted" if sum(averages) / len(averages) >= 10 else "repeat"
        )
        decision = decisions_by_student.get(student_id)
        if decision and decision.decision == "excluded":
            continue
        if decision is None:
            decision = StudentAnnualDecision(
                establishment_id=school_class.establishment_id,
                student_id=student_id,
                academic_year_id=school_class.academic_year_id,
            )
            session.add(decision)
            decisions_by_student[student_id] = decision
        elif decision.decision == automatic_decision and decision.reason is None:
            continue

        decision.decision = automatic_decision
        decision.reason = None
        decision.decided_by = actor_id
        decision.decided_at = decided_at
        decision.updated_at = decided_at
        updated += 1
    return updated


@app.post("/api/v1/school/results/calculate")
def calculate_school_results(
    class_id: uuid.UUID,
    period_id: uuid.UUID,
    current: Principal = Depends(require_module_roles(
        "grades", "superadmin", "admin"
    )),
    session: Session = Depends(db),
    event_code: str | None = None,
):
    if event_code:
        return calculate_school_event_results(
            class_id, period_id, event_code, current, session
        )
    school_class = session.get(SchoolClass, class_id)
    period = session.get(AcademicPeriod, period_id)
    if not school_class or not period:
        raise HTTPException(404, "Classe ou periode introuvable")
    if current.role == "superadmin":
        database_id = school_class.establishment_id
    else:
        _, database_id = module_tenant_scope(current, session)
    if (school_class.establishment_id != database_id
            or period.establishment_id != database_id
            or period.academic_year_id != school_class.academic_year_id):
        raise HTTPException(403, "Acces inter-etablissement interdit")
    submission = school_submission_status(
        school_class.id, period.id, current, session
    )
    if not submission["readyForCalculation"]:
        missing = sum(
            row["status"] != "submitted" for row in submission["submissions"]
        )
        raise HTTPException(
            409,
            f"Calcul impossible : {missing} releve(s) restent a recevoir",
        )
    payload = _compute_school_results(
        school_class.id, period.id, current, session
    )
    payload["readyForCalculation"] = True
    payload["calculationStatus"] = "official"
    payload["calculationRuleVersion"] = RESULT_CALCULATION_RULE_VERSION
    payload["submissions"] = submission["submissions"]
    source_updated_at = _result_source_updated_at(
        session, database_id, school_class, period
    )
    snapshot = session.scalar(select(ResultCalculation).where(
        ResultCalculation.establishment_id == database_id,
        ResultCalculation.class_id == school_class.id,
        ResultCalculation.academic_period_id == period.id,
    ))
    now = datetime.now(timezone.utc)
    if not snapshot:
        snapshot = ResultCalculation(
            establishment_id=database_id,
            academic_year_id=school_class.academic_year_id,
            class_id=school_class.id,
            academic_period_id=period.id,
            payload=payload,
            source_updated_at=source_updated_at,
            calculated_by=uuid.UUID(current.id),
            calculated_at=now,
        )
        session.add(snapshot)
    else:
        event_results = dict((snapshot.payload or {}).get('eventResults') or {})
        if event_results:
            payload['eventResults'] = event_results
        snapshot.status = "official"
        snapshot.payload = payload
        snapshot.source_updated_at = source_updated_at
        snapshot.calculated_by = uuid.UUID(current.id)
        snapshot.calculated_at = now
        snapshot.updated_at = now
    ready_id = f"results-ready-{school_class.id}-{period.id}"
    ready_resource = session.get(
        Resource, {"kind": "notifications", "id": ready_id}
    )
    if ready_resource:
        notification_payload = dict(ready_resource.payload)
        notification_payload.update({
            "type": "results_calculated",
            "title": "Resultats calcules",
            "message": (
                f"{school_class.name} - {period.name} : le classement est a jour."
            ),
            "readyForCalculation": False,
            "requiresRecalculation": False,
            "read": True,
            "time": now.isoformat(),
        })
        ready_resource.payload = notification_payload
        ready_resource.updated_at = now
    school_public_id = public_school_id(session, database_id)
    for result in payload.get("students") or []:
        try:
            student_id = uuid.UUID(str(result.get("studentId")))
        except (TypeError, ValueError):
            continue
        parent_user_ids = [str(value) for value in session.scalars(
            select(Guardian.user_id).join(
                StudentGuardian,
                StudentGuardian.guardian_id == Guardian.id,
            ).where(
                StudentGuardian.student_id == student_id,
                Guardian.user_id.is_not(None),
                Guardian.status == "active",
            )
        ).all()]
        notification_id = f"results-available-{school_class.id}-{period.id}-{student_id}"
        notification_payload = {
            "id": notification_id,
            "type": "results_available",
            "title": "Résultats disponibles",
            "message": f"Les résultats de {period.name} sont disponibles.",
            "studentId": str(student_id),
            "parentUserIds": parent_user_ids,
            "classId": str(school_class.id),
            "periodId": str(period.id),
            "academicYearId": str(school_class.academic_year_id),
            "read": False,
            "time": now.isoformat(),
            "schoolId": school_public_id,
        }
        notification = session.get(
            Resource, {"kind": "notifications", "id": notification_id}
        )
        if notification:
            notification.payload = notification_payload
            notification.updated_at = now
        else:
            session.add(Resource(
                id=notification_id,
                kind="notifications",
                school_id=school_public_id,
                establishment_id=database_id,
                cycle_id=school_class.cycle_id,
                school_level_id=school_class.school_level_id,
                academic_year_id=school_class.academic_year_id,
                payload=notification_payload,
            ))
    session.flush()
    sync_automatic_annual_decisions_for_class(
        school_class, current, session, now
    )
    session.commit()
    return {
        **payload,
        "calculatedAt": now.isoformat(),
    }

def ensure_student_results_access(
    student: Student,
    registration: StudentAcademicRegistration,
    current: Principal,
    session: Session,
) -> None:
    if current.role == "superadmin":
        return
    if public_school_id(session, student.establishment_id) != current.school_id:
        raise HTTPException(403, "Acces inter-etablissement interdit")
    if current.role == "admin":
        ensure_class_module_access(
            current,
            session.get(SchoolClass, registration.class_id),
            student.establishment_id,
            session,
        )
        return
    if current.role == "teacher":
        ensure_class_module_access(
            current,
            session.get(SchoolClass, registration.class_id),
            student.establishment_id,
            session,
        )
        return
    if current.role == "student" and current.student_id == str(student.id):
        return
    if current.role == "parent":
        guardian = session.scalar(select(Guardian).where(
            Guardian.user_id == uuid.UUID(current.id),
            Guardian.establishment_id == student.establishment_id,
        ))
        if guardian and session.scalar(select(StudentGuardian).where(
            StudentGuardian.guardian_id == guardian.id,
            StudentGuardian.student_id == student.id,
            StudentGuardian.establishment_id == student.establishment_id,
        )):
            return
    raise HTTPException(403, "Resultats non autorises")

@app.get("/api/v1/school/students/{student_id}/bulletin")
def student_bulletin(
    student_id: uuid.UUID,
    academic_year_id: uuid.UUID,
    current: Principal = Depends(require_module_roles(
        "grades", "superadmin", "admin", "teacher", "student", "parent"
    )),
    session: Session = Depends(db),
):
    if current.role not in ('superadmin', 'admin'):
        raise HTTPException(403, 'Le bulletin complet est reserve a l administration scolaire')
    student = session.get(Student, student_id)
    if not student:
        raise HTTPException(404, "Eleve introuvable")
    registration = session.scalar(select(StudentAcademicRegistration).where(
        StudentAcademicRegistration.establishment_id == student.establishment_id,
        StudentAcademicRegistration.student_id == student.id,
        StudentAcademicRegistration.academic_year_id == academic_year_id,
        StudentAcademicRegistration.status.in_(("pending", "validated", "active")),
    ))
    if not registration:
        raise HTTPException(404, "Inscription annuelle introuvable")
    ensure_student_results_access(student, registration, current, session)
    school_class = session.get(SchoolClass, registration.class_id)
    periods = annual_trimester_periods(session, student.establishment_id, academic_year_id)
    period_results = []
    for period in periods:
        official_result = school_results(registration.class_id, period.id, current, session)
        own_result = next((
            row for row in official_result.get('students', [])
            if row['studentId'] == str(student.id)
        ), None) if official_result.get('calculationStatus') == 'official' else None
        behavior_average = None
        if own_result:
            from .behavior import results as official_behavior_results
            behavior_result = official_behavior_results(
                current, session, registration.class_id, period.id
            )
            if behavior_result.get('calculationStatus') != 'official':
                missing = int(behavior_result.get('missingCount') or 0)
                raise HTTPException(
                    409,
                    f"Bulletin indisponible : {missing} enseignant(s) doivent encore envoyer les étoiles comportementales pour {period.name}",
                )
            own_behavior = next((row for row in behavior_result.get('students', [])
                if row.get('studentId') == str(student.id)), None)
            behavior_average = own_behavior.get('average') if own_behavior else None
        period_results.append({
            "periodId": str(period.id),
            "period": period.name,
            "code": period.code,
            "calculationStatus": official_result.get('calculationStatus', 'waiting'),
            "average": own_result['average'] if own_result else None,
            "rank": own_result.get('rank') if own_result else None,
            "effectif": len(official_result.get('students', [])) if own_result else None,
            "subjects": own_result.get('subjects', []) if own_result else [],
            "detailsAvailable": bool(own_result and 'subjects' in own_result),
            "calculatedAt": official_result.get('calculatedAt'),
            "evaluationCount": official_result.get('evaluationCount', 0),
            "behaviorAverage": behavior_average,
        })
    available = [item["average"] for item in period_results if item["average"] is not None]
    annual_calculable = len(periods) == 3 and len(available) == 3
    school_class = session.get(SchoolClass, registration.class_id)
    year = session.get(AcademicYear, academic_year_id)
    decision_record = session.scalar(select(StudentAnnualDecision).where(
        StudentAnnualDecision.establishment_id == student.establishment_id,
        StudentAnnualDecision.student_id == student.id,
        StudentAnnualDecision.academic_year_id == academic_year_id,
    ))
    # Canonical administrative bulletin payload.
    student_payload = student_json(student, session, academic_year_id)
    student_payload["photo"] = _student_photo_document_data(session, student.id)
    payload = {
        "student": student_payload,
        "academicYear": academic_year_json(year, session) if year else None,
        "class": class_json(school_class, session) if school_class else None,
        "periods": period_results,
        "annualCalculable": annual_calculable,
        "annualAverage": round(sum(available) / len(available), 2)
        if annual_calculable else None,
        "decision": None,
        "decisionImplemented": False,
    }

    payload['decision'] = ({
        'id': str(decision_record.id),
        'decision': decision_record.decision,
        'reason': decision_record.reason,
        'decidedAt': (
            decision_record.decided_at.isoformat()
            if decision_record.decided_at else None
        ),
    } if decision_record and (decision_record.decision == 'excluded' or annual_calculable) else None)
    payload['decisionImplemented'] = True
    return payload

def ensure_class_module_access(
    current: Principal,
    school_class: SchoolClass | None,
    database_id: uuid.UUID,
    session: Session,
) -> SchoolClass:
    if not school_class:
        raise HTTPException(404, "Classe introuvable")
    if school_class.establishment_id != database_id:
        raise HTTPException(403, "Classe inter-etablissement interdite")
    ensure_direction_cycle_access(current, school_class.cycle_id)
    if current.role == "teacher":
        if not current.teacher_id or not session.scalar(select(Affectation).where(
            Affectation.teacher_id == uuid.UUID(current.teacher_id),
            Affectation.class_id == school_class.id,
            Affectation.status == "active",
        )):
            raise HTTPException(403, "Classe non affectee a cet enseignant")
    return school_class

def attendance_json(item: AttendanceRecord, session: Session) -> dict[str, Any]:
    schedule = session.get(ScheduleEntry, item.schedule_entry_id) if item.schedule_entry_id else None
    subject = session.get(Subject, item.subject_id) if item.subject_id else None
    teacher = session.get(Teacher, item.teacher_id) if item.teacher_id else None
    return {
        "id": str(item.id),
        "studentId": str(item.student_id),
        "classId": str(item.class_id),
        "academicYearId": str(item.academic_year_id),
        "scheduleId": str(item.schedule_entry_id) if item.schedule_entry_id else None,
        "teacherId": str(item.teacher_id) if item.teacher_id else None,
        "subjectId": str(item.subject_id) if item.subject_id else None,
        "subject": subject.name if subject else None,
        "teacher": (
            f"{teacher.last_name} {teacher.first_name}" if teacher else None
        ),
        "startTime": (
            schedule.start_time.isoformat(timespec="minutes") if schedule else None
        ),
        "endTime": (
            schedule.end_time.isoformat(timespec="minutes") if schedule else None
        ),
        "date": item.attendance_date.isoformat(),
        "status": item.status,
        "note": item.note,
        "reason": item.note,
        "recordedBy": str(item.recorded_by) if item.recorded_by else None,
    }

def behavior_json(item: BehaviorEvent, session: Session) -> dict[str, Any]:
    teacher = session.scalar(select(Teacher).where(Teacher.user_id == item.recorded_by)) if item.recorded_by else None
    period = session.get(AcademicPeriod, item.academic_period_id) if item.academic_period_id else None
    return {
        "id": str(item.id),
        "studentId": str(item.student_id),
        "classId": str(item.class_id),
        "academicYearId": str(item.academic_year_id),
        "periodId": str(item.academic_period_id) if item.academic_period_id else None,
        "period": period.name if period else None,
        "date": item.event_date.isoformat(),
        "category": item.category,
        "eventType": item.event_type,
        "severity": item.severity,
        "title": item.title,
        "description": item.description,
        "comment": item.description or item.title,
        "score": (
            int(item.category.split(':', 1)[1])
            if item.category.startswith('stars:')
            and item.category.split(':', 1)[1].isdigit()
            else 1 if item.event_type == "positive"
            else -1 if item.event_type == "negative" else 0
        ),
        "teacherId": str(teacher.id) if teacher else "",
        "schoolId": public_school_id(session, item.establishment_id),
        "status": item.status,
        "recordedBy": str(item.recorded_by) if item.recorded_by else None,
    }

def assignment_json(item: SchoolAssignment, session: Session) -> dict[str, Any]:
    subject = session.get(Subject, item.subject_id)
    school_class = session.get(SchoolClass, item.class_id)
    return {
        "id": str(item.id),
        "schoolId": public_school_id(session, item.establishment_id),
        "academicYearId": str(item.academic_year_id),
        "classId": str(item.class_id),
        "subjectId": str(item.subject_id),
        "teacherId": str(item.teacher_id) if item.teacher_id else None,
        "affectationId": str(item.affectation_id) if item.affectation_id else None,
        "title": item.title,
        "description": item.description,
        "subject": subject.name if subject else None,
        "class": school_class.name if school_class else None,
        "assignedDate": item.assigned_date.isoformat(),
        "dueDate": item.due_date.isoformat(),
        "maxScore": float(item.max_score) if item.max_score is not None else None,
        "status": item.status,
        "createdBy": str(item.created_by) if item.created_by else None,
    }

def schedule_json(item: ScheduleEntry, session: Session) -> dict[str, Any]:
    subject = session.get(Subject, item.subject_id)
    teacher = session.get(Teacher, item.teacher_id)
    school_class = session.get(SchoolClass, item.class_id)
    cycle = (
        session.get(SchoolCycle, school_class.cycle_id)
        if school_class and school_class.cycle_id else None
    )
    level = (
        session.get(SchoolLevel, school_class.school_level_id)
        if school_class and school_class.school_level_id else None
    )
    from .attendance import now_local
    now = now_local()
    year = session.get(AcademicYear, item.academic_year_id)
    in_school_year = bool(year and year.status == 'active' and year.start_date <= now.date() <= year.end_date)
    can_take_attendance = (now.isoweekday() == item.weekday and item.status == "active"
                           and now.time().replace(tzinfo=None) >= item.start_time and in_school_year)
    days = ("", "Lundi", "Mardi", "Mercredi", "Jeudi", "Vendredi", "Samedi", "Dimanche")
    return {
        "id": str(item.id),
        "schoolId": public_school_id(session, item.establishment_id),
        "academicYearId": str(item.academic_year_id),
        "classId": str(item.class_id),
        "subjectId": str(item.subject_id),
        "teacherId": str(item.teacher_id),
        "affectationId": str(item.affectation_id) if item.affectation_id else None,
        "weekday": item.weekday,
        "startTime": item.start_time.isoformat(timespec="minutes"),
        "endTime": item.end_time.isoformat(timespec="minutes"),
        "room": item.room,
        "status": item.status,
        "day": days[item.weekday],
        "time": f"{item.start_time.isoformat(timespec='minutes')} - {item.end_time.isoformat(timespec='minutes')}",
        "subject": subject.name if subject else None,
        "teacher": f"{teacher.last_name} {teacher.first_name}" if teacher else None,
        "class": school_class.name if school_class else None,
        "cycleId": str(school_class.cycle_id) if school_class and school_class.cycle_id else None,
        "cycle": cycle.name if cycle else None,
        "levelId": str(school_class.school_level_id) if school_class and school_class.school_level_id else None,
        "level": level.name if level else None,
        "isToday": now.isoweekday() == item.weekday,
        "canTakeAttendance": can_take_attendance,
        "attendanceDate": now.date().isoformat(),
        "attendanceUnavailableReason": (None if in_school_year else
            f'Année scolaire : du {year.start_date:%d/%m/%Y} au {year.end_date:%d/%m/%Y}. Vérifiez que cette année est active.' if year else 'Année scolaire indisponible.'),
        "serverTime": now.isoformat(),
        "nextAttendanceChangeAt": (
            datetime.combine(now.date(), item.start_time, tzinfo=now.tzinfo)
            if now.isoweekday() == item.weekday and now.time().replace(tzinfo=None) < item.start_time
            else datetime.combine(now.date() + timedelta(days=1), dt_time.min, tzinfo=now.tzinfo)
        ).isoformat(),
    }


def attendance_schedule_context(
    current: Principal,
    session: Session,
    database_id: uuid.UUID,
    class_id: uuid.UUID,
    schedule_id: uuid.UUID,
    *,
    attendance_date: date | None = None,
    enforce_current_window: bool = False,
) -> ScheduleEntry:
    schedule = session.get(ScheduleEntry, schedule_id)
    if not schedule:
        raise HTTPException(404, "Creneau d emploi du temps introuvable")
    if schedule.establishment_id != database_id or schedule.class_id != class_id:
        raise HTTPException(403, "Creneau inter-etablissement ou classe interdit")
    if schedule.status != "active" and enforce_current_window:
        raise HTTPException(409, "Ce cours n est plus actif")
    if current.role == "teacher":
        if not current.teacher_id or schedule.teacher_id != uuid.UUID(current.teacher_id):
            raise HTTPException(403, "Ce cours appartient a un autre enseignant")
        affectation = session.scalar(select(Affectation.id).where(
            Affectation.id == schedule.affectation_id,
            Affectation.establishment_id == database_id,
            Affectation.teacher_id == schedule.teacher_id,
            Affectation.class_id == schedule.class_id,
            Affectation.subject_id == schedule.subject_id,
            Affectation.status == "active",
        ))
        if not affectation:
            raise HTTPException(403, "Affectation active requise pour ce cours")
    if enforce_current_window:
        from .attendance import now_local
        now = now_local()
        current_date = now.date()
        if attendance_date != current_date or schedule.weekday != now.isoweekday():
            if attendance_date and attendance_date > current_date:
                raise HTTPException(409, "L’appel ne peut être effectué qu’à la date prévue de la séance.")
            raise HTTPException(409, "La période de saisie de cette présence est terminée.")
        if now.time().replace(tzinfo=None) < schedule.start_time:
            raise HTTPException(409, "L’appel sera disponible à partir de l’heure de début de la séance.")
    return schedule

@app.get("/api/v1/school/attendance/sheet")
def attendance_sheet(schedule_id: uuid.UUID, attendance_date: date, class_id: uuid.UUID | None = None,
    current: Principal = Depends(require_module_roles("attendance", "teacher", "admin", "superadmin")),
    session: Session = Depends(db)):
    from .attendance import open_sheet
    return open_sheet(current, session, schedule_id, attendance_date, class_id)

@app.get("/api/v1/school/attendance/report")
def attendance_report(academic_year_id: uuid.UUID, attendance_date: date | None = None,
    school_id: str | None = None, period_id: uuid.UUID | None = None,
    class_id: uuid.UUID | None = None, subject_id: uuid.UUID | None = None,
    teacher_id: uuid.UUID | None = None, schedule_id: uuid.UUID | None = None,
    cycle_id: uuid.UUID | None = None, level_id: uuid.UUID | None = None,
    student_id: uuid.UUID | None = None, direction_id: uuid.UUID | None = None,
    current: Principal = Depends(require_module_roles("attendance", "admin", "superadmin", "teacher")),
    session: Session = Depends(db)):
    from .attendance import report
    return report(current, session, academic_year_id, attendance_date, school_id, period_id,
        class_id, subject_id, teacher_id, schedule_id, cycle_id, level_id, student_id, direction_id=direction_id)

@app.get("/api/v1/school/attendance/contexts")
def attendance_contexts(
    current: Principal = Depends(require_module_roles("attendance", "admin", "superadmin")),
    session: Session = Depends(db)):
    from .attendance import contexts
    return contexts(current, session)

@app.get("/api/v1/school/attendance")
def list_attendance(class_id: uuid.UUID, attendance_date: date | None = None,
    schedule_id: uuid.UUID | None = None,
    current: Principal = Depends(require_module_roles("attendance", "superadmin", "admin", "teacher")),
    session: Session = Depends(db)):
    from .attendance import open_sheet, report
    if current.role == "teacher":
        if schedule_id is None or attendance_date is None:
            raise HTTPException(422, "Sélectionnez une séance et sa date")
        return open_sheet(current, session, schedule_id, attendance_date, class_id)["records"]
    school_class = session.get(SchoolClass, class_id)
    if not school_class:
        raise HTTPException(404, "Classe introuvable")
    return report(current, session, school_class.academic_year_id,
        day=attendance_date, class_id=class_id, schedule_id=schedule_id)["records"]

@app.put("/api/v1/school/attendance")
def save_attendance(body: AttendanceBatchInput,
    current: Principal = Depends(require_module_roles("attendance", "teacher")),
    session: Session = Depends(db)):
    from .attendance import save
    return save(current, session, body)["records"]

@app.get("/api/v1/school/behavior")
def list_behavior(
    class_id: uuid.UUID | None = None, student_id: uuid.UUID | None = None,
    academic_year_id: uuid.UUID | None = None, period_id: uuid.UUID | None = None,
    school_id: str | None = None,
    current: Principal = Depends(require_module_roles("behavior", "superadmin", "admin", "teacher")),
    session: Session = Depends(db),
):
    from .behavior import list_events
    return list_events(current, session, class_id, period_id, academic_year_id, student_id, school_id)

@app.post("/api/v1/school/behavior", status_code=201)
def create_behavior(
    body: BehaviorEventInput,
    current: Principal = Depends(require_module_roles("behavior", "teacher")),
    session: Session = Depends(db),
):
    # Compatibility entry point, subject to the same whole-class validation.
    from .behavior import save_sheet
    batch = BehaviorBatchInput(classId=body.class_id, periodId=body.academic_period_id,
        entries=[{"studentId": body.student_id, "stars": int(body.category.split(":")[1]),
                  "comment": body.description}])
    return save_sheet(current, session, batch)[0]

@app.put("/api/v1/school/behavior")
def submit_behavior_batch(
    body: BehaviorBatchInput,
    current: Principal = Depends(require_module_roles("behavior", "teacher")),
    session: Session = Depends(db),
):
    from .behavior import save_sheet
    return save_sheet(current, session, body)

@app.get("/api/v1/school/behavior/results")
def behavior_results(
    class_id: uuid.UUID, period_id: uuid.UUID, school_id: str | None = None,
    current: Principal = Depends(require_module_roles("behavior", "superadmin", "admin")),
    session: Session = Depends(db),
):
    from .behavior import results
    return results(current, session, class_id, period_id, school_id)

@app.get("/api/v1/school/behavior/contexts")
def behavior_contexts(
    current: Principal = Depends(require_module_roles("behavior", "superadmin")),
    session: Session = Depends(db),
):
    from .behavior import global_contexts
    return global_contexts(session)

@app.post("/api/v1/school/behavior/calculate")
def calculate_behavior(
    body: BehaviorCalculationInput,
    current: Principal = Depends(require_module_roles("behavior", "superadmin", "admin")),
    session: Session = Depends(db),
):
    from .behavior import calculate
    return calculate(current, session, body.class_id, body.academic_period_id, body.school_id)

@app.delete("/api/v1/school/behavior/{event_id}", status_code=204)
def archive_behavior(
    event_id: uuid.UUID,
    current: Principal = Depends(require_module_roles("behavior", "superadmin")),
    session: Session = Depends(db),
):
    # No route may circumvent a locked teacher sheet.
    raise HTTPException(409, "Un relevé envoyé ne peut pas être supprimé")

@app.get("/api/v1/school/assignments")
def list_assignments(
    academic_year_id: uuid.UUID | None = None,
    class_id: uuid.UUID | None = None,
    current: Principal = Depends(require_module_roles("assignments", "superadmin", "admin", "teacher")),
    session: Session = Depends(db),
):
    _, database_id = module_tenant_scope(current, session)
    statement = select(SchoolAssignment).where(
        SchoolAssignment.establishment_id == database_id,
        SchoolAssignment.status != "archived",
    )
    if academic_year_id:
        statement = statement.where(SchoolAssignment.academic_year_id == academic_year_id)
    allowed = direction_cycle_scope(current)
    if allowed is not None:
        statement = statement.where(SchoolAssignment.class_id.in_(
            select(SchoolClass.id).where(SchoolClass.cycle_id.in_(allowed))
        ))
    if class_id:
        ensure_class_module_access(current, session.get(SchoolClass, class_id), database_id, session)
        statement = statement.where(SchoolAssignment.class_id == class_id)
    if current.role == "teacher":
        statement = statement.where(SchoolAssignment.teacher_id == uuid.UUID(current.teacher_id))
    return [assignment_json(item, session) for item in session.scalars(
        statement.order_by(SchoolAssignment.due_date)
    ).all()]

@app.post("/api/v1/school/assignments", status_code=201)
def create_assignment(
    body: AssignmentInput,
    current: Principal = Depends(require_module_roles("assignments", "superadmin", "admin", "teacher")),
    session: Session = Depends(db),
):
    _, database_id = module_tenant_scope(current, session)
    school_class = ensure_class_module_access(
        current, session.get(SchoolClass, body.class_id), database_id, session
    )
    subject = session.get(Subject, body.subject_id)
    if not subject:
        raise HTTPException(422, "Matiere introuvable")
    if subject.establishment_id != database_id:
        raise HTTPException(403, "Matiere inter-etablissement interdite")
    affectation = None
    teacher_id = None
    if current.role == "teacher":
        affectation = teacher_evaluation_affectation(
            current, school_class.id, subject.id, session
        )
        teacher_id = affectation.teacher_id
    else:
        affectation = session.scalar(select(Affectation).where(
            Affectation.establishment_id == database_id,
            Affectation.class_id == school_class.id,
            Affectation.subject_id == subject.id,
            Affectation.status == "active",
        ))
        teacher_id = affectation.teacher_id if affectation else None
    item = SchoolAssignment(
        establishment_id=database_id,
        academic_year_id=school_class.academic_year_id,
        class_id=school_class.id,
        subject_id=subject.id,
        teacher_id=teacher_id,
        affectation_id=affectation.id if affectation else None,
        title=body.title.strip(),
        description=body.description,
        assigned_date=body.assigned_date,
        due_date=body.due_date,
        max_score=body.max_score,
        status="published",
        created_by=uuid.UUID(current.id),
    )
    session.add(item)
    session.commit()
    session.refresh(item)
    return assignment_json(item, session)

@app.put("/api/v1/school/assignments/{assignment_id}")
def update_assignment(
    assignment_id: uuid.UUID,
    body: AssignmentInput,
    current: Principal = Depends(require_module_roles("assignments", "superadmin", "admin", "teacher")),
    session: Session = Depends(db),
):
    _, database_id = module_tenant_scope(current, session)
    item = session.get(SchoolAssignment, assignment_id)
    if not item:
        raise HTTPException(404, "Devoir introuvable")
    if item.establishment_id != database_id:
        raise HTTPException(403, "Acces inter-etablissement interdit")
    ensure_class_module_access(
        current, session.get(SchoolClass, item.class_id), database_id, session
    )
    if current.role == "teacher" and item.teacher_id != uuid.UUID(current.teacher_id):
        raise HTTPException(403, "Devoir non attribue a cet enseignant")
    school_class = ensure_class_module_access(
        current, session.get(SchoolClass, body.class_id), database_id, session
    )
    subject = session.get(Subject, body.subject_id)
    if not subject or subject.establishment_id != database_id:
        raise HTTPException(422, "Matiere introuvable")
    item.class_id = school_class.id
    item.academic_year_id = school_class.academic_year_id
    item.subject_id = subject.id
    item.title = body.title.strip()
    item.description = body.description
    item.assigned_date = body.assigned_date
    item.due_date = body.due_date
    item.max_score = body.max_score
    item.updated_at = datetime.now(timezone.utc)
    session.commit()
    return assignment_json(item, session)

@app.delete("/api/v1/school/assignments/{assignment_id}", status_code=204)
def archive_assignment(
    assignment_id: uuid.UUID,
    current: Principal = Depends(require_module_roles("assignments", "superadmin", "admin", "teacher")),
    session: Session = Depends(db),
):
    _, database_id = module_tenant_scope(current, session)
    item = session.get(SchoolAssignment, assignment_id)
    if not item:
        raise HTTPException(404, "Devoir introuvable")
    if item.establishment_id != database_id:
        raise HTTPException(403, "Acces inter-etablissement interdit")
    ensure_class_module_access(
        current, session.get(SchoolClass, item.class_id), database_id, session
    )
    if current.role == "teacher" and item.teacher_id != uuid.UUID(current.teacher_id):
        raise HTTPException(403, "Devoir non attribue a cet enseignant")
    item.status = "archived"
    item.updated_at = datetime.now(timezone.utc)
    session.commit()
    return Response(status_code=status.HTTP_204_NO_CONTENT)

@app.get("/api/v1/school/schedule")
def list_schedule(
    academic_year_id: uuid.UUID,
    class_id: uuid.UUID | None = None,
    current: Principal = Depends(require_module_roles(
        "schedule", "superadmin", "admin", "teacher", "student", "parent"
    )),
    session: Session = Depends(db),
):
    _, database_id = module_tenant_scope(current, session)
    statement = select(ScheduleEntry).where(
        ScheduleEntry.establishment_id == database_id,
        ScheduleEntry.academic_year_id == academic_year_id,
        ScheduleEntry.status == "active",
    )
    allowed = direction_cycle_scope(current)
    if allowed is not None:
        statement = statement.where(ScheduleEntry.class_id.in_(
            select(SchoolClass.id).where(SchoolClass.cycle_id.in_(allowed))
        ))
    if class_id:
        ensure_class_module_access(current, session.get(SchoolClass, class_id), database_id, session)
        statement = statement.where(ScheduleEntry.class_id == class_id)
    if current.role == "teacher":
        teacher_id = uuid.UUID(current.teacher_id)
        statement = statement.where(
            ScheduleEntry.teacher_id == teacher_id,
            ScheduleEntry.affectation_id.in_(
                select(Affectation.id).where(
                    Affectation.establishment_id == database_id,
                    Affectation.teacher_id == teacher_id,
                    Affectation.status == "active",
                )
            ),
        )
    elif current.role == "student":
        if not current.student_id:
            raise HTTPException(403, "Profil élève non associé")
        student_id = uuid.UUID(current.student_id)
        own_class_ids = select(StudentAcademicRegistration.class_id).where(
            StudentAcademicRegistration.student_id == student_id,
            StudentAcademicRegistration.academic_year_id == academic_year_id,
            StudentAcademicRegistration.status.in_(("pending", "validated", "active")),
        )
        if class_id and not session.scalar(select(StudentAcademicRegistration.id).where(
            StudentAcademicRegistration.student_id == student_id,
            StudentAcademicRegistration.academic_year_id == academic_year_id,
            StudentAcademicRegistration.class_id == class_id,
            StudentAcademicRegistration.status.in_(("pending", "validated", "active")),
        )):
            raise HTTPException(403, "Cette classe n’appartient pas à l’élève connecté")
        statement = statement.where(ScheduleEntry.class_id.in_(own_class_ids))
    elif current.role == "parent":
        guardian = session.scalar(select(Guardian).where(
            Guardian.user_id == uuid.UUID(current.id),
            Guardian.establishment_id == database_id,
        ))
        if not guardian:
            return []
        child_ids = select(StudentGuardian.student_id).where(
            StudentGuardian.guardian_id == guardian.id,
            StudentGuardian.establishment_id == database_id,
        )
        own_class_ids = select(StudentAcademicRegistration.class_id).where(
            StudentAcademicRegistration.student_id.in_(child_ids),
            StudentAcademicRegistration.academic_year_id == academic_year_id,
            StudentAcademicRegistration.status.in_(("pending", "validated", "active")),
        )
        if class_id and not session.scalar(select(StudentAcademicRegistration.id).where(
            StudentAcademicRegistration.student_id.in_(child_ids),
            StudentAcademicRegistration.academic_year_id == academic_year_id,
            StudentAcademicRegistration.class_id == class_id,
            StudentAcademicRegistration.status.in_(("pending", "validated", "active")),
        )):
            raise HTTPException(403, "Cette classe n’appartient pas à un enfant lié")
        statement = statement.where(ScheduleEntry.class_id.in_(own_class_ids))
    return [schedule_json(item, session) for item in session.scalars(
        statement.order_by(ScheduleEntry.weekday, ScheduleEntry.start_time)
    ).all()]

@app.post("/api/v1/school/schedule", status_code=201)
def create_schedule_entry(
    body: ScheduleEntryInput,
    current: Principal = Depends(require_module_roles("schedule", "superadmin", "admin")),
    session: Session = Depends(db),
):
    _, database_id = module_tenant_scope(current, session)
    school_class = ensure_class_module_access(
        current, session.get(SchoolClass, body.class_id), database_id, session
    )
    subject = session.get(Subject, body.subject_id)
    teacher = session.get(Teacher, body.teacher_id)
    if not subject or not teacher:
        raise HTTPException(422, "Matiere ou enseignant introuvable")
    if subject.establishment_id != database_id or teacher.establishment_id != database_id:
        raise HTTPException(403, "Reference inter-etablissement interdite")
    affectation = session.scalar(select(Affectation).where(
        Affectation.establishment_id == database_id,
        Affectation.class_id == school_class.id,
        Affectation.subject_id == subject.id,
        Affectation.teacher_id == teacher.id,
        Affectation.status == "active",
    ))
    if not affectation:
        raise HTTPException(422, "Affectation enseignant/matiere/classe requise")
    calendar = session.scalar(select(SchoolCalendarSetting).where(
        SchoolCalendarSetting.establishment_id == database_id,
        SchoolCalendarSetting.academic_year_id == school_class.academic_year_id,
        SchoolCalendarSetting.status == 'active'))
    if calendar:
        if body.weekday not in calendar.teaching_days:
            raise HTTPException(422, 'Ce jour ne fait pas partie des jours de cours configures')
        if body.start_time < calendar.day_start or body.end_time > calendar.day_end:
            raise HTTPException(422, 'Le cours est hors des horaires configures')
    overlap = session.scalar(select(ScheduleEntry).where(
        ScheduleEntry.establishment_id == database_id,
        ScheduleEntry.academic_year_id == school_class.academic_year_id,
        ScheduleEntry.weekday == body.weekday,
        ScheduleEntry.status == 'active',
        ScheduleEntry.start_time < body.end_time,
        ScheduleEntry.end_time > body.start_time,
        (ScheduleEntry.teacher_id == teacher.id) | (ScheduleEntry.class_id == school_class.id),
    ))
    if overlap:
        if overlap.teacher_id == teacher.id:
            raise HTTPException(409, 'Conflit enseignant sur ce creneau')
        raise HTTPException(409, 'Cette classe possede deja un cours sur ce creneau')
    item = ScheduleEntry(
        establishment_id=database_id,
        academic_year_id=school_class.academic_year_id,
        class_id=school_class.id,
        subject_id=subject.id,
        teacher_id=teacher.id,
        affectation_id=affectation.id,
        weekday=body.weekday,
        start_time=body.start_time,
        end_time=body.end_time,
        room=None,
        status="active",
        created_by=uuid.UUID(current.id),
    )
    from .attendance import snapshot
    item.attendance_context = snapshot(session, item)
    session.add(item)
    try:
        session.commit()
    except IntegrityError as exc:
        session.rollback()
        raise HTTPException(409, "Conflit d'emploi du temps") from exc
    session.refresh(item)
    return schedule_json(item, session)

@app.delete("/api/v1/school/schedule/{entry_id}", status_code=204)
def archive_schedule_entry(
    entry_id: uuid.UUID,
    current: Principal = Depends(require_module_roles("schedule", "superadmin", "admin")),
    session: Session = Depends(db),
):
    from .attendance import lock_schedule
    lock_schedule(session, entry_id)
    _, database_id = module_tenant_scope(current, session)
    item = session.get(ScheduleEntry, entry_id)
    if not item:
        raise HTTPException(404, "Cours introuvable")
    if item.establishment_id != database_id:
        raise HTTPException(403, "Acces inter-etablissement interdit")
    ensure_class_module_access(
        current, session.get(SchoolClass, item.class_id), database_id, session
    )
    item.status = "archived"
    item.retired_at = datetime.now(timezone.utc)
    item.updated_at = datetime.now(timezone.utc)
    session.commit()
    return Response(status_code=status.HTTP_204_NO_CONTENT)

@app.get("/api/v1/school/organization-summary")
def school_organization_summary(
    academic_year_id: uuid.UUID | None = None,
    current: Principal = Depends(require("admin")),
    session: Session = Depends(db),
):
    _, database_id = school_scope(current, session, None, required=True)
    active_year = session.scalar(
        select(AcademicYear).where(
            AcademicYear.establishment_id == database_id,
            AcademicYear.is_active.is_(True),
        )
    )
    selected_year = session.get(AcademicYear, academic_year_id) if academic_year_id else active_year
    if selected_year and selected_year.establishment_id != database_id:
        raise HTTPException(403, "Année scolaire inter-établissement interdite")
    class_count = 0
    student_count = 0
    attendance_rate = None
    overall_average = None
    assignment_count = 0
    ready_results = []
    allowed = direction_cycle_scope(current)
    selected_class_ids: set[uuid.UUID] = set()
    if selected_year:
        class_scope = select(SchoolClass.id).where(
            SchoolClass.establishment_id == database_id,
            SchoolClass.academic_year_id == selected_year.id,
        )
        if allowed is not None:
            class_scope = class_scope.where(SchoolClass.cycle_id.in_(allowed))
        selected_class_ids = set(session.scalars(class_scope).all())
        class_count = len(selected_class_ids)
        student_count = session.scalar(
            select(func.count(func.distinct(StudentAcademicRegistration.student_id)))
            .where(
                StudentAcademicRegistration.establishment_id == database_id,
                StudentAcademicRegistration.academic_year_id == selected_year.id,
                StudentAcademicRegistration.status.in_(("pending", "validated", "active")),
                StudentAcademicRegistration.class_id.in_(selected_class_ids),
            )
        )
        attendance_rows = session.scalars(select(AttendanceRecord).join(
            AttendanceSheet, AttendanceSheet.id == AttendanceRecord.sheet_id).where(
            AttendanceSheet.status == "locked",
            AttendanceRecord.establishment_id == database_id,
            AttendanceRecord.academic_year_id == selected_year.id,
            AttendanceRecord.class_id.in_(selected_class_ids),
        )).all()
        if attendance_rows:
            present_equivalent = sum(
                1 if item.status == "present" else 0.5 if item.status == "late" else 0
                for item in attendance_rows
            )
            attendance_rate = round(100 * present_equivalent / len(attendance_rows), 2)
        official_averages = []
        for calculation in session.scalars(select(ResultCalculation).where(
            ResultCalculation.establishment_id == database_id,
            ResultCalculation.academic_year_id == selected_year.id,
            ResultCalculation.status == "official",
            ResultCalculation.class_id.in_(selected_class_ids),
        )).all():
            result_class = session.get(SchoolClass, calculation.class_id)
            result_period = session.get(
                AcademicPeriod, calculation.academic_period_id
            )
            if not result_class or not result_period:
                continue
            source_updated_at = _result_source_updated_at(
                session, database_id, result_class, result_period
            )
            snapshot_source = calculation.source_updated_at
            if snapshot_source.tzinfo is None:
                snapshot_source = snapshot_source.replace(tzinfo=timezone.utc)
            if source_updated_at > snapshot_source:
                continue
            official_averages.extend(
                float(item["average"])
                for item in calculation.payload.get("students", [])
                if item.get("average") is not None
            )
        if official_averages:
            overall_average = round(
                sum(official_averages) / len(official_averages), 2
            )
        assignment_count = session.scalar(select(func.count()).select_from(
            SchoolAssignment
        ).where(
            SchoolAssignment.establishment_id == database_id,
            SchoolAssignment.academic_year_id == selected_year.id,
            SchoolAssignment.status != "archived",
            SchoolAssignment.class_id.in_(selected_class_ids),
        ))
        ready_results = [
            dict(item.payload)
            for item in session.scalars(select(Resource).where(
                Resource.kind == "notifications",
                Resource.establishment_id == database_id,
            )).all()
            if item.payload.get("type") == "results_ready"
            and item.payload.get("readyForCalculation") is True
            and str(item.payload.get("classId")) in {
                str(class_id) for class_id in selected_class_ids
            }
        ]
    cycle_query = select(func.count()).select_from(SchoolCycle).where(
        SchoolCycle.establishment_id == database_id,
        SchoolCycle.status == "active",
    )
    if allowed is not None:
        cycle_query = cycle_query.where(SchoolCycle.id.in_(allowed))
    cycle_count = session.scalar(cycle_query)
    if allowed is None:
        teacher_count = session.scalar(select(func.count()).select_from(Teacher).where(
            Teacher.establishment_id == database_id,
            Teacher.status == "active",
        ))
        subject_count = session.scalar(select(func.count()).select_from(Subject).where(
            Subject.establishment_id == database_id,
            Subject.status == "active",
        ))
    else:
        teacher_count = session.scalar(select(func.count(func.distinct(Affectation.teacher_id))).join(
            SchoolClass, SchoolClass.id == Affectation.class_id
        ).where(
            Affectation.establishment_id == database_id,
            Affectation.status == "active",
            SchoolClass.cycle_id.in_(allowed),
        ))
        subject_count = session.scalar(select(func.count(func.distinct(Affectation.subject_id))).join(
            SchoolClass, SchoolClass.id == Affectation.class_id
        ).where(
            Affectation.establishment_id == database_id,
            Affectation.status == "active",
            SchoolClass.cycle_id.in_(allowed),
        ))
    return {
        "activeAcademicYear": academic_year_json(active_year, session) if active_year else None,
        "selectedAcademicYear": academic_year_json(selected_year, session) if selected_year else None,
        "activeCycleCount": cycle_count,
        "classCount": class_count,
        "studentCount": student_count,
        "teacherCount": teacher_count,
        "subjectCount": subject_count,
        "assignmentCount": assignment_count,
        "attendanceRate": attendance_rate,
        "overallAverage": overall_average,
        "readyResults": ready_results,
        "direction": {
            "id": current.direction_id,
            "name": current.direction_name,
            "legacyScope": current.legacy_direction_scope,
        },
    }
@app.post("/api/v1/users", status_code=201)
def create_user(body: UserCreateInput, current: Principal = Depends(require("superadmin", "admin")), session: Session = Depends(db)):
    user, initial_password = create_user_record(body, current, session)
    return {**user_json(user, session), "initialPassword": initial_password}

def admin_establishment_record(current: Principal, session: Session) -> tuple[Resource, Establishment]:
    row = session.get(Resource, {"kind": "establishments", "id": current.school_id})
    user = session.get(User, uuid.UUID(current.id))
    if not row or not user or not user.school_id:
        raise HTTPException(404, "Établissement introuvable")
    try:
        database_id = uuid.UUID(str(row.payload.get("databaseId")))
    except (TypeError, ValueError) as exc:
        raise HTTPException(409, "Relation établissement invalide") from exc
    if database_id != user.school_id:
        raise HTTPException(403, "Accès inter-établissement interdit")
    establishment = session.get(Establishment, database_id)
    if not establishment:
        raise HTTPException(409, "Relation établissement invalide")
    return row, establishment

def active_establishment_cycles(establishment_id: uuid.UUID, session: Session) -> list[SchoolCycle]:
    return list(session.scalars(
        select(SchoolCycle).where(
            SchoolCycle.establishment_id == establishment_id,
            SchoolCycle.status == "active",
        ).order_by(SchoolCycle.sort_order, SchoolCycle.name)
    ).all())


def admin_establishment_json(row: Resource, establishment: Establishment, session: Session) -> dict[str, Any]:
    return {
        "id": row.id,
        "name": establishment.name,
        "type": establishment.type_label or row.payload.get("type") or establishment.institution_type,
        "institutionType": establishment.institution_type,
        "address": establishment.address if establishment.address is not None else row.payload.get("address"),
        "city": establishment.city,
        "country": establishment.country if establishment.country is not None else row.payload.get("country"),
        "phone": establishment.phone if establishment.phone is not None else row.payload.get("phone"),
        "email": establishment.email if establishment.email is not None else row.payload.get("email"),
        "status": establishment.status,
        "enabledModules": list(establishment.enabled_modules or []),
        "cycles": [
            cycle_json(cycle, session)
            for cycle in active_establishment_cycles(establishment.id, session)
        ],
        "plan": row.payload.get("plan"),
        "date": str(row.payload.get("date") or establishment.created_at.date()),
        "createdAt": establishment.created_at.isoformat(),
    }

@app.get("/api/v1/admin/establishment")
def admin_establishment(current: Principal = Depends(require("admin")), session: Session = Depends(db)):
    row, establishment = admin_establishment_record(current, session)
    return admin_establishment_json(row, establishment, session)

@app.put("/api/v1/admin/establishment")
def update_admin_establishment(body: AdminEstablishmentUpdateInput, current: Principal = Depends(require("admin")), session: Session = Depends(db)):
    if not body.model_fields_set:
        raise HTTPException(422, "Aucun champ à modifier")
    row, establishment = admin_establishment_record(current, session)
    changes = body.model_dump(include=body.model_fields_set)
    payload = dict(row.payload)
    for field, value in changes.items():
        setattr(establishment, field, value)
        payload[field] = value
    establishment.updated_at = datetime.now(timezone.utc)
    row.payload = payload
    session.commit()
    session.refresh(establishment)
    return admin_establishment_json(row, establishment, session)

def superadmin_establishment_json(resource: Resource, session: Session) -> dict[str, Any]:
    payload = dict(resource.payload)
    database_id = payload.get("databaseId")
    establishment = None
    try:
        establishment = session.get(Establishment, uuid.UUID(str(database_id))) if database_id else None
    except ValueError:
        pass
    administrator = session.scalar(
        select(User).where(User.school_id == establishment.id, User.role == "admin").order_by(User.created_at)
    ) if establishment else None
    subscription = session.get(Resource, {"kind": "subscriptions", "id": f"SUB_{resource.id}"})
    administrator_payload = payload.get("administrator") if isinstance(payload.get("administrator"), dict) else {}
    if establishment:
        payload.update({
            "name": establishment.name,
            "institutionType": establishment.institution_type,
            "type": establishment.type_label or payload.get("type") or establishment.institution_type,
            "address": establishment.address if establishment.address is not None else payload.get("address"),
            "city": establishment.city,
            "country": establishment.country if establishment.country is not None else payload.get("country"),
            "phone": establishment.phone if establishment.phone is not None else payload.get("phone"),
            "email": establishment.email if establishment.email is not None else payload.get("email"),
            "status": establishment.status,
            "enabledModules": list(establishment.enabled_modules or []),
            "cycles": [
                cycle_json(cycle, session)
                for cycle in active_establishment_cycles(establishment.id, session)
            ],
            "createdAt": establishment.created_at.isoformat(),
        })
    else:
        payload["createdAt"] = resource.created_at.isoformat()
        payload["cycles"] = []
    payload["administrator"] = ({
        **user_json(administrator, session),
        "phone": administrator_payload.get("phone"),
        "createdAt": administrator.created_at.isoformat(),
    } if administrator else None)
    payload["subscription"] = ({
        **dict(subscription.payload),
        "status": canonical_subscription_status(subscription.payload),
    } if subscription else None)
    plan = plan_by_name(session, str(payload.get("plan") or ""))
    payload["planFeatures"] = list(plan.payload.get("features") or []) if plan else []
    labels = dict(MODULE_CATALOG)
    payload["planFeatureLabels"] = [
        labels[module_id]
        for module_id in payload["planFeatures"]
        if module_id in labels
    ]
    payload["enabledModuleLabels"] = [
        labels[module_id]
        for module_id in payload.get("enabledModules", [])
        if module_id in labels
    ]
    return payload

def valid_establishment_resource(resource: Resource, session: Session) -> bool:
    try:
        return session.get(Establishment, uuid.UUID(str(resource.payload.get("databaseId")))) is not None
    except (TypeError, ValueError):
        return False

def subscription_establishment_status(subscription: Resource, session: Session) -> str:
    school = session.get(Resource, {"kind": "establishments", "id": subscription.school_id})
    if not school:
        return "unknown"
    try:
        establishment = session.get(Establishment, uuid.UUID(str(school.payload.get("databaseId"))))
    except (TypeError, ValueError):
        establishment = None
    return establishment.status if establishment else "unknown"

def subscription_amount(payload: dict[str, Any]) -> int:
    digits = "".join(character for character in str(payload.get("price") or "0") if character.isdigit())
    return int(digits or "0")

def canonical_subscription_status(payload: dict[str, Any]) -> str:
    status_value = str(payload.get("status") or "").lower()
    today = date.today()
    try:
        start_date = date.fromisoformat(str(payload.get("startDate")))
        end_date = date.fromisoformat(str(payload.get("endDate")))
    except (TypeError, ValueError):
        return "overdue" if status_value == "past_due" else status_value
    if status_value in {"cancelled", "suspended"}:
        return status_value
    if end_date < today:
        return "expired"
    if start_date > today:
        return "upcoming"
    if status_value in {"overdue", "past_due"}:
        return "overdue"
    return "active"

def subscription_days_remaining(payload: dict[str, Any]) -> int | None:
    try:
        end_date = date.fromisoformat(str(payload.get("endDate")))
    except (TypeError, ValueError):
        return None
    return max(0, (end_date - date.today()).days)

def plan_by_name(session: Session, name: str) -> Resource | None:
    normalized = name.strip().lower()
    return next((
        row for row in session.scalars(select(Resource).where(Resource.kind == "plans"))
        if str(row.payload.get("name") or "").strip().lower() == normalized
    ), None)

def ensure_plan_capability(
    current: Principal, session: Session, capability: str,
    *, offer: str = "Professionnel",
) -> None:
    """Enforce configured plan capabilities while preserving legacy plans."""
    if current.role == "superadmin":
        return
    establishment_resource = session.get(
        Resource, {"kind": "establishments", "id": current.school_id}
    ) if current.school_id else None
    if establishment_resource is None:
        user = session.get(User, uuid.UUID(current.id))
        if user and user.school_id:
            establishment_resource = session.scalar(select(Resource).where(
                Resource.kind == "establishments",
                Resource.establishment_id == user.school_id,
            ))
    plan = plan_by_name(
        session, str(establishment_resource.payload.get("plan") or "")
    ) if establishment_resource else None
    limits = dict(plan.payload.get("limits") or {}) if plan else {}
    # Plans created before capability granularity remain compatible until the
    # Super Admin explicitly saves their detailed configuration.
    if not limits.get("capabilitiesConfigured"):
        return
    if capability not in set(limits.get("capabilities") or []):
        raise HTTPException(
            403,
            f"Cette fonctionnalité est disponible dans le forfait {offer}. Changez de forfait pour l’activer.",
        )

def subscriptions_for_plan(session: Session, plan_name: str) -> list[Resource]:
    normalized = plan_name.strip().lower()
    return [
        row for row in session.scalars(select(Resource).where(Resource.kind == "subscriptions"))
        if str(row.payload.get("plan") or "").strip().lower() == normalized
    ]

def plan_json(row: Resource, session: Session, include_subscriptions: bool = False) -> dict[str, Any]:
    payload = dict(row.payload)
    subscriptions = subscriptions_for_plan(session, str(payload.get("name") or ""))
    data = {
        **payload,
        "id": row.id,
        "subscriptionCount": len(subscriptions),
        "createdAt": row.created_at.isoformat(),
        "updatedAt": row.updated_at.isoformat(),
    }
    if include_subscriptions:
        data["subscriptions"] = [{
            "id": item.id,
            "schoolId": item.school_id,
            "establishment": item.payload.get("client"),
            "status": canonical_subscription_status(item.payload),
            "price": item.payload.get("price"),
            "startDate": item.payload.get("startDate"),
            "endDate": item.payload.get("endDate"),
        } for item in subscriptions]
    return data

def subscription_summary(subscriptions: list[Resource]) -> dict[str, int]:
    statuses = [canonical_subscription_status(row.payload) for row in subscriptions]
    active = [row for row in subscriptions if canonical_subscription_status(row.payload) == "active"]
    active_amount = sum(subscription_amount(row.payload) for row in active)
    return {
        "total": len(subscriptions),
        "active": len(active),
        "upcoming": statuses.count("upcoming"),
        "overdue": statuses.count("overdue"),
        "expired": statuses.count("expired"),
        "activeAmountTotal": active_amount,
        # Compatibility keys retained for the already validated subscriptions page.
        "pastDue": statuses.count("overdue"),
        "activeAmount": active_amount,
    }

def recent_valid_establishments(session: Session, limit: int = 5) -> list[dict[str, Any]]:
    items: list[tuple[Establishment, Resource]] = []
    seen: set[uuid.UUID] = set()
    resources = session.scalars(select(Resource).where(Resource.kind == "establishments")).all()
    for resource in resources:
        try:
            establishment_id = uuid.UUID(str(resource.payload.get("databaseId")))
        except (TypeError, ValueError):
            continue
        establishment = session.get(Establishment, establishment_id)
        if not establishment or establishment.id in seen:
            continue
        seen.add(establishment.id)
        items.append((establishment, resource))
    items.sort(key=lambda item: item[0].created_at, reverse=True)
    return [{
        "id": resource.id,
        "name": establishment.name,
        "status": establishment.status,
        "createdAt": establishment.created_at.isoformat(),
        "type": establishment.type_label or resource.payload.get("type") or establishment.institution_type,
        "city": establishment.city,
        "plan": resource.payload.get("plan"),
    } for establishment, resource in items[:limit]]

def _platform_monthly_counts(
    rows: list[Any],
    date_getter,
    *,
    months: int = 12,
) -> list[dict[str, Any]]:
    now = datetime.now(timezone.utc)
    year = now.year
    month = now.month
    keys: list[str] = []
    for offset in range(months - 1, -1, -1):
        absolute = year * 12 + (month - 1) - offset
        y, m = divmod(absolute, 12)
        keys.append(f"{y:04d}-{m + 1:02d}")
    counts = {key: 0 for key in keys}
    for row in rows:
        value = date_getter(row)
        if value is None:
            continue
        if isinstance(value, date) and not isinstance(value, datetime):
            dt = datetime.combine(value, dt_time.min, tzinfo=timezone.utc)
        elif isinstance(value, datetime):
            dt = value if value.tzinfo else value.replace(tzinfo=timezone.utc)
        else:
            try:
                parsed = datetime.fromisoformat(str(value).replace("Z", "+00:00"))
            except (TypeError, ValueError):
                continue
            dt = parsed if parsed.tzinfo else parsed.replace(tzinfo=timezone.utc)
        key = dt.strftime("%Y-%m")
        if key in counts:
            counts[key] += 1
    return [{"month": key, "count": counts[key]} for key in keys]


@app.get("/api/v1/superadmin/dashboard")
def superadmin_dashboard(current: Principal = Depends(require("superadmin")), session: Session = Depends(db)):
    establishments = list(session.scalars(select(Establishment)).all())
    subscriptions = list(session.scalars(select(Resource).where(Resource.kind == "subscriptions")).all())
    users = list(session.scalars(select(User)).all())
    plans = list(session.scalars(select(Resource).where(Resource.kind == "plans")).all())
    subscriptions_summary = subscription_summary(subscriptions)
    user_roles = {
        role: sum(item.role == role and item.status == "active" for item in users)
        for role in ("admin", "teacher", "student", "parent")
    }
    status_distribution = [
        {"label": "Actifs", "count": subscriptions_summary["active"]},
        {"label": "À venir", "count": subscriptions_summary["upcoming"]},
        {"label": "En retard", "count": subscriptions_summary["overdue"]},
        {"label": "Expirés", "count": subscriptions_summary["expired"]},
    ]
    plan_distribution: dict[str, int] = {}
    for row in subscriptions:
        plan = str(
            row.payload.get("planName")
            or row.payload.get("plan")
            or row.payload.get("planId")
            or "Non renseigné"
        )
        plan_distribution[plan] = plan_distribution.get(plan, 0) + 1
    return {
        "generatedAt": datetime.now(timezone.utc).isoformat(),
        "privacyScope": "platform-only",
        "establishments": {
            "total": len(establishments),
            "active": sum(item.status == "active" for item in establishments),
            "suspended": sum(item.status == "suspended" for item in establishments),
            "recent": recent_valid_establishments(session),
            "trend": _platform_monthly_counts(
                establishments, lambda item: item.created_at
            ),
        },
        "subscriptions": {
            key: subscriptions_summary[key]
            for key in ("total", "active", "upcoming", "overdue", "expired", "activeAmountTotal")
        } | {
            "trend": _platform_monthly_counts(
                subscriptions, lambda item: item.created_at
            ),
            "statusDistribution": status_distribution,
            "planDistribution": [
                {"label": key, "count": value}
                for key, value in sorted(plan_distribution.items())
            ],
        },
        "users": {
            "total": len(users),
            "admins": user_roles["admin"],
            "teachers": user_roles["teacher"],
            "students": user_roles["student"],
            "parents": user_roles["parent"],
            "trend": _platform_monthly_counts(users, lambda item: item.created_at),
            "distribution": [
                {"label": "Administrateurs", "count": user_roles["admin"]},
                {"label": "Enseignants", "count": user_roles["teacher"]},
                {"label": "Élèves", "count": user_roles["student"]},
                {"label": "Parents", "count": user_roles["parent"]},
            ],
        },
        "plans": {
            "total": len(plans),
        },
    }

@app.get("/api/v1/superadmin/establishments")
def superadmin_establishments(
    search: str | None = None,
    status_filter: str | None = None,
    institution_type: str | None = None,
    _: Principal = Depends(require("superadmin")),
    session: Session = Depends(db),
):
    rows = [row for row in session.scalars(select(Resource).where(Resource.kind == "establishments").order_by(Resource.created_at.desc())).all() if valid_establishment_resource(row, session)]
    data = [superadmin_establishment_json(row, session) for row in rows]
    if search:
        needle = search.lower()
        data = [item for item in data if any(needle in str(value or "").lower() for value in (
            item.get("name"), item.get("id"), item.get("city"), item.get("type"),
            (item.get("administrator") or {}).get("name"),
            (item.get("administrator") or {}).get("email"),
        ))]
    if status_filter:
        data = [item for item in data if item.get("status") == status_filter]
    if institution_type:
        data = [item for item in data if item.get("institutionType") == institution_type]
    return data

@app.get("/api/v1/superadmin/establishments/{resource_id}")
def superadmin_establishment_detail(resource_id: str, _: Principal = Depends(require("superadmin")), session: Session = Depends(db)):
    row = session.get(Resource, {"kind": "establishments", "id": resource_id})
    if not row:
        raise HTTPException(404, "Establishment not found")
    if not valid_establishment_resource(row, session):
        raise HTTPException(409, "Establishment database relation is invalid")
    return superadmin_establishment_json(row, session)

def direction_record(
    direction_id: uuid.UUID,
    session: Session,
) -> SchoolDirection:
    item = session.get(SchoolDirection, direction_id)
    if not item:
        raise HTTPException(404, "Direction introuvable")
    return item

def validate_direction_cycles(
    establishment_id: uuid.UUID,
    cycle_ids: list[uuid.UUID],
    session: Session,
    *,
    direction_id: uuid.UUID | None = None,
) -> list[SchoolCycle]:
    if len(cycle_ids) != len(set(cycle_ids)):
        raise HTTPException(422, "Un cycle ne peut pas etre selectionne plusieurs fois")
    cycles = list(session.scalars(select(SchoolCycle).where(
        SchoolCycle.id.in_(cycle_ids)
    )).all())
    if len(cycles) != len(cycle_ids):
        raise HTTPException(422, "Un ou plusieurs cycles sont introuvables")
    if any(cycle.establishment_id != establishment_id for cycle in cycles):
        raise HTTPException(403, "Un cycle appartient a un autre etablissement")
    if any(cycle.status != "active" for cycle in cycles):
        raise HTTPException(409, "Une direction ne peut utiliser qu'un cycle actif")
    occupied = session.scalar(select(SchoolDirectionCycle).where(
        SchoolDirectionCycle.cycle_id.in_(cycle_ids),
        SchoolDirectionCycle.establishment_id == establishment_id,
        *([SchoolDirectionCycle.direction_id != direction_id] if direction_id else []),
    ).limit(1))
    if occupied:
        raise HTTPException(409, "Un cycle selectionne appartient deja a une direction")
    return cycles

@app.get("/api/v1/superadmin/establishments/{resource_id}/directions")
def list_superadmin_directions(
    resource_id: str,
    _: Principal = Depends(require("superadmin")),
    session: Session = Depends(db),
):
    _, establishment = superadmin_establishment_record(resource_id, session)
    directions = list(session.scalars(select(SchoolDirection).where(
        SchoolDirection.establishment_id == establishment.id
    ).order_by(SchoolDirection.created_at)).all())
    unassigned = list(session.scalars(select(User).where(
        User.school_id == establishment.id,
        User.role == "admin",
        User.direction_id.is_(None),
    ).order_by(User.name)).all())
    administrators = list(session.scalars(select(User).where(
        User.school_id == establishment.id,
        User.role == "admin",
        User.status == "active",
    ).order_by(User.name)).all())
    establishment_class_ids = select(SchoolClass.id).where(
        SchoolClass.establishment_id == establishment.id,
        SchoolClass.status == "active",
    )
    establishment_statistics = {
        "classes": session.scalar(
            select(func.count()).select_from(SchoolClass).where(
                SchoolClass.establishment_id == establishment.id,
                SchoolClass.status == "active",
            )
        ) or 0,
        "students": session.scalar(
            select(func.count(func.distinct(StudentAcademicRegistration.student_id))).where(
                StudentAcademicRegistration.establishment_id == establishment.id,
                StudentAcademicRegistration.class_id.in_(establishment_class_ids),
                StudentAcademicRegistration.status.in_(("pending", "validated", "active")),
            )
        ) or 0,
        "teachers": session.scalar(
            select(func.count(func.distinct(Affectation.teacher_id))).where(
                Affectation.establishment_id == establishment.id,
                Affectation.class_id.in_(establishment_class_ids),
                Affectation.status == "active",
            )
        ) or 0,
    }
    return {
        "establishment": {
            "id": resource_id,
            "name": establishment.name,
            "statistics": establishment_statistics,
        },
        "directions": [direction_json(item, session) for item in directions],
        "unassignedAdministrators": [
            superadmin_user_json(user, session) for user in unassigned
        ],
        "administrators": [
            superadmin_user_json(user, session) for user in administrators
        ],
    }

@app.post("/api/v1/superadmin/establishments/{resource_id}/directions", status_code=201)
def create_superadmin_direction(
    resource_id: str,
    body: SchoolDirectionInput,
    _: Principal = Depends(require("superadmin")),
    session: Session = Depends(db),
):
    _, establishment = superadmin_establishment_record(resource_id, session)
    cycles = validate_direction_cycles(establishment.id, body.cycle_ids, session)
    code = (body.code or f"DIRECTION_{uuid.uuid4().hex[:12]}").strip().upper()
    item = SchoolDirection(
        establishment_id=establishment.id,
        code=code,
        name=body.name.strip(),
        status=body.status,
    )
    session.add(item)
    session.flush()
    for cycle in cycles:
        session.add(SchoolDirectionCycle(
            direction_id=item.id,
            establishment_id=establishment.id,
            cycle_id=cycle.id,
        ))
    try:
        session.commit()
    except IntegrityError as exc:
        session.rollback()
        raise HTTPException(409, "Cette direction ou l'un de ses cycles est deja configure") from exc
    session.refresh(item)
    return direction_json(item, session)

@app.put("/api/v1/superadmin/directions/{direction_id}")
def update_superadmin_direction(
    direction_id: uuid.UUID,
    body: SchoolDirectionUpdateInput,
    _: Principal = Depends(require("superadmin")),
    session: Session = Depends(db),
):
    item = direction_record(direction_id, session)
    if not body.model_fields_set:
        raise HTTPException(422, "Aucune modification demandee")
    if body.cycle_ids is not None:
        cycles = validate_direction_cycles(
            item.establishment_id, body.cycle_ids, session,
            direction_id=item.id,
        )
        for link in list(session.scalars(select(SchoolDirectionCycle).where(
            SchoolDirectionCycle.direction_id == item.id
        )).all()):
            session.delete(link)
        session.flush()
        for cycle in cycles:
            session.add(SchoolDirectionCycle(
                direction_id=item.id,
                establishment_id=item.establishment_id,
                cycle_id=cycle.id,
            ))
    if body.name is not None:
        item.name = body.name.strip()
    if body.status is not None:
        item.status = body.status
    item.updated_at = datetime.now(timezone.utc)
    try:
        session.commit()
    except IntegrityError as exc:
        session.rollback()
        raise HTTPException(409, "Cette configuration de direction existe deja") from exc
    session.refresh(item)
    return direction_json(item, session)

@app.put("/api/v1/superadmin/directions/{direction_id}/administrator")
def assign_direction_administrator(
    direction_id: uuid.UUID,
    body: DirectionAdministratorInput,
    _: Principal = Depends(require("superadmin")),
    session: Session = Depends(db),
):
    direction = direction_record(direction_id, session)
    current_admin = session.scalar(select(User).where(
        User.direction_id == direction.id,
        User.role == "admin",
    ))
    if body.user_id is None:
        raise HTTPException(
            409,
            "Un administrateur actif doit toujours rester rattaché à une direction scolaire.",
        )
    administrator = session.get(User, body.user_id)
    if not administrator or administrator.role != "admin":
        raise HTTPException(422, "Administrateur scolaire introuvable")
    if administrator.school_id != direction.establishment_id:
        raise HTTPException(403, "Cet administrateur appartient a un autre etablissement")
    if current_admin and current_admin.id != administrator.id:
        source_direction_id = administrator.direction_id
        if source_direction_id is None:
            raise HTTPException(
                409,
                "Cette direction possède déjà un administrateur. Choisissez un compte déjà rattaché afin d’échanger les directions.",
            )
        current_admin.direction_id = None
        administrator.direction_id = None
        session.flush()
        current_admin.direction_id = source_direction_id
        current_admin.updated_at = datetime.now(timezone.utc)
    administrator.direction_id = direction.id
    administrator.updated_at = datetime.now(timezone.utc)
    try:
        session.commit()
    except IntegrityError as exc:
        session.rollback()
        raise HTTPException(409, "Cet administrateur ou cette direction est deja attribue") from exc
    session.refresh(direction)
    return direction_json(direction, session)

def superadmin_establishment_record(resource_id: str, session: Session) -> tuple[Resource, Establishment]:
    row = session.get(Resource, {"kind": "establishments", "id": resource_id})
    if not row:
        raise HTTPException(404, "Establishment not found")
    try:
        establishment = session.get(Establishment, uuid.UUID(str(row.payload.get("databaseId"))))
    except (TypeError, ValueError):
        establishment = None
    if not establishment:
        raise HTTPException(409, "Establishment database relation is invalid")
    return row, establishment

def establishment_modules_json(row: Resource, establishment: Establishment, session: Session) -> dict[str, Any]:
    plan = plan_by_name(session, str(row.payload.get("plan") or ""))
    return {
        "establishment": {
            "id": row.id,
            "name": establishment.name,
            "status": establishment.status,
        },
        "availableModules": [
            {"id": module_id, "label": label}
            for module_id, label in MODULE_CATALOG
        ],
        "currentPlan": ({
            "id": plan.id,
            "name": plan.payload.get("name"),
            "status": plan.payload.get("status"),
        } if plan else None),
        "planFeatures": list(plan.payload.get("features") or []) if plan else [],
        "enabledModules": list(establishment.enabled_modules or []),
    }

@app.get("/api/v1/superadmin/establishments/{resource_id}/modules")
def get_superadmin_establishment_modules(resource_id: str, _: Principal = Depends(require("superadmin")), session: Session = Depends(db)):
    row, establishment = superadmin_establishment_record(resource_id, session)
    return establishment_modules_json(row, establishment, session)

@app.put("/api/v1/superadmin/establishments/{resource_id}/modules")
def update_superadmin_establishment_modules(resource_id: str, body: EstablishmentModulesInput, _: Principal = Depends(require("superadmin")), session: Session = Depends(db)):
    row, establishment = superadmin_establishment_record(resource_id, session)
    modules = list(body.enabledModules)
    establishment.enabled_modules = modules
    establishment.updated_at = datetime.now(timezone.utc)
    session.commit()
    session.refresh(establishment)
    return establishment_modules_json(row, establishment, session)


def validate_establishment_cycle_selection(raw_cycles: Any) -> list[str]:
    if not isinstance(raw_cycles, list):
        raise HTTPException(422, "La liste des cycles est invalide")
    if any(not isinstance(code, str) or code not in CYCLE_CATALOG_BY_CODE for code in raw_cycles):
        raise HTTPException(422, "Un ou plusieurs cycles sont inconnus")
    if len(raw_cycles) != len(set(raw_cycles)):
        raise HTTPException(422, "Un cycle ne peut pas être sélectionné plusieurs fois")
    if not raw_cycles:
        raise HTTPException(422, "Au moins un cycle est obligatoire pour un établissement scolaire")
    selected = set(raw_cycles)
    return [code for code, _, _ in CYCLE_CATALOG if code in selected]


def cycle_has_dependencies(cycle: SchoolCycle, session: Session) -> bool:
    checks = (
        (SchoolLevel, SchoolLevel.cycle_id),
        (SchoolSeries, SchoolSeries.cycle_id),
        (SchoolClass, SchoolClass.cycle_id),
        (EvaluationRule, EvaluationRule.cycle_id),
        (Resource, Resource.cycle_id),
    )
    return any(
        bool(session.scalar(
            select(func.count()).select_from(model).where(column == cycle.id)
        ))
        for model, column in checks
    )


def reconcile_establishment_cycles(
    establishment: Establishment,
    desired_codes: list[str],
    session: Session,
) -> None:
    existing = {
        cycle.code: cycle
        for cycle in session.scalars(
            select(SchoolCycle).where(SchoolCycle.establishment_id == establishment.id)
        ).all()
    }
    desired = set(desired_codes)
    for code, cycle in existing.items():
        if code not in desired and cycle.status == "active":
            if cycle_has_dependencies(cycle, session):
                raise HTTPException(
                    409,
                    f"Le cycle {cycle.name} contient des données et ne peut pas être retiré",
                )
            cycle.status = "inactive"
            cycle.updated_at = datetime.now(timezone.utc)
    for code in desired_codes:
        catalog = CYCLE_CATALOG_BY_CODE[code]
        cycle = existing.get(code)
        if cycle:
            cycle.name = catalog["name"]
            cycle.sort_order = catalog["sortOrder"]
            cycle.status = "active"
            cycle.updated_at = datetime.now(timezone.utc)
        else:
            session.add(SchoolCycle(
                establishment_id=establishment.id,
                code=code,
                name=catalog["name"],
                status="active",
                sort_order=catalog["sortOrder"],
            ))


def default_initial_academic_year(today: date | None = None) -> str:
    current = today or date.today()
    start_year = current.year if current.month >= 9 else current.year - 1
    return f"{start_year}-{start_year + 1}"


def ensure_base_establishment_configuration(
    establishment: Establishment,
    selected_cycle_codes: list[str],
    academic_year_name: str,
    session: Session,
) -> dict[str, Any]:
    """Create only editable school reference data, without operational data."""
    start_year, end_year = (int(value) for value in academic_year_name.split("-"))
    if end_year != start_year + 1:
        raise HTTPException(422, "L’année scolaire doit suivre le format AAAA-AAAA+1")
    session.flush()

    cycles = {
        item.code: item for item in session.scalars(select(SchoolCycle).where(
            SchoolCycle.establishment_id == establishment.id,
            SchoolCycle.code.in_(selected_cycle_codes),
        )).all()
    }
    if set(cycles) != set(selected_cycle_codes):
        raise HTTPException(409, "La configuration initiale des cycles est incomplète")

    year = session.scalar(select(AcademicYear).where(
        AcademicYear.establishment_id == establishment.id,
        func.lower(AcademicYear.name) == academic_year_name.lower(),
    ))
    if year is None:
        year = AcademicYear(
            establishment_id=establishment.id,
            name=academic_year_name,
            start_date=date(start_year, 10, 1),
            end_date=date(end_year, 6, 30),
            is_active=True,
            status="active",
        )
        session.add(year)
        session.flush()

    period_specs = (
        ("T1", "1er trimestre", 1, date(start_year, 10, 1), date(start_year, 12, 31)),
        ("T2", "2e trimestre", 2, date(end_year, 1, 1), date(end_year, 3, 31)),
        ("T3", "3e trimestre", 3, date(end_year, 4, 1), date(end_year, 6, 30)),
    )
    periods = {
        item.code: item for item in session.scalars(select(AcademicPeriod).where(
            AcademicPeriod.establishment_id == establishment.id,
            AcademicPeriod.academic_year_id == year.id,
        )).all()
    }
    missing_periods = [AcademicPeriod(
        establishment_id=establishment.id,
        academic_year_id=year.id,
        code=code,
        name=name,
        period_type="trimester",
        sort_order=sort_order,
        start_date=start_date,
        end_date=end_date,
        status="active",
    ) for code, name, sort_order, start_date, end_date in period_specs
        if code not in periods]
    session.add_all(missing_periods)

    existing_levels = {
        (item.cycle_id, item.code.upper()): item
        for item in session.scalars(select(SchoolLevel).where(
            SchoolLevel.establishment_id == establishment.id,
        )).all()
    }
    missing_levels = []
    for cycle_code in selected_cycle_codes:
        cycle = cycles[cycle_code]
        for sort_order, (code, name) in enumerate(
            BASE_LEVEL_CATALOG[cycle_code], start=1
        ):
            if (cycle.id, code) not in existing_levels:
                level = SchoolLevel(
                    establishment_id=establishment.id,
                    cycle_id=cycle.id,
                    code=code,
                    name=name,
                    status="active",
                    sort_order=sort_order,
                )
                missing_levels.append(level)
                existing_levels[(cycle.id, code)] = level
    session.add_all(missing_levels)
    session.flush()

    series_by_code: dict[str, SchoolSeries] = {}
    if "LYCEE" in cycles:
        lycee = cycles["LYCEE"]
        series_by_code = {
            item.code.upper(): item
            for item in session.scalars(select(SchoolSeries).where(
                SchoolSeries.establishment_id == establishment.id,
                SchoolSeries.cycle_id == lycee.id,
                SchoolSeries.status != "archived",
            )).all()
        }
        missing_series = []
        for sort_order, (code, name) in enumerate(BASE_LYCEE_SERIES, start=1):
            if code not in series_by_code:
                series = SchoolSeries(
                    establishment_id=establishment.id,
                    cycle_id=lycee.id,
                    code=code,
                    name=name,
                    sort_order=sort_order,
                    status="active",
                )
                missing_series.append(series)
                series_by_code[code] = series
        session.add_all(missing_series)
        session.flush()

    subjects_by_code = {
        str(item.code or "").upper(): item
        for item in session.scalars(select(Subject).where(
            Subject.establishment_id == establishment.id,
        )).all()
        if item.code
    }
    missing_subjects = []
    preschool_codes = {code for code, _ in BASE_PRESCHOOL_DOMAINS}
    for code, name in BASE_SUBJECT_CATALOG:
        if code not in subjects_by_code:
            subject = Subject(
                establishment_id=establishment.id,
                code=code,
                name=name,
                description=(
                    "Domaine de compétence maternelle"
                    if code in preschool_codes else None
                ),
                status="active",
            )
            missing_subjects.append(subject)
            subjects_by_code[code] = subject
    session.add_all(missing_subjects)
    session.flush()

    subject_codes_by_cycle = {
        "MATERNELLE": tuple(code for code, _ in BASE_PRESCHOOL_DOMAINS),
        "PRIMAIRE": tuple(code for code, _ in BASE_PRIMARY_SUBJECTS),
        "COLLEGE": tuple(code for code, _ in BASE_GENERAL_SUBJECTS),
        "LYCEE": tuple(code for code, _ in BASE_GENERAL_SUBJECTS),
    }
    existing_settings = {
        (item.subject_id, item.school_level_id, item.series_id)
        for item in session.scalars(select(SubjectLevelSetting).where(
            SubjectLevelSetting.establishment_id == establishment.id,
            SubjectLevelSetting.academic_year_id == year.id,
            SubjectLevelSetting.status != "archived",
        )).all()
    }
    missing_settings = []
    for cycle_code in selected_cycle_codes:
        cycle = cycles[cycle_code]
        cycle_levels = [
            existing_levels[(cycle.id, code)]
            for code, _ in BASE_LEVEL_CATALOG[cycle_code]
        ]
        series_values = (
            list(series_by_code.values()) if cycle_code == "LYCEE" else [None]
        )
        grading_scale = 10 if cycle_code == "PRIMAIRE" else 20
        for level in cycle_levels:
            for subject_code in subject_codes_by_cycle[cycle_code]:
                subject = subjects_by_code[subject_code]
                for series in series_values:
                    key = (subject.id, level.id, series.id if series else None)
                    if key in existing_settings:
                        continue
                    missing_settings.append(SubjectLevelSetting(
                        establishment_id=establishment.id,
                        academic_year_id=year.id,
                        subject_id=subject.id,
                        school_level_id=level.id,
                        series_id=series.id if series else None,
                        coefficient=1 if cycle_code == "LYCEE" else None,
                        grading_scale=grading_scale,
                        contributes_to_average=True,
                        status="active",
                    ))
                    existing_settings.add(key)
    session.add_all(missing_settings)

    existing_rules = {
        (item.cycle_id, item.school_level_id, item.series_id,
         item.evaluation_type, item.label.casefold())
        for item in session.scalars(select(EvaluationRule).where(
            EvaluationRule.establishment_id == establishment.id,
            EvaluationRule.academic_year_id == year.id,
            EvaluationRule.status != "archived",
        )).all()
    }
    rule_specs: list[tuple[SchoolCycle, SchoolLevel | None, str, str, bool, bool, int]] = []
    for cycle_code in selected_cycle_codes:
        cycle = cycles[cycle_code]
        if cycle_code in {"COLLEGE", "LYCEE"}:
            rule_specs.extend((
                (cycle, None, "devoir", "Devoir 1", True, True, 10),
                (cycle, None, "devoir", "Devoir 2", True, True, 20),
            ))
        rule_specs.append(
            (cycle, None, "composition", "Composition", True, True, 30)
        )
    exam_specs = {
        "PRIMAIRE": ("CM2", (("test", "CEPE Test"), ("exam_blanc", "CEPE Blanc"))),
        "COLLEGE": ("3E", (("test", "BEPC Test"), ("exam_blanc", "BEPC Blanc"))),
        "LYCEE": ("TERMINALE", (("test", "BAC Test"), ("exam_blanc", "BAC Blanc"))),
    }
    for cycle_code, (level_code, exams) in exam_specs.items():
        if cycle_code not in cycles:
            continue
        cycle = cycles[cycle_code]
        level = existing_levels[(cycle.id, level_code)]
        for sort_order, (evaluation_type, label) in enumerate(exams, start=40):
            rule_specs.append(
                (cycle, level, evaluation_type, label, False, False, sort_order)
            )
    missing_rules = []
    for cycle, level, evaluation_type, label, contributes, required, sort_order in rule_specs:
        key = (cycle.id, level.id if level else None, None,
               evaluation_type, label.casefold())
        if key in existing_rules:
            continue
        missing_rules.append(EvaluationRule(
            establishment_id=establishment.id,
            academic_year_id=year.id,
            cycle_id=cycle.id,
            school_level_id=level.id if level else None,
            series_id=None,
            evaluation_type=evaluation_type,
            label=label,
            expected_count=1,
            contributes_to_average=contributes,
            is_required=required,
            sort_order=sort_order,
            status="active",
        ))
        existing_rules.add(key)
    session.add_all(missing_rules)
    session.flush()
    return {
        "academicYear": academic_year_name,
        "periodCount": 3,
        "levelCount": len(existing_levels),
        "seriesCount": len(series_by_code),
        "subjectCount": len(subjects_by_code),
        "gradingSettingCount": len(existing_settings),
        "evaluationTypeCount": len(existing_rules),
    }


@app.post("/api/v1/superadmin/establishments", status_code=201)
def create_superadmin_establishment(body: SuperAdminEstablishmentCreateInput, _: Principal = Depends(require("superadmin")), session: Session = Depends(db)):
    normalized_email = body.admin_email.lower().strip()
    establishment_code = normalized_establishment_code(body.code)
    lock_establishment_code(session, establishment_code)
    ensure_establishment_code_available(session, establishment_code)
    catalog_plan = plan_by_name(session, body.plan)
    if not catalog_plan:
        raise HTTPException(422, "Plan introuvable")
    if catalog_plan and catalog_plan.payload.get("status") != "active":
        raise HTTPException(409, "Ce plan est inactif et ne peut pas être utilisé pour une nouvelle souscription")
    resource_id = body.id or f"school_{secrets.token_hex(6)}"
    while session.get(Resource, {"kind": "establishments", "id": resource_id}):
        if body.id:
            raise HTTPException(409, "Establishment identifier already used")
        resource_id = f"school_{secrets.token_hex(6)}"
    if session.scalar(select(Establishment).where(func.lower(Establishment.name) == body.name.lower().strip())):
        raise HTTPException(409, "Establishment name already used")
    if session.scalar(select(User).where(func.lower(User.email) == normalized_email)):
        raise HTTPException(409, "Administrator email already used")

    now = datetime.now(timezone.utc)
    duration_days = int(catalog_plan.payload.get("durationDays"))
    end_date = (now + timedelta(days=duration_days)).date().isoformat()
    plan_name = str(catalog_plan.payload.get("name"))
    plan_price = str(catalog_plan.payload.get("price"))
    plan_features = list(catalog_plan.payload.get("features") or [])
    if len(plan_features) != len(set(plan_features)) or set(plan_features) - MODULE_IDS:
        raise HTTPException(409, "Le plan contient des fonctionnalités invalides")
    initial_modules = [
        module_id for module_id, _ in MODULE_CATALOG
        if module_id in set(plan_features)
    ]
    establishment = Establishment(
        name=body.name.strip(), institution_type="school", type_label="Établissement scolaire",
        city=body.city.strip(), country=body.country.strip(), phone=body.phone,
        email=body.email, status="active",
        enabled_modules=initial_modules,
    )
    session.add(establishment)
    session.flush()
    reconcile_establishment_cycles(establishment, list(body.cycles), session)
    initial_configuration = None
    if body.use_base_configuration:
        try:
            initial_configuration = ensure_base_establishment_configuration(
                establishment,
                list(body.cycles),
                body.initial_academic_year or default_initial_academic_year(),
                session,
            )
        except HTTPException:
            session.rollback()
            raise
        except Exception as exc:
            session.rollback()
            raise HTTPException(
                409,
                "La configuration de base n’a pas pu être créée. Aucun établissement partiel n’a été conservé.",
            ) from exc
    establishment_payload = {
        "id": resource_id, "databaseId": str(establishment.id), "name": body.name.strip(),
        "code": establishment_code,
        "institutionType": "school", "type": "Établissement scolaire",
        "city": body.city.strip(), "country": body.country.strip(), "phone": body.phone,
        "email": body.email, "status": "active", "plan": plan_name.lower(),
        "date": now.date().isoformat(), "subscriptionEndDate": end_date, "students": 0,
        "administrator": {"name": body.admin_name.strip(), "email": normalized_email, "phone": body.admin_phone},
        "baseConfigurationCreated": body.use_base_configuration,
    }
    session.add(Resource(id=resource_id, kind="establishments", school_id=resource_id, establishment_id=establishment.id, payload=establishment_payload))
    session.add(Resource(id=f"SUB_{resource_id}", kind="subscriptions", school_id=resource_id, establishment_id=establishment.id, payload={
        "id": f"SUB_{resource_id}", "schoolId": resource_id, "client": body.name.strip(),
        "plan": plan_name, "price": plan_price, "startDate": now.date().isoformat(),
        "endDate": end_date, "status": "active",
    }))
    administrator = User(
        email=normalized_email, password_hash="", name=body.admin_name.strip(),
        role="admin", school_id=establishment.id, direction_id=None,
        status="active", password_set=False,
    )
    session.add(administrator)
    session.flush()
    initial_password = issue_temporary_access(session, administrator, "initial-administrator")
    try:
        session.commit()
    except IntegrityError as exc:
        session.rollback()
        raise HTTPException(409, "La création transactionnelle de l'établissement a échoué") from exc
    session.refresh(administrator)
    return {
        "establishment": superadmin_establishment_json(session.get(Resource, {"kind": "establishments", "id": resource_id}), session),
        "administrator": user_json(administrator, session),
        "initialPassword": initial_password,
        "baseConfigurationCreated": body.use_base_configuration,
        "initialConfiguration": initial_configuration,
    }

@app.put("/api/v1/superadmin/establishments/{resource_id}")
def update_superadmin_establishment(resource_id: str, body: ResourceInput, _: Principal = Depends(require("superadmin")), session: Session = Depends(db)):
    row = session.get(Resource, {"kind": "establishments", "id": resource_id})
    if not row:
        raise HTTPException(404, "Establishment not found")
    allowed_fields = {"name", "code", "city", "address", "country", "phone", "email", "status", "cycles"}
    unknown_fields = set(body.payload) - allowed_fields
    if unknown_fields:
        raise HTTPException(422, f"System fields cannot be modified: {', '.join(sorted(unknown_fields))}")
    if "status" in body.payload and body.payload["status"] not in {"active", "suspended"}:
        raise HTTPException(422, "Status must be active or suspended")
    changes = dict(body.payload)
    raw_cycles = changes.pop("cycles", None)
    if "code" in changes:
        changes["code"] = normalized_establishment_code(changes["code"])
        lock_establishment_code(session, changes["code"])
        ensure_establishment_code_available(
            session, changes["code"], exclude_resource_id=resource_id
        )
    payload = {**row.payload, **changes, "id": resource_id}
    database_id = payload.get("databaseId")
    try:
        establishment = session.get(Establishment, uuid.UUID(str(database_id)))
    except (TypeError, ValueError):
        establishment = None
    if not establishment:
        raise HTTPException(409, "Establishment database relation is invalid")
    duplicate = session.scalar(select(Establishment).where(
        func.lower(Establishment.name) == str(payload.get("name") or "").lower().strip(),
        Establishment.id != establishment.id,
    ))
    if duplicate:
        raise HTTPException(409, "Establishment name already used")
    establishment.name = str(payload.get("name") or establishment.name).strip()
    establishment.city = str(payload.get("city") or establishment.city).strip()
    establishment.status = str(payload.get("status") or establishment.status)
    for field in ("address", "country", "phone", "email"):
        if field in body.payload:
            setattr(establishment, field, body.payload[field])
    establishment.updated_at = datetime.now(timezone.utc)
    if raw_cycles is not None:
        cycle_codes = validate_establishment_cycle_selection(raw_cycles)
        reconcile_establishment_cycles(establishment, cycle_codes, session)
    row.payload = payload
    subscription = session.get(Resource, {"kind": "subscriptions", "id": f"SUB_{resource_id}"})
    if subscription and subscription.payload.get("client") != establishment.name:
        subscription.payload = {**subscription.payload, "client": establishment.name}
    try:
        session.commit()
    except IntegrityError as exc:
        session.rollback()
        raise HTTPException(409, "La modification transactionnelle de l'établissement a échoué") from exc
    return superadmin_establishment_json(row, session)

@app.get("/api/v1/superadmin/subscriptions")
def superadmin_subscriptions(_: Principal = Depends(require("superadmin")), session: Session = Depends(db)):
    subscriptions = list(session.scalars(select(Resource).where(Resource.kind == "subscriptions").order_by(Resource.created_at.desc())).all())
    plans = {
        str(row.payload.get("name") or "").strip().lower(): row
        for row in session.scalars(select(Resource).where(Resource.kind == "plans"))
    }
    items = []
    for row in subscriptions:
        plan = plans.get(str(row.payload.get("plan") or "").strip().lower())
        items.append({
            **dict(row.payload),
            "status": canonical_subscription_status(row.payload),
            "daysRemaining": subscription_days_remaining(row.payload),
            "establishmentStatus": subscription_establishment_status(row, session),
            "planDefinition": plan_json(plan, session) if plan else None,
            "planStatus": plan.payload.get("status") if plan else "unmanaged",
        })
    return {
        "items": items,
        "summary": subscription_summary(subscriptions),
        "expirationAutomatic": True,
    }

@app.post("/api/v1/superadmin/subscriptions/{subscription_id}/renew")
def renew_superadmin_subscription(
    subscription_id: str,
    body: SubscriptionRenewInput,
    _: Principal = Depends(require("superadmin")),
    session: Session = Depends(db),
):
    subscription = session.get(Resource, {"kind": "subscriptions", "id": subscription_id})
    if not subscription:
        raise HTTPException(404, "Abonnement introuvable")
    plan = plan_by_name(session, body.plan)
    if not plan:
        raise HTTPException(422, "Plan introuvable")
    if plan.payload.get("status") != "active":
        raise HTTPException(409, "Ce plan est inactif")
    duration_days = int(plan.payload.get("durationDays"))
    start_date = body.start_date or date.today()
    end_date = start_date + timedelta(days=duration_days)
    payload = {
        **subscription.payload,
        "plan": plan.payload.get("name"),
        "price": str(plan.payload.get("price")),
        "startDate": start_date.isoformat(),
        "endDate": end_date.isoformat(),
        "status": "active" if start_date <= date.today() else "upcoming",
    }
    subscription.payload = payload
    subscription.updated_at = datetime.now(timezone.utc)
    establishment_resource = session.get(
        Resource, {"kind": "establishments", "id": subscription.school_id}
    )
    if establishment_resource:
        establishment_resource.payload = {
            **establishment_resource.payload,
            "plan": str(plan.payload.get("name") or "").lower(),
            "subscriptionEndDate": end_date.isoformat(),
        }
    session.commit()
    return {
        **payload,
        "id": subscription.id,
        "schoolId": subscription.school_id,
        "status": canonical_subscription_status(payload),
        "daysRemaining": subscription_days_remaining(payload),
        "planDefinition": plan_json(plan, session),
        "planStatus": plan.payload.get("status"),
        "establishmentStatus": subscription_establishment_status(subscription, session),
    }

@app.get("/api/v1/superadmin/plans")
def superadmin_plans(_: Principal = Depends(require("superadmin")), session: Session = Depends(db)):
    rows = list(session.scalars(select(Resource).where(Resource.kind == "plans").order_by(Resource.created_at.desc())).all())
    subscription_counts = Counter(
        str(item.payload.get("plan") or "").strip().casefold()
        for item in session.scalars(select(Resource).where(Resource.kind == "subscriptions")).all()
    )
    return [{
        **dict(row.payload),
        "id": row.id,
        "subscriptionCount": subscription_counts[
            str(row.payload.get("name") or "").strip().casefold()
        ],
        "createdAt": row.created_at.isoformat(),
        "updatedAt": row.updated_at.isoformat(),
    } for row in rows]

@app.get("/api/v1/superadmin/modules/catalog")
def superadmin_modules_catalog(_: Principal = Depends(require("superadmin"))):
    return [
        {"id": module_id, "label": label,
         "group": MODULE_GROUP_BY_ID.get(module_id, "Scolarité"),
         "capabilities": [
             {"id": capability_id, "label": capability_label, "group": group}
             for group, entries in PLAN_CAPABILITY_GROUPS.items()
             for capability_id, capability_label in entries
             if capability_id.startswith(f"{module_id}.")
             or (module_id == "students" and capability_id.startswith(("parents.", "students.")))
         ]}
        for module_id, label in MODULE_CATALOG
    ]

@app.get("/api/v1/superadmin/plans/{plan_id}")
def superadmin_plan_detail(plan_id: str, _: Principal = Depends(require("superadmin")), session: Session = Depends(db)):
    row = session.get(Resource, {"kind": "plans", "id": plan_id})
    if not row:
        raise HTTPException(404, "Plan introuvable")
    return plan_json(row, session, include_subscriptions=True)

@app.post("/api/v1/superadmin/plans", status_code=201)
def create_superadmin_plan(body: PlanCreateInput, _: Principal = Depends(require("superadmin")), session: Session = Depends(db)):
    if plan_by_name(session, body.name):
        raise HTTPException(409, "Un plan portant ce nom existe déjà")
    plan_id = f"plan_{secrets.token_hex(6)}"
    payload = body.model_dump()
    payload["durationDays"] = payload.pop("duration_days")
    row = Resource(id=plan_id, kind="plans", school_id=None, payload=payload)
    session.add(row)
    session.commit()
    session.refresh(row)
    return plan_json(row, session)

@app.put("/api/v1/superadmin/plans/{plan_id}")
def update_superadmin_plan(plan_id: str, body: PlanUpdateInput, _: Principal = Depends(require("superadmin")), session: Session = Depends(db)):
    if not body.model_fields_set:
        raise HTTPException(422, "Aucun champ à modifier")
    row = session.get(Resource, {"kind": "plans", "id": plan_id})
    if not row:
        raise HTTPException(404, "Plan introuvable")
    changes = body.model_dump(exclude_unset=True)
    if "name" in changes:
        duplicate = plan_by_name(session, changes["name"])
        if duplicate and duplicate.id != plan_id:
            raise HTTPException(409, "Un plan portant ce nom existe déjà")
    if "duration_days" in changes:
        changes["durationDays"] = changes.pop("duration_days")
    previous_name = str(row.payload.get("name") or "")
    payload = {**row.payload, **changes}
    row.payload = payload
    row.updated_at = datetime.now(timezone.utc)
    if payload.get("name") != previous_name:
        for subscription in subscriptions_for_plan(session, previous_name):
            subscription.payload = {**subscription.payload, "plan": payload["name"]}
        for establishment in session.scalars(select(Resource).where(Resource.kind == "establishments")):
            if str(establishment.payload.get("plan") or "").strip().lower() == previous_name.strip().lower():
                establishment.payload = {**establishment.payload, "plan": str(payload["name"]).lower()}
    session.commit()
    session.refresh(row)
    return plan_json(row, session)

@app.get("/api/v1/superadmin/users")
def superadmin_users(
    role: str | None = None,
    search: str | None = None,
    status_filter: str | None = None,
    establishment_id: str | None = None,
    _: Principal = Depends(require("superadmin")),
    session: Session = Depends(db),
):
    query = select(User).order_by(User.created_at.desc())
    if role:
        query = query.where(User.role == role)
    users = list(session.scalars(query).all())
    data = [superadmin_user_json(user, session) for user in users]
    if search:
        needle = search.lower().strip()
        data = [item for item in data if any(
            needle in str(value or "").lower()
            for value in (
                item.get("name"), item.get("email"), item.get("phone"),
                (item.get("establishment") or {}).get("name"),
            )
        )]
    if status_filter:
        data = [item for item in data if item.get("status") == status_filter]
    if establishment_id:
        data = [item for item in data if item.get("schoolId") == establishment_id]
    return data

def superadmin_user_json(user: User, session: Session) -> dict[str, Any]:
    data = user_json(user, session)
    establishment = session.get(Establishment, user.school_id) if user.school_id else None
    public_id = public_school_id(session, user.school_id)
    resource = session.get(Resource, {"kind": "establishments", "id": public_id}) if public_id else None
    administrator_payload = resource.payload.get("administrator") if resource and isinstance(resource.payload.get("administrator"), dict) else {}
    phone = administrator_payload.get("phone") if str(administrator_payload.get("email") or "").lower() == user.email.lower() else None
    data.update({
        "phone": phone,
        "createdAt": user.created_at.isoformat(),
        "updatedAt": user.updated_at.isoformat(),
        "lastLoginAt": None,
        "establishment": ({
            "id": public_id,
            "name": establishment.name,
            "status": establishment.status,
        } if establishment else None),
    })
    return data

@app.get("/api/v1/superadmin/users/{user_id}")
def superadmin_user_detail(user_id: uuid.UUID, _: Principal = Depends(require("superadmin")), session: Session = Depends(db)):
    user = session.get(User, user_id)
    if not user:
        raise HTTPException(404, "Utilisateur introuvable")
    if user.role != "admin":
        raise HTTPException(403, "Cette route est réservée aux administrateurs scolaires")
    return superadmin_user_json(user, session)

@app.put("/api/v1/superadmin/users/{user_id}/status")
def update_admin_account_status(body: AdminAccountStatusInput, user_id: uuid.UUID, _: Principal = Depends(require("superadmin")), session: Session = Depends(db)):
    user = session.get(User, user_id)
    if not user:
        raise HTTPException(404, "Utilisateur introuvable")
    if user.role != "admin":
        raise HTTPException(403, "Seul un compte administrateur scolaire peut être modifié")
    if not user.school_id or not session.get(Establishment, user.school_id):
        raise HTTPException(409, "Relation établissement invalide")
    user.status = body.status
    user.updated_at = datetime.now(timezone.utc)
    session.commit()
    session.refresh(user)
    return superadmin_user_json(user, session)

@app.post("/api/v1/superadmin/users/{user_id}/reset-password")
def reset_admin_password(user_id: uuid.UUID, _: Principal = Depends(require("superadmin")), session: Session = Depends(db)):
    user = session.get(User, user_id)
    if not user:
        raise HTTPException(404, "Utilisateur introuvable")
    if user.role != "admin":
        raise HTTPException(403, "Seul un compte administrateur scolaire peut être réinitialisé")
    if not user.school_id or not session.get(Establishment, user.school_id):
        raise HTTPException(409, "Relation établissement invalide")
    temporary_password = issue_temporary_access(session, user, "administrator-reset")
    session.commit()
    return {
        "temporaryPassword": temporary_password,
        "expiresAt": (datetime.now(timezone.utc) + TEMPORARY_ACCESS_TTL).isoformat(),
    }
def _performance_band(value_20: float) -> str:
    if value_20 >= 19:
        return "Excellent"
    if value_20 >= 16:
        return "Très bien"
    if value_20 >= 14:
        return "Bien"
    if value_20 >= 12:
        return "Assez bien"
    if value_20 >= 10:
        return "Passable"
    return "Insuffisant"


def _statistics_class_scale(session: Session, school_class: SchoolClass) -> float:
    return general_average_scale(session, school_class)


@app.get("/api/v1/statistics")
def statistics(
    school_id: str | None = None,
    academic_year_id: str | None = None,
    cycle: str | None = None,
    level_id: str | None = None,
    class_id: str | None = None,
    period_id: str | None = None,
    subject_id: str | None = None,
    current: Principal = Depends(require_module_roles("statistics", "admin")),
    session: Session = Depends(db),
):
    """Official-result statistics for a school administration/direction.

    Only the latest official trimester available for each class contributes to
    rankings/distribution. Primary/Maternelle averages are normalized to /20
    only for cross-cycle statistics; their bulletin/display scale stays /10.
    """
    if current.role != "admin":
        raise HTTPException(403, "Les statistiques scolaires privées sont réservées à l’administration de l’établissement")
    if school_id and school_id != current.school_id:
        raise HTTPException(403, "Accès inter-établissement interdit")

    database_id = resolve_establishment_id(session, school_id or current.school_id)
    class_stmt = select(SchoolClass).where(SchoolClass.status == "active")
    if database_id:
        class_stmt = class_stmt.where(SchoolClass.establishment_id == database_id)
    requested_year_id: uuid.UUID | None = None
    if academic_year_id:
        try:
            requested_year_id = uuid.UUID(academic_year_id)
        except ValueError as exc:
            raise HTTPException(422, "Année scolaire invalide") from exc
        requested_year = session.get(AcademicYear, requested_year_id)
        if not requested_year or requested_year.establishment_id != database_id:
            raise HTTPException(422, "Année scolaire hors du périmètre")
        class_stmt = class_stmt.where(SchoolClass.academic_year_id == requested_year_id)
    else:
        # Without an explicit year, compare only the active year of each
        # establishment. Historical classes must not inflate platform KPIs.
        class_stmt = class_stmt.join(
            AcademicYear, AcademicYear.id == SchoolClass.academic_year_id
        ).where(AcademicYear.is_active.is_(True))
    if level_id:
        try:
            class_stmt = class_stmt.where(SchoolClass.school_level_id == uuid.UUID(level_id))
        except ValueError as exc:
            raise HTTPException(422, "Niveau invalide") from exc
    if class_id:
        try:
            class_stmt = class_stmt.where(SchoolClass.id == uuid.UUID(class_id))
        except ValueError as exc:
            raise HTTPException(422, "Classe invalide") from exc
    requested_period_id = None
    selected_stat_period: AcademicPeriod | None = None
    if period_id:
        try:
            requested_period_id = uuid.UUID(period_id)
        except ValueError as exc:
            raise HTTPException(422, "Période invalide") from exc
        selected_stat_period = session.get(AcademicPeriod, requested_period_id)
        if (
            not selected_stat_period
            or selected_stat_period.establishment_id != database_id
            or selected_stat_period.status != "active"
            or (
                requested_year_id is not None
                and selected_stat_period.academic_year_id != requested_year_id
            )
        ):
            raise HTTPException(422, "Période hors du périmètre")
    requested_subject_id = None
    if subject_id:
        try:
            requested_subject_id = uuid.UUID(subject_id)
        except ValueError as exc:
            raise HTTPException(422, "Matière invalide") from exc
        selected_subject = session.get(Subject, requested_subject_id)
        if (
            not selected_subject
            or selected_subject.establishment_id != database_id
            or selected_subject.status != "active"
        ):
            raise HTTPException(422, "Matière hors du périmètre")
    allowed = direction_cycle_scope(current)
    if allowed is not None:
        class_stmt = class_stmt.where(SchoolClass.cycle_id.in_(allowed))

    school_classes = list(session.scalars(class_stmt).all())
    selected_cycle_ids = {item.cycle_id for item in school_classes if item.cycle_id}
    cycles_by_id: dict[uuid.UUID, SchoolCycle] = {
        item.id: item for item in session.scalars(select(SchoolCycle).where(
            SchoolCycle.id.in_(selected_cycle_ids)
        )).all()
    } if selected_cycle_ids else {}
    filtered_classes: list[SchoolClass] = []
    requested_cycle = (cycle or "").strip().casefold()
    for item in school_classes:
        cycle_row = cycles_by_id.get(item.cycle_id) if item.cycle_id else None
        if requested_cycle:
            aliases = {
                str(item.cycle_id).casefold() if item.cycle_id else "",
                (cycle_row.code if cycle_row else "").casefold(),
                (cycle_row.name if cycle_row else "").casefold(),
            }
            if requested_cycle not in aliases:
                continue
        filtered_classes.append(item)
    school_classes = filtered_classes
    class_ids = [item.id for item in school_classes]
    classes_by_id = {item.id: item for item in school_classes}
    selected_level_ids = {
        item.school_level_id for item in school_classes if item.school_level_id
    }
    levels_by_id: dict[uuid.UUID, SchoolLevel] = {
        item.id: item for item in session.scalars(select(SchoolLevel).where(
            SchoolLevel.id.in_(selected_level_ids)
        )).all()
    } if selected_level_ids else {}

    latest_by_class: dict[uuid.UUID, tuple[ResultCalculation, int]] = {}
    valid_snapshots: list[tuple[ResultCalculation, AcademicPeriod]] = []
    periods: dict[uuid.UUID, AcademicPeriod] = {}
    if class_ids:
        snapshots = session.scalars(select(ResultCalculation).where(
            ResultCalculation.class_id.in_(class_ids),
            ResultCalculation.status == "official",
        )).all()
        periods = {
            item.id: item for item in session.scalars(select(AcademicPeriod).where(
                AcademicPeriod.id.in_([snap.academic_period_id for snap in snapshots])
            )).all()
        } if snapshots else {}
        for snap in snapshots:
            payload = snap.payload or {}
            if payload.get("calculationRuleVersion") != RESULT_CALCULATION_RULE_VERSION:
                continue
            period = periods.get(snap.academic_period_id)
            if not period or period.status != "active":
                continue
            valid_snapshots.append((snap, period))
            if requested_period_id:
                if snap.academic_period_id != requested_period_id:
                    continue
            elif period.period_type != "trimester":
                # Preserve the historical dashboard default: without an
                # explicit filter, headline KPIs use the latest official
                # trimester. Month/custom snapshots are available through
                # their own configured period filters and evolution series.
                continue
            order = int(period.sort_order or 0)
            previous = latest_by_class.get(snap.class_id)
            if previous is None or order > previous[1] or (
                order == previous[1] and snap.calculated_at > previous[0].calculated_at
            ):
                latest_by_class[snap.class_id] = (snap, order)

    ranking: list[dict[str, Any]] = []
    # The result success KPI always follows the official general result. A
    # subject filter may refine subject analysis, but must never redefine a
    # pupil as admitted/failed from one subject alone.
    official_result_averages: list[float] = []
    subject_values: dict[str, dict[str, Any]] = {}
    class_values: dict[str, list[float]] = {}
    level_values: dict[str, list[float]] = {}
    cycle_values: dict[str, list[float]] = {}
    distribution = {
        "Excellent": 0,
        "Très bien": 0,
        "Bien": 0,
        "Assez bien": 0,
        "Passable": 0,
        "Insuffisant": 0,
    }
    for school_class in school_classes:
        pair = latest_by_class.get(school_class.id)
        if not pair:
            continue
        snapshot, _ = pair
        scale = _statistics_class_scale(session, school_class)
        cycle_row = cycles_by_id.get(school_class.cycle_id) if school_class.cycle_id else None
        cycle_name = cycle_row.name if cycle_row else "Cycle non renseigné"
        level_row = levels_by_id.get(school_class.school_level_id) if school_class.school_level_id else None
        level_name = level_row.name if level_row else "Niveau non renseigné"
        for result in (snapshot.payload or {}).get("students") or []:
            general_average = result.get("average")
            if general_average is not None:
                official_result_averages.append(
                    round(float(general_average) * 20.0 / scale, 2)
                )
            selected_subject = None
            if requested_subject_id:
                selected_subject = next((subject for subject in result.get("subjects") or []
                    if str(subject.get("subjectId") or "") == str(requested_subject_id)), None)
                if selected_subject is None or selected_subject.get("average") is None:
                    continue
            source_average = (selected_subject or result).get("average")
            if source_average is None:
                continue
            raw_average = float(source_average)
            average20 = round(raw_average * 20.0 / scale, 2)
            entry = {
                "studentId": result.get("studentId"),
                "name": result.get("studentName") or "Élève",
                "classId": str(school_class.id),
                "className": school_class.name,
                "cycleId": str(school_class.cycle_id) if school_class.cycle_id else None,
                "cycle": cycle_name,
                "levelId": str(school_class.school_level_id)
                    if school_class.school_level_id else None,
                "level": level_name,
                "average": round(raw_average, 2),
                "average20": average20,
                "scale": scale,
                "mention": _performance_band(average20),
            }
            ranking.append(entry)
            distribution[entry["mention"]] += 1
            class_values.setdefault(str(school_class.id), []).append(average20)
            level_values.setdefault(level_name, []).append(average20)
            cycle_values.setdefault(cycle_name, []).append(average20)
            for subject in result.get("subjects") or []:
                if subject.get("average") is None:
                    continue
                if requested_subject_id and str(subject.get("subjectId") or "") != str(requested_subject_id):
                    continue
                subject_name = str(subject.get("subject") or "Matière")
                subject_average20 = float(subject["average"]) * 20.0 / scale
                bucket = subject_values.setdefault(subject_name, {
                    "sum": 0.0, "sumSquares": 0.0, "count": 0, "success": 0,
                })
                bucket["sum"] += subject_average20
                bucket["sumSquares"] += subject_average20 * subject_average20
                bucket["count"] += 1
                bucket["success"] += subject_average20 >= 10

    ranking.sort(key=lambda item: (-item["average20"], item["name"].casefold()))
    top10 = ranking[:10]
    overall = round(sum(item["average20"] for item in ranking) / len(ranking), 2) if ranking else None
    ordered_averages = sorted(item["average20"] for item in ranking)
    success_count = sum(value >= 10 for value in official_result_averages)
    failure_count = len(official_result_averages) - success_count
    success_rate = round(100 * success_count / len(official_result_averages), 2) if official_result_averages else None
    failure_rate = round(100 * failure_count / len(official_result_averages), 2) if official_result_averages else None
    if not ordered_averages:
        median = None
    elif len(ordered_averages) % 2:
        median = ordered_averages[len(ordered_averages) // 2]
    else:
        middle = len(ordered_averages) // 2
        median = round((ordered_averages[middle - 1] + ordered_averages[middle]) / 2, 2)
    standard_deviation = None
    if ordered_averages:
        mean = sum(ordered_averages) / len(ordered_averages)
        standard_deviation = round(
            (sum((value - mean) ** 2 for value in ordered_averages)
             / len(ordered_averages)) ** .5,
            2,
        )
    by_class = [
        {
            "classId": class_key,
            "className": classes_by_id[uuid.UUID(class_key)].name,
            "studentCount": len(values),
            "average20": round(sum(values) / len(values), 2),
            "successRate": round(100 * sum(value >= 10 for value in values) / len(values), 2),
        }
        for class_key, values in class_values.items() if values
    ]
    by_class.sort(key=lambda item: item["className"].casefold())
    by_level = [
        {
            "level": name,
            "studentCount": len(values),
            "average20": round(sum(values) / len(values), 2),
        }
        for name, values in level_values.items() if values
    ]
    by_level.sort(key=lambda item: item["level"].casefold())
    by_cycle = [
        {"cycle": name, "studentCount": len(values), "average20": round(sum(values) / len(values), 2)}
        for name, values in cycle_values.items() if values
    ]
    by_cycle.sort(key=lambda item: item["cycle"].casefold())
    by_subject = []
    for name, data in subject_values.items():
        if not data["count"]:
            continue
        subject_mean = data["sum"] / data["count"]
        dispersion = max(0.0, data["sumSquares"] / data["count"] - subject_mean ** 2) ** .5
        by_subject.append({
            "subject": name,
            "average20": round(subject_mean, 2),
            "studentCount": data["count"],
            "successRate": round(100 * data["success"] / data["count"], 2),
            "standardDeviation": round(dispersion, 2),
        })
    by_subject.sort(key=lambda item: (-item["average20"], item["subject"].casefold()))

    evolution_buckets: dict[uuid.UUID, dict[str, Any]] = {}
    class_period_averages: dict[uuid.UUID, list[tuple[int, float]]] = {}
    for snapshot, period in valid_snapshots:
        if period.period_type != "trimester":
            continue
        school_class = classes_by_id.get(snapshot.class_id)
        if not school_class:
            continue
        scale = _statistics_class_scale(session, school_class)
        values = []
        for result in (snapshot.payload or {}).get("students") or []:
            source = result
            if requested_subject_id:
                source = next((subject for subject in result.get("subjects") or []
                    if str(subject.get("subjectId") or "") == str(requested_subject_id)), None)
            if source and source.get("average") is not None:
                values.append(float(source["average"]) * 20.0 / scale)
        if not values:
            continue
        bucket = evolution_buckets.setdefault(period.id, {
            "periodId": str(period.id), "period": period.name,
            "sortOrder": int(period.sort_order or 0), "sum": 0.0, "count": 0,
        })
        bucket["sum"] += sum(values)
        bucket["count"] += len(values)
        class_period_averages.setdefault(snapshot.class_id, []).append(
            (int(period.sort_order or 0), sum(values) / len(values))
        )
    evolution = [{
        "periodId": item["periodId"], "period": item["period"],
        "sortOrder": item["sortOrder"],
        "average20": round(item["sum"] / item["count"], 2),
    } for item in evolution_buckets.values() if item["count"]]
    evolution.sort(key=lambda item: item["sortOrder"])
    for item in by_class:
        history = sorted(class_period_averages.get(uuid.UUID(item["classId"]), []))
        item["progression"] = (
            round(history[-1][1] - history[-2][1], 2)
            if len(history) >= 2 else None
        )
    monthly_statement = select(
        Evaluation.date_scheduled, Grade.value, Grade.max_value
    ).join(Grade, Grade.evaluation_id == Evaluation.id).where(
        Evaluation.class_id.in_(class_ids),
        Evaluation.status.in_(("submitted", "validated")),
        Evaluation.date_scheduled.is_not(None),
        Grade.value.is_not(None),
        Grade.max_value > 0,
    )
    if requested_period_id:
        monthly_statement = monthly_statement.where(
            Evaluation.academic_period_id == requested_period_id)
    if requested_subject_id:
        monthly_statement = monthly_statement.where(
            Evaluation.subject_id == requested_subject_id)
    monthly_buckets: dict[str, dict[str, Any]] = {}
    if class_ids:
        for scheduled_date, value, maximum in session.execute(monthly_statement).all():
            key = scheduled_date.strftime("%Y-%m")
            bucket = monthly_buckets.setdefault(key, {
                "month": key, "sum": 0.0, "count": 0,
            })
            bucket["sum"] += float(value) * 20.0 / float(maximum)
            bucket["count"] += 1
    monthly_evolution = [{
        "month": item["month"],
        "average20": round(item["sum"] / item["count"], 2),
        "gradeCount": item["count"],
    } for item in sorted(monthly_buckets.values(), key=lambda row: row["month"])
        if item["count"]]

    # Attendance uses the current relational source of truth. The legacy
    # generic ``absences`` resources are incomplete and made this KPI display
    # zero even when official locked attendance sheets existed.
    attendance_statement = select(AttendanceRecord).join(
            AttendanceSheet, AttendanceSheet.id == AttendanceRecord.sheet_id
        ).where(
            AttendanceSheet.status == "locked",
            AttendanceRecord.class_id.in_(class_ids),
        )
    if requested_period_id:
        if selected_stat_period.start_date:
            attendance_statement = attendance_statement.where(
                AttendanceRecord.attendance_date >= selected_stat_period.start_date)
        if selected_stat_period.end_date:
            attendance_statement = attendance_statement.where(
                AttendanceRecord.attendance_date <= selected_stat_period.end_date)
    if requested_subject_id:
        attendance_statement = attendance_statement.where(
            AttendanceRecord.subject_id == requested_subject_id)
    attendance_rows = [] if not class_ids else list(session.scalars(attendance_statement).all())
    attendance_total = len(attendance_rows)
    attendance_present = sum(row.status in ("present", "late") for row in attendance_rows)
    attendance_rate = round(100 * attendance_present / attendance_total, 2) if attendance_total else None
    attendance_by_class = []
    for school_class in school_classes:
        rows = [row for row in attendance_rows if row.class_id == school_class.id]
        if not rows:
            continue
        present = sum(row.status in ("present", "late") for row in rows)
        attendance_by_class.append({
            "classId": str(school_class.id), "className": school_class.name,
            "rate": round(100 * present / len(rows), 2),
            "absent": sum(row.status == "absent" for row in rows),
            "late": sum(row.status == "late" for row in rows),
            "recordCount": len(rows),
        })
    for item in by_class:
        attendance_item = next((row for row in attendance_by_class
            if row["classId"] == item["classId"]), None)
        item["attendanceRate"] = attendance_item["rate"] if attendance_item else None
    today_absence_count = sum(
        row.attendance_date == date.today() and row.status == "absent"
        for row in attendance_rows
    )

    student_count = 0 if not class_ids else int(session.scalar(
        select(func.count(func.distinct(StudentAcademicRegistration.student_id))).where(
            StudentAcademicRegistration.class_id.in_(class_ids),
            StudentAcademicRegistration.status.in_(("pending", "validated", "active")),
        )
    ) or 0)
    decision_rows = [] if not class_ids else list(session.scalars(
        select(StudentAnnualDecision).where(
            StudentAnnualDecision.student_id.in_(
                select(StudentAcademicRegistration.student_id).where(
                    StudentAcademicRegistration.class_id.in_(class_ids),
                    StudentAcademicRegistration.status.in_(("pending", "validated", "active")),
                )
            ),
            StudentAnnualDecision.academic_year_id.in_(
                {item.academic_year_id for item in school_classes}
            ),
        )
    ).all())
    decisions = {
        "admitted": sum(item.decision == "admitted" for item in decision_rows),
        "failed": sum(item.decision in ("repeat", "failed") for item in decision_rows),
        "excluded": sum(item.decision == "excluded" for item in decision_rows),
        "total": len(decision_rows),
    }
    # Once annual decisions exist they are the strongest source of truth for
    # the headline success/failure rate (admitted versus not admitted).
    if decisions["total"]:
        success_count = decisions["admitted"]
        failure_count = decisions["failed"] + decisions["excluded"]
        decided_total = success_count + failure_count
        success_rate = round(100 * success_count / decided_total, 2) if decided_total else None
        failure_rate = round(100 * failure_count / decided_total, 2) if decided_total else None
    teacher_count = 0 if not class_ids else int(session.scalar(
        select(func.count(func.distinct(Affectation.teacher_id)))
        .join(Teacher, Teacher.id == Affectation.teacher_id)
        .join(User, User.id == Teacher.user_id)
        .where(
            Affectation.class_id.in_(class_ids),
            Affectation.status == "active",
            Teacher.status == "active",
            User.status == "active",
        )
    ) or 0)
    planned_course_count = 0 if not class_ids else int(session.scalar(
        select(func.count()).select_from(ScheduleEntry).where(
            ScheduleEntry.class_id.in_(class_ids),
            ScheduleEntry.status == "active",
        )
    ) or 0)
    completed_course_count = 0 if not class_ids else int(session.scalar(
        select(func.count()).select_from(AttendanceSheet).where(
            AttendanceSheet.class_id.in_(class_ids),
            AttendanceSheet.status == "locked",
        )
    ) or 0)
    teacher_subject_rows = [] if not class_ids else session.execute(
        select(Subject.name, func.count(func.distinct(Affectation.teacher_id)))
        .join(Affectation, Affectation.subject_id == Subject.id)
        .where(Affectation.class_id.in_(class_ids), Affectation.status == "active")
        .group_by(Subject.id, Subject.name).order_by(Subject.name)
    ).all()
    teacher_level_rows = [] if not class_ids else session.execute(
        select(SchoolLevel.name, func.count(func.distinct(Affectation.teacher_id)))
        .join(SchoolClass, SchoolClass.school_level_id == SchoolLevel.id)
        .join(Affectation, Affectation.class_id == SchoolClass.id)
        .where(Affectation.class_id.in_(class_ids), Affectation.status == "active")
        .group_by(SchoolLevel.id, SchoolLevel.name).order_by(SchoolLevel.sort_order)
    ).all()
    teacher_statistics = {
        "active": teacher_count,
        "plannedCourses": planned_course_count,
        "completedCourses": completed_course_count,
        "bySubject": [{"label": name, "count": count}
                      for name, count in teacher_subject_rows],
        "byLevel": [{"label": name, "count": count}
                    for name, count in teacher_level_rows],
    }

    evaluation_statement = select(Evaluation).where(
        Evaluation.class_id.in_(class_ids), Evaluation.status != "archived"
    )
    if requested_period_id:
        evaluation_statement = evaluation_statement.where(
            Evaluation.academic_period_id == requested_period_id)
    if requested_subject_id:
        evaluation_statement = evaluation_statement.where(
            Evaluation.subject_id == requested_subject_id)
    evaluations = [] if not class_ids else list(session.scalars(evaluation_statement).all())
    evaluation_ids = [item.id for item in evaluations]
    grade_counts = dict(session.execute(
        select(Grade.evaluation_id, func.count(Grade.id))
        .where(Grade.evaluation_id.in_(evaluation_ids))
        .group_by(Grade.evaluation_id)
    ).all()) if evaluation_ids else {}
    registration_counts = dict(session.execute(
        select(StudentAcademicRegistration.class_id,
               func.count(func.distinct(StudentAcademicRegistration.student_id)))
        .where(
            StudentAcademicRegistration.class_id.in_(class_ids),
            StudentAcademicRegistration.status.in_(("pending", "validated", "active")),
        ).group_by(StudentAcademicRegistration.class_id)
    ).all()) if class_ids else {}
    affectation_ids = {item.affectation_id for item in evaluations if item.affectation_id}
    affectations = {
        item.id: item for item in session.scalars(select(Affectation).where(
            Affectation.id.in_(affectation_ids))).all()
    } if affectation_ids else {}
    teacher_ids = {item.teacher_id for item in affectations.values()}
    teachers = {
        item.id: item for item in session.scalars(select(Teacher).where(
            Teacher.id.in_(teacher_ids))).all()
    } if teacher_ids else {}
    subject_ids = {item.subject_id for item in evaluations}
    subjects = {
        item.id: item for item in session.scalars(select(Subject).where(
            Subject.id.in_(subject_ids))).all()
    } if subject_ids else {}
    completion_buckets: dict[tuple[Any, ...], dict[str, Any]] = {}
    for evaluation in evaluations:
        affectation = affectations.get(evaluation.affectation_id)
        teacher = teachers.get(affectation.teacher_id) if affectation else None
        subject = subjects.get(evaluation.subject_id)
        key = (evaluation.class_id, evaluation.subject_id,
               teacher.id if teacher else None)
        bucket = completion_buckets.setdefault(key, {
            "classId": str(evaluation.class_id),
            "className": classes_by_id[evaluation.class_id].name,
            "subjectId": str(evaluation.subject_id),
            "subject": subject.name if subject else "Matière",
            "teacherId": str(teacher.id) if teacher else None,
            "teacher": f"{teacher.last_name} {teacher.first_name}" if teacher else "Non affecté",
            "expected": 0, "entered": 0, "evaluationCount": 0,
        })
        bucket["evaluationCount"] += 1
        bucket["expected"] += int(registration_counts.get(evaluation.class_id, 0))
        bucket["entered"] += int(grade_counts.get(evaluation.id, 0))
    grade_completion = []
    for bucket in completion_buckets.values():
        expected = bucket["expected"]
        bucket["completionRate"] = round(
            min(100, 100 * bucket["entered"] / expected), 2
        ) if expected else 0
        grade_completion.append(bucket)
    grade_completion.sort(key=lambda item: (
        item["className"].casefold(), item["subject"].casefold(), item["teacher"].casefold()
    ))

    finance = None
    establishment = session.get(Establishment, database_id) if database_id else None
    if establishment and "finance" in set(establishment.enabled_modules or []):
        assignments = finance_rows(
            session, "finance-fee-assignments", current.school_id, current
        )
        if academic_year_id:
            assignments = [item for item in assignments
                if str(item.payload.get("academicYearId")) == academic_year_id]
        finance_rows_data = []
        for assignment in assignments:
            registration_reference = assignment.payload.get("registrationId")
            registration_resource = session.get(Resource, {
                "kind": "finance-registrations", "id": str(registration_reference)
            }) if registration_reference else None
            registration_payload = registration_resource.payload if registration_resource else {}
            linked_class_id = str(
                registration_payload.get("classId") or assignment.payload.get("classId") or ""
            )
            linked_class = None
            try:
                linked_class = session.get(SchoolClass, uuid.UUID(linked_class_id))
            except (TypeError, ValueError):
                pass
            if class_id and linked_class_id != class_id:
                continue
            if level_id and (not linked_class or str(linked_class.school_level_id) != level_id):
                continue
            if requested_cycle and (not linked_class or str(linked_class.cycle_id).casefold() != requested_cycle):
                linked_cycle = session.get(SchoolCycle, linked_class.cycle_id) if linked_class and linked_class.cycle_id else None
                aliases = {(linked_cycle.code if linked_cycle else "").casefold(),
                           (linked_cycle.name if linked_cycle else "").casefold()}
                if requested_cycle not in aliases:
                    continue
            balance = finance_assignment_balance(session, current.school_id, assignment)
            fee_reference = assignment.payload.get("feeId")
            fee = session.get(Resource, {"kind": "finance-fees", "id": str(fee_reference)}) if fee_reference else None
            finance_rows_data.append({
                **balance,
                "className": linked_class.name if linked_class else
                    registration_payload.get("className") or "Classe non renseignée",
                "level": registration_payload.get("level") or
                    (linked_class.level if linked_class else "Niveau non renseigné"),
                "type": (fee.payload.get("type") if fee else None) or "other",
            })
        expected_amount = sum(item["expected"] for item in finance_rows_data)
        paid_amount = sum(item["paid"] for item in finance_rows_data)
        def finance_breakdown(field: str) -> list[dict[str, Any]]:
            buckets: dict[str, dict[str, float]] = {}
            for item in finance_rows_data:
                label = str(item.get(field) or "Non renseigné")
                bucket = buckets.setdefault(label, {"expected": 0.0, "paid": 0.0})
                bucket["expected"] += float(item["expected"])
                bucket["paid"] += float(item["paid"])
            return [{"label": label, **amounts,
                     "remaining": max(0, amounts["expected"] - amounts["paid"])}
                    for label, amounts in sorted(buckets.items())]
        finance = {
            "expected": expected_amount,
            "paid": paid_amount,
            "remaining": max(0, expected_amount - paid_amount),
            "collectionRate": round(100 * paid_amount / expected_amount, 2)
                if expected_amount else 0,
            "unpaidCount": sum(item["status"] in ("unpaid", "partial")
                               for item in finance_rows_data),
            "byClass": finance_breakdown("className"),
            "byLevel": finance_breakdown("level"),
            "byType": finance_breakdown("type"),
        }

    insights: list[dict[str, str]] = []
    alerts: list[dict[str, str]] = []
    if overall is not None:
        insights.append({
            "type": "academic",
            "title": "Niveau académique",
            "message": f"La moyenne générale officielle du périmètre est de {overall:.2f}/20.",
        })
    if success_rate is not None:
        insights.append({
            "type": "success",
            "title": "Réussite",
            "message": f"{success_rate:.2f} % des élèves disposant d’un résultat officiel sont admis.",
        })
    if attendance_rate is not None:
        insights.append({
            "type": "attendance",
            "title": "Présence",
            "message": f"Le taux de présence issu des appels envoyés est de {attendance_rate:.2f} %.",
        })
        if attendance_rate < 80:
            alerts.append({
                "type": "attendance",
                "title": "Présence insuffisante",
                "message": (
                    f"Le taux de présence du périmètre sélectionné est de "
                    f"{attendance_rate:.2f} %, sous le seuil d’attention de 80 %."
                ),
            })
    if len(evolution) >= 2:
        insights.append({
            "type": "evolution",
            "title": "Évolution trimestrielle",
            "message": (
                f"La moyenne générale a évolué de {evolution[0]['average20']:.2f}/20 "
                f"à {evolution[-1]['average20']:.2f}/20 entre "
                f"{evolution[0]['period']} et {evolution[-1]['period']}."
            ),
        })
    if grade_completion:
        expected_grades = sum(item["expected"] for item in grade_completion)
        entered_grades = sum(item["entered"] for item in grade_completion)
        completion_rate = round(100 * entered_grades / expected_grades, 2) if expected_grades else 0
        insights.append({
            "type": "grades",
            "title": "Saisie des notes",
            "message": f"Le taux de complétude des notes est de {completion_rate:.2f} % sur le périmètre sélectionné.",
        })
    else:
        completion_rate = None
    difficult_subjects = [item for item in by_subject if item["average20"] < 10]
    if difficult_subjects:
        names = ", ".join(item["subject"] for item in difficult_subjects[:3])
        alerts.append({
            "type": "subject",
            "title": "Matières en difficulté",
            "message": f"Moyenne inférieure à 10/20 : {names}.",
        })
    period_filter_statement = select(AcademicPeriod).where(
        AcademicPeriod.establishment_id == database_id,
        AcademicPeriod.status == "active",
    )
    if academic_year_id:
        period_filter_statement = period_filter_statement.where(
            AcademicPeriod.academic_year_id == uuid.UUID(academic_year_id))
    filter_periods = list(session.scalars(period_filter_statement.order_by(
        AcademicPeriod.sort_order, AcademicPeriod.name)).all())
    filter_subjects = list(session.scalars(select(Subject).where(
        Subject.id.in_(select(Affectation.subject_id).where(
            Affectation.class_id.in_(class_ids), Affectation.status == "active"
        )), Subject.status == "active"
    ).order_by(Subject.name)).all()) if class_ids else []
    applied_cycle_id = None
    if requested_cycle and len(selected_cycle_ids) == 1:
        applied_cycle_id = str(next(iter(selected_cycle_ids)))
    return {
        "snapshotGeneratedAt": datetime.now(timezone.utc).isoformat(),
        "appliedFilters": {
            "academicYearId": str(requested_year_id) if requested_year_id else None,
            "cycleId": applied_cycle_id,
            "levelId": level_id,
            "classId": class_id,
            "periodId": str(requested_period_id) if requested_period_id else None,
            "subjectId": str(requested_subject_id) if requested_subject_id else None,
        },
        "studentCount": student_count,
        "teacherCount": teacher_count,
        "teacherStatistics": teacher_statistics,
        "classCount": len(school_classes),
        "officialStudentCount": len(ranking),
        "overallAverage": overall,
        "overallScale": 20,
        "successCount": success_count,
        "failureCount": failure_count,
        "successRate": success_rate,
        "failureRate": failure_rate,
        "decisions": decisions,
        "highestAverage": ordered_averages[-1] if ordered_averages else None,
        "lowestAverage": ordered_averages[0] if ordered_averages else None,
        "medianAverage": median,
        "standardDeviation": standard_deviation,
        "attendanceRate": attendance_rate,
        "attendanceRecordCount": attendance_total,
        "absenceCount": sum(row.status == "absent" for row in attendance_rows),
        "lateCount": sum(row.status == "late" for row in attendance_rows),
        "todayAbsenceCount": today_absence_count,
        "top5": top10[:5],
        "top10": top10,
        "distribution": distribution,
        "byCycle": by_cycle,
        "byLevel": by_level,
        "byClass": by_class,
        "bySubject": by_subject,
        "evolution": evolution,
        "monthlyEvolution": monthly_evolution,
        "attendanceByClass": attendance_by_class,
        "gradeCompletion": grade_completion,
        "gradeCompletionRate": completion_rate,
        "finance": finance,
        "filters": {
            "periods": [{
                "id": str(item.id),
                "name": item.name,
                "periodType": item.period_type,
                "parentPeriodId": str(item.parent_period_id)
                    if item.parent_period_id else None,
                "sortOrder": item.sort_order,
            } for item in filter_periods],
            "subjects": [{"id": str(item.id), "name": item.name}
                         for item in filter_subjects],
        },
        "insights": insights,
        "alerts": alerts,
        "calculationRuleVersion": RESULT_CALCULATION_RULE_VERSION,
    }

@app.post("/api/v1/announcements/{resource_id}/reactions")
def react_to_announcement(resource_id: str, body: ReactionInput, current: Principal = Depends(principal), session: Session = Depends(db)):
    row = session.get(Resource, {"kind": "announcements", "id": resource_id})
    if not row or not visible(row, current, session):
        raise HTTPException(404, "Annonce introuvable")
    payload = dict(row.payload)
    reactions = dict(payload.get("reactions") or {})
    reactions[current.id] = body.reaction
    payload["reactions"] = reactions
    row.payload = payload
    session.commit()
    return payload
def resource_direction_cycle_id(
    session: Session,
    item: Resource,
    seen: set[tuple[str, str]] | None = None,
) -> uuid.UUID | None:
    seen = seen or set()
    key = (item.kind, item.id)
    if key in seen:
        return None
    seen.add(key)
    payload = item.payload
    if payload.get('schoolRegistrationId'):
        try:
            reg = session.get(StudentAcademicRegistration, uuid.UUID(str(payload['schoolRegistrationId'])))
        except (TypeError, ValueError):
            return None
        cl = session.get(SchoolClass, reg.class_id) if reg else None
        return cl.cycle_id if cl and cl.establishment_id == item.establishment_id else None
    class_reference = payload.get("classId")
    if class_reference:
        try:
            school_class = session.get(SchoolClass, uuid.UUID(str(class_reference)))
        except (TypeError, ValueError):
            school_class = None
        if school_class:
            return school_class.cycle_id
        linked_class = session.get(Resource, {"kind": "classes", "id": str(class_reference)})
        if linked_class:
            return resource_direction_cycle_id(session, linked_class, seen)
    level_reference = payload.get("structuredLevelId") or payload.get("levelId")
    if level_reference:
        try:
            level = session.get(SchoolLevel, uuid.UUID(str(level_reference)))
        except (TypeError, ValueError):
            level = None
        if level:
            return level.cycle_id
    cycle_reference = payload.get("cycleId") or payload.get("cycle")
    if cycle_reference and item.establishment_id:
        try:
            cycle_uuid = uuid.UUID(str(cycle_reference))
            cycle = session.get(SchoolCycle, cycle_uuid)
        except (TypeError, ValueError):
            cycle = session.scalar(select(SchoolCycle).where(
                SchoolCycle.establishment_id == item.establishment_id,
                SchoolCycle.code == canonical_cycle_code(str(cycle_reference)),
            ))
        if cycle:
            return cycle.id
    for field, orm_model, resource_kind in (
        ("evaluationId", Evaluation, "evaluations"),
        ("affectationId", Affectation, "affectations"),
        ("studentId", Student, "students"),
        ("teacherId", Teacher, "teachers"),
    ):
        reference = payload.get(field)
        if not reference:
            continue
        try:
            relational = session.get(orm_model, uuid.UUID(str(reference)))
        except (TypeError, ValueError):
            relational = None
        if isinstance(relational, Evaluation):
            school_class = session.get(SchoolClass, relational.class_id)
            if school_class:
                return school_class.cycle_id
        elif isinstance(relational, Affectation):
            school_class = session.get(SchoolClass, relational.class_id)
            if school_class:
                return school_class.cycle_id
        elif isinstance(relational, Student):
            registration = session.scalar(select(StudentAcademicRegistration).where(
                StudentAcademicRegistration.student_id == relational.id,
                StudentAcademicRegistration.status.in_(("pending", "validated", "active")),
            ).order_by(StudentAcademicRegistration.registration_date.desc()))
            school_class = session.get(SchoolClass, registration.class_id) if registration else None
            if school_class:
                return school_class.cycle_id
        elif isinstance(relational, Teacher):
            if relational.created_direction_id:
                direction_cycle = session.scalar(select(SchoolDirectionCycle.cycle_id).where(
                    SchoolDirectionCycle.direction_id == relational.created_direction_id
                ).limit(1))
                if direction_cycle:
                    return direction_cycle
            affectation = session.scalar(select(Affectation).where(
                Affectation.teacher_id == relational.id,
                Affectation.status == "active",
            ))
            school_class = session.get(SchoolClass, affectation.class_id) if affectation else None
            if school_class:
                return school_class.cycle_id
        linked = session.get(Resource, {"kind": resource_kind, "id": str(reference)})
        if linked:
            linked_cycle = resource_direction_cycle_id(session, linked, seen)
            if linked_cycle:
                return linked_cycle
    references = (
        ("registrationId", "finance-registrations"),
        ("feeAssignmentId", "finance-fee-assignments"),
        ("paymentId", "finance-payments"),
    )
    for field, kind in references:
        reference = payload.get(field)
        if reference:
            linked = session.get(Resource, {"kind": kind, "id": str(reference)})
            if linked:
                return resource_direction_cycle_id(session, linked, seen)
    entity_id = payload.get("entityId")
    if item.kind == "documents" and entity_id:
        try:
            entity_uuid = uuid.UUID(str(entity_id))
        except (TypeError, ValueError):
            return None
        school_class = session.get(SchoolClass, entity_uuid)
        if school_class:
            return school_class.cycle_id
        student = session.get(Student, entity_uuid)
        if student:
            registration = session.scalar(select(StudentAcademicRegistration).where(
                StudentAcademicRegistration.student_id == student.id,
                StudentAcademicRegistration.status.in_(("pending", "validated", "active")),
            ).order_by(StudentAcademicRegistration.registration_date.desc()))
            linked_class = session.get(SchoolClass, registration.class_id) if registration else None
            return linked_class.cycle_id if linked_class else None
        teacher = session.get(Teacher, entity_uuid)
        if teacher:
            affectation = session.scalar(select(Affectation).where(
                Affectation.teacher_id == teacher.id,
                Affectation.status == "active",
            ))
            linked_class = session.get(SchoolClass, affectation.class_id) if affectation else None
            return linked_class.cycle_id if linked_class else None
    return None

def direction_resource_allowed(
    current: Principal,
    item: Resource,
    session: Session,
) -> bool:
    allowed = direction_cycle_scope(current)
    if allowed is None:
        return True
    cycle_id = resource_direction_cycle_id(session, item)
    return cycle_id in allowed if cycle_id else False

def ensure_generic_resource_direction_access(
    kind: str,
    payload: dict[str, Any],
    school_id: str | None,
    current: Principal,
    session: Session,
) -> None:
    if current.role != "admin" or kind not in {
        "students", "teachers", "classes", "subjects", "evaluations",
        "grades", "affectations", "absences", "assignments", "documents",
        "student-registrations", "finance-fees", "finance-registrations",
        "finance-fee-assignments", "finance-payments", "finance-receipts",
        "annual-bulletins", "annual-decisions", "re-enrollment-requests",
        "behavior-assessments",
    }:
        return
    probe = Resource(
        id=str(payload.get("id") or "scope-probe"),
        kind=kind,
        school_id=school_id,
        establishment_id=resolve_establishment_id(session, school_id),
        payload=payload,
    )
    if not direction_resource_allowed(current, probe, session):
        raise HTTPException(403, "Vous n'avez pas acces a ces donnees dans votre direction")

def finance_rows(
    session: Session,
    kind: str,
    school_id: str,
    current: Principal | None = None,
) -> list[Resource]:
    read_cache = session.info.get("finance_read_cache")
    cache_key = (kind, school_id, current.id if current else None,
                 current.direction_id if current else None)
    if read_cache is not None and cache_key in read_cache:
        return read_cache[cache_key]
    rows = list(session.scalars(select(Resource).where(
        Resource.kind == kind,
        Resource.school_id == school_id,
    )).all())
    visible_rows = [
        item for item in rows
        if current is None or direction_resource_allowed(current, item, session)
    ]
    if read_cache is not None:
        read_cache[cache_key] = visible_rows
    return visible_rows

def finance_lock(session: Session, key: str) -> None:
    """Serialize a financial operation without changing the generic Resource schema."""
    if not session.scalar(text("SELECT pg_try_advisory_xact_lock(hashtextextended(:key, 0))"),
                          {"key": f"finance:{key}"}):
        raise HTTPException(409, "Une opération financière est déjà en cours. Réessayez.")

def finance_resource(
    session: Session,
    kind: str,
    resource_id: str,
    school_id: str,
    current: Principal | None = None,
) -> Resource:
    item = session.get(Resource, {"kind": kind, "id": resource_id})
    if not item:
        raise HTTPException(404, "Ressource financière introuvable")
    if item.school_id != school_id:
        raise HTTPException(403, "Ressource financière inter-établissement interdite")
    if current is not None and not direction_resource_allowed(current, item, session):
        raise HTTPException(403, "Vous n'avez pas acces a ces donnees dans votre direction")
    return item

def finance_assignment_balance(session: Session, school_id: str, assignment: Resource) -> dict[str, Any]:
    balance_cache = session.info.get("finance_balance_cache")
    cache_key = (school_id, assignment.id)
    if balance_cache is not None and cache_key in balance_cache:
        return dict(balance_cache[cache_key])
    payments = [
        row.payload for row in finance_rows(session, "finance-payments", school_id)
        if row.payload.get("status", "active") == "active"
        and (
            row.payload.get("feeAssignmentId") == assignment.id
            or any(
                allocation.get("feeAssignmentId") == assignment.id
                for allocation in row.payload.get("allocations") or []
            )
        )
    ]
    expected = int(assignment.payload.get("amount") or 0)
    paid = sum(
        int(item.get("amount") or 0)
        if item.get("feeAssignmentId") == assignment.id
        else sum(
            int(allocation.get("amount") or 0)
            for allocation in item.get("allocations") or []
            if allocation.get("feeAssignmentId") == assignment.id
        )
        for item in payments
    )
    remaining = max(0, expected - paid)
    result = {
        "expected": expected,
        "paid": paid,
        "remaining": remaining,
        "status": "paid" if remaining == 0 else ("partial" if paid > 0 else "unpaid"),
    }
    if balance_cache is not None:
        balance_cache[cache_key] = result
    return dict(result)

def finance_fee_matches_registration(
    body: FinanceFeeInput,
    registration: Resource,
    session: Session,
    establishment_id: uuid.UUID,
) -> bool:
    if body.scope == "establishment":
        return True
    class_id = registration.payload.get("classId")
    if not class_id:
        return False
    try:
        school_class = session.get(SchoolClass, uuid.UUID(str(class_id)))
    except (TypeError, ValueError):
        school_class = None
    if not school_class or school_class.establishment_id != establishment_id:
        return False
    if body.scope == "class":
        return str(school_class.id) == str(body.classId)
    if body.scope == "level":
        return str(school_class.school_level_id) == str(body.levelId)
    if body.scope == "cycle":
        cycle = session.get(SchoolCycle, school_class.cycle_id) if school_class.cycle_id else None
        return bool(cycle and (
            str(cycle.id) == str(body.cycle)
            or cycle.code == canonical_cycle_code(body.cycle)
        ))
    return False

@app.post("/api/v1/school/finance/fees", status_code=201)
def create_finance_fee(
    body: FinanceFeeInput,
    current: Principal = Depends(require_module_roles("finance", "admin", "superadmin")),
    session: Session = Depends(db),
):
    school_id, establishment_id = module_tenant_scope(current, session, body.schoolId)
    try:
        academic_year_id = uuid.UUID(body.academicYearId)
    except ValueError as exc:
        raise HTTPException(422, "Année scolaire invalide") from exc
    academic_year = session.get(AcademicYear, academic_year_id)
    if not academic_year or academic_year.establishment_id != establishment_id:
        raise HTTPException(403, "Année scolaire inter-établissement interdite")
    if body.scope == "class":
        try:
            target_class = session.get(SchoolClass, uuid.UUID(str(body.classId)))
        except (TypeError, ValueError):
            target_class = None
        if not target_class or target_class.establishment_id != establishment_id:
            raise HTTPException(403, "Classe inter-établissement interdite")
        if target_class.academic_year_id != academic_year_id:
            raise HTTPException(422, 'La classe ne correspond pas à l’année scolaire du tarif')
        ensure_class_module_access(current, target_class, establishment_id, session)
    if body.scope == "level":
        try:
            target_level = session.get(SchoolLevel, uuid.UUID(str(body.levelId)))
        except (TypeError, ValueError):
            target_level = None
        if not target_level or target_level.establishment_id != establishment_id:
            raise HTTPException(403, "Niveau inter-établissement interdit")
        ensure_direction_cycle_access(current, target_level.cycle_id)
    if body.scope == "cycle":
        try:
            cycle = session.get(SchoolCycle, uuid.UUID(str(body.cycle)))
        except (TypeError, ValueError):
            cycle = session.scalar(select(SchoolCycle).where(
                SchoolCycle.establishment_id == establishment_id,
                SchoolCycle.code == canonical_cycle_code(str(body.cycle)),
            ))
        if cycle and cycle.establishment_id != establishment_id:
            cycle = None
        if not cycle:
            raise HTTPException(422, "Cycle introuvable")
        ensure_direction_cycle_access(current, cycle.id)
    if body.scope == "establishment" and direction_cycle_scope(current) is not None:
        raise HTTPException(
            403,
            "Un administrateur de direction doit choisir un perimetre cycle, niveau ou classe",
        )
    if body.schoolRegime is not None:
        if body.scope == "establishment":
            raise HTTPException(
                422,
                "Un tarif lié au régime doit cibler un cycle, un niveau ou une classe",
            )
        target_cycle = None
        if body.scope == "class":
            target_class = session.get(SchoolClass, uuid.UUID(str(body.classId)))
            target_cycle = session.get(SchoolCycle, target_class.cycle_id) if target_class else None
        elif body.scope == "level":
            target_level = session.get(SchoolLevel, uuid.UUID(str(body.levelId)))
            target_cycle = session.get(SchoolCycle, target_level.cycle_id) if target_level else None
        elif body.scope == "cycle":
            try:
                target_cycle = session.get(SchoolCycle, uuid.UUID(str(body.cycle)))
            except (TypeError, ValueError):
                target_cycle = session.scalar(select(SchoolCycle).where(
                    SchoolCycle.establishment_id == establishment_id,
                    SchoolCycle.code == canonical_cycle_code(str(body.cycle)),
                ))
        if not target_cycle or target_cycle.code.strip().upper() not in {"MATERNELLE", "PRIMAIRE"}:
            raise HTTPException(
                422,
                "Les tarifs Mi-temps/Plein temps sont réservés à la Maternelle et au Primaire",
            )
    finance_lock(session, f"tariffs:{school_id}:{body.academicYearId}")
    if body.month is not None:
        from .finance import month_key
        if body.type != 'tuition':
            raise HTTPException(422, 'Un mois ne concerne que les frais mensuels')
        month_key(body.month, academic_year)
    finance_lock(session, f"fee:{school_id}:{body.academicYearId}:{body.scope}:{body.name.strip().casefold()}:{body.classId}:{body.levelId}:{body.cycle}")
    duplicate = next((
        row for row in finance_rows(session, "finance-fees", school_id, current)
        if row.payload.get("status", "active") == "active"
        and str(row.payload.get("academicYearId")) == body.academicYearId
        and row.payload.get('type', 'tuition') == body.type
        and row.payload.get('month') == body.month
        and (body.type != 'other' or row.payload.get('name', '').strip().casefold() == body.name.strip().casefold())
        and row.payload.get("scope", "establishment") == body.scope
        and str(row.payload.get("classId")) == str(body.classId)
        and str(row.payload.get("levelId")) == str(body.levelId)
        and str(row.payload.get("cycle")) == str(body.cycle)
        and row.payload.get("schoolRegime") == body.schoolRegime
    ), None)
    if duplicate:
        raise HTTPException(409, "Ce frais existe déjà pour ce périmètre")
    fee_id = f"FEE_{uuid.uuid4().hex[:16].upper()}"
    fee_payload = {
        "id": fee_id, "name": body.name.strip(), "amount": body.amount,
        "scope": body.scope, "cycle": body.cycle, "levelId": body.levelId,
        "classId": body.classId, "description": body.description.strip(),
        "type": body.type, "frequency": body.frequency, "month": body.month,
        "schoolRegime": body.schoolRegime,
        "schoolId": school_id, "institutionId": school_id,
        "academicYearId": body.academicYearId, "schoolYearId": body.academicYearId,
        "status": "active", "createdAt": datetime.now(timezone.utc).isoformat(),
    }
    session.add(Resource(
        id=fee_id, kind="finance-fees", school_id=school_id,
        establishment_id=establishment_id, academic_year_id=academic_year_id,
        payload=fee_payload,
    ))
    assignments = []
    for registration in finance_rows(session, "finance-registrations", school_id, current):
        if str(registration.payload.get("academicYearId")) != body.academicYearId:
            continue
        if registration.payload.get("status", "active") != "active":
            continue
        if not finance_fee_matches_registration(body, registration, session, establishment_id):
            continue
        assignment_id = f"FFA_{uuid.uuid4().hex[:16].upper()}"
        assignment_payload = {
            "id": assignment_id, "registrationId": registration.id,
            "feeId": fee_id, "studentId": registration.payload.get("studentId"),
            "studentName": registration.payload.get("studentName"),
            "amount": body.amount, "dueDate": None, "schoolId": school_id,
            "institutionId": school_id, "academicYearId": body.academicYearId,
            "schoolYearId": body.academicYearId, "status": "assigned",
        }
        session.add(Resource(
            id=assignment_id, kind="finance-fee-assignments", school_id=school_id,
            establishment_id=establishment_id, academic_year_id=academic_year_id,
            payload=assignment_payload,
        ))
        assignments.append(assignment_payload)
    session.commit()
    return {"fee": fee_payload, "assignments": assignments}

@app.get("/api/v1/school/finance/summary")
def finance_summary(
    current: Principal = Depends(require_module_roles("finance", "admin", "superadmin")),
    session: Session = Depends(db),
    school_id: str | None = None,
    academic_year_id: uuid.UUID | None = None,
):
    school_id, establishment_id = module_tenant_scope(current, session, school_id)
    if academic_year_id:
        year = session.get(AcademicYear, academic_year_id)
        if not year or year.establishment_id != establishment_id:
            raise HTTPException(403, 'Année scolaire hors établissement')
    assignments = finance_rows(session, "finance-fee-assignments", school_id, current)
    if academic_year_id:
        assignments = [item for item in assignments
            if str(item.payload.get('academicYearId')) == str(academic_year_id)]
    balances = [finance_assignment_balance(session, school_id, item) for item in assignments]
    expected = sum(item["expected"] for item in balances)
    paid = sum(item["paid"] for item in balances)
    return {
        "expected": expected,
        "paid": paid,
        "remaining": max(0, expected - paid),
        "collectionRate": round((paid * 100 / expected), 2) if expected else 0,
        "counts": {
            state: sum(1 for item in balances if item["status"] == state)
            for state in ("paid", "partial", "unpaid")
        },
    }

@app.get("/api/v1/school/finance/students/by-matricule/{matricule}")
def finance_student_by_matricule(
    matricule: str,
    school_id: str | None = None,
    current: Principal = Depends(require_module_roles("finance", "admin", "superadmin")),
    session: Session = Depends(db),
):
    school_id, establishment_id = module_tenant_scope(current, session, school_id)
    normalized_matricule = matricule.strip().lower()
    legacy_student_ids = select(StudentAcademicRegistration.student_id).where(
        StudentAcademicRegistration.establishment_id == establishment_id,
        func.lower(StudentAcademicRegistration.registration_number) == normalized_matricule,
    )
    student = session.scalar(select(Student).where(
        Student.establishment_id == establishment_id,
        or_(
            func.lower(Student.registration_number) == normalized_matricule,
            Student.id.in_(legacy_student_ids),
        ),
        Student.status != "archived",
    ))
    if not student:
        raise HTTPException(404, "Élève introuvable pour ce matricule")
    ensure_student_scope(student.id, current, session)
    registrations = [
        row for row in finance_rows(session, "finance-registrations", school_id, current)
        if str(row.payload.get("studentId")) == str(student.id)
    ]
    assignments = finance_rows(session, "finance-fee-assignments", school_id, current)
    situations = []
    for registration in registrations:
        lines = [
            item for item in assignments
            if item.payload.get("registrationId") == registration.id
        ]
        situations.append({
            "registration": registration.payload,
            "lines": [
                {**item.payload, **finance_assignment_balance(session, school_id, item)}
                for item in lines
            ],
        })
    return {"student": student_json(student, session), "situations": situations}

@app.post("/api/v1/school/finance/payments", status_code=201)
def create_finance_payment(
    body: FinancePaymentInput,
    current: Principal = Depends(require_module_roles("finance", "admin", "superadmin")),
    session: Session = Depends(db),
):
    school_id, establishment_id = module_tenant_scope(current, session, body.schoolId)
    # The assignment lock makes a simultaneous payment re-read the real balance
    # before it inserts its payment and receipt.
    finance_lock(session, f"assignment:{body.feeAssignmentId}")
    if body.reference:
        finance_lock(session, f"reference:{school_id}:{body.reference.strip().casefold()}")
    registration = finance_resource(
        session, "finance-registrations", body.registrationId, school_id, current
    )
    assignment = finance_resource(
        session, "finance-fee-assignments", body.feeAssignmentId, school_id, current
    )
    if assignment.payload.get("registrationId") != registration.id:
        raise HTTPException(422, "Le frais ne correspond pas à cette inscription")
    before = finance_assignment_balance(session, school_id, assignment)
    if body.amount > before["remaining"]:
        raise HTTPException(409, "Le montant dépasse le reste à payer")
    result = persist_finance_payment(body, current, session, school_id, establishment_id, registration, assignment, before)
    try:
        session.commit()
    except IntegrityError as exc:
        session.rollback()
        raise HTTPException(409, "Le paiement n’a pas pu être enregistré. Actualisez le solde puis réessayez.") from exc
    return result

def persist_finance_payment(
    body: FinancePaymentInput,
    current: Principal,
    session: Session,
    school_id: str,
    establishment_id: uuid.UUID,
    registration: Resource,
    assignment: Resource,
    before: dict[str, Any],
) -> dict[str, Any]:
    if body.reference and any(
        str(row.payload.get("reference") or '').strip().casefold() == body.reference.strip().casefold()
        for row in finance_rows(session, "finance-payments", school_id)
    ):
        raise HTTPException(409, "Cette référence de paiement existe déjà")
    now = datetime.now(timezone.utc)
    payment_id = f"PAY_{uuid.uuid4().hex[:16].upper()}"
    payment_payload = {
        "id": payment_id,
        "registrationId": registration.id,
        "feeAssignmentId": assignment.id,
        "studentId": registration.payload.get("studentId"),
        "studentName": registration.payload.get("studentName"),
        "amount": body.amount,
        "date": now.date().isoformat(),
        "paymentMethod": body.paymentMethod,
        "reference": body.reference.strip() if body.reference else None,
        "receivedBy": current.id,
        "note": body.note.strip() if body.note else None,
        "schoolId": school_id,
        "institutionId": school_id,
        "academicYearId": registration.payload.get("academicYearId"),
        "status": "active",
        "createdAt": now.isoformat(),
    }
    receipt_id = f"RC_{uuid.uuid4().hex[:16].upper()}"
    receipt_payload = {
        "id": receipt_id,
        "paymentId": payment_id,
        "receiptNumber": f"REC-{now:%Y%m%d}-{uuid.uuid4().hex[:6].upper()}",
        "date": now.date().isoformat(),
        "studentId": registration.payload.get("studentId"),
        "studentName": registration.payload.get("studentName"),
        "amount": body.amount,
        "schoolId": school_id,
        "academicYearId": registration.payload.get("academicYearId"),
        "status": "active",
        "createdAt": now.isoformat(),
    }
    session.add(Resource(
        id=payment_id, kind="finance-payments", school_id=school_id,
        establishment_id=establishment_id,
        academic_year_id=registration.academic_year_id,
        payload=payment_payload,
    ))
    session.add(Resource(
        id=receipt_id, kind="finance-receipts", school_id=school_id,
        establishment_id=establishment_id,
        academic_year_id=registration.academic_year_id,
        payload=receipt_payload,
    ))
    remaining = before["remaining"] - body.amount
    return {
        "payment": payment_payload,
        "receipt": receipt_payload,
        "balance": {
            "expected": before["expected"],
            "paid": before["paid"] + body.amount,
            "remaining": remaining,
            "status": "paid" if remaining == 0 else "partial",
        },
    }

@app.post("/api/v1/school/finance/payments/{payment_id}/cancel")
def cancel_finance_payment(
    payment_id: str,
    body: FinanceCancelInput,
    school_id: str | None = None,
    current: Principal = Depends(require_module_roles("finance", "admin", "superadmin")),
    session: Session = Depends(db),
):
    school_id, _ = module_tenant_scope(current, session, school_id)
    finance_lock(session, f"payment:{payment_id}")
    payment = finance_resource(
        session, "finance-payments", payment_id, school_id, current
    )
    if payment.payload.get('feeAssignmentId'):
        finance_lock(session, f"assignment:{payment.payload['feeAssignmentId']}")
    for allocation in payment.payload.get('allocations') or []:
        if allocation.get('feeAssignmentId'):
            finance_lock(session, f"assignment:{allocation['feeAssignmentId']}")
    if payment.payload.get("status") == "cancelled":
        raise HTTPException(409, "Ce paiement est déjà annulé")
    payload = dict(payment.payload)
    payload.update({
        "status": "cancelled",
        "cancelledAt": datetime.now(timezone.utc).isoformat(),
        "cancelledBy": current.id,
        "cancellationReason": body.reason.strip(),
    })
    payment.payload = payload
    # The receipt remains archived for audit but is never presented as a valid
    # proof of payment after cancellation.
    for receipt in finance_rows(session, "finance-receipts", school_id, current):
        if receipt.payload.get("paymentId") != payment_id:
            continue
        receipt_payload = dict(receipt.payload)
        receipt_payload.update({
            "status": "cancelled",
            "cancelledAt": payload["cancelledAt"],
            "cancelledBy": current.id,
            "cancellationReason": payload["cancellationReason"],
        })
        receipt.payload = receipt_payload
    session.commit()
    return payload

@app.post("/api/v1/school/documents", status_code=201)
def create_school_document(
    body: DocumentCreateInput,
    current: Principal = Depends(require_module_roles("documents", "admin", "superadmin")),
    session: Session = Depends(db),
):
    school_id, establishment_id = module_tenant_scope(current, session, body.schoolId)
    academic_year_id = None
    if body.academicYearId:
        try:
            academic_year_id = uuid.UUID(body.academicYearId)
        except ValueError as exc:
            raise HTTPException(422, "Année scolaire invalide") from exc
        year = session.get(AcademicYear, academic_year_id)
        if not year or year.establishment_id != establishment_id:
            raise HTTPException(403, "Année scolaire inter-établissement interdite")
    entity_id = body.entityId
    metadata = dict(body.metadata)
    if body.type in {"student_record", "financial_statement"}:
        try:
            entity = session.get(Student, uuid.UUID(str(entity_id)))
        except (TypeError, ValueError):
            entity = None
        if not entity or entity.establishment_id != establishment_id:
            raise HTTPException(403, "Élève inter-établissement interdit")
        ensure_student_scope(entity.id, current, session)
    elif body.type in {"class_list", "schedule", "attendance", "behavior", "official_results"}:
        try:
            entity = session.get(SchoolClass, uuid.UUID(str(entity_id)))
        except (TypeError, ValueError):
            entity = None
        if not entity or entity.establishment_id != establishment_id:
            raise HTTPException(403, "Classe inter-établissement interdite")
        ensure_class_module_access(current, entity, establishment_id, session)
    elif body.type == "registration":
        try:
            entity = session.get(
                StudentAcademicRegistration, uuid.UUID(str(entity_id))
            )
        except (TypeError, ValueError):
            entity = None
        if not entity or entity.establishment_id != establishment_id:
            raise HTTPException(403, "Inscription inter-établissement interdite")
        ensure_class_module_access(
            current,
            session.get(SchoolClass, entity.class_id),
            establishment_id,
            session,
        )
    elif body.type in {"teacher_record", "teacher_assignments"}:
        try:
            entity = session.get(Teacher, uuid.UUID(str(entity_id)))
        except (TypeError, ValueError):
            entity = None
        if not entity or entity.establishment_id != establishment_id:
            raise HTTPException(403, "Enseignant inter-établissement interdit")
        scoped_teacher(entity.id, current, session)
    elif body.type == "payment_receipt":
        finance_resource(
            session, "finance-receipts", str(entity_id), school_id, current
        )
    if body.type == 'official_results':
        try:
            period_id = uuid.UUID(str(metadata.get('periodId')))
        except (ValueError, TypeError) as exc:
            raise HTTPException(422, 'La période du résultat est obligatoire') from exc
        result = school_results(entity.id, period_id, current, session)
        if result.get('calculationStatus') != 'official':
            raise HTTPException(409, 'Les résultats doivent être officiels avant génération')
        if metadata.get('studentId'):
            student_result = next((row for row in result['students']
                if row['studentId'] == str(metadata['studentId'])), None)
            if student_result is None:
                raise HTTPException(403, 'Élève absent des résultats de cette classe')
            if metadata.get('documentKind') == 'bulletin' and 'subjects' not in student_result:
                raise HTTPException(409, 'Recalculez les résultats pour obtenir le détail officiel du bulletin')
        metadata.update({'resultStatus': 'official', 'calculatedAt': result.get('calculatedAt')})
    document_id = f"DOC_{uuid.uuid4().hex[:16].upper()}"
    payload = {
        "id": document_id,
        "title": body.title.strip(),
        "type": body.type,
        "entityId": entity_id,
        "academicYearId": body.academicYearId,
        "metadata": metadata,
        "date": datetime.now(timezone.utc).isoformat(),
        "createdBy": current.id,
        "status": "generated",
        "schoolId": school_id,
    }
    session.add(Resource(
        id=document_id, kind="documents", school_id=school_id,
        establishment_id=establishment_id, academic_year_id=academic_year_id,
        payload=payload,
    ))
    session.commit()
    return payload

def resource_view(row: Resource, current: Principal, session: Session) -> dict[str, Any]:
    payload = dict(row.payload)
    if row.kind == "notifications":
        read_by = {str(value) for value in payload.get("readByUserIds", [])}
        payload["read"] = bool(payload.get("read")) or current.id in read_by
    if row.kind == 'documents' and payload.get('type') == 'official_results':
        metadata = payload.get('metadata') or {}
        try:
            result = school_results(uuid.UUID(str(payload.get('entityId'))),
                uuid.UUID(str(metadata.get('periodId'))), current, session)
            if (result.get('calculationStatus') != 'official'
                    or result.get('calculatedAt') != metadata.get('calculatedAt')):
                payload['status'] = 'stale'
        except (HTTPException, ValueError, TypeError):
            payload['status'] = 'stale'
    return payload

def _virtual_registration_receipts(
    current: Principal, session: Session,
    academic_year_id: uuid.UUID | None = None,
) -> list[Resource]:
    """Expose registration/re-enrollment proofs in Documents without duplicating cash.

    Finance intentionally synthesizes these receipts from a validated academic
    registration.  Documents mirrors the same source of truth as transient
    Resource objects so existing and future registrations appear immediately.
    Nothing is inserted in the ledger or database by this read operation.
    """
    if current.role == "superadmin" or not current.school_id:
        return []
    try:
        database_id = resolve_establishment_id(session, current.school_id)
    except HTTPException:
        return []
    if not database_id:
        return []
    from .finance import registration_receipts
    virtual: list[Resource] = []
    year_statement = select(AcademicYear).where(
        AcademicYear.establishment_id == database_id
    )
    if academic_year_id:
        year_statement = year_statement.where(AcademicYear.id == academic_year_id)
    years = session.scalars(year_statement).all()
    for year in years:
        for receipt in registration_receipts(
            session, current, current.school_id, database_id, year
        ):
            created = datetime.now(timezone.utc)
            raw_date = receipt.get("date")
            if raw_date:
                try:
                    created = datetime.fromisoformat(str(raw_date))
                    if created.tzinfo is None:
                        created = created.replace(tzinfo=timezone.utc)
                except ValueError:
                    pass
            virtual.append(Resource(
                id=str(receipt["id"]),
                kind="finance-receipts",
                school_id=current.school_id,
                establishment_id=database_id,
                academic_year_id=year.id,
                payload=dict(receipt),
                created_at=created,
                updated_at=created,
            ))
    return virtual


def document_history_rows(
    current: Principal, session: Session,
    academic_year_id: uuid.UUID | None = None,
) -> list[Resource]:
    """Load document metadata with a set-based direction scope."""
    statement = select(Resource).where(
        Resource.kind.in_(("documents", "finance-receipts"))
    )
    if current.role != "superadmin":
        statement = statement.where(Resource.school_id == current.school_id)
    if academic_year_id:
        statement = statement.where(Resource.academic_year_id == academic_year_id)
    rows = list(session.scalars(statement.order_by(
        Resource.created_at.desc(), Resource.id.desc()
    )).all())
    existing_receipt_ids = {row.id for row in rows if row.kind == "finance-receipts"}
    rows.extend(
        row for row in _virtual_registration_receipts(
            current, session, academic_year_id
        )
        if row.id not in existing_receipt_ids
    )
    rows.sort(key=lambda row: (row.created_at or datetime.min.replace(tzinfo=timezone.utc), row.id), reverse=True)
    if current.role == "student":
        student_id = str(current.student_id or "")
        return [
            row for row in rows
            if str(
                row.payload.get("studentId")
                or (row.payload.get("metadata") or {}).get("studentId")
                or ""
            ) == student_id
        ]
    if current.role == "parent":
        guardian = session.scalar(select(Guardian).where(
            Guardian.user_id == uuid.UUID(current.id),
            Guardian.status == "active",
        ))
        if not guardian:
            return []
        child_ids = {str(value) for value in session.scalars(select(
            StudentGuardian.student_id
        ).where(
            StudentGuardian.guardian_id == guardian.id,
            StudentGuardian.establishment_id == guardian.establishment_id,
        )).all()}
        return [
            row for row in rows
            if str(
                row.payload.get("studentId")
                or (row.payload.get("metadata") or {}).get("studentId")
                or ""
            ) in child_ids
        ]
    allowed = direction_cycle_scope(current)
    if current.role != "admin" or allowed is None:
        return rows
    class_ids = set(session.scalars(select(SchoolClass.id).where(
        SchoolClass.cycle_id.in_(allowed)
    )).all())
    registration_rows = session.execute(select(
        StudentAcademicRegistration.id,
        StudentAcademicRegistration.student_id,
    ).where(StudentAcademicRegistration.class_id.in_(class_ids))).all()
    registration_ids = {str(item.id) for item in registration_rows}
    student_ids = {str(item.student_id) for item in registration_rows}
    teacher_ids = {str(value) for value in session.scalars(select(
        Affectation.teacher_id
    ).where(Affectation.class_id.in_(class_ids))).all()}
    class_ids_text = {str(value) for value in class_ids}
    visible_rows = []
    for row in rows:
        if row.kind == "finance-receipts" and direction_resource_allowed(
            current, row, session
        ):
            visible_rows.append(row)
            continue
        if row.cycle_id in allowed:
            visible_rows.append(row)
            continue
        entity_id = str(row.payload.get("entityId") or "")
        document_type = row.payload.get("type")
        if (
            entity_id in class_ids_text
            or document_type in {"student_record", "financial_statement"}
            and entity_id in student_ids
            or document_type == "registration"
            and entity_id in registration_ids
            or document_type in {"teacher_record", "teacher_assignments"}
            and entity_id in teacher_ids
        ):
            visible_rows.append(row)
            continue
        if document_type == "payment_receipt" and direction_resource_allowed(
            current, row, session
        ):
            visible_rows.append(row)
    return visible_rows

def document_history_payload(row: Resource, current: Principal, session: Session) -> dict[str, Any]:
    if row.kind != "finance-receipts":
        return resource_view(row, current, session)
    receipt = dict(row.payload)
    return {
        "id": f"DOC_RECEIPT_{row.id}",
        "title": receipt.get("label") or "Reçu de paiement",
        "type": "payment_receipt",
        "entityId": row.id,
        "academicYearId": receipt.get("academicYearId"),
        "metadata": {
            "documentKind": "receipt",
            "studentId": receipt.get("studentId"),
            "receiptId": row.id,
            "registrationId": receipt.get("registrationId") or receipt.get("schoolRegistrationId"),
            "nature": receipt.get("type"),
        },
        "studentId": receipt.get("studentId"),
        "studentName": receipt.get("studentName"),
        "classId": receipt.get("classId"),
        "className": receipt.get("className"),
        "matricule": receipt.get("matricule"),
        "nature": receipt.get("type"),
        "amount": receipt.get("amount"),
        "receiptNumber": receipt.get("receiptNumber"),
        "date": receipt.get("date") or receipt.get("createdAt"),
        "status": "cancelled" if receipt.get("status") == "cancelled" else "generated",
        "schoolId": row.school_id,
    }

DOCUMENT_CATEGORIES = (
    "Bulletins", "Reçus", "Documents scolaires", "Documents administratifs",
)

def document_category(payload: dict[str, Any]) -> str:
    metadata = payload.get("metadata") or {}
    if metadata.get("documentKind") == "bulletin" or payload.get("type") == "official_results":
        return "Bulletins"
    if payload.get("type") == "payment_receipt":
        return "Reçus"
    if payload.get("type") in {"student_record", "class_list", "registration", "financial_statement", "schedule", "generated_report"}:
        return "Documents scolaires"
    return "Documents administratifs"

def enriched_document_history_payload(
    row: Resource, payload: dict[str, Any], session: Session,
) -> tuple[dict[str, Any], SchoolClass | None, Student | None]:
    metadata = payload.get("metadata") or {}
    document_class_id = str(
        payload.get("classId")
        or (payload.get("entityId") if payload.get("type") != "payment_receipt" else "")
        or ""
    )
    document_class = None
    if document_class_id:
        try:
            document_class = session.get(SchoolClass, uuid.UUID(document_class_id))
        except (TypeError, ValueError):
            pass
    if document_class is None and metadata.get("registrationId"):
        try:
            registration = session.get(
                StudentAcademicRegistration,
                uuid.UUID(str(metadata["registrationId"])),
            )
            if registration:
                document_class = session.get(SchoolClass, registration.class_id)
                document_class_id = str(registration.class_id)
        except (TypeError, ValueError):
            pass
    student_id = metadata.get("studentId") or payload.get("studentId")
    student = None
    if student_id:
        try:
            student = session.get(Student, uuid.UUID(str(student_id)))
        except (TypeError, ValueError):
            pass
    return ({
        **payload,
        "category": document_category(payload),
        "studentName": payload.get("studentName") or (
            f"{student.last_name} {student.first_name}" if student else None
        ),
        "matricule": payload.get("matricule") or (
            student.registration_number if student else None
        ),
        "className": payload.get("className") or (
            document_class.name if document_class else None
        ),
        "classId": document_class_id or None,
    }, document_class, student)

def paged_document_history(
    current: Principal, session: Session, *, category: str | None = None,
    page: int = 1, page_size: int = 100, academic_year_id: str | None = None,
    cycle_id: str | None = None, level_id: str | None = None,
    class_id: str | None = None,
    last_name: str | None = None, first_name: str | None = None,
    matricule: str | None = None, generated_month: str | None = None,
    nature: str | None = None,
) -> dict[str, Any]:
    """Filter then page the already direction-scoped document history server-side."""
    if category is not None and category not in DOCUMENT_CATEGORIES:
        raise HTTPException(422, "Catégorie de document invalide")
    rows = []
    parsed_year_id: uuid.UUID | None = None
    if academic_year_id:
        try:
            parsed_year_id = uuid.UUID(academic_year_id)
        except ValueError as exc:
            raise HTTPException(422, "Année scolaire invalide") from exc
    for row in document_history_rows(current, session, parsed_year_id):
        payload = document_history_payload(row, current, session)
        if category and document_category(payload) != category:
            continue
        if academic_year_id and str(payload.get("academicYearId")) != academic_year_id:
            continue
        enriched, document_class, student = enriched_document_history_payload(
            row, payload, session
        )
        document_class_id = str(enriched.get("classId") or "")
        if cycle_id and str(row.cycle_id or (document_class.cycle_id if document_class else "")) != cycle_id:
            continue
        if level_id and str(document_class.school_level_id if document_class else "") != level_id:
            continue
        if class_id and document_class_id != class_id:
            continue
        if generated_month and not str(payload.get("date") or "").startswith(generated_month):
            continue
        if last_name and (not student or last_name.casefold() not in student.last_name.casefold()):
            continue
        if first_name and (not student or first_name.casefold() not in student.first_name.casefold()):
            continue
        if matricule and matricule.casefold() not in str(enriched.get("matricule") or "").casefold():
            continue
        if nature and str(enriched.get("nature") or "") != nature:
            continue
        rows.append(enriched)
    total = len(rows)
    start = (page - 1) * page_size
    return {"items": rows[start:start + page_size], "page": page,
            "pageSize": page_size, "total": total,
            "pageCount": max(1, (total + page_size - 1) // page_size)}

@app.get("/api/v1/school/documents/history")
def paginated_documents(
    category: str | None = None, page: int = Query(1, ge=1),
    page_size: int = Query(100, ge=1, le=100), academic_year_id: str | None = None,
    cycle_id: str | None = None, level_id: str | None = None,
    class_id: str | None = None,
    last_name: str | None = None, first_name: str | None = None,
    matricule: str | None = None, generated_month: str | None = None,
    nature: str | None = None,
    current: Principal = Depends(require_module_roles(
        "documents", "superadmin", "admin"
    )),
    session: Session = Depends(db),
):
    if current.role in {"superadmin", "admin"}:
        ensure_plan_capability(current, session, "documents.advanced_search")
    return paged_document_history(current, session, category=category, page=page,
        page_size=page_size, academic_year_id=academic_year_id, cycle_id=cycle_id,
        level_id=level_id,
        class_id=class_id, last_name=last_name, first_name=first_name,
        matricule=matricule, generated_month=generated_month, nature=nature)

@app.get("/api/v1/school/documents/overview")
def document_overview(
    current: Principal = Depends(require_module_roles(
        "documents", "superadmin", "admin"
    )),
    session: Session = Depends(db),
    academic_year_id: str | None = None,
):
    selected_year_id: uuid.UUID | None = None
    if academic_year_id:
        try:
            selected_year_id = uuid.UUID(academic_year_id)
        except ValueError as exc:
            raise HTTPException(422, "Année scolaire invalide") from exc
        selected_year = session.get(AcademicYear, selected_year_id)
        if not selected_year:
            raise HTTPException(404, "Année scolaire introuvable")
        if current.role != "superadmin":
            _, database_id = school_scope(current, session, None, required=True)
            if selected_year.establishment_id != database_id:
                raise HTTPException(403, "Année scolaire hors du périmètre")
    overview = {
        category: {"items": [], "page": 1, "pageSize": 5, "total": 0,
                   "pageCount": 1}
        for category in DOCUMENT_CATEGORIES
    }
    # One direction-scoped traversal supplies all four cards; the former
    # implementation repeated the complete history scan once per category.
    for row in document_history_rows(current, session, selected_year_id):
        if selected_year_id and row.academic_year_id != selected_year_id:
            continue
        payload = document_history_payload(row, current, session)
        category = document_category(payload)
        group = overview[category]
        group["total"] += 1
        if len(group["items"]) < 5:
            enriched, _, _ = enriched_document_history_payload(
                row, payload, session
            )
            group["items"].append(enriched)
    for group in overview.values():
        group["pageCount"] = max(1, (group["total"] + 4) // 5)
    return overview


class DocumentReportInput(BaseModel):
    model_config = ConfigDict(populate_by_name=True, extra="forbid")
    report_type: Literal[
        "unpaid_tuition", "partial_tuition", "class_results",
        "enrolled_students", "evaluation_schedule", "cycle_top10",
        "cycle_statistics",
    ] = Field(alias="reportType")
    academic_year_id: uuid.UUID = Field(alias="academicYearId")
    cycle_id: uuid.UUID | None = Field(default=None, alias="cycleId")
    level_id: uuid.UUID | None = Field(default=None, alias="levelId")
    class_id: uuid.UUID | None = Field(default=None, alias="classId")
    period_id: uuid.UUID | None = Field(default=None, alias="periodId")
    subject_id: uuid.UUID | None = Field(default=None, alias="subjectId")
    month: str | None = None


def _document_report_context(
    body: DocumentReportInput, current: Principal, session: Session,
) -> tuple[AcademicYear, uuid.UUID, list[SchoolClass]]:
    if current.role == "superadmin":
        year = session.get(AcademicYear, body.academic_year_id)
        if not year:
            raise HTTPException(404, "Année scolaire introuvable")
        database_id = year.establishment_id
    else:
        _, database_id = module_tenant_scope(current, session)
        year = ensure_year_tenant(body.academic_year_id, database_id, session)
    stmt = select(SchoolClass).where(
        SchoolClass.establishment_id == database_id,
        SchoolClass.academic_year_id == year.id,
        SchoolClass.status == "active",
    )
    allowed = direction_cycle_scope(current)
    if allowed is not None:
        stmt = stmt.where(SchoolClass.cycle_id.in_(allowed))
    if body.cycle_id:
        ensure_direction_cycle_access(current, body.cycle_id)
        stmt = stmt.where(SchoolClass.cycle_id == body.cycle_id)
    if body.level_id:
        level = session.get(SchoolLevel, body.level_id)
        if not level or level.establishment_id != database_id:
            raise HTTPException(404, "Niveau introuvable dans ce périmètre")
        ensure_direction_cycle_access(current, level.cycle_id)
        stmt = stmt.where(SchoolClass.school_level_id == body.level_id)
    if body.class_id:
        stmt = stmt.where(SchoolClass.id == body.class_id)
    classes = list(session.scalars(stmt.order_by(SchoolClass.name)).all())
    if body.class_id and not classes:
        raise HTTPException(404, "Classe introuvable dans ce périmètre")
    return year, database_id, classes


def _report_school_header(session: Session, database_id: uuid.UUID, year: AcademicYear) -> dict[str, Any]:
    establishment = session.get(Establishment, database_id)
    return {
        "schoolName": establishment.name if establishment else "Établissement",
        "schoolCity": establishment.city if establishment else "",
        "academicYear": year.name,
        "generatedAt": datetime.now(timezone.utc).isoformat(),
    }


@app.post("/api/v1/school/documents/reports/generate")
def generate_document_report(
    body: DocumentReportInput,
    current: Principal = Depends(require_module_roles("documents", "superadmin", "admin")),
    session: Session = Depends(db),
):
    """Generate an auditable data snapshot for the requested school PDF."""
    year, database_id, classes = _document_report_context(body, current, session)
    header = _report_school_header(session, database_id, year)
    rows: list[dict[str, Any]] = []
    columns: list[dict[str, str]] = []
    title = "Rapport scolaire"

    if body.report_type in {"unpaid_tuition", "partial_tuition"}:
        if not body.class_id or not body.month:
            raise HTTPException(422, "La classe et le mois sont obligatoires")
        from .finance import roster as finance_roster
        public_id = public_school_id(session, database_id)
        data = finance_roster(
            year.id, "tuition", body.month, body.class_id, "", public_id,
            current, session,
        )
        expected_status = "unpaid" if body.report_type == "unpaid_tuition" else "partial"
        rows = [dict(item) for item in data.get("students", []) if item.get("status") == expected_status]
        title = "Élèves n’ayant pas payé les frais mensuels" if expected_status == "unpaid" else "Élèves ayant avancé sur les frais mensuels"
        columns = [
            {"key": "matricule", "label": "Matricule"},
            {"key": "studentName", "label": "Élève"},
            {"key": "className", "label": "Classe"},
            {"key": "expected", "label": "Attendu"},
            {"key": "paid", "label": "Payé"},
            {"key": "remaining", "label": "Reste"},
        ]
    elif body.report_type == "enrolled_students":
        if not body.class_id:
            raise HTTPException(422, "La classe est obligatoire")
        registrations = session.execute(select(StudentAcademicRegistration, Student).join(
            Student, Student.id == StudentAcademicRegistration.student_id
        ).where(
            StudentAcademicRegistration.establishment_id == database_id,
            StudentAcademicRegistration.academic_year_id == year.id,
            StudentAcademicRegistration.class_id == body.class_id,
            StudentAcademicRegistration.status.in_(("pending", "validated", "active")),
        ).order_by(StudentAcademicRegistration.registration_date)).all()
        for registration, student in registrations:
            rows.append({
                "matricule": registration.registration_number or student.registration_number or "",
                "studentName": f"{student.last_name} {student.first_name}",
                "sex": student.gender or "",
                "registrationDate": registration.registration_date.isoformat(),
            })
        title = "Liste des élèves inscrits"
        columns = [
            {"key": "matricule", "label": "Matricule"},
            {"key": "studentName", "label": "Élève"},
            {"key": "sex", "label": "Sexe"},
            {"key": "registrationDate", "label": "Date d’inscription"},
        ]
    elif body.report_type == "evaluation_schedule":
        class_ids = [item.id for item in classes]
        evaluations = [] if not class_ids else session.scalars(select(Evaluation).where(
            Evaluation.establishment_id == database_id,
            Evaluation.academic_year_id == year.id,
            Evaluation.class_id.in_(class_ids),
        ).order_by(Evaluation.date_scheduled, Evaluation.name)).all()
        evaluation_subject_ids = {item.subject_id for item in evaluations}
        evaluation_period_ids = {item.academic_period_id for item in evaluations}
        classes_by_id = {item.id: item for item in classes}
        subjects_by_id = {
            item.id: item for item in session.scalars(select(Subject).where(
                Subject.id.in_(evaluation_subject_ids)
            )).all()
        } if evaluation_subject_ids else {}
        periods_by_id = {
            item.id: item for item in session.scalars(select(AcademicPeriod).where(
                AcademicPeriod.id.in_(evaluation_period_ids)
            )).all()
        } if evaluation_period_ids else {}
        for evaluation in evaluations:
            school_class = classes_by_id.get(evaluation.class_id)
            subject = subjects_by_id.get(evaluation.subject_id)
            period = periods_by_id.get(evaluation.academic_period_id)
            rows.append({
                "date": evaluation.date_scheduled.isoformat() if evaluation.date_scheduled else "",
                "className": school_class.name if school_class else "",
                "period": period.name if period else "",
                "subject": subject.name if subject else "",
                "evaluation": evaluation.name,
                "type": evaluation.type,
            })
        title = "Calendrier des évaluations"
        columns = [
            {"key": "date", "label": "Date"},
            {"key": "className", "label": "Classe"},
            {"key": "period", "label": "Période"},
            {"key": "subject", "label": "Matière"},
            {"key": "evaluation", "label": "Évaluation"},
        ]
    elif body.report_type == "class_results":
        if not body.class_id or not body.period_id:
            raise HTTPException(422, "La classe et la période sont obligatoires")
        result = school_results(body.class_id, body.period_id, current, session)
        if result.get("calculationStatus") != "official":
            raise HTTPException(409, "Les résultats de cette classe ne sont pas officiels")
        rows = [dict(item) for item in result.get("students", [])]
        title = "Liste des résultats de la classe"
        columns = [
            {"key": "rank", "label": "Rang"},
            {"key": "studentName", "label": "Élève"},
            {"key": "average", "label": "Moyenne"},
        ]
    elif body.report_type in {"cycle_top10", "cycle_statistics"}:
        if body.report_type == "cycle_top10" and not body.cycle_id:
            raise HTTPException(422, "Le cycle est obligatoire")
        stat = statistics(
            school_id=public_school_id(session, database_id),
            academic_year_id=str(year.id),
            cycle=str(body.cycle_id) if body.cycle_id else None,
            level_id=str(body.level_id) if body.level_id else None,
            class_id=str(body.class_id) if body.class_id else None,
            period_id=str(body.period_id) if body.period_id else None,
            subject_id=str(body.subject_id) if body.subject_id else None,
            current=current,
            session=session,
        )
        if body.report_type == "cycle_top10":
            rows = [dict(item) for item in stat.get("top10", [])]
            title = "Les 10 meilleurs du cycle — tous niveaux confondus"
            columns = [
                {"key": "name", "label": "Élève"},
                {"key": "className", "label": "Classe"},
                {"key": "average20", "label": "Moyenne /20"},
                {"key": "mention", "label": "Appréciation"},
            ]
        else:
            rows = [
                {"indicator": "Élèves avec résultats officiels", "value": stat.get("officialStudentCount", 0)},
                {"indicator": "Moyenne générale /20", "value": stat.get("overallAverage") or "—"},
                {"indicator": "Élèves admis", "value": stat.get("successCount", 0)},
                {"indicator": "Élèves échoués", "value": stat.get("failureCount", 0)},
                {"indicator": "Taux de réussite", "value": f"{stat.get('successRate')} %" if stat.get("successRate") is not None else "—"},
                {"indicator": "Taux d’échec", "value": f"{stat.get('failureRate')} %" if stat.get("failureRate") is not None else "—"},
                *({"indicator": key, "value": value} for key, value in (stat.get("distribution") or {}).items()),
            ]
            title = "Statistiques scolaires" if not body.cycle_id else "Statistiques du cycle"
            columns = [
                {"key": "indicator", "label": "Indicateur"},
                {"key": "value", "label": "Valeur"},
            ]
    else:
        raise HTTPException(422, "Type de rapport non pris en charge")

    selected_class = classes[0] if body.class_id and classes else None
    selected_cycle = session.get(SchoolCycle, body.cycle_id) if body.cycle_id else (
        session.get(SchoolCycle, selected_class.cycle_id) if selected_class and selected_class.cycle_id else None
    )
    selected_period = session.get(AcademicPeriod, body.period_id) if body.period_id else None
    selected_level = session.get(SchoolLevel, body.level_id) if body.level_id else None
    selected_subject = session.get(Subject, body.subject_id) if body.subject_id else None
    payload = {
        **header,
        "title": title,
        "reportType": body.report_type,
        "academicYearId": str(year.id),
        "cycleId": str(body.cycle_id) if body.cycle_id else None,
        "cycleName": selected_cycle.name if selected_cycle else None,
        "levelId": str(body.level_id) if body.level_id else None,
        "levelName": selected_level.name if selected_level else None,
        "classId": str(body.class_id) if body.class_id else None,
        "className": selected_class.name if selected_class else None,
        "periodId": str(body.period_id) if body.period_id else None,
        "periodName": selected_period.name if selected_period else None,
        "subjectId": str(body.subject_id) if body.subject_id else None,
        "subjectName": selected_subject.name if selected_subject else None,
        "month": body.month,
        "columns": columns,
        "rows": rows,
        # Même instantané canonique que l'écran Statistiques : le document ne
        # maintient pas un second calcul susceptible de diverger.
        **({"statisticsData": stat} if body.report_type == "cycle_statistics" else {}),
    }
    report_id = f"DOC_REPORT_{uuid.uuid4().hex[:16].upper()}"
    document = {
        "id": report_id,
        "title": title,
        "type": "generated_report",
        "entityId": str(body.class_id or body.cycle_id or year.id),
        "academicYearId": str(year.id),
        "metadata": {"documentKind": "report", "report": payload},
        "date": datetime.now(timezone.utc).isoformat(),
        "createdBy": current.id,
        "status": "generated",
        "schoolId": public_school_id(session, database_id),
        "classId": str(body.class_id) if body.class_id else None,
        "className": selected_class.name if selected_class else None,
    }
    session.add(Resource(
        id=report_id,
        kind="documents",
        school_id=public_school_id(session, database_id),
        establishment_id=database_id,
        cycle_id=body.cycle_id or (selected_class.cycle_id if selected_class else None),
        academic_year_id=year.id,
        payload=document,
    ))
    session.commit()
    return {"document": document, "report": payload}

@app.post("/api/v1/school/notifications/teachers", status_code=201)
def create_teacher_in_app_notification(
    body: InAppTeacherNotificationInput,
    current: Principal = Depends(principal),
    session: Session = Depends(db),
):
    if current.role != "admin":
        raise HTTPException(
            403, "Les notifications groupées des enseignants sont réservées à l'administration"
        )
    school_id, database_id = module_tenant_scope(current, session)
    statement = select(Teacher).where(
        Teacher.establishment_id == database_id,
        Teacher.status == "active",
    )
    if body.teacher_ids:
        statement = statement.where(Teacher.id.in_(body.teacher_ids))
    allowed = direction_cycle_scope(current)
    if allowed is not None:
        scoped_teacher_ids = select(Affectation.teacher_id).join(
            SchoolClass, SchoolClass.id == Affectation.class_id
        ).where(
            Affectation.establishment_id == database_id,
            Affectation.status == "active",
            SchoolClass.cycle_id.in_(allowed),
        )
        statement = statement.where(Teacher.id.in_(scoped_teacher_ids))
    teachers = list(session.scalars(
        statement.order_by(Teacher.last_name, Teacher.first_name)
    ).all())
    if body.teacher_ids and len(teachers) != len(body.teacher_ids):
        raise HTTPException(
            403,
            "Un ou plusieurs enseignants sont hors de votre périmètre",
        )
    if not teachers:
        raise HTTPException(422, "Aucun enseignant actif dans ce périmètre")
    if len(teachers) > 500:
        raise HTTPException(409, "Notification groupée limitée à 500 enseignants")

    now = datetime.now(timezone.utc)
    notification_id = f"teacher-announcement-{uuid.uuid4().hex}"
    payload = {
        "id": notification_id,
        "type": "teacher_announcement",
        "category": body.category,
        "title": body.title,
        "message": body.message,
        "teacherIds": [str(item.id) for item in teachers],
        "schoolId": school_id,
        "createdBy": current.id,
        "read": False,
        "time": now.isoformat(),
    }
    session.add(Resource(
        id=notification_id,
        kind="notifications",
        school_id=school_id,
        establishment_id=database_id,
        academic_year_id=None,
        payload=payload,
    ))
    session.commit()
    return {
        **payload,
        "recipientCount": len(teachers),
    }


@app.put("/api/v1/notifications/{notification_id}/read", status_code=204)
def mark_workflow_notification_read(
    notification_id: str,
    current: Principal = Depends(principal),
    session: Session = Depends(db),
):
    row = session.get(Resource, {"kind": "notifications", "id": notification_id})
    if not row or not visible(row, current, session):
        raise HTTPException(404, "Notification introuvable")
    payload = dict(row.payload)
    read_by = {str(value) for value in payload.get("readByUserIds", [])}
    read_by.add(current.id)
    payload["readByUserIds"] = sorted(read_by)
    row.payload = payload
    row.updated_at = datetime.now(timezone.utc)
    session.commit()
    return Response(status_code=status.HTTP_204_NO_CONTENT)

@app.post("/api/v1/notifications/read-all", status_code=204)
def mark_all_workflow_notifications_read(
    current: Principal = Depends(principal),
    session: Session = Depends(db),
):
    for row in session.scalars(
        select(Resource).where(Resource.kind == "notifications")
    ).all():
        if not visible(row, current, session):
            continue
        payload = dict(row.payload)
        read_by = {str(value) for value in payload.get("readByUserIds", [])}
        read_by.add(current.id)
        payload["readByUserIds"] = sorted(read_by)
        row.payload = payload
        row.updated_at = datetime.now(timezone.utc)
    session.commit()
    return Response(status_code=status.HTTP_204_NO_CONTENT)

@app.get("/api/v1/{kind}")
def list_resources(kind: str, current: Principal = Depends(principal), session: Session = Depends(db)):
    if kind not in KINDS: raise HTTPException(404, "Ressource inconnue")
    ensure_generic_resource_module_access(kind, current, session)
    if kind == "documents":
        # Documents is an administrative workspace. Old Flutter links and
        # direct generic API calls must follow the same role policy.
        if current.role not in {"superadmin", "admin"}:
            raise HTTPException(403, "Les documents sont réservés à l'administration")
        return [
            document_history_payload(row, current, session)
            for row in document_history_rows(current, session)
        ]
    rows = [r for r in session.scalars(select(Resource).where(Resource.kind == kind)).all()
            if visible(r, current, session)]
    if kind == "notifications" and current.role == "superadmin":
        rows = [row for row in rows if not row.school_id]
    # The history page needs metadata only. Re-running the complete Results
    # workflow once per archived bulletin made a simple list increasingly slow.
    # Source freshness remains validated when a new official document is made.
    return [resource_view(r, current, session) for r in rows]
@app.post("/api/v1/{kind}", status_code=201)
def create_resource(kind: str, body: ResourceInput, current: Principal = Depends(require("superadmin", "admin", "teacher")), session: Session = Depends(db)):
    if kind.startswith(('finance-', 'financial-')) or kind == 'documents':
        raise HTTPException(409, 'Utilisez le workflow métier dédié pour cette opération')
    if kind not in KINDS: raise HTTPException(404, "Ressource inconnue")
    ensure_generic_resource_module_access(kind, current, session)
    if kind == "behavior-assessments":
        raise HTTPException(410, "Utilisez le workflow relationnel /api/v1/school/behavior")
    if kind == "establishments":
        raise HTTPException(
            410,
            "La création générique d'un établissement est retirée; utilisez le workflow Super Admin multi-cycle",
        )
    if kind == "subscriptions" and current.role != "superadmin": raise HTTPException(403, "Seul le superadmin gère les abonnements")
    if current.role == "teacher" and kind not in {"evaluations", "grades", "behavior-assessments", "absences", "assignments", "announcements"}: raise HTTPException(403, "Permission insuffisante")
    payload = dict(body.payload); resource_id = str(payload.get("id") or uuid.uuid4()); payload["id"] = resource_id
    school_id = tenant_for(kind, payload, current)
    validate_tenant_references(payload, school_id, session)
    validate_registration_class_consistency(kind, payload, school_id, session)
    database_establishment_id, cycle_id, school_level_id, academic_year_id = structured_resource_columns(
        kind, payload, school_id, session
    )
    ensure_generic_resource_direction_access(kind, payload, school_id, current, session)
    if kind == "announcements" and current.role == "teacher":
        if str(payload.get("authorUserId")) != current.id:
            raise HTTPException(403, "L’auteur de l’annonce doit être l’enseignant connecté")
        if payload.get("classId") and not teacher_has_class_access(payload.get("classId"), current, session):
            raise HTTPException(403, "Cette classe n’est pas affectée à l’enseignant")
    if kind == "absences" and current.role == "teacher" and not teacher_has_class_access(payload.get("classId"), current, session):
        raise HTTPException(403, "Cette classe n’est pas affectée à l’enseignant")
    if kind == "behavior-assessments":
        try:
            score = float(payload.get("score"))
        except (TypeError, ValueError) as exc:
            raise HTTPException(422, "La note comportementale doit être numérique") from exc
        if not 0 <= score <= 20:
            raise HTTPException(422, "La note comportementale doit être comprise entre 0 et 20")
        payload["score"] = score
        if current.role == "teacher":
            if str(payload.get("teacherId")) != current.teacher_id or str(payload.get("teacherUserId")) != current.id:
                raise HTTPException(403, "Seul l’enseignant connecté peut attribuer cette évaluation")
            if not teacher_has_class_access(payload.get("classId"), current, session):
                raise HTTPException(403, "Cette classe n’est pas affectée à l’enseignant")
    if session.get(Resource, {"kind":kind,"id":resource_id}): raise HTTPException(409, "Identifiant déjà utilisé")
    session.add(Resource(
        id=resource_id,
        kind=kind,
        school_id=school_id,
        establishment_id=database_establishment_id,
        cycle_id=cycle_id,
        school_level_id=school_level_id,
        academic_year_id=academic_year_id,
        payload=payload,
    )); session.commit(); return payload
@app.put("/api/v1/{kind}/{resource_id}")
def update_resource(kind: str, resource_id: str, body: ResourceInput, current: Principal = Depends(require("superadmin", "admin", "teacher")), session: Session = Depends(db)):
    if kind.startswith(('finance-', 'financial-')) or kind == 'documents':
        raise HTTPException(409, 'Cette pièce est archivée; utilisez le workflow métier dédié')
    if kind not in KINDS: raise HTTPException(404, "Ressource inconnue")
    ensure_generic_resource_module_access(kind, current, session)
    if kind == "behavior-assessments":
        raise HTTPException(410, "Un comportement envoye est immuable; utilisez /api/v1/school/behavior")
    if kind == "establishments" and current.role != "superadmin": raise HTTPException(403, "Utilisez la route établissement Admin")
    row = session.get(Resource, {"kind":kind,"id":resource_id})
    if not row or not visible(row,current,session): raise HTTPException(404, "Ressource introuvable")
    if kind == "subscriptions" and current.role != "superadmin": raise HTTPException(403, "Seul le superadmin gère les abonnements")
    if current.role == "teacher" and kind not in {"evaluations", "grades", "behavior-assessments", "absences", "assignments", "announcements"}: raise HTTPException(403, "Permission insuffisante")
    payload = dict(body.payload); payload["id"] = resource_id
    if kind == "establishments" and not payload.get("databaseId"):
        payload["databaseId"] = row.payload.get("databaseId")
    school_id = tenant_for(kind,payload,current)
    if kind != "establishments":
        validate_tenant_references(payload, school_id, session)
        validate_registration_class_consistency(kind, payload, school_id, session)
        database_establishment_id, cycle_id, school_level_id, academic_year_id = structured_resource_columns(
            kind, payload, school_id, session, row
        )
        ensure_generic_resource_direction_access(kind, payload, school_id, current, session)
    else:
        database_establishment_id = resolve_establishment_id(session, resource_id)
        cycle_id, school_level_id, academic_year_id = row.cycle_id, row.school_level_id, row.academic_year_id
    if kind == "behavior-assessments":
        try: score = float(payload.get("score"))
        except (TypeError, ValueError) as exc: raise HTTPException(422, "La note comportementale doit être numérique") from exc
        if not 0 <= score <= 20: raise HTTPException(422, "La note comportementale doit être comprise entre 0 et 20")
        if current.role == "teacher" and (str(row.payload.get("teacherId")) != current.teacher_id or str(row.payload.get("teacherUserId")) != current.id):
            raise HTTPException(403, "Un enseignant ne peut modifier que sa propre évaluation")
        payload["score"] = score
    row.payload, row.school_id = payload, school_id
    row.establishment_id = database_establishment_id
    row.cycle_id, row.school_level_id, row.academic_year_id = cycle_id, school_level_id, academic_year_id
    session.commit(); return payload
@app.delete("/api/v1/{kind}/{resource_id}", status_code=204)
def delete_resource(kind: str, resource_id: str, current: Principal = Depends(require("superadmin", "admin")), session: Session = Depends(db)):
    if kind.startswith(('finance-', 'financial-')) or kind == 'documents':
        raise HTTPException(409, 'Cette pièce est conservée pour audit; annulez le paiement si nécessaire')
    if kind not in KINDS: raise HTTPException(404, "Ressource inconnue")
    ensure_generic_resource_module_access(kind, current, session)
    if kind == "behavior-assessments":
        raise HTTPException(410, "Les comportements relationnels ne se suppriment pas par la route generique")
    if kind == "establishments" and current.role != "superadmin": raise HTTPException(403, "Seul le superadmin peut supprimer un établissement")
    if kind == "subscriptions" and current.role != "superadmin": raise HTTPException(403, "Seul le superadmin gère les abonnements")
    row = session.get(Resource, {"kind":kind,"id":resource_id})
    if not row or not visible(row,current,session): raise HTTPException(404, "Ressource introuvable")
    session.delete(row); session.commit(); return Response(status_code=status.HTTP_204_NO_CONTENT)

def series_json(item: SchoolSeries, session: Session) -> dict[str, Any]:
    cycle = session.get(SchoolCycle, item.cycle_id)
    return {'id': str(item.id), 'schoolId': public_school_id(session, item.establishment_id),
        'cycleId': str(item.cycle_id), 'cycle': cycle.name if cycle else None,
        'code': item.code, 'name': item.name, 'description': item.description,
        'sortOrder': item.sort_order, 'status': item.status}

@app.get('/api/v1/school/series')
def list_school_series(cycle_id: uuid.UUID | None = None, school_id: str | None = None,
    current: Principal = Depends(require_module('classes')), session: Session = Depends(db)):
    _, database_id = school_scope(current, session, school_id, required=True)
    statement = select(SchoolSeries).where(SchoolSeries.establishment_id == database_id,
        SchoolSeries.status != 'archived')
    allowed = direction_cycle_scope(current)
    if allowed is not None:
        statement = statement.where(SchoolSeries.cycle_id.in_(allowed))
    if cycle_id:
        ensure_direction_cycle_access(current, cycle_id)
        statement = statement.where(SchoolSeries.cycle_id == cycle_id)
    return [series_json(item, session) for item in session.scalars(
        statement.order_by(SchoolSeries.sort_order, SchoolSeries.name)).all()]

@app.post('/api/v1/school/series', status_code=201)
def create_school_series(body: SchoolSeriesInput,
    current: Principal = Depends(require_module_roles('classes', 'superadmin', 'admin')),
    session: Session = Depends(db)):
    _, database_id = school_scope(current, session, None, required=True)
    cycle = session.get(SchoolCycle, body.cycle_id)
    if not cycle:
        raise HTTPException(422, 'Cycle introuvable')
    if cycle.establishment_id != database_id:
        raise HTTPException(403, 'Cycle inter-etablissement interdit')
    ensure_direction_cycle_access(current, cycle.id)
    item = SchoolSeries(establishment_id=database_id, **body.model_dump())
    session.add(item)
    try:
        session.commit()
    except IntegrityError as exc:
        session.rollback()
        raise HTTPException(409, 'Une serie de meme code ou nom existe deja') from exc
    session.refresh(item)
    return series_json(item, session)

@app.put('/api/v1/school/series/{series_id}')
def update_school_series(series_id: uuid.UUID, body: SchoolSeriesInput,
    current: Principal = Depends(require_module_roles('classes', 'superadmin', 'admin')),
    session: Session = Depends(db)):
    _, database_id = module_tenant_scope(current, session)
    item = session.get(SchoolSeries, series_id)
    if not item:
        raise HTTPException(404, 'Serie introuvable')
    if item.establishment_id != database_id:
        raise HTTPException(403, 'Acces inter-etablissement interdit')
    ensure_direction_cycle_access(current, item.cycle_id)
    cycle = session.get(SchoolCycle, body.cycle_id)
    if not cycle or cycle.establishment_id != database_id:
        raise HTTPException(422, 'Cycle invalide')
    ensure_direction_cycle_access(current, cycle.id)
    for field, value in body.model_dump().items():
        setattr(item, field, value)
    item.updated_at = datetime.now(timezone.utc)
    session.commit()
    return series_json(item, session)

@app.delete('/api/v1/school/series/{series_id}', status_code=204)
def archive_school_series(series_id: uuid.UUID,
    current: Principal = Depends(require_module_roles('classes', 'superadmin', 'admin')),
    session: Session = Depends(db)):
    _, database_id = module_tenant_scope(current, session)
    item = session.get(SchoolSeries, series_id)
    if not item:
        raise HTTPException(404, 'Serie introuvable')
    if item.establishment_id != database_id:
        raise HTTPException(403, 'Acces inter-etablissement interdit')
    ensure_direction_cycle_access(current, item.cycle_id)
    used = session.scalar(select(func.count()).select_from(SchoolClass).where(
        SchoolClass.series_id == item.id, SchoolClass.status == 'active'))
    if used:
        raise HTTPException(409, 'Cette serie est utilisee par des classes actives')
    item.status = 'archived'
    item.updated_at = datetime.now(timezone.utc)
    session.commit()
    return Response(status_code=status.HTTP_204_NO_CONTENT)

@app.get('/api/v1/school/student-registrations/{registration_id}/transfers')
def registration_transfers(registration_id: uuid.UUID,
    current: Principal = Depends(require_module('students')), session: Session = Depends(db)):
    registration = session.get(StudentAcademicRegistration, registration_id)
    if not registration:
        raise HTTPException(404, 'Inscription introuvable')
    ensure_student_scope(registration.student_id, current, session)
    items = session.scalars(select(StudentClassTransfer).where(
        StudentClassTransfer.registration_id == registration.id
    ).order_by(StudentClassTransfer.effective_date)).all()
    return [{'id': str(item.id), 'fromClassId': str(item.from_class_id),
        'toClassId': str(item.to_class_id), 'effectiveDate': item.effective_date.isoformat(),
        'reason': item.reason, 'gradeHandlingDecision': item.grade_handling_decision} for item in items]

def _normalize_phone_for_provider(value: str) -> str:
    compact = re.sub(r'[^0-9+]', '', value)
    if not compact.startswith('+'):
        raise HTTPException(422, 'Le numéro doit être au format international, par exemple +242...')
    return compact


def _send_email_notification(body: ExternalNotificationInput) -> dict[str, Any]:
    host = os.getenv('SMTP_HOST')
    port = int(os.getenv('SMTP_PORT', '587'))
    username = os.getenv('SMTP_USERNAME')
    password = os.getenv('SMTP_PASSWORD')
    sender = os.getenv('SMTP_FROM') or username
    if not host or not sender:
        raise HTTPException(503, 'Le service e-mail n’est pas configuré')
    msg = EmailMessage()
    msg['From'] = sender
    msg['To'] = body.recipient
    msg['Subject'] = body.subject or 'Notification de votre établissement'
    msg.set_content(body.message)
    try:
        with smtplib.SMTP(host, port, timeout=10) as smtp:
            if os.getenv('SMTP_STARTTLS', 'true').lower() not in {'0', 'false', 'no'}:
                smtp.starttls()
            if username and password:
                smtp.login(username, password)
            smtp.send_message(msg)
    except (OSError, smtplib.SMTPException) as exc:
        raise HTTPException(502, 'Le fournisseur e-mail a refusé ou interrompu l’envoi') from exc
    return {'provider': 'smtp', 'status': 'accepted'}


def _send_twilio_notification(body: ExternalNotificationInput) -> dict[str, Any]:
    sid = os.getenv('TWILIO_ACCOUNT_SID')
    token = os.getenv('TWILIO_AUTH_TOKEN')
    from_number = (
        os.getenv('TWILIO_WHATSAPP_FROM')
        if body.channel == 'whatsapp'
        else os.getenv('TWILIO_SMS_FROM')
    )
    if not sid or not token or not from_number:
        raise HTTPException(503, f'Le service {body.channel.upper()} n’est pas configuré')
    recipient = _normalize_phone_for_provider(body.recipient)
    to_value = f'whatsapp:{recipient}' if body.channel == 'whatsapp' else recipient
    from_value = (
        from_number if body.channel == 'sms' or from_number.startswith('whatsapp:')
        else f'whatsapp:{from_number}'
    )
    payload = urllib.parse.urlencode({
        'To': to_value,
        'From': from_value,
        'Body': body.message,
    }).encode()
    request = urllib.request.Request(
        f'https://api.twilio.com/2010-04-01/Accounts/{sid}/Messages.json',
        data=payload,
        method='POST',
    )
    credentials = base64.b64encode(f'{sid}:{token}'.encode()).decode()
    request.add_header('Authorization', f'Basic {credentials}')
    request.add_header('Content-Type', 'application/x-www-form-urlencoded')
    try:
        with urllib.request.urlopen(request, timeout=10) as response:
            data = json.loads(response.read().decode())
    except Exception as exc:
        raise HTTPException(502, f'Le fournisseur {body.channel.upper()} a refusé ou interrompu l’envoi') from exc
    return {
        'provider': 'twilio',
        'status': data.get('status') or 'accepted',
        'providerMessageId': data.get('sid'),
    }


@app.post('/api/v1/school/communications/send')
def send_external_notification(
    body: ExternalNotificationInput,
    current: Principal = Depends(require_module_roles('messages', 'superadmin', 'admin')),
    session: Session = Depends(db),
):
    raise HTTPException(410, 'Le module Communication est retiré de cette version')
    # School users remain tenant-scoped. Super Admin may send an explicit
    # platform notification because the recipient is provided directly and no
    # school data is read for this operation.
    if current.role != 'superadmin':
        module_tenant_scope(current, session)
    result = (
        _send_email_notification(body)
        if body.channel == 'email'
        else _send_twilio_notification(body)
    )
    return {
        'channel': body.channel,
        'recipient': body.recipient,
        **result,
        'message': 'Envoi accepté par le fournisseur configuré.',
    }



@app.post('/api/v1/school/communications/teachers/broadcast')
def broadcast_to_teachers(
    body: TeacherBroadcastInput,
    current: Principal = Depends(require_module_roles('messages', 'superadmin', 'admin')),
    session: Session = Depends(db),
):
    raise HTTPException(410, 'Le module Communication est retiré de cette version')
    if current.role == 'superadmin':
        if not body.school_id:
            raise HTTPException(422, 'Sélectionnez un établissement avant l’envoi groupé')
        database_id = resolve_establishment_id(session, body.school_id)
        if not database_id:
            raise HTTPException(404, 'Établissement introuvable')
    else:
        public_id, database_id = module_tenant_scope(current, session)
        if body.school_id and body.school_id != public_id:
            raise HTTPException(403, 'Envoi inter-établissement interdit')
    stmt = select(Teacher).where(
        Teacher.establishment_id == database_id,
        Teacher.status == 'active',
    )
    allowed = direction_cycle_scope(current)
    if allowed is not None:
        teacher_ids = select(Affectation.teacher_id).join(
            SchoolClass, SchoolClass.id == Affectation.class_id
        ).where(
            Affectation.establishment_id == database_id,
            Affectation.status == 'active',
            SchoolClass.cycle_id.in_(allowed),
        )
        stmt = stmt.where(Teacher.id.in_(teacher_ids))
    teachers = list(session.scalars(stmt.order_by(Teacher.last_name, Teacher.first_name)).all())
    if len(teachers) > 500:
        raise HTTPException(409, 'Envoi groupé limité à 500 enseignants par opération')
    sent: list[dict[str, Any]] = []
    skipped: list[dict[str, Any]] = []
    failed: list[dict[str, Any]] = []
    for teacher in teachers:
        recipient = teacher.email if body.channel == 'email' else teacher.phone
        if not recipient:
            skipped.append({'teacherId': str(teacher.id), 'name': f'{teacher.last_name} {teacher.first_name}', 'reason': 'contact manquant'})
            continue
        notification = ExternalNotificationInput(
            channel=body.channel,
            recipient=recipient,
            subject=body.subject,
            message=body.message,
            confirmed=True,
        )
        try:
            result = _send_email_notification(notification) if body.channel == 'email' else _send_twilio_notification(notification)
            sent.append({'teacherId': str(teacher.id), 'recipient': recipient, **result})
        except HTTPException as exc:
            failed.append({'teacherId': str(teacher.id), 'recipient': recipient, 'reason': str(exc.detail)})
    if failed and not sent:
        raise HTTPException(502, {
            'message': 'Aucun message n’a été accepté par le fournisseur configuré.',
            'failed': failed,
            'skipped': skipped,
        })
    return {
        'channel': body.channel,
        'teacherCount': len(teachers),
        'sentCount': len(sent),
        'skippedCount': len(skipped),
        'failedCount': len(failed),
        'sent': sent,
        'skipped': skipped,
        'failed': failed,
        'message': f'{len(sent)} envoi(s) accepté(s) par le fournisseur.',
    }


def calendar_setting_json(item: SchoolCalendarSetting) -> dict[str, Any]:
    return {'id': str(item.id), 'academicYearId': str(item.academic_year_id),
        'teachingDays': item.teaching_days, 'dayStart': item.day_start.isoformat(timespec='minutes'),
        'dayEnd': item.day_end.isoformat(timespec='minutes'),
        'courseDurationMinutes': item.course_duration_minutes,
        'pauseDurationMinutes': item.pause_duration_minutes,
        'pauseFrequency': item.pause_frequency, 'status': item.status}

def calendar_event_json(item: SchoolCalendarEvent) -> dict[str, Any]:
    return {'id': str(item.id), 'academicYearId': str(item.academic_year_id),
        'periodId': str(item.academic_period_id) if item.academic_period_id else None,
        'title': item.title, 'eventType': item.event_type,
        'startDate': item.start_date.isoformat(), 'endDate': item.end_date.isoformat(),
        'description': item.description, 'status': item.status}

def ensure_year_tenant(year_id: uuid.UUID, database_id: uuid.UUID, session: Session) -> AcademicYear:
    year = session.get(AcademicYear, year_id)
    if not year:
        raise HTTPException(422, 'Annee scolaire introuvable')
    if year.establishment_id != database_id:
        raise HTTPException(403, 'Annee scolaire inter-etablissement interdite')
    return year

@app.get('/api/v1/school/calendar/settings')
def get_calendar_setting(academic_year_id: uuid.UUID,
    current: Principal = Depends(require_module('schedule')), session: Session = Depends(db)):
    _, database_id = module_tenant_scope(current, session)
    ensure_year_tenant(academic_year_id, database_id, session)
    item = session.scalar(select(SchoolCalendarSetting).where(
        SchoolCalendarSetting.establishment_id == database_id,
        SchoolCalendarSetting.academic_year_id == academic_year_id))
    return calendar_setting_json(item) if item else None

@app.put('/api/v1/school/calendar/settings')
def upsert_calendar_setting(body: CalendarSettingInput,
    current: Principal = Depends(require_module_roles('schedule', 'superadmin', 'admin')),
    session: Session = Depends(db)):
    _, database_id = module_tenant_scope(current, session)
    ensure_year_tenant(body.academic_year_id, database_id, session)
    item = session.scalar(select(SchoolCalendarSetting).where(
        SchoolCalendarSetting.establishment_id == database_id,
        SchoolCalendarSetting.academic_year_id == body.academic_year_id))
    if not item:
        item = SchoolCalendarSetting(establishment_id=database_id, academic_year_id=body.academic_year_id)
        session.add(item)
    for field, value in body.model_dump().items():
        setattr(item, field, value)
    item.updated_at = datetime.now(timezone.utc)
    session.commit()
    session.refresh(item)
    return calendar_setting_json(item)

@app.get('/api/v1/school/calendar/events')
def list_calendar_events(academic_year_id: uuid.UUID,
    current: Principal = Depends(require_module('schedule')), session: Session = Depends(db)):
    _, database_id = module_tenant_scope(current, session)
    ensure_year_tenant(academic_year_id, database_id, session)
    items = session.scalars(select(SchoolCalendarEvent).where(
        SchoolCalendarEvent.establishment_id == database_id,
        SchoolCalendarEvent.academic_year_id == academic_year_id,
        SchoolCalendarEvent.status != 'archived'
    ).order_by(SchoolCalendarEvent.start_date)).all()
    return [calendar_event_json(item) for item in items]

@app.post('/api/v1/school/calendar/events', status_code=201)
def create_calendar_event(body: CalendarEventInput,
    current: Principal = Depends(require_module_roles('schedule', 'superadmin', 'admin')),
    session: Session = Depends(db)):
    _, database_id = module_tenant_scope(current, session)
    year = ensure_year_tenant(body.academic_year_id, database_id, session)
    if body.start_date < year.start_date or body.end_date > year.end_date or body.start_date > body.end_date:
        raise HTTPException(422, 'Evenement hors des limites de l annee scolaire')
    if body.academic_period_id:
        period = session.get(AcademicPeriod, body.academic_period_id)
        if not period or period.establishment_id != database_id or period.academic_year_id != year.id:
            raise HTTPException(422, 'Periode pedagogique invalide')
    item = SchoolCalendarEvent(establishment_id=database_id, **body.model_dump(), status='active')
    session.add(item)
    session.commit()
    session.refresh(item)
    return calendar_event_json(item)

@app.put('/api/v1/school/calendar/events/{event_id}')
def update_calendar_event(event_id: uuid.UUID, body: CalendarEventInput,
    current: Principal = Depends(require_module_roles('schedule', 'superadmin', 'admin')),
    session: Session = Depends(db)):
    _, database_id = module_tenant_scope(current, session)
    item = session.get(SchoolCalendarEvent, event_id)
    if not item:
        raise HTTPException(404, 'Evenement introuvable')
    if item.establishment_id != database_id:
        raise HTTPException(403, 'Acces inter-etablissement interdit')
    year = ensure_year_tenant(body.academic_year_id, database_id, session)
    if body.start_date < year.start_date or body.end_date > year.end_date or body.start_date > body.end_date:
        raise HTTPException(422, 'Evenement hors des limites de l annee scolaire')
    for field, value in body.model_dump().items():
        setattr(item, field, value)
    item.updated_at = datetime.now(timezone.utc)
    session.commit()
    return calendar_event_json(item)

def evaluation_rule_json(item: EvaluationRule) -> dict[str, Any]:
    return {'id': str(item.id), 'academicYearId': str(item.academic_year_id),
        'cycleId': str(item.cycle_id),
        'schoolLevelId': str(item.school_level_id) if item.school_level_id else None,
        'seriesId': str(item.series_id) if item.series_id else None,
        'evaluationType': item.evaluation_type, 'label': item.label,
        'expectedCount': item.expected_count,
        'contributesToAverage': item.contributes_to_average,
        'isRequired': item.is_required, 'sortOrder': item.sort_order, 'status': item.status}

def validate_evaluation_rule_context(body: EvaluationRuleInput, database_id: uuid.UUID, session: Session) -> None:
    ensure_year_tenant(body.academic_year_id, database_id, session)
    cycle = session.get(SchoolCycle, body.cycle_id)
    if not cycle or cycle.establishment_id != database_id:
        raise HTTPException(422, 'Cycle invalide')
    if body.school_level_id:
        level = session.get(SchoolLevel, body.school_level_id)
        if not level or level.establishment_id != database_id or level.cycle_id != cycle.id:
            raise HTTPException(422, 'Niveau incompatible avec le cycle')
    validate_series_scope(body.series_id, database_id, cycle.id, session)

@app.get('/api/v1/school/evaluation-rules')
def list_evaluation_rules(academic_year_id: uuid.UUID,
    current: Principal = Depends(require_module('grades')), session: Session = Depends(db)):
    _, database_id = module_tenant_scope(current, session)
    ensure_year_tenant(academic_year_id, database_id, session)
    statement = select(EvaluationRule).where(
        EvaluationRule.establishment_id == database_id,
        EvaluationRule.academic_year_id == academic_year_id,
        EvaluationRule.status != 'archived'
    )
    allowed = direction_cycle_scope(current)
    if allowed is not None:
        statement = statement.where(EvaluationRule.cycle_id.in_(allowed))
    items = session.scalars(statement.order_by(
        EvaluationRule.sort_order, EvaluationRule.label
    )).all()
    return [evaluation_rule_json(item) for item in items]

@app.post('/api/v1/school/evaluation-rules', status_code=201)
def create_evaluation_rule(body: EvaluationRuleInput,
    current: Principal = Depends(require_module_roles('grades', 'superadmin', 'admin')),
    session: Session = Depends(db)):
    _, database_id = module_tenant_scope(current, session)
    validate_evaluation_rule_context(body, database_id, session)
    ensure_direction_cycle_access(current, body.cycle_id)
    item = EvaluationRule(establishment_id=database_id, **body.model_dump(), status='active')
    session.add(item)
    try:
        session.commit()
    except IntegrityError as exc:
        session.rollback()
        raise HTTPException(409, 'Cette regle pedagogique existe deja') from exc
    session.refresh(item)
    return evaluation_rule_json(item)

@app.put('/api/v1/school/evaluation-rules/{rule_id}')
def update_evaluation_rule(rule_id: uuid.UUID, body: EvaluationRuleInput,
    current: Principal = Depends(require_module_roles('grades', 'superadmin', 'admin')),
    session: Session = Depends(db)):
    _, database_id = module_tenant_scope(current, session)
    item = session.get(EvaluationRule, rule_id)
    if not item:
        raise HTTPException(404, 'Regle pedagogique introuvable')
    if item.establishment_id != database_id:
        raise HTTPException(403, 'Acces inter-etablissement interdit')
    ensure_direction_cycle_access(current, item.cycle_id)
    validate_evaluation_rule_context(body, database_id, session)
    ensure_direction_cycle_access(current, body.cycle_id)
    for field, value in body.model_dump().items():
        setattr(item, field, value)
    item.updated_at = datetime.now(timezone.utc)
    session.commit()
    return evaluation_rule_json(item)

@app.put('/api/v1/school/students/{student_id}/annual-decision')
def upsert_annual_decision(student_id: uuid.UUID, body: AnnualDecisionInput,
    current: Principal = Depends(require_module_roles('students', 'superadmin', 'admin')),
    session: Session = Depends(db)):
    student = ensure_student_scope(student_id, current, session)
    ensure_year_tenant(body.academic_year_id, student.establishment_id, session)
    registration = session.scalar(select(StudentAcademicRegistration).where(
        StudentAcademicRegistration.student_id == student.id,
        StudentAcademicRegistration.academic_year_id == body.academic_year_id,
        StudentAcademicRegistration.status.in_(('pending', 'validated', 'active'))))
    if not registration:
        raise HTTPException(409, 'Une inscription annuelle est requise pour cette decision')
    decision = body.decision
    if decision == 'excluded' and not (body.reason or '').strip():
        raise HTTPException(422, 'Le motif de l’exclusion est obligatoire')
    if decision != 'excluded':
        bulletin = student_bulletin(
            student.id, body.academic_year_id, current, session
        )
        annual_average = bulletin.get('annualAverage')
        if not bulletin.get('annualCalculable') or annual_average is None:
            raise HTTPException(
                409,
                'Le resultat annuel ne peut pas etre calcule avant la reception de toutes les notes requises',
            )
        automatic_decision = 'admitted' if float(annual_average) >= 10 else 'repeat'
        if decision != automatic_decision:
            raise HTTPException(
                422,
                'La decision academique est calculee automatiquement a partir de la moyenne annuelle',
            )
        decision = automatic_decision
    item = session.scalar(select(StudentAnnualDecision).where(
        StudentAnnualDecision.establishment_id == student.establishment_id,
        StudentAnnualDecision.student_id == student.id,
        StudentAnnualDecision.academic_year_id == body.academic_year_id))
    if not item:
        item = StudentAnnualDecision(establishment_id=student.establishment_id,
            student_id=student.id, academic_year_id=body.academic_year_id)
        session.add(item)
    item.decision = decision
    item.reason = body.reason.strip() if body.reason else None
    item.decided_by = uuid.UUID(current.id)
    item.decided_at = datetime.now(timezone.utc)
    item.updated_at = datetime.now(timezone.utc)
    session.commit()
    session.refresh(item)
    return {'id': str(item.id), 'studentId': str(item.student_id),
        'academicYearId': str(item.academic_year_id), 'decision': item.decision,
        'reason': item.reason, 'decidedAt': item.decided_at.isoformat()}

@app.get('/api/v1/school/attendance/statistics')
def attendance_statistics(class_id: uuid.UUID, period_id: uuid.UUID | None = None,
    month: int | None = None,
    current: Principal = Depends(require_module_roles('attendance', 'superadmin', 'admin', 'teacher')),
    session: Session = Depends(db)):
    from .attendance import report
    school_class = session.get(SchoolClass, class_id)
    if not school_class:
        raise HTTPException(404, "Classe introuvable")
    return report(current, session, school_class.academic_year_id,
        class_id=class_id, period_id=period_id, month=month)["statistics"]

@app.get('/api/v1/school/students/{student_id}/results')
def student_results(student_id: uuid.UUID, academic_year_id: uuid.UUID,
    current: Principal = Depends(require_module_roles(
        'grades', 'superadmin', 'admin', 'teacher', 'student', 'parent')),
    session: Session = Depends(db)):
    if current.role == "teacher":
        ensure_plan_capability(current, session, "grades.publish_teacher")
    elif current.role == "parent":
        ensure_plan_capability(current, session, "grades.publish_parent")
    elif current.role == "student":
        ensure_plan_capability(current, session, "grades.publish_student")
    student = session.get(Student, student_id)
    if not student:
        raise HTTPException(404, 'Eleve introuvable')
    registration = session.scalar(select(StudentAcademicRegistration).where(
        StudentAcademicRegistration.student_id == student.id,
        StudentAcademicRegistration.academic_year_id == academic_year_id,
        StudentAcademicRegistration.status.in_(('pending', 'validated', 'active'))))
    if not registration:
        raise HTTPException(404, 'Inscription annuelle introuvable')
    ensure_student_results_access(student, registration, current, session)
    periods = session.scalars(select(AcademicPeriod).where(
        AcademicPeriod.establishment_id == student.establishment_id,
        AcademicPeriod.academic_year_id == academic_year_id,
        AcademicPeriod.status == 'active'
    ).order_by(AcademicPeriod.sort_order, AcademicPeriod.code)).all()
    payload = []
    school_class = session.get(SchoolClass, registration.class_id)
    average_scale = general_average_scale(session, school_class)

    period_by_id = {item.id: item for item in periods}
    subject_ids = set(session.scalars(select(Grade.subject_id).join(
        Evaluation, Evaluation.id == Grade.evaluation_id
    ).where(
        Grade.establishment_id == student.establishment_id,
        Grade.student_id == student.id,
        Evaluation.establishment_id == student.establishment_id,
        Evaluation.class_id == registration.class_id,
        Evaluation.academic_year_id == academic_year_id,
        Evaluation.status.in_(('submitted', 'validated', 'locked')),
    )).all())
    subjects_by_id = {
        item.id: item for item in session.scalars(
            select(Subject).where(Subject.id.in_(subject_ids))
        ).all()
    } if subject_ids else {}
    submitted_notes = []
    note_rows = session.execute(select(Grade, Evaluation).join(
        Evaluation, Evaluation.id == Grade.evaluation_id
    ).where(
        Grade.establishment_id == student.establishment_id,
        Grade.student_id == student.id,
        Evaluation.establishment_id == student.establishment_id,
        Evaluation.class_id == registration.class_id,
        Evaluation.academic_year_id == academic_year_id,
        Evaluation.status.in_(('submitted', 'validated', 'locked')),
    ).order_by(
        Evaluation.date_scheduled.asc().nulls_last(),
        Evaluation.created_at.asc(),
        Grade.updated_at.asc(),
    )).all()
    for grade, evaluation in note_rows:
        period = period_by_id.get(evaluation.academic_period_id)
        subject = subjects_by_id.get(grade.subject_id)
        submitted_notes.append({
            'gradeId': str(grade.id),
            'evaluationId': str(evaluation.id),
            'evaluation': evaluation.name,
            'evaluationType': evaluation.type,
            'examCode': evaluation.exam_code,
            'periodId': str(period.id) if period else None,
            'period': period.name if period else evaluation.period,
            'periodType': period.period_type if period else None,
            'periodOrder': period.sort_order if period else None,
            'subjectId': str(grade.subject_id),
            'subject': subject.name if subject else '',
            'date': evaluation.date_scheduled.isoformat()
                if evaluation.date_scheduled else grade.updated_at.date().isoformat(),
            'value': effective_grade_value(grade),
            'maxValue': float(grade.max_value),
            'presence': grade.presence,
            'status': evaluation.status,
            'comment': grade.comment,
        })
    for period in periods:
        class_result = school_results(registration.class_id, period.id, current, session)
        if class_result.get('calculationStatus') != 'official':
            continue
        own_result = next((row for row in class_result['students'] if row['studentId'] == str(student.id)), None)
        if own_result is None:
            continue
        exams = []
        for code, event_result in (class_result.get('eventResults') or {}).items():
            own_event = next((
                row for row in event_result.get('students', [])
                if row.get('studentId') == str(student.id)
            ), None)
            if own_event:
                exams.append({
                    'code': code,
                    'name': event_result.get('event') or KNOWN_EVALUATION_EVENTS.get(code, code),
                    'average': own_event.get('average'),
                    'rank': own_event.get('rank'),
                    'subjects': own_event.get('subjects') or [],
                })
        average = own_result.get('average')
        ratio = (float(average) / average_scale) if average is not None else 0
        mention = (
            'Très bien' if ratio >= .8 else
            'Bien' if ratio >= .7 else
            'Assez bien' if ratio >= .6 else
            'Passable' if ratio >= .5 else
            'Insuffisant'
        ) if average is not None else None
        class_ranking = [{'studentId': row['studentId'], 'studentName': row['studentName'],
                'average': row['average'], 'rank': row['rank']} for row in class_result['students']]
        # A pupil or guardian needs the pupil's rank and the class size, not
        # the identity or marks of the other pupils. Administration and the
        # assigned teacher keep the existing detailed class-ranking payload.
        can_view_class_ranking = current.role not in {'student', 'parent'}
        payload.append({'periodId': str(period.id), 'period': period.name,
            'periodType': period.period_type,
            'periodOrder': period.sort_order,
            'parentPeriodId': str(period.parent_period_id) if period.parent_period_id else None,
            'startDate': period.start_date.isoformat() if period.start_date else None,
            'endDate': period.end_date.isoformat() if period.end_date else None,
            'average': average,
            'averageScale': average_scale,
            'rank': own_result.get('rank'),
            'mention': mention,
            'subjects': own_result.get('subjects') or [],
            'grades': [{
                **grade,
                'subjectId': subject.get('subjectId'),
                'subject': subject.get('subject'),
            } for subject in own_result.get('subjects', [])
                for grade in subject.get('grades', [])],
            'exams': exams,
            'rankingCount': len(class_ranking),
            'ranking': class_ranking if can_view_class_ranking else []})
    return {'studentId': str(student.id), 'academicYearId': str(academic_year_id),
        'registration': registration_json(registration, session),
        'notes': submitted_notes,
        'periods': payload}

@app.get('/api/v1/school/my-results')
def my_student_results(
    current: Principal = Depends(require_module_roles('grades', 'student')),
    session: Session = Depends(db),
):
    ensure_plan_capability(current, session, "students.access")
    ensure_plan_capability(current, session, "grades.publish_student")
    if not current.student_id:
        raise HTTPException(403, 'Aucun eleve associe a ce compte')
    try:
        student_id = uuid.UUID(current.student_id)
    except ValueError as exc:
        raise HTTPException(403, 'Association eleve invalide') from exc
    student = session.get(Student, student_id)
    if not student or student.user_id != uuid.UUID(current.id):
        raise HTTPException(403, 'Association eleve invalide')
    registrations = session.scalars(select(StudentAcademicRegistration).where(
        StudentAcademicRegistration.establishment_id == student.establishment_id,
        StudentAcademicRegistration.student_id == student.id,
        StudentAcademicRegistration.status.in_(('pending', 'validated', 'active')),
    ).order_by(StudentAcademicRegistration.registration_date.desc())).all()
    return {
        'studentId': str(student.id),
        'studentName': f'{student.last_name} {student.first_name}',
        'years': [
            student_results(student.id, registration.academic_year_id, current, session)
            for registration in registrations
        ],
    }

@app.get('/api/v1/school/my-children')
def my_children_for_results(
    current: Principal = Depends(require_module_roles('grades', 'parent')),
    session: Session = Depends(db),
):
    ensure_plan_capability(current, session, "parents.access")
    ensure_plan_capability(current, session, "grades.publish_parent")
    """Return only the children linked to the authenticated parent account."""
    guardian = session.scalar(select(Guardian).where(
        Guardian.user_id == uuid.UUID(current.id),
    ))
    if not guardian:
        return []
    rows = session.execute(select(Student, StudentAcademicRegistration).join(
        StudentGuardian, StudentGuardian.student_id == Student.id
    ).join(StudentAcademicRegistration, StudentAcademicRegistration.student_id == Student.id
    ).where(
        StudentGuardian.guardian_id == guardian.id,
        StudentGuardian.establishment_id == guardian.establishment_id,
        StudentAcademicRegistration.establishment_id == guardian.establishment_id,
        StudentAcademicRegistration.status.in_(('pending', 'validated', 'active')),
    ).order_by(Student.last_name, Student.first_name,
               StudentAcademicRegistration.registration_date.desc())).all()
    children: dict[uuid.UUID, dict[str, Any]] = {}
    for student, registration in rows:
        item = children.setdefault(student.id, {
            'id': str(student.id),
            'fullName': f'{student.last_name} {student.first_name}',
            'years': [],
        })
        academic_year = session.get(AcademicYear, registration.academic_year_id)
        item['years'].append({
            'id': str(registration.academic_year_id),
            'name': academic_year.name if academic_year else None,
            'className': registration_json(registration, session).get('className'),
        })
    return list(children.values())

def student_tracking_payload(
    student: Student,
    academic_year_id: uuid.UUID,
    current: Principal,
    session: Session,
) -> dict[str, Any]:
    registration = session.scalar(select(StudentAcademicRegistration).where(
        StudentAcademicRegistration.student_id == student.id,
        StudentAcademicRegistration.academic_year_id == academic_year_id,
        StudentAcademicRegistration.status.in_(("pending", "validated", "active")),
    ))
    if not registration:
        raise HTTPException(404, "Inscription annuelle introuvable")
    ensure_student_results_access(student, registration, current, session)
    establishment = session.get(Establishment, student.establishment_id)
    enabled_modules = set(establishment.enabled_modules or []) if establishment else set()
    result_data = student_results(student.id, academic_year_id, current, session)
    periods = list(session.scalars(select(AcademicPeriod).where(
        AcademicPeriod.establishment_id == student.establishment_id,
        AcademicPeriod.academic_year_id == academic_year_id,
        AcademicPeriod.period_type == "trimester",
        AcademicPeriod.status == "active",
    ).order_by(AcademicPeriod.sort_order, AcademicPeriod.code)))

    attendance = {"available": False, "total": 0, "present": 0,
                  "absent": 0, "late": 0, "byPeriod": []}
    if "attendance" in enabled_modules:
        records = session.scalars(select(AttendanceRecord).join(
            AttendanceSheet, AttendanceSheet.id == AttendanceRecord.sheet_id
        ).where(
            AttendanceRecord.establishment_id == student.establishment_id,
            AttendanceRecord.student_id == student.id,
            AttendanceRecord.academic_year_id == academic_year_id,
            AttendanceSheet.status == "locked",
        ).order_by(AttendanceRecord.attendance_date)).all()

        def attendance_counts(values: list[AttendanceRecord]) -> dict[str, int]:
            return {
                "total": len(values),
                "present": sum(item.status == "present" for item in values),
                "absent": sum(item.status == "absent" for item in values),
                "late": sum(item.status == "late" for item in values),
            }

        attendance.update(attendance_counts(records))
        attendance["available"] = True
        attendance["byPeriod"] = [{
            "periodId": str(period.id),
            "period": period.name,
            **attendance_counts([
                item for item in records
                if (period.start_date is None or item.attendance_date >= period.start_date)
                and (period.end_date is None or item.attendance_date <= period.end_date)
            ]),
        } for period in periods]

    behavior = {"available": False, "periods": []}
    if "behavior" in enabled_modules:
        from .behavior import state as behavior_state
        locked_events = list(session.scalars(select(BehaviorEvent).where(
            BehaviorEvent.establishment_id == student.establishment_id,
            BehaviorEvent.academic_year_id == academic_year_id,
            BehaviorEvent.class_id == registration.class_id,
            BehaviorEvent.student_id == student.id,
            BehaviorEvent.status.in_(("locked", "active")),
        ).order_by(BehaviorEvent.created_at)))
        behavior_teacher_ids = {item.teacher_id for item in locked_events if item.teacher_id}
        behavior_teachers = {item.id: item for item in session.scalars(
            select(Teacher).where(Teacher.id.in_(behavior_teacher_ids))).all()
        } if behavior_teacher_ids else {}
        behavior_periods = []
        for period in periods:
            behavior_payload, _ = behavior_state(
                current, session, registration.class_id, period.id
            )
            own_result = next((
                row for row in behavior_payload.get("students", [])
                if row.get("studentId") == str(student.id)
            ), None)
            comments = [item.description for item in locked_events
                        if item.academic_period_id == period.id and item.description]
            contributions = [{
                "teacher": (
                    f"{behavior_teachers[item.teacher_id].last_name} "
                    f"{behavior_teachers[item.teacher_id].first_name}"
                    if item.teacher_id in behavior_teachers else None
                ),
                "score": int(item.category.split(":")[1])
                    if re.fullmatch(r"stars:[1-5]", item.category or "") else None,
                "comment": item.description,
            } for item in locked_events if item.academic_period_id == period.id]
            if own_result or contributions:
                behavior_periods.append({
                    "periodId": str(period.id),
                    "period": period.name,
                    "status": behavior_payload.get("calculationStatus"),
                    "average": own_result.get("average") if own_result else None,
                    "contributionCount": own_result.get("contributionCount") if own_result else len(comments),
                    "comments": comments,
                    "contributions": contributions,
                })
        behavior = {"available": True, "periods": behavior_periods}

    return {
        "studentId": str(student.id),
        "studentName": f"{student.last_name} {student.first_name}",
        "academicYearId": str(academic_year_id),
        "results": result_data,
        "attendance": attendance,
        "behavior": behavior,
    }

@app.get('/api/v1/school/my-tracking')
def my_student_tracking(
    academic_year_id: uuid.UUID,
    current: Principal = Depends(require_module_roles('grades', 'student')),
    session: Session = Depends(db),
):
    if not current.student_id:
        raise HTTPException(403, "Aucun élève associé à ce compte")
    try:
        student_id = uuid.UUID(current.student_id)
    except ValueError as exc:
        raise HTTPException(403, "Association élève invalide") from exc
    student = session.get(Student, student_id)
    if not student or student.user_id != uuid.UUID(current.id):
        raise HTTPException(403, "Association élève invalide")
    return student_tracking_payload(student, academic_year_id, current, session)

@app.get('/api/v1/school/my-children/{student_id}/tracking')
def my_child_tracking(
    student_id: uuid.UUID,
    academic_year_id: uuid.UUID,
    current: Principal = Depends(require_module_roles('grades', 'parent')),
    session: Session = Depends(db),
):
    guardian = session.scalar(select(Guardian).where(
        Guardian.user_id == uuid.UUID(current.id),
    ))
    linked = guardian and session.scalar(select(StudentGuardian).where(
        StudentGuardian.guardian_id == guardian.id,
        StudentGuardian.student_id == student_id,
        StudentGuardian.establishment_id == guardian.establishment_id,
    ))
    if not linked:
        raise HTTPException(403, "Cet élève n’est pas lié à votre compte parent")
    student = session.get(Student, student_id)
    if not student or student.establishment_id != guardian.establishment_id:
        raise HTTPException(404, "Élève introuvable")
    return student_tracking_payload(student, academic_year_id, current, session)

@app.put('/api/v1/school/academic-periods/{period_id}')
def update_academic_period(period_id: uuid.UUID, body: AcademicPeriodInput,
    current: Principal = Depends(require_module_roles('grades', 'superadmin', 'admin')),
    session: Session = Depends(db)):
    _, database_id = module_tenant_scope(current, session)
    item = session.get(AcademicPeriod, period_id)
    if not item:
        raise HTTPException(404, 'Periode pedagogique introuvable')
    if item.establishment_id != database_id:
        raise HTTPException(403, 'Acces inter-etablissement interdit')
    ensure_year_tenant(body.academic_year_id, database_id, session)
    if body.parent_period_id:
        parent = session.get(AcademicPeriod, body.parent_period_id)
        if (not parent or parent.id == item.id
                or parent.establishment_id != database_id
                or parent.academic_year_id != body.academic_year_id
                or parent.period_type != 'trimester'
                or body.period_type == 'trimester'):
            raise HTTPException(422, 'Le trimestre parent est invalide')
    changes = body.model_dump()
    if changes['code'] is None:
        changes.pop('code')
    for field, value in changes.items():
        setattr(item, field, value)
    item.updated_at = datetime.now(timezone.utc)
    try:
        session.commit()
    except IntegrityError as exc:
        session.rollback()
        raise HTTPException(409, 'Cette periode existe deja') from exc
    session.refresh(item)
    return academic_period_json(item, session)

@app.delete('/api/v1/school/academic-periods/{period_id}', status_code=204)
def archive_academic_period(period_id: uuid.UUID,
    current: Principal = Depends(require_module_roles('grades', 'superadmin', 'admin')),
    session: Session = Depends(db)):
    _, database_id = module_tenant_scope(current, session)
    item = session.get(AcademicPeriod, period_id)
    if not item:
        raise HTTPException(404, 'Periode pedagogique introuvable')
    if item.establishment_id != database_id:
        raise HTTPException(403, 'Acces inter-etablissement interdit')
    in_use = session.scalar(select(Evaluation.id).where(
        Evaluation.academic_period_id == item.id).limit(1))
    behavior_in_use = session.scalar(select(BehaviorEvent.id).where(
        BehaviorEvent.academic_period_id == item.id,
        BehaviorEvent.status != 'archived').limit(1))
    if in_use or behavior_in_use:
        raise HTTPException(
            409,
            'Une periode utilisee par des evaluations ou comportements '
            'ne peut pas etre archivee',
        )
    item.status = 'archived'
    item.updated_at = datetime.now(timezone.utc)
    session.commit()
    return Response(status_code=status.HTTP_204_NO_CONTENT)

@app.delete('/api/v1/school/calendar/events/{event_id}', status_code=204)
def archive_calendar_event(event_id: uuid.UUID,
    current: Principal = Depends(require_module_roles('schedule', 'superadmin', 'admin')),
    session: Session = Depends(db)):
    _, database_id = module_tenant_scope(current, session)
    item = session.get(SchoolCalendarEvent, event_id)
    if not item:
        raise HTTPException(404, 'Evenement introuvable')
    if item.establishment_id != database_id:
        raise HTTPException(403, 'Acces inter-etablissement interdit')
    item.status = 'archived'
    item.updated_at = datetime.now(timezone.utc)
    session.commit()
    return Response(status_code=status.HTTP_204_NO_CONTENT)

@app.delete('/api/v1/school/evaluation-rules/{rule_id}', status_code=204)
def archive_evaluation_rule(rule_id: uuid.UUID,
    current: Principal = Depends(require_module_roles('grades', 'superadmin', 'admin')),
    session: Session = Depends(db)):
    _, database_id = module_tenant_scope(current, session)
    item = session.get(EvaluationRule, rule_id)
    if not item:
        raise HTTPException(404, 'Regle pedagogique introuvable')
    if item.establishment_id != database_id:
        raise HTTPException(403, 'Acces inter-etablissement interdit')
    ensure_direction_cycle_access(current, item.cycle_id)
    item.status = 'archived'
    item.updated_at = datetime.now(timezone.utc)
    session.commit()
    return Response(status_code=status.HTTP_204_NO_CONTENT)

@app.get('/api/v1/school/annual-decisions')
def list_annual_decisions(academic_year_id: uuid.UUID,
    current: Principal = Depends(require_module_roles(
        'students', 'superadmin', 'admin', 'teacher', 'student', 'parent')),
    session: Session = Depends(db)):
    _, database_id = module_tenant_scope(current, session)
    ensure_year_tenant(academic_year_id, database_id, session)
    statement = select(StudentAnnualDecision).where(
        StudentAnnualDecision.establishment_id == database_id,
        StudentAnnualDecision.academic_year_id == academic_year_id)
    if not annual_trimester_periods(session, database_id, academic_year_id):
        statement = statement.where(StudentAnnualDecision.decision == 'excluded')
    allowed = direction_cycle_scope(current)
    if allowed is not None:
        visible_students = (
            select(StudentAcademicRegistration.student_id)
            .join(SchoolClass, SchoolClass.id == StudentAcademicRegistration.class_id)
            .where(
                StudentAcademicRegistration.academic_year_id == academic_year_id,
                StudentAcademicRegistration.status.in_(("pending", "validated", "active")),
                SchoolClass.cycle_id.in_(allowed),
            )
        )
        statement = statement.where(
            StudentAnnualDecision.student_id.in_(visible_students)
        )
    if current.role == 'student':
        student = session.scalar(select(Student).where(
            Student.user_id == uuid.UUID(current.id)))
        if not student:
            raise HTTPException(403, 'Aucun eleve associe')
        statement = statement.where(StudentAnnualDecision.student_id == student.id)
    elif current.role == 'teacher':
        teacher_class_ids = select(Affectation.class_id).join(
            SchoolClass, SchoolClass.id == Affectation.class_id).where(
            Affectation.teacher_id == uuid.UUID(current.teacher_id),
            SchoolClass.academic_year_id == academic_year_id,
            Affectation.status == 'active',
        )
        teacher_student_ids = select(StudentAcademicRegistration.student_id).where(
            StudentAcademicRegistration.academic_year_id == academic_year_id,
            StudentAcademicRegistration.class_id.in_(teacher_class_ids),
            StudentAcademicRegistration.status.in_(("pending", "validated", "active")),
        )
        statement = statement.where(
            StudentAnnualDecision.student_id.in_(teacher_student_ids)
        )
    elif current.role == 'parent':
        allowed_student_ids = select(StudentGuardian.student_id).join(
            Guardian, Guardian.id == StudentGuardian.guardian_id).where(
                Guardian.user_id == uuid.UUID(current.id))
        statement = statement.where(
            StudentAnnualDecision.student_id.in_(allowed_student_ids))
    rows = session.scalars(statement.order_by(StudentAnnualDecision.decided_at)).all()
    return [{
        'id': str(item.id),
        'studentId': str(item.student_id),
        'academicYearId': str(item.academic_year_id),
        'decision': item.decision,
        'reason': item.reason,
        'decidedAt': item.decided_at.isoformat() if item.decided_at else None,
    } for item in rows]

@app.put('/api/v1/school/schedule/{entry_id}')
def update_schedule_entry(entry_id: uuid.UUID, body: ScheduleEntryInput,
    current: Principal = Depends(require_module_roles('schedule', 'superadmin', 'admin')),
    session: Session = Depends(db)):
    from .attendance import lock_schedule, snapshot
    lock_schedule(session, entry_id)
    _, database_id = module_tenant_scope(current, session)
    item = session.get(ScheduleEntry, entry_id)
    if not item:
        raise HTTPException(404, 'Creneau introuvable')
    if item.establishment_id != database_id:
        raise HTTPException(403, 'Acces inter-etablissement interdit')
    ensure_class_module_access(
        current, session.get(SchoolClass, item.class_id), database_id, session
    )
    school_class = ensure_class_module_access(
        current, session.get(SchoolClass, body.class_id), database_id, session)
    subject = session.get(Subject, body.subject_id)
    teacher = session.get(Teacher, body.teacher_id)
    if not subject or not teacher:
        raise HTTPException(422, 'Matiere ou enseignant introuvable')
    if subject.establishment_id != database_id or teacher.establishment_id != database_id:
        raise HTTPException(403, 'Reference inter-etablissement interdite')
    affectation = session.scalar(select(Affectation).where(
        Affectation.establishment_id == database_id,
        Affectation.class_id == school_class.id,
        Affectation.subject_id == subject.id,
        Affectation.teacher_id == teacher.id,
        Affectation.status == 'active'))
    if not affectation:
        raise HTTPException(422, 'Affectation enseignant/matiere/classe requise')
    calendar = session.scalar(select(SchoolCalendarSetting).where(
        SchoolCalendarSetting.establishment_id == database_id,
        SchoolCalendarSetting.academic_year_id == school_class.academic_year_id,
        SchoolCalendarSetting.status == 'active'))
    if calendar:
        if body.weekday not in calendar.teaching_days:
            raise HTTPException(422, 'Ce jour ne fait pas partie des jours de cours configures')
        if body.start_time < calendar.day_start or body.end_time > calendar.day_end:
            raise HTTPException(422, 'Le cours est hors des horaires configures')
    overlap = session.scalar(select(ScheduleEntry).where(
        ScheduleEntry.establishment_id == database_id,
        ScheduleEntry.academic_year_id == school_class.academic_year_id,
        ScheduleEntry.id != item.id,
        ScheduleEntry.weekday == body.weekday,
        ScheduleEntry.status == 'active',
        ScheduleEntry.start_time < body.end_time,
        ScheduleEntry.end_time > body.start_time,
        (ScheduleEntry.teacher_id == teacher.id) | (
            ScheduleEntry.class_id == school_class.id)))
    if overlap:
        if overlap.teacher_id == teacher.id:
            raise HTTPException(409, 'Conflit enseignant sur ce creneau')
        raise HTTPException(409, 'Cette classe possede deja un cours sur ce creneau')
    if item.status != 'active':
        raise HTTPException(409, 'Ce créneau a déjà été remplacé. Actualisez le planning')
    item.status = 'archived'
    item.retired_at = datetime.now(timezone.utc)
    session.flush()
    item = ScheduleEntry(establishment_id=database_id, created_by=uuid.UUID(current.id))
    session.add(item)
    item.academic_year_id = school_class.academic_year_id
    item.class_id = school_class.id
    item.subject_id = subject.id
    item.teacher_id = teacher.id
    item.affectation_id = affectation.id
    item.weekday = body.weekday
    item.start_time = body.start_time
    item.end_time = body.end_time
    item.room = None
    item.attendance_context = snapshot(session, item)
    item.updated_at = datetime.now(timezone.utc)
    session.commit()
    session.refresh(item)
    return schedule_json(item, session)


from .finance import router as school_finance_router
app.include_router(school_finance_router)

# The production Flutter build is served by FastAPI when it is available.
# Keeping this mount last preserves every API route and allows a single public
# endpoint (including an ngrok tunnel) to expose both the UI and the backend.
flutter_web_directory = Path(__file__).resolve().parents[2] / "build" / "web"
if flutter_web_directory.is_dir():
    app.mount(
        "/",
        StaticFiles(directory=str(flutter_web_directory), html=True),
        name="flutter-web",
    )

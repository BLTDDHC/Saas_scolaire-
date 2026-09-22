"""Explicit, interactive bootstrap for the first global Super Admin."""

from __future__ import annotations

import argparse
import getpass
import re
import sys

from fastapi import HTTPException
from sqlalchemy import func, select, text
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.main import (
    User,
    engine,
    password_policy_available,
    passwords,
    validate_new_password,
)


BOOTSTRAP_LOCK = "godfirst-school:first-superadmin"


class BootstrapError(RuntimeError):
    """Expected refusal that must not expose credentials or a traceback."""


def normalize_email(value: str) -> str:
    email = value.strip().lower()
    if len(email) > 254 or not re.fullmatch(r"[^\s@]+@[^\s@]+\.[^\s@]+", email):
        raise BootstrapError("Adresse e-mail invalide.")
    return email


def validate_name(value: str) -> str:
    name = " ".join(value.strip().split())
    if not 2 <= len(name) <= 160:
        raise BootstrapError("Le nom doit contenir entre 2 et 160 caractères.")
    return name


def read_password(*, show_password: bool = False) -> str:
    reader = input if show_password else getpass.getpass
    password = reader("Mot de passe : ")
    confirmation = reader("Confirmez le mot de passe : ")
    if password != confirmation:
        raise BootstrapError("Les mots de passe ne correspondent pas.")
    try:
        validate_new_password(password)
    except HTTPException as error:
        raise BootstrapError(str(error.detail)) from error
    return password


def assert_available(session: Session, email: str) -> None:
    existing_superadmin = session.scalar(
        select(User.id).where(User.role == "superadmin").limit(1)
    )
    if existing_superadmin is not None:
        raise BootstrapError("Le système possède déjà un Super Admin.")
    existing_email = session.scalar(
        select(User.id).where(func.lower(User.email) == email).limit(1)
    )
    if existing_email is not None:
        raise BootstrapError(
            "Cette adresse e-mail existe déjà. Utilisez une autre adresse ou le mécanisme administratif approprié."
        )


def create_first_superadmin(name: str, email: str, password: str) -> User:
    with Session(engine) as session:
        # Serialize concurrent bootstrap attempts. Preconditions are repeated
        # while the transaction lock is held so two invocations cannot win.
        session.execute(
            text("SELECT pg_advisory_xact_lock(hashtext(:lock_name))"),
            {"lock_name": BOOTSTRAP_LOCK},
        )
        assert_available(session, email)
        password_hash = passwords.hash(password)
        user = User(
            email=email,
            password_hash=password_hash,
            name=name,
            role="superadmin",
            school_id=None,
            direction_id=None,
            status="active",
            password_set=True,
        )
        session.add(user)
        session.flush()
        if password_policy_available(session):
            session.execute(
                text(
                    "UPDATE users SET must_change_password = FALSE WHERE id = :user_id"
                ),
                {"user_id": user.id},
            )
        session.commit()
        session.refresh(user)
        return user


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Créer explicitement le premier Super Admin global."
    )
    parser.add_argument(
        "--show-password",
        action="store_true",
        help="Afficher localement le mot de passe pendant la saisie.",
    )
    arguments = parser.parse_args()
    if not sys.stdin.isatty():
        print(
            "Ce script exige un terminal interactif afin de masquer le mot de passe.",
            file=sys.stderr,
        )
        return 2
    try:
        name = validate_name(input("Nom affiché : "))
        email = normalize_email(input("Adresse e-mail : "))
        with Session(engine) as session:
            assert_available(session, email)
        password = read_password(show_password=arguments.show_password)
        user = create_first_superadmin(name, email, password)
        del password
    except BootstrapError as error:
        print(f"Création refusée : {error}", file=sys.stderr)
        return 1
    except IntegrityError:
        print(
            "Création refusée : conflit d'unicité en base de données.",
            file=sys.stderr,
        )
        return 1
    print(
        f"Super Admin créé : email={user.email}, rôle={user.role}, état={user.status}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

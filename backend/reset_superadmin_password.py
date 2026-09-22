"""Explicit interactive password reset for the existing global Super Admin."""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
import getpass
import json
import sys
from urllib.request import Request, urlopen

from fastapi import HTTPException
from sqlalchemy import func, select, text
from sqlalchemy.orm import Session

from app.main import (
    User,
    engine,
    password_policy_available,
    passwords,
    validate_new_password,
)


LOCK_NAME = "godfirst-school:reset-superadmin-password"


class ResetError(RuntimeError):
    """Expected refusal without credential disclosure or traceback."""


def read_password(*, show_password: bool) -> str:
    reader = input if show_password else getpass.getpass
    password = reader("Nouveau mot de passe : ")
    confirmation = reader("Confirmez le nouveau mot de passe : ")
    if password != confirmation:
        raise ResetError("Les mots de passe ne correspondent pas.")
    try:
        validate_new_password(password)
    except HTTPException as error:
        raise ResetError(str(error.detail)) from error
    return password


def reset_password(email: str, password: str) -> User:
    normalized_email = email.strip().lower()
    with Session(engine) as session:
        session.execute(
            text("SELECT pg_advisory_xact_lock(hashtext(:name))"),
            {"name": LOCK_NAME},
        )
        superadmins = list(session.scalars(
            select(User).where(User.role == "superadmin").with_for_update()
        ).all())
        if len(superadmins) != 1:
            raise ResetError(
                "Le reset exige exactement un Super Admin existant."
            )
        user = superadmins[0]
        if user.email.strip().lower() != normalized_email:
            raise ResetError("L'adresse ne correspond pas au Super Admin existant.")
        if user.school_id is not None or user.direction_id is not None:
            raise ResetError("Le Super Admin existant n'est pas global.")
        if user.status != "active":
            raise ResetError("Le Super Admin existant n'est pas actif.")

        user.password_hash = passwords.hash(password)
        user.password_set = True
        user.updated_at = datetime.now(timezone.utc)
        if password_policy_available(session):
            session.execute(
                text(
                    "UPDATE users SET must_change_password = FALSE "
                    "WHERE id = :user_id"
                ),
                {"user_id": user.id},
            )
        session.commit()
        session.refresh(user)
        return user


def verify_live_authentication(email: str, password: str) -> None:
    base_url = "http://127.0.0.1:8000"
    request = Request(
        f"{base_url}/api/v1/auth/login",
        data=json.dumps({"email": email, "password": password}).encode("utf-8"),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urlopen(request, timeout=10) as response:
        login_payload = json.loads(response.read())
        if response.status != 200 or not login_payload.get("accessToken"):
            raise ResetError("La vérification du login a échoué.")
    request = Request(
        f"{base_url}/api/v1/auth/me",
        headers={"Authorization": f"Bearer {login_payload['accessToken']}"},
    )
    with urlopen(request, timeout=10) as response:
        profile = json.loads(response.read())
        if (
            response.status != 200
            or profile.get("email") != email
            or profile.get("role") != "superadmin"
        ):
            raise ResetError("La vérification de /auth/me a échoué.")


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Réinitialiser explicitement le mot de passe du Super Admin existant."
    )
    parser.add_argument(
        "--show-password",
        action="store_true",
        help="Afficher localement le mot de passe pendant la saisie.",
    )
    arguments = parser.parse_args()
    if not sys.stdin.isatty():
        print("Ce script exige un terminal interactif.", file=sys.stderr)
        return 2

    try:
        email = input("Adresse exacte du Super Admin : ").strip().lower()
        with Session(engine) as session:
            count = session.scalar(select(func.count()).select_from(User).where(
                User.role == "superadmin",
                func.lower(User.email) == email,
            ))
        if count != 1:
            raise ResetError("Super Admin unique introuvable pour cette adresse.")
        password = read_password(show_password=arguments.show_password)
        user = reset_password(email, password)
        verify_live_authentication(user.email, password)
        del password
    except ResetError as error:
        print(f"Réinitialisation refusée : {error}", file=sys.stderr)
        return 1

    print(
        "Mot de passe réinitialisé avec succès pour "
        f"{user.email}. Login, JWT et /auth/me vérifiés. "
        "Aucun autre champ du compte n'a été modifié."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

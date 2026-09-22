"""Targeted student-photo regression tests; database writes are rolled back."""

import base64
import tempfile
import unittest
import uuid
from pathlib import Path

from fastapi import HTTPException

from app import main as m
import test_behavior_foundations as fixtures


class StudentPhotoTests(unittest.TestCase):
    add = fixtures.BehaviorFoundations.add
    assign = fixtures.BehaviorFoundations.assign
    cleanup = fixtures.BehaviorFoundations.cleanup

    def setUp(self):
        fixtures.BehaviorFoundations.setUp(self)
        self.previous_root = m.STUDENT_PHOTO_ROOT
        self.photo_directory = tempfile.TemporaryDirectory()
        m.STUDENT_PHOTO_ROOT = Path(self.photo_directory.name)
        self.addCleanup(self._restore_photo_root)
        self.tenant.enabled_modules = [*self.tenant.enabled_modules, "students"]
        registration = self.s.scalar(m.select(
            m.StudentAcademicRegistration
        ).where(
            m.StudentAcademicRegistration.student_id == self.students[0].id,
            m.StudentAcademicRegistration.academic_year_id == self.year.id,
        ))
        registration.registration_number = "EDU-2026-0001"
        self.students[0].registration_number = "EDU-2026-0001"
        self.s.flush()

    def _restore_photo_root(self):
        m.STUDENT_PHOTO_ROOT = self.previous_root
        self.photo_directory.cleanup()

    def _admin(self):
        return m.Principal(
            id=self.principals[0].id,
            role="admin",
            school_id=m.public_school_id(self.s, self.tenant.id),
            direction_id=str(uuid.uuid4()),
            direction_cycle_ids=[str(self.cycle.id)],
        )

    @staticmethod
    def _file(name="1.jpg"):
        return m.StudentPhotoFileInput(
            name=name,
            mimeType="image/jpeg",
            contentBase64=base64.b64encode(b"\xff\xd8\xffphoto-test").decode(),
        )

    @staticmethod
    def _photo_input(name, mime_type, content):
        return m.StudentPhotoFileInput(
            name=name,
            mimeType=mime_type,
            contentBase64=base64.b64encode(content).decode(),
        )

    def test_supported_formats_and_five_megabyte_limit(self):
        formats = (
            ("photo.jpg", "image/jpeg", b"\xff\xd8\xffdata"),
            ("photo.png", "image/png", b"\x89PNG\r\n\x1a\ndata"),
            ("photo.webp", "image/webp", b"RIFF\x04\x00\x00\x00WEBPdata"),
            ("photo.gif", "image/gif", b"GIF89adata"),
            ("photo.bmp", "image/bmp", b"BMdata"),
            ("photo.heic", "image/heic", b"\x00\x00\x00\x18ftypheicdata"),
            ("photo.heif", "image/heif", b"\x00\x00\x00\x18ftypmif1data"),
        )
        for name, mime_type, content in formats:
            with self.subTest(mime_type=mime_type):
                decoded, extension = m._decode_student_photo(
                    self._photo_input(name, mime_type, content)
                )
                self.assertEqual(decoded, content)
                self.assertTrue(extension.startswith("."))

        exact_limit = b"\xff\xd8\xff" + bytes(m.STUDENT_PHOTO_MAX_BYTES - 3)
        decoded, _ = m._decode_student_photo(
            self._photo_input("limit.jpg", "image/jpeg", exact_limit)
        )
        self.assertEqual(len(decoded), m.STUDENT_PHOTO_MAX_BYTES)

        over_limit = exact_limit + b"x"
        with self.assertRaises(HTTPException) as too_large:
            m._decode_student_photo(
                self._photo_input("too-large.jpg", "image/jpeg", over_limit)
            )
        self.assertEqual(too_large.exception.status_code, 422)
        self.assertIn("5 Mo", str(too_large.exception.detail))

    def test_bulk_import_matches_exact_matricule_and_serves_private_photo(self):
        result = m.import_student_photos(
            m.StudentPhotoImportInput(
                academicYearId=self.year.id,
                cycleId=self.cycle.id,
                files=[self._file(), self._file("999.jpg")],
            ),
            self._admin(),
            self.s,
        )
        self.assertEqual(
            [item["status"] for item in result["items"]],
            ["associated", "not_found"],
        )
        response = m.get_student_photo(
            self.students[0].id, self._admin(), self.s
        )
        self.assertEqual(response.body, b"\xff\xd8\xffphoto-test")
        teacher_response = m.get_student_photo(
            self.students[0].id, self.principals[0], self.s
        )
        self.assertEqual(teacher_response.body, b"\xff\xd8\xffphoto-test")

        repeated = m.import_student_photos(
            m.StudentPhotoImportInput(
                academicYearId=self.year.id,
                cycleId=self.cycle.id,
                files=[self._file()],
            ),
            self._admin(),
            self.s,
        )
        self.assertEqual(repeated["items"][0]["status"], "already_present")

    def test_profile_permissions_and_bulletin_payload(self):
        m.update_student_photo(
            self.students[0].id,
            m.StudentPhotoUpdateInput(**self._file().model_dump(by_alias=True)),
            self._admin(),
            self.s,
        )
        parent = m.Principal(
            id=str(uuid.uuid4()),
            role="parent",
            school_id=m.public_school_id(self.s, self.tenant.id),
        )
        with self.assertRaises(HTTPException) as denied:
            m.update_student_photo(
                self.students[0].id,
                m.StudentPhotoUpdateInput(**self._file().model_dump(by_alias=True)),
                parent,
                self.s,
            )
        self.assertEqual(denied.exception.status_code, 403)

        bulletin = m.student_bulletin(
            self.students[0].id, self.year.id, self._admin(), self.s
        )
        self.assertEqual(
            base64.b64decode(bulletin["student"]["photo"]["contentBase64"]),
            b"\xff\xd8\xffphoto-test",
        )

        pupil = m.Principal(
            id=str(uuid.uuid4()),
            role="student",
            school_id=m.public_school_id(self.s, self.tenant.id),
            student_id=str(self.students[0].id),
        )
        with self.assertRaises(HTTPException) as student_denied:
            m.update_student_photo(
                self.students[0].id,
                m.StudentPhotoUpdateInput(**self._file().model_dump(by_alias=True)),
                pupil,
                self.s,
            )
        self.assertEqual(student_denied.exception.status_code, 403)


if __name__ == "__main__":
    unittest.main()

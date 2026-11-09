"""Positive and negative contract tests for the merged Lab APK permission gate."""

import unittest

from tool.issue13_lab_permission_gate import FORBIDDEN, REQUIRED, validate_permissions


def dump(*names: str) -> str:
    return "package: com.easonliu.cloud500diag\n" + "".join(
        f"uses-permission: name='{name}'\n" for name in names
    )


class LabPermissionGateTest(unittest.TestCase):
    def test_minimal_lab_permissions_pass(self):
        self.assertEqual(validate_permissions(dump(*sorted(REQUIRED))), REQUIRED)

    def test_each_inherited_sensitive_permission_fails(self):
        for name in sorted(FORBIDDEN):
            with self.subTest(name=name), self.assertRaisesRegex(ValueError, "FORBIDDEN"):
                validate_permissions(dump(*sorted(REQUIRED), name))

    def test_required_permissions_cannot_be_dropped(self):
        for name in sorted(REQUIRED):
            with self.subTest(name=name), self.assertRaisesRegex(ValueError, "REQUIRED_MISSING"):
                validate_permissions(dump(*(REQUIRED - {name})))

    def test_sdk23_variant_is_checked(self):
        text = dump(*sorted(REQUIRED)) + (
            "uses-permission-sdk-23: name='android.permission.CAMERA'\n"
        )
        with self.assertRaisesRegex(ValueError, "FORBIDDEN"):
            validate_permissions(text)

    def test_required_camera_or_microphone_feature_fails(self):
        for feature in ("android.hardware.camera.any", "android.hardware.camera", "android.hardware.microphone"):
            with self.subTest(feature=feature), self.assertRaisesRegex(ValueError, "REQUIRED_HARDWARE"):
                validate_permissions(dump(*sorted(REQUIRED)), f"uses-feature: name='{feature}'\n")
        self.assertEqual(
            validate_permissions(dump(*sorted(REQUIRED)), "uses-feature-not-required: name='android.hardware.camera.any'\n"),
            REQUIRED,
        )

    def test_empty_or_non_permission_lines_fail_closed(self):
        with self.assertRaisesRegex(ValueError, "REQUIRED_MISSING"):
            validate_permissions("uses-feature: name='android.hardware.camera'\n")


if __name__ == "__main__":
    unittest.main()

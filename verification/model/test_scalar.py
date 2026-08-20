"""Tests for the independent M64K scalar architectural model."""

from __future__ import annotations

import unittest

from model.m64k.scalar import (
    Condition,
    ConditionFlags,
    OperandSize,
    add,
    add_with_extend,
    bitwise_and,
    bitwise_or,
    bitwise_xor,
    evaluate_condition,
    sign_extend,
    subtract,
    subtract_with_extend,
    write_subword,
)


class ScalarModelTests(unittest.TestCase):
    def test_subword_writes_always_zero_extend(self) -> None:
        source = 0xFEDC_BA98_7654_3210
        self.assertEqual(write_subword(source, OperandSize.BYTE), 0x10)
        self.assertEqual(write_subword(source, OperandSize.WORD), 0x3210)
        self.assertEqual(write_subword(source, OperandSize.LONG), 0x7654_3210)
        self.assertEqual(write_subword(source, OperandSize.QUAD), source)

    def test_explicit_sign_extension(self) -> None:
        self.assertEqual(sign_extend(0x80, OperandSize.BYTE), 0xFFFF_FFFF_FFFF_FF80)
        self.assertEqual(sign_extend(0x7F, OperandSize.BYTE), 0x7F)
        self.assertEqual(sign_extend(0x8000_0000, OperandSize.LONG), 0xFFFF_FFFF_8000_0000)

    def test_byte_add_and_subtract_are_exhaustive(self) -> None:
        for left in range(256):
            for right in range(256):
                added = add(left, right, OperandSize.BYTE, update_flags=True)
                subtracted = subtract(left, right, OperandSize.BYTE, update_flags=True)

                self.assertEqual(added.value, (left + right) & 0xFF)
                self.assertEqual(added.flags.carry_or_borrow, left + right > 0xFF)
                self.assertEqual(subtracted.value, (left - right) & 0xFF)
                self.assertEqual(subtracted.flags.carry_or_borrow, left < right)

    def test_byte_extend_arithmetic_is_exhaustive(self) -> None:
        for left in range(256):
            for right in range(256):
                for extend in (False, True):
                    added = add_with_extend(left, right, extend, OperandSize.BYTE, update_flags=True)
                    subtracted = subtract_with_extend(left, right, extend, OperandSize.BYTE, update_flags=True)
                    full_sum = left + right + int(extend)
                    full_subtrahend = right + int(extend)

                    self.assertEqual(added.value, full_sum & 0xFF)
                    self.assertEqual(added.extend, full_sum > 0xFF)
                    self.assertEqual(subtracted.value, (left - full_subtrahend) & 0xFF)
                    self.assertEqual(subtracted.extend, left < full_subtrahend)

                    signed_left = left - 256 if left & 0x80 else left
                    signed_right = right - 256 if right & 0x80 else right
                    self.assertEqual(added.flags.overflow, not -128 <= signed_left + signed_right + int(extend) <= 127)
                    self.assertEqual(subtracted.flags.overflow, not -128 <= signed_left - signed_right - int(extend) <= 127)

    def test_flags_are_optional_and_do_not_modify_extend_implicitly(self) -> None:
        result = add(0xFFFF_FFFF, 1, OperandSize.LONG)
        self.assertEqual(result.value, 0)
        self.assertIsNone(result.flags)
        self.assertIsNone(result.extend)

        extended = add_with_extend(0xFF, 0, True, OperandSize.BYTE)
        self.assertEqual(extended.value, 0)
        self.assertTrue(extended.extend)
        self.assertIsNone(extended.flags)

    def test_signed_overflow_boundaries(self) -> None:
        positive_overflow = add(0x7FFF_FFFF, 1, OperandSize.LONG, update_flags=True)
        negative_overflow = subtract(0x8000_0000, 1, OperandSize.LONG, update_flags=True)
        no_overflow = add(0xFFFF_FFFF, 1, OperandSize.LONG, update_flags=True)

        self.assertTrue(positive_overflow.flags.overflow)
        self.assertTrue(negative_overflow.flags.overflow)
        self.assertFalse(no_overflow.flags.overflow)

    def test_logical_flag_policy(self) -> None:
        operations_and_expected_sign = (
            (bitwise_and, True),
            (bitwise_or, True),
            (bitwise_xor, False),
        )

        for operation, expected_negative in operations_and_expected_sign:
            result = operation(0x8000_0000, 0xFFFF_FFFF, OperandSize.LONG, update_flags=True)
            self.assertEqual(result.flags.negative, expected_negative)
            self.assertFalse(result.flags.zero)
            self.assertFalse(result.flags.overflow)
            self.assertFalse(result.flags.carry_or_borrow)

    def test_all_condition_codes(self) -> None:
        for raw_flags in range(16):
            flags = ConditionFlags(
                negative=bool(raw_flags & 8),
                zero=bool(raw_flags & 4),
                overflow=bool(raw_flags & 2),
                carry_or_borrow=bool(raw_flags & 1),
            )
            results = [evaluate_condition(condition, flags) for condition in Condition]
            self.assertEqual(len(results), 16)
            self.assertTrue(results[Condition.TRUE.value])
            self.assertFalse(results[Condition.FALSE.value])
            self.assertEqual(results[Condition.HIGH.value], not flags.carry_or_borrow and not flags.zero)
            self.assertEqual(results[Condition.GREATER_THAN.value], not flags.zero and flags.negative == flags.overflow)


if __name__ == "__main__":
    unittest.main()

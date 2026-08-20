"""Tests for the independent M64K scalar architectural model."""

from __future__ import annotations

import unittest

from model.m64k.scalar import (
    Condition,
    ConditionFlags,
    OperandSize,
    ShiftOperation,
    add,
    add_with_extend,
    bitwise_and,
    bitwise_not,
    bitwise_or,
    bitwise_xor,
    compare,
    evaluate_condition,
    negate,
    negate_with_extend,
    sign_extend,
    shift_rotate,
    subtract,
    subtract_with_extend,
    test,
    write_subword,
)


class ScalarModelTests(unittest.TestCase):
    @staticmethod
    def reference_shift_rotate(value: int, count: int, operation: ShiftOperation, extend: bool) -> tuple[int, bool, bool]:
        result = value & 0xFF
        extend_result = extend
        carry = False

        for _ in range(count & 0x3F):
            if operation in {ShiftOperation.LOGICAL_LEFT, ShiftOperation.ARITHMETIC_LEFT}:
                carry = bool(result & 0x80)
                result = (result << 1) & 0xFF
            elif operation is ShiftOperation.LOGICAL_RIGHT:
                carry = bool(result & 1)
                result >>= 1
            elif operation is ShiftOperation.ARITHMETIC_RIGHT:
                carry = bool(result & 1)
                result = (result >> 1) | (result & 0x80)
            elif operation is ShiftOperation.ROTATE_LEFT:
                carry = bool(result & 0x80)
                result = ((result << 1) & 0xFF) | int(carry)
            elif operation is ShiftOperation.ROTATE_RIGHT:
                carry = bool(result & 1)
                result = (result >> 1) | (int(carry) << 7)
            elif operation is ShiftOperation.ROTATE_EXTEND_LEFT:
                carry = bool(result & 0x80)
                result = ((result << 1) & 0xFF) | int(extend_result)
                extend_result = carry
            elif operation is ShiftOperation.ROTATE_EXTEND_RIGHT:
                carry = bool(result & 1)
                result = (result >> 1) | (int(extend_result) << 7)
                extend_result = carry
            else:
                raise AssertionError(f"Unhandled reference operation {operation!r}")

        if (count & 0x3F) == 0:
            carry = extend if operation in {ShiftOperation.ROTATE_EXTEND_LEFT, ShiftOperation.ROTATE_EXTEND_RIGHT} else False
        return result, carry, extend_result

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
                self.assertEqual(added.flags.negative, bool(added.value & 0x80))
                self.assertEqual(added.flags.zero, added.value == 0)
                self.assertEqual(subtracted.value, (left - right) & 0xFF)
                self.assertEqual(subtracted.flags.carry_or_borrow, left < right)
                self.assertEqual(subtracted.flags.negative, bool(subtracted.value & 0x80))
                self.assertEqual(subtracted.flags.zero, subtracted.value == 0)

                signed_left = left - 256 if left & 0x80 else left
                signed_right = right - 256 if right & 0x80 else right
                self.assertEqual(added.flags.overflow, not -128 <= signed_left + signed_right <= 127)
                self.assertEqual(subtracted.flags.overflow, not -128 <= signed_left - signed_right <= 127)

                for operation, expected_value in (
                    (bitwise_and, left & right),
                    (bitwise_or, left | right),
                    (bitwise_xor, left ^ right),
                ):
                    logical = operation(left, right, OperandSize.BYTE, update_flags=True)
                    expected_value &= 0xFF
                    self.assertEqual(logical.value, expected_value)
                    self.assertEqual(logical.flags.negative, bool(expected_value & 0x80))
                    self.assertEqual(logical.flags.zero, expected_value == 0)
                    self.assertFalse(logical.flags.overflow)
                    self.assertFalse(logical.flags.carry_or_borrow)

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
                    self.assertEqual(added.flags.negative, bool(added.value & 0x80))
                    self.assertEqual(added.flags.zero, added.value == 0)
                    self.assertEqual(subtracted.value, (left - full_subtrahend) & 0xFF)
                    self.assertEqual(subtracted.extend, left < full_subtrahend)
                    self.assertEqual(subtracted.flags.negative, bool(subtracted.value & 0x80))
                    self.assertEqual(subtracted.flags.zero, subtracted.value == 0)

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

    def test_byte_unary_compare_and_test_matrix(self) -> None:
        for value in range(256):
            complemented = bitwise_not(value, OperandSize.BYTE, update_flags=True)
            negated = negate(value, OperandSize.BYTE, update_flags=True)
            tested = test(value, OperandSize.BYTE)

            self.assertEqual(complemented.value, (~value) & 0xFF)
            self.assertEqual(complemented.flags.negative, bool(complemented.value & 0x80))
            self.assertEqual(complemented.flags.zero, complemented.value == 0)
            self.assertFalse(complemented.flags.overflow)
            self.assertFalse(complemented.flags.carry_or_borrow)
            self.assertEqual(negated.value, (-value) & 0xFF)
            self.assertEqual(negated.flags.negative, bool(negated.value & 0x80))
            self.assertEqual(negated.flags.zero, negated.value == 0)
            self.assertEqual(negated.flags.carry_or_borrow, value != 0)
            self.assertEqual(negated.flags.overflow, value == 0x80)
            self.assertEqual(tested.negative, bool(value & 0x80))
            self.assertEqual(tested.zero, value == 0)
            self.assertFalse(tested.overflow)
            self.assertFalse(tested.carry_or_borrow)

            for extend in (False, True):
                extended = negate_with_extend(value, extend, OperandSize.BYTE, update_flags=True)
                full_subtrahend = value + int(extend)
                self.assertEqual(extended.value, (-full_subtrahend) & 0xFF)
                self.assertEqual(extended.extend, full_subtrahend != 0)
                self.assertEqual(extended.flags.negative, bool(extended.value & 0x80))
                self.assertEqual(extended.flags.zero, extended.value == 0)
                signed_value = value - 256 if value & 0x80 else value
                self.assertEqual(extended.flags.overflow, not -128 <= -signed_value - int(extend) <= 127)

            for right in range(256):
                compared = compare(value, right, OperandSize.BYTE)
                self.assertEqual(compared.carry_or_borrow, value < right)
                self.assertEqual(compared.zero, value == right)
                self.assertEqual(compared.negative, bool(((value - right) & 0xFF) & 0x80))
                signed_value = value - 256 if value & 0x80 else value
                signed_right = right - 256 if right & 0x80 else right
                self.assertEqual(compared.overflow, not -128 <= signed_value - signed_right <= 127)

    def test_non_flag_forms_do_not_synthesize_condition_updates(self) -> None:
        for operation in (bitwise_not, negate):
            result = operation(0x8000_0000, OperandSize.LONG)
            self.assertIsNone(result.flags)
            self.assertIsNone(result.extend)

        extended = negate_with_extend(0, True, OperandSize.LONG)
        self.assertIsNone(extended.flags)
        self.assertTrue(extended.extend)

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

    def test_byte_shift_and_rotate_matrix(self) -> None:
        for operation in ShiftOperation:
            for value in range(256):
                for count in range(64):
                    for extend in (False, True):
                        expected_value, expected_carry, expected_extend = self.reference_shift_rotate(value, count, operation, extend)
                        result = shift_rotate(value, count, OperandSize.BYTE, operation, extend=extend, update_flags=True)

                        self.assertEqual(result.value, expected_value)
                        self.assertEqual(result.flags.carry_or_borrow, expected_carry)
                        self.assertEqual(result.flags.negative, bool(expected_value & 0x80))
                        self.assertEqual(result.flags.zero, expected_value == 0)
                        signed_value = value - 256 if value & 0x80 else value
                        expected_overflow = operation is ShiftOperation.ARITHMETIC_LEFT and not -128 <= signed_value << (count & 0x3F) <= 127
                        self.assertEqual(result.flags.overflow, expected_overflow)
                        if operation in {ShiftOperation.ROTATE_EXTEND_LEFT, ShiftOperation.ROTATE_EXTEND_RIGHT}:
                            self.assertEqual(result.extend, expected_extend)
                        else:
                            self.assertIsNone(result.extend)

    def test_arithmetic_left_overflow_is_mathematical(self) -> None:
        for size in OperandSize:
            maximum = (1 << (size.value - 1)) - 1
            minimum = 1 << (size.value - 1)

            self.assertFalse(shift_rotate(maximum, 0, size, ShiftOperation.ARITHMETIC_LEFT, update_flags=True).flags.overflow)
            self.assertTrue(shift_rotate(maximum, 1, size, ShiftOperation.ARITHMETIC_LEFT, update_flags=True).flags.overflow)
            self.assertTrue(shift_rotate(minimum, 1, size, ShiftOperation.ARITHMETIC_LEFT, update_flags=True).flags.overflow)
            self.assertFalse(shift_rotate(0, 63, size, ShiftOperation.ARITHMETIC_LEFT, update_flags=True).flags.overflow)

    def test_quad_rotate_and_large_shift_boundaries(self) -> None:
        value = 0x8000_0000_0000_0001

        self.assertEqual(shift_rotate(value, 63, OperandSize.QUAD, ShiftOperation.ROTATE_LEFT).value, 0xC000_0000_0000_0000)
        self.assertEqual(shift_rotate(value, 63, OperandSize.QUAD, ShiftOperation.ROTATE_RIGHT).value, 0x0000_0000_0000_0003)
        self.assertEqual(shift_rotate(value, 63, OperandSize.LONG, ShiftOperation.LOGICAL_LEFT).value, 0)
        self.assertEqual(shift_rotate(0x8000_0000, 63, OperandSize.LONG, ShiftOperation.ARITHMETIC_RIGHT).value, 0xFFFF_FFFF)

    def test_shift_count_uses_only_low_six_bits(self) -> None:
        for operation in ShiftOperation:
            low_count = shift_rotate(0xA5, 3, OperandSize.BYTE, operation, extend=True, update_flags=True)
            wrapped_count = shift_rotate(0xA5, 0xC3, OperandSize.BYTE, operation, extend=True, update_flags=True)
            self.assertEqual(low_count, wrapped_count)

    def test_rotate_through_extend_publishes_x_without_flag_update(self) -> None:
        for operation in (ShiftOperation.ROTATE_EXTEND_LEFT, ShiftOperation.ROTATE_EXTEND_RIGHT):
            for value in range(256):
                for count in range(64):
                    for extend in (False, True):
                        _, _, expected_extend = self.reference_shift_rotate(value, count, operation, extend)
                        result = shift_rotate(value, count, OperandSize.BYTE, operation, extend=extend)
                        self.assertIsNone(result.flags)
                        self.assertEqual(result.extend, expected_extend)


if __name__ == "__main__":
    unittest.main()

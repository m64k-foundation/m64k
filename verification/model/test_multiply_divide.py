"""Architectural tests for the encoding-independent M64K multiply/divide model."""

from __future__ import annotations

import unittest

from model.m64k.multiply_divide import (
    ArithmeticFault,
    DividendWidth,
    DivideResultForm,
    MultiplyForm,
    divide,
    multiply,
)
from model.m64k.scalar import OperandSize


def as_signed(value: int, width: int) -> int:
    mask = (1 << width) - 1
    value &= mask
    return value - (1 << width) if value & (1 << (width - 1)) else value


class MultiplyDivideTests(unittest.TestCase):
    def assert_double_width_divide(self, dividend_bits: int, divisor_bits: int, size: OperandSize, signed: bool) -> None:
        width = size.value
        mask = (1 << width) - 1
        dividend_mask = (1 << (width * 2)) - 1
        dividend = as_signed(dividend_bits, width * 2) if signed else dividend_bits & dividend_mask
        divisor = as_signed(divisor_bits, width) if signed else divisor_bits & mask
        result = divide(
            dividend_bits & mask,
            divisor_bits,
            size,
            signed=signed,
            result_form=DivideResultForm.QUOTIENT_REMAINDER,
            dividend_width=DividendWidth.DOUBLE,
            dividend_high=(dividend_bits >> width) & mask,
            update_flags=True,
        )

        if divisor == 0:
            self.assertEqual(result.fault, ArithmeticFault.INTEGER_DIVIDE_BY_ZERO)
            self.assertIsNone(result.quotient)
            self.assertIsNone(result.remainder)
            self.assertIsNone(result.flags)
            return

        quotient_magnitude = abs(dividend) // abs(divisor)
        quotient = -quotient_magnitude if (dividend < 0) != (divisor < 0) else quotient_magnitude
        remainder = dividend - quotient * divisor
        minimum = -(1 << (width - 1)) if signed else 0
        maximum = (1 << (width - 1)) - 1 if signed else mask
        if not minimum <= quotient <= maximum:
            self.assertEqual(result.fault, ArithmeticFault.INTEGER_DIVIDE_OVERFLOW)
            self.assertIsNone(result.quotient)
            self.assertIsNone(result.remainder)
            self.assertIsNone(result.flags)
            return

        self.assertIsNone(result.fault)
        self.assertEqual(result.quotient, quotient & mask)
        self.assertEqual(result.remainder, remainder & mask)
        self.assertIsNotNone(result.flags)
        self.assertEqual(dividend, quotient * divisor + remainder)
        self.assertLess(abs(remainder), abs(divisor))
        if remainder != 0 and signed:
            self.assertEqual(remainder < 0, dividend < 0)

    def test_exhaustive_byte_multiply(self) -> None:
        for signed in (False, True):
            for left_bits in range(256):
                left = as_signed(left_bits, 8) if signed else left_bits
                for right_bits in range(256):
                    right = as_signed(right_bits, 8) if signed else right_bits
                    mathematical = left * right

                    narrow = multiply(left_bits, right_bits, OperandSize.BYTE, signed=signed, form=MultiplyForm.NARROW, update_flags=True)
                    self.assertEqual(narrow.low, mathematical & 0xFF)
                    self.assertIsNone(narrow.high)
                    self.assertIsNotNone(narrow.flags)
                    if narrow.flags is not None:
                        expected_overflow = not (-128 <= mathematical <= 127) if signed else mathematical > 0xFF
                        self.assertEqual(narrow.flags.overflow, expected_overflow)
                        self.assertEqual(narrow.flags.negative, bool(narrow.low & 0x80))
                        self.assertEqual(narrow.flags.zero, narrow.low == 0)
                        self.assertFalse(narrow.flags.carry_or_borrow)

                    widening = multiply(left_bits, right_bits, OperandSize.BYTE, signed=signed, form=MultiplyForm.WIDENING, update_flags=True)
                    self.assertEqual(widening.low, mathematical & 0xFFFF)
                    self.assertIsNone(widening.high)
                    self.assertIsNotNone(widening.flags)
                    if widening.flags is not None:
                        self.assertEqual(widening.flags.negative, bool(widening.low & 0x8000))
                        self.assertEqual(widening.flags.zero, widening.low == 0)
                        self.assertFalse(widening.flags.overflow)
                        self.assertFalse(widening.flags.carry_or_borrow)

    def test_exhaustive_byte_same_width_divide(self) -> None:
        for signed in (False, True):
            for dividend_bits in range(256):
                dividend = as_signed(dividend_bits, 8) if signed else dividend_bits
                for divisor_bits in range(256):
                    divisor = as_signed(divisor_bits, 8) if signed else divisor_bits
                    for result_form in DivideResultForm:
                        result = divide(
                            dividend_bits,
                            divisor_bits,
                            OperandSize.BYTE,
                            signed=signed,
                            result_form=result_form,
                            update_flags=True,
                        )
                        if divisor == 0:
                            self.assertEqual(result.fault, ArithmeticFault.INTEGER_DIVIDE_BY_ZERO)
                            self.assertIsNone(result.quotient)
                            self.assertIsNone(result.remainder)
                            self.assertIsNone(result.flags)
                            continue

                        quotient_magnitude = abs(dividend) // abs(divisor)
                        quotient = -quotient_magnitude if (dividend < 0) != (divisor < 0) else quotient_magnitude
                        remainder = dividend - quotient * divisor
                        quotient_requested = result_form is not DivideResultForm.REMAINDER
                        overflow = quotient_requested and signed and not -128 <= quotient <= 127
                        if overflow:
                            self.assertEqual(result.fault, ArithmeticFault.INTEGER_DIVIDE_OVERFLOW)
                            self.assertIsNone(result.quotient)
                            self.assertIsNone(result.remainder)
                            self.assertIsNone(result.flags)
                            continue

                        self.assertIsNone(result.fault)
                        expected_quotient = quotient & 0xFF if quotient_requested else None
                        remainder_requested = result_form is not DivideResultForm.QUOTIENT
                        expected_remainder = remainder & 0xFF if remainder_requested else None
                        self.assertEqual(result.quotient, expected_quotient)
                        self.assertEqual(result.remainder, expected_remainder)
                        self.assertEqual(dividend, quotient * divisor + remainder)
                        self.assertLess(abs(remainder), abs(divisor))
                        if remainder != 0:
                            self.assertEqual(remainder < 0, dividend < 0)

    def test_byte_double_width_dividend_boundaries(self) -> None:
        dividend_patterns = [0x0000, 0x0001, 0x007F, 0x0080, 0x00FF, 0x0100, 0x7FFF, 0x8000, 0xFF00, 0xFF7F, 0xFFFF]
        divisor_patterns = [0x00, 0x01, 0x02, 0x7F, 0x80, 0xFE, 0xFF]
        for signed in (False, True):
            for dividend_bits in dividend_patterns:
                for divisor_bits in divisor_patterns:
                    result = divide(
                        dividend_bits & 0xFF,
                        divisor_bits,
                        OperandSize.BYTE,
                        signed=signed,
                        result_form=DivideResultForm.QUOTIENT_REMAINDER,
                        dividend_width=DividendWidth.DOUBLE,
                        dividend_high=dividend_bits >> 8,
                    )
                    if divisor_bits == 0:
                        self.assertEqual(result.fault, ArithmeticFault.INTEGER_DIVIDE_BY_ZERO)
                        continue
                    dividend = as_signed(dividend_bits, 16) if signed else dividend_bits
                    divisor = as_signed(divisor_bits, 8) if signed else divisor_bits
                    quotient_magnitude = abs(dividend) // abs(divisor)
                    quotient = -quotient_magnitude if (dividend < 0) != (divisor < 0) else quotient_magnitude
                    minimum = -128 if signed else 0
                    maximum = 127 if signed else 255
                    if not minimum <= quotient <= maximum:
                        self.assertEqual(result.fault, ArithmeticFault.INTEGER_DIVIDE_OVERFLOW)
                    else:
                        remainder = dividend - quotient * divisor
                        self.assertIsNone(result.fault)
                        self.assertEqual(result.quotient, quotient & 0xFF)
                        self.assertEqual(result.remainder, remainder & 0xFF)

    def test_exhaustive_byte_double_width_boundary_partition(self) -> None:
        unsigned_quotient_boundaries = (-1, 0, 1, 254, 255, 256)
        signed_quotient_boundaries = (-129, -128, -127, 126, 127, 128)
        double_width_boundaries = (0x0000, 0x0001, 0x7FFF, 0x8000, 0xFFFE, 0xFFFF)

        for signed in (False, True):
            quotient_boundaries = signed_quotient_boundaries if signed else unsigned_quotient_boundaries
            for divisor_bits in range(256):
                divisor = as_signed(divisor_bits, 8) if signed else divisor_bits
                if divisor == 0:
                    for dividend_bits in double_width_boundaries:
                        self.assert_double_width_divide(dividend_bits, divisor_bits, OperandSize.BYTE, signed)
                    continue

                maximum_remainder_magnitude = abs(divisor) - 1
                remainder_boundaries = (0, maximum_remainder_magnitude, -maximum_remainder_magnitude) if signed else (0, maximum_remainder_magnitude)
                for quotient in quotient_boundaries:
                    for remainder in remainder_boundaries:
                        dividend = quotient * divisor + remainder
                        if signed:
                            if not -0x8000 <= dividend <= 0x7FFF:
                                continue
                            if remainder != 0 and (remainder < 0) != (dividend < 0):
                                continue
                        elif not 0 <= dividend <= 0xFFFF:
                            continue

                        self.assert_double_width_divide(dividend & 0xFFFF, divisor_bits, OperandSize.BYTE, signed)

    def test_directed_wide_word_long_quad_extrema_and_quotient_thresholds(self) -> None:
        for size in (OperandSize.WORD, OperandSize.LONG, OperandSize.QUAD):
            width = size.value
            mask = (1 << width) - 1
            double_mask = (1 << (width * 2)) - 1
            sign = 1 << (width - 1)

            for quotient in (mask - 1, mask, mask + 1):
                self.assert_double_width_divide(quotient, 1, size, False)
            self.assert_double_width_divide(0, 1, size, False)
            self.assert_double_width_divide(double_mask, mask, size, False)

            for quotient in (-sign - 1, -sign, -sign + 1, sign - 2, sign - 1, sign):
                self.assert_double_width_divide(quotient & double_mask, 1, size, True)
                self.assert_double_width_divide((-quotient) & double_mask, mask, size, True)
            self.assert_double_width_divide(1 << ((width * 2) - 1), 1, size, True)
            self.assert_double_width_divide((1 << ((width * 2) - 1)) - 1, 1, size, True)

    def test_directed_word_long_quad_multiply(self) -> None:
        cases = [
            (OperandSize.WORD, 0x8000, 2),
            (OperandSize.LONG, 0x8000_0000, 0xFFFF_FFFF),
            (OperandSize.QUAD, 0x8000_0000_0000_0000, 2),
            (OperandSize.QUAD, 0xFFFF_FFFF_FFFF_FFFF, 0xFFFF_FFFF_FFFF_FFFF),
        ]
        for size, left, right in cases:
            width = size.value
            for signed in (False, True):
                left_value = as_signed(left, width) if signed else left & ((1 << width) - 1)
                right_value = as_signed(right, width) if signed else right & ((1 << width) - 1)
                product = (left_value * right_value) & ((1 << (width * 2)) - 1)
                narrow = multiply(left, right, size, signed=signed, form=MultiplyForm.NARROW, update_flags=True)
                self.assertEqual(narrow.low, product & ((1 << width) - 1))
                self.assertIsNotNone(narrow.flags)
                if narrow.flags is not None:
                    if signed:
                        expected_overflow = not -(1 << (width - 1)) <= left_value * right_value <= (1 << (width - 1)) - 1
                    else:
                        expected_overflow = left_value * right_value > (1 << width) - 1
                    self.assertEqual(narrow.flags.overflow, expected_overflow)

                result = multiply(left, right, size, signed=signed, form=MultiplyForm.WIDENING, update_flags=True)
                self.assertEqual(result.low, product & 0xFFFF_FFFF_FFFF_FFFF)
                expected_high = product >> 64 if width == 64 else None
                self.assertEqual(result.high, expected_high)

    def test_directed_divide_faults_and_remainder_sign(self) -> None:
        for size in (OperandSize.WORD, OperandSize.LONG, OperandSize.QUAD):
            sign = 1 << (size.value - 1)
            mask = (1 << size.value) - 1
            by_zero = divide(1, 0, size, signed=True, result_form=DivideResultForm.QUOTIENT_REMAINDER)
            self.assertEqual(by_zero.fault, ArithmeticFault.INTEGER_DIVIDE_BY_ZERO)

            overflow = divide(sign, mask, size, signed=True, result_form=DivideResultForm.QUOTIENT_REMAINDER)
            self.assertEqual(overflow.fault, ArithmeticFault.INTEGER_DIVIDE_OVERFLOW)

            remainder_only = divide(sign, mask, size, signed=True, result_form=DivideResultForm.REMAINDER, update_flags=True)
            self.assertIsNone(remainder_only.fault)
            self.assertEqual(remainder_only.remainder, 0)
            self.assertIsNotNone(remainder_only.flags)
            if remainder_only.flags is not None:
                self.assertTrue(remainder_only.flags.zero)

            negative_remainder = divide((-7) & mask, 3, size, signed=True, result_form=DivideResultForm.QUOTIENT_REMAINDER)
            self.assertIsNone(negative_remainder.fault)
            self.assertEqual(as_signed(negative_remainder.quotient or 0, size.value), -2)
            self.assertEqual(as_signed(negative_remainder.remainder or 0, size.value), -1)

    def test_directed_128_by_64_boundaries(self) -> None:
        mask = 0xFFFF_FFFF_FFFF_FFFF
        maximum = divide(mask, 1, OperandSize.QUAD, signed=False, result_form=DivideResultForm.QUOTIENT_REMAINDER, dividend_width=DividendWidth.DOUBLE, dividend_high=0)
        self.assertIsNone(maximum.fault)
        self.assertEqual(maximum.quotient, mask)
        self.assertEqual(maximum.remainder, 0)

        too_large = divide(0, 1, OperandSize.QUAD, signed=False, result_form=DivideResultForm.QUOTIENT_REMAINDER, dividend_width=DividendWidth.DOUBLE, dividend_high=1)
        self.assertEqual(too_large.fault, ArithmeticFault.INTEGER_DIVIDE_OVERFLOW)

        divide_zero_wins = divide(0, 0, OperandSize.QUAD, signed=False, result_form=DivideResultForm.QUOTIENT_REMAINDER, dividend_width=DividendWidth.DOUBLE, dividend_high=1)
        self.assertEqual(divide_zero_wins.fault, ArithmeticFault.INTEGER_DIVIDE_BY_ZERO)

        with self.assertRaises(ValueError):
            divide(0, 1, OperandSize.QUAD, signed=False, result_form=DivideResultForm.QUOTIENT, dividend_width=DividendWidth.DOUBLE, dividend_high=0)

    def test_without_F_has_no_flag_write(self) -> None:
        self.assertIsNone(multiply(3, 5, OperandSize.QUAD, signed=False, form=MultiplyForm.NARROW).flags)
        self.assertIsNone(divide(7, 3, OperandSize.QUAD, signed=False, result_form=DivideResultForm.QUOTIENT).flags)


if __name__ == "__main__":
    unittest.main()

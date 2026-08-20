"""Independent executable semantics for native M64K scalar multiply and divide."""

from __future__ import annotations

from dataclasses import dataclass
from enum import Enum

from .scalar import ConditionFlags, OperandSize


class MultiplyForm(Enum):
    NARROW = "narrow"
    WIDENING = "widening"


class DivideResultForm(Enum):
    QUOTIENT = "quotient"
    REMAINDER = "remainder"
    QUOTIENT_REMAINDER = "quotient-remainder"


class DividendWidth(Enum):
    SAME = "W"
    DOUBLE = "2W"


class ArithmeticFault(Enum):
    INTEGER_DIVIDE_BY_ZERO = "IntegerDivideByZero"
    INTEGER_DIVIDE_OVERFLOW = "IntegerDivideOverflow"


@dataclass(frozen=True)
class MultiplyResult:
    low: int
    high: int | None
    flags: ConditionFlags | None


@dataclass(frozen=True)
class DivideResult:
    quotient: int | None
    remainder: int | None
    flags: ConditionFlags | None
    fault: ArithmeticFault | None


def _width_bits(size: OperandSize) -> int:
    return size.value


def _mask(width: int) -> int:
    return (1 << width) - 1


def _as_signed(value: int, width: int) -> int:
    masked = value & _mask(width)
    sign = 1 << (width - 1)
    return masked - (1 << width) if masked & sign else masked


def _flags(value: int, width: int, overflow: bool) -> ConditionFlags:
    masked = value & _mask(width)
    return ConditionFlags(
        negative=bool(masked & (1 << (width - 1))),
        zero=masked == 0,
        overflow=overflow,
        carry_or_borrow=False,
    )


def multiply(
    left: int,
    right: int,
    size: OperandSize,
    *,
    signed: bool,
    form: MultiplyForm,
    update_flags: bool = False,
) -> MultiplyResult:
    """Return the exact M64K multiply result without encoding-dependent behavior."""

    width = _width_bits(size)
    operand_mask = _mask(width)
    left_bits = left & operand_mask
    right_bits = right & operand_mask
    left_value = _as_signed(left_bits, width) if signed else left_bits
    right_value = _as_signed(right_bits, width) if signed else right_bits
    mathematical_product = left_value * right_value
    full_width = width * 2
    full_product = mathematical_product & _mask(full_width)

    if form is MultiplyForm.WIDENING:
        low = full_product & _mask(min(full_width, 64))
        high = (full_product >> 64) & _mask(64) if full_width == 128 else None
        flags = _flags(full_product, full_width, False) if update_flags else None
        return MultiplyResult(low=low, high=high, flags=flags)

    low = full_product & operand_mask
    if signed:
        minimum = -(1 << (width - 1))
        maximum = (1 << (width - 1)) - 1
        overflow = not minimum <= mathematical_product <= maximum
    else:
        overflow = mathematical_product > operand_mask
    flags = _flags(low, width, overflow) if update_flags else None
    return MultiplyResult(low=low, high=None, flags=flags)


def divide(
    dividend_low: int,
    divisor: int,
    size: OperandSize,
    *,
    signed: bool,
    result_form: DivideResultForm,
    dividend_width: DividendWidth = DividendWidth.SAME,
    dividend_high: int = 0,
    update_flags: bool = False,
) -> DivideResult:
    """Return a precise quotient/remainder result or a no-write arithmetic fault."""

    if dividend_width is DividendWidth.DOUBLE and result_form is not DivideResultForm.QUOTIENT_REMAINDER:
        raise ValueError("double-width dividends require the fused quotient-remainder result form")

    width = _width_bits(size)
    operand_mask = _mask(width)
    divisor_bits = divisor & operand_mask
    divisor_value = _as_signed(divisor_bits, width) if signed else divisor_bits

    if divisor_value == 0:
        return DivideResult(None, None, None, ArithmeticFault.INTEGER_DIVIDE_BY_ZERO)

    if dividend_width is DividendWidth.DOUBLE:
        dividend_bits = ((dividend_high & operand_mask) << width) | (dividend_low & operand_mask)
        dividend_value = _as_signed(dividend_bits, width * 2) if signed else dividend_bits
    else:
        dividend_bits = dividend_low & operand_mask
        dividend_value = _as_signed(dividend_bits, width) if signed else dividend_bits

    quotient_magnitude = abs(dividend_value) // abs(divisor_value)
    quotient = -quotient_magnitude if (dividend_value < 0) != (divisor_value < 0) else quotient_magnitude
    remainder = dividend_value - quotient * divisor_value

    quotient_requested = result_form is not DivideResultForm.REMAINDER
    if signed:
        minimum_quotient = -(1 << (width - 1))
        maximum_quotient = (1 << (width - 1)) - 1
    else:
        minimum_quotient = 0
        maximum_quotient = operand_mask
    if quotient_requested and not minimum_quotient <= quotient <= maximum_quotient:
        return DivideResult(None, None, None, ArithmeticFault.INTEGER_DIVIDE_OVERFLOW)

    quotient_result = quotient & operand_mask if quotient_requested else None
    remainder_requested = result_form is not DivideResultForm.QUOTIENT
    remainder_result = remainder & operand_mask if remainder_requested else None

    if update_flags:
        flag_value = remainder_result if result_form is DivideResultForm.REMAINDER else quotient_result
        if flag_value is None:
            raise AssertionError("successful division must select a result for flags")
        flags = _flags(flag_value, width, False)
    else:
        flags = None

    return DivideResult(quotient_result, remainder_result, flags, None)

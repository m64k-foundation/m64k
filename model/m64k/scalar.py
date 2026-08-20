"""Reference semantics for M64K scalar integer operations.

This module models typed architectural operations rather than instruction
encodings. The fixed-width binary encoding remains unavailable until the M64K v1
allocation is frozen. Keeping this model independent of the decoder allows it
to serve as a differential oracle for generated tools and RTL.
"""

from __future__ import annotations

from dataclasses import dataclass
from enum import Enum


class OperandSize(Enum):
    """Architectural scalar operand widths."""

    BYTE = 8
    WORD = 16
    LONG = 32
    QUAD = 64

    @property
    def mask(self) -> int:
        return (1 << self.value) - 1

    @property
    def sign_bit(self) -> int:
        return 1 << (self.value - 1)


@dataclass(frozen=True, slots=True)
class ConditionFlags:
    """The renameable M64K integer condition state."""

    negative: bool
    zero: bool
    overflow: bool
    carry_or_borrow: bool


@dataclass(frozen=True, slots=True)
class IntegerResult:
    """A zero-extended GPR result and optional condition-state update."""

    value: int
    flags: ConditionFlags | None = None
    extend: bool | None = None


class Condition(Enum):
    """Conditions available to flag branches and predicate materialization."""

    TRUE = 0
    FALSE = 1
    HIGH = 2
    LOW_OR_SAME = 3
    CARRY_CLEAR = 4
    CARRY_SET = 5
    NOT_EQUAL = 6
    EQUAL = 7
    OVERFLOW_CLEAR = 8
    OVERFLOW_SET = 9
    PLUS = 10
    MINUS = 11
    GREATER_OR_EQUAL = 12
    LESS_THAN = 13
    GREATER_THAN = 14
    LESS_OR_EQUAL = 15


def _masked(value: int, size: OperandSize) -> int:
    return value & size.mask


def _nz(result: int, size: OperandSize) -> tuple[bool, bool]:
    narrowed = _masked(result, size)
    return bool(narrowed & size.sign_bit), narrowed == 0


def _as_signed(value: int, size: OperandSize) -> int:
    narrowed = _masked(value, size)
    return narrowed - (1 << size.value) if narrowed & size.sign_bit else narrowed


def _signed_result_overflows(value: int, size: OperandSize) -> bool:
    minimum = -(1 << (size.value - 1))
    maximum = (1 << (size.value - 1)) - 1
    return value < minimum or value > maximum


def write_subword(value: int, size: OperandSize) -> int:
    """Apply the architectural zero-extension rule for a GPR write."""

    return _masked(value, size)


def sign_extend(value: int, size: OperandSize) -> int:
    """Sign-extend an explicitly signed operand to one 64-bit GPR value."""

    narrowed = _masked(value, size)
    if narrowed & size.sign_bit:
        return narrowed | (((1 << 64) - 1) ^ size.mask)
    return narrowed


def add(left: int, right: int, size: OperandSize, *, update_flags: bool = False) -> IntegerResult:
    """Add two sized operands and optionally produce NZVC.

    C is the unsigned carry out of the selected operand width.
    """

    left_value = _masked(left, size)
    right_value = _masked(right, size)
    full_result = left_value + right_value
    result = _masked(full_result, size)

    if not update_flags:
        return IntegerResult(value=result)

    negative, zero = _nz(result, size)
    overflow = _signed_result_overflows(_as_signed(left_value, size) + _as_signed(right_value, size), size)
    carry = full_result > size.mask
    return IntegerResult(result, ConditionFlags(negative, zero, overflow, carry))


def subtract(left: int, right: int, size: OperandSize, *, update_flags: bool = False) -> IntegerResult:
    """Subtract right from left and optionally produce NZVC.

    For subtraction, C is one when the unsigned operation borrows. This keeps
    the familiar M64K `CS`, `CC`, `HI`, and `LS` condition relationships.
    """

    left_value = _masked(left, size)
    right_value = _masked(right, size)
    result = _masked(left_value - right_value, size)

    if not update_flags:
        return IntegerResult(value=result)

    negative, zero = _nz(result, size)
    overflow = _signed_result_overflows(_as_signed(left_value, size) - _as_signed(right_value, size), size)
    borrow = left_value < right_value
    return IntegerResult(result, ConditionFlags(negative, zero, overflow, borrow))


def add_with_extend(left: int, right: int, extend: bool, size: OperandSize, *, update_flags: bool = False) -> IntegerResult:
    """Add two operands and explicit X input, producing a new X value."""

    left_value = _masked(left, size)
    right_value = _masked(right, size)
    full_result = left_value + right_value + int(extend)
    result = _masked(full_result, size)
    carry = full_result > size.mask

    if not update_flags:
        return IntegerResult(value=result, extend=carry)

    negative, zero = _nz(result, size)
    signed_sum = _as_signed(left_value, size) + _as_signed(right_value, size) + int(extend)
    overflow = _signed_result_overflows(signed_sum, size)
    return IntegerResult(result, ConditionFlags(negative, zero, overflow, carry), carry)


def subtract_with_extend(left: int, right: int, extend: bool, size: OperandSize, *, update_flags: bool = False) -> IntegerResult:
    """Subtract right and explicit X from left, producing a new X value."""

    left_value = _masked(left, size)
    right_value = _masked(right, size)
    subtrahend = right_value + int(extend)
    result = _masked(left_value - subtrahend, size)
    borrow = left_value < subtrahend

    if not update_flags:
        return IntegerResult(value=result, extend=borrow)

    negative, zero = _nz(result, size)
    signed_difference = _as_signed(left_value, size) - _as_signed(right_value, size) - int(extend)
    overflow = _signed_result_overflows(signed_difference, size)
    return IntegerResult(result, ConditionFlags(negative, zero, overflow, borrow), borrow)


def bitwise_and(left: int, right: int, size: OperandSize, *, update_flags: bool = False) -> IntegerResult:
    return _logical_result(left & right, size, update_flags)


def bitwise_or(left: int, right: int, size: OperandSize, *, update_flags: bool = False) -> IntegerResult:
    return _logical_result(left | right, size, update_flags)


def bitwise_xor(left: int, right: int, size: OperandSize, *, update_flags: bool = False) -> IntegerResult:
    return _logical_result(left ^ right, size, update_flags)


def _logical_result(value: int, size: OperandSize, update_flags: bool) -> IntegerResult:
    result = _masked(value, size)
    if not update_flags:
        return IntegerResult(value=result)

    negative, zero = _nz(result, size)
    return IntegerResult(result, ConditionFlags(negative, zero, False, False))


def evaluate_condition(condition: Condition, flags: ConditionFlags) -> bool:
    """Evaluate one architectural condition from a committed NZVC value."""

    if condition is Condition.TRUE:
        return True
    if condition is Condition.FALSE:
        return False
    if condition is Condition.HIGH:
        return not flags.carry_or_borrow and not flags.zero
    if condition is Condition.LOW_OR_SAME:
        return flags.carry_or_borrow or flags.zero
    if condition is Condition.CARRY_CLEAR:
        return not flags.carry_or_borrow
    if condition is Condition.CARRY_SET:
        return flags.carry_or_borrow
    if condition is Condition.NOT_EQUAL:
        return not flags.zero
    if condition is Condition.EQUAL:
        return flags.zero
    if condition is Condition.OVERFLOW_CLEAR:
        return not flags.overflow
    if condition is Condition.OVERFLOW_SET:
        return flags.overflow
    if condition is Condition.PLUS:
        return not flags.negative
    if condition is Condition.MINUS:
        return flags.negative
    if condition is Condition.GREATER_OR_EQUAL:
        return flags.negative == flags.overflow
    if condition is Condition.LESS_THAN:
        return flags.negative != flags.overflow
    if condition is Condition.GREATER_THAN:
        return not flags.zero and flags.negative == flags.overflow
    if condition is Condition.LESS_OR_EQUAL:
        return flags.zero or flags.negative != flags.overflow
    raise AssertionError(f"Unhandled condition {condition!r}")

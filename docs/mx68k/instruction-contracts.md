# MX68K instruction contracts

An opcode family is implemented from the Motorola architectural contract, not
from observed program behaviour.  `isa/mx68k_m00_contracts.json` is the
machine-checked inventory for every family advertised as `verified`.

Each contract records:

- exact manual/errata sections and the complete 16-bit encoding domain;
- legal sizes and effective-address classes;
- operation and every X/N/Z/V/C rule, including preserved/undefined state;
- ordered memory accesses and architectural checkpoints;
- synchronous, privilege, extension-fetch and data-access exceptions;
- model/profile limits and the test domains that establish coverage.

The audit checker requires the contract inventory to match the set of
`verified` formats exactly.  Promoting a partial format without a complete
contract therefore fails the build.  References in a contract must also be
present in the audit entry so reviewers can trace the claim to its evidence.

## Workflow for a new family

1. Read the applicable Programmer's Reference Manual entry, User's Manual bus
   and exception sections, and known errata.
2. Add the decoder pattern and a manual contract.  Record the number of legal
   opcode words; register and size fields do not create separate RTL copies.
3. Generate and exhaustively classify the 16-bit opcode domain.
4. Implement direct lowering or a symbolic microprogram using the same
   contract fields.
5. Test legal/reserved encodings, flags, EAs, aliases, privilege, ordered
   accesses and a fault at every architectural checkpoint.
6. Keep the audit `partial` until every declared domain is covered.  Linux,
   firmware and differential runs are integration evidence, not the semantic
   specification.

For condition-code bits documented as undefined, the RTL may choose a stable
implementation value, but neither the contract nor the tests may advertise
that value as portable architectural behaviour.

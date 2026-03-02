---
name: speckit-constitution
description: Create or update the project constitution from interactive or provided principle inputs, ensuring dependent planning artifacts stay aligned.
source_repository: https://github.com/tolulawson/speckit-agent-skills
source_commit: c21d8d2defd2d74670fe10fb63fc73e689a0a671
vendored_note: Condensed local copy used by Ralph planning.
---

# Spec Kit Constitution Skill

## Purpose

Create or update `.specify/memory/constitution.md` so planning and implementation
artifacts have a stable governance source of truth.

## Inputs

- User-provided principles, constraints, or amendments
- Existing `.specify/memory/constitution.md`
- Existing `.specify/templates/*` files

## Workflow

1. Load the current constitution template or existing constitution.
2. Resolve all placeholder values from:
   - explicit user input
   - repository context
   - prior constitution content
3. Decide the version bump:
   - major for breaking governance changes
   - minor for new principles or materially expanded rules
   - patch for clarifications
4. Rewrite `.specify/memory/constitution.md` with no unresolved placeholders unless
   explicitly deferred as a `TODO(...)`.
5. Propagate consistency updates to dependent artifacts when needed:
   - `.specify/templates/spec-template.md`
   - `.specify/templates/plan-template.md`
   - `.specify/templates/tasks-template.md`
   - runtime prompts or docs that reference the constitution
6. Add a short sync impact report at the top describing:
   - version change
   - principle changes
   - files updated or still needing manual follow-up

## Validation

- No unexplained bracket placeholders remain
- Dates use `YYYY-MM-DD`
- Principles are explicit and testable
- The version line matches the reported change

## Outputs

- Updated `.specify/memory/constitution.md`
- Any aligned templates or planning docs required by the constitution

## Next Step

Proceed to `speckit-specify`.

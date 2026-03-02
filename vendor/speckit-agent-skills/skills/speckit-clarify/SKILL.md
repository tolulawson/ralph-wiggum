---
name: speckit-clarify
description: Identify underspecified areas in the current feature spec and record clarifications directly in the spec.
source_repository: https://github.com/tolulawson/speckit-agent-skills
source_commit: c21d8d2defd2d74670fe10fb63fc73e689a0a671
vendored_note: Condensed local copy used by Ralph planning.
---

# Spec Kit Clarify Skill

## Purpose

Reduce ambiguity in an existing feature spec before technical planning.

## Inputs

- `specs/<feature>/spec.md`
- Any user constraints or clarifications already provided
- `.specify/scripts/bash/check-prerequisites.sh` when available

## Workflow

1. Resolve the active feature directory and spec path.
2. Scan the spec for ambiguity across:
   - scope and behavior
   - data and entities
   - user flows and edge cases
   - non-functional requirements
   - integrations and failure handling
   - completion criteria
3. Prioritize only the ambiguities that materially affect:
   - architecture
   - task breakdown
   - testing
   - operational behavior
4. Ask one focused clarification at a time, up to a small bounded maximum.
5. After each accepted answer:
   - append it to a `## Clarifications` section
   - integrate the answer into the most relevant section of the spec
   - remove contradictory or obsolete wording
6. If ambiguity is low-impact, defer it rather than over-interviewing.

## Validation

- The updated spec remains internally consistent
- Clarifications are directly reflected in requirements, flows, or constraints
- No duplicate or contradictory statements remain
- The spec is now safer to hand to `speckit-plan`

## Output

- Updated `specs/<feature>/spec.md`

## Next Step

Proceed to `speckit-plan`.

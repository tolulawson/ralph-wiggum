---
name: speckit-plan
description: Execute the implementation planning workflow using the plan template to generate design artifacts.
source_repository: https://github.com/tolulawson/speckit-agent-skills
source_commit: c21d8d2defd2d74670fe10fb63fc73e689a0a671
vendored_note: Condensed local copy used by Ralph planning.
---

# Spec Kit Plan Skill

## Purpose

Translate a completed feature spec into a technical plan and design artifacts.

## Inputs

- `specs/<feature>/spec.md`
- `.specify/memory/constitution.md`
- `.specify/templates/plan-template.md`
- `.specify/scripts/bash/setup-plan.sh` when available

## Workflow

1. Resolve the active feature paths and plan target.
2. Load the feature spec and constitution.
3. Fill the plan template with:
   - technical context
   - constraints
   - constitution checks
4. Phase 0: research unresolved technical questions and record them in `research.md`.
5. Phase 1: produce design artifacts:
   - `data-model.md`
   - `contracts/`
   - `quickstart.md`
6. Re-evaluate the plan against the constitution after design decisions are made.
7. Stop after planning artifacts are complete. Do not implement product code.

## Validation

- The plan is consistent with the feature spec
- Unknowns have been resolved or explicitly flagged
- The constitution check passes or justified exceptions are documented
- Design artifacts are sufficient to generate tasks

## Outputs

- `specs/<feature>/plan.md`
- `specs/<feature>/research.md`
- `specs/<feature>/data-model.md`
- `specs/<feature>/contracts/*`
- `specs/<feature>/quickstart.md`

## Next Steps

- Proceed to `speckit-tasks`
- Optionally run `speckit-checklist`

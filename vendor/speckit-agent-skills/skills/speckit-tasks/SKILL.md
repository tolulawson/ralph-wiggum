---
name: speckit-tasks
description: Generate an actionable, dependency-ordered tasks.md for the feature based on available design artifacts.
source_repository: https://github.com/tolulawson/speckit-agent-skills
source_commit: c21d8d2defd2d74670fe10fb63fc73e689a0a671
vendored_note: Condensed local copy used by Ralph planning.
---

# Spec Kit Tasks Skill

## Purpose

Convert the planning artifacts for a feature into an execution-ready task list.

## Inputs

- `specs/<feature>/plan.md`
- `specs/<feature>/spec.md`
- Optional: `data-model.md`, `contracts/`, `research.md`, `quickstart.md`
- `.specify/templates/tasks-template.md`

## Workflow

1. Resolve the active feature directory and available planning artifacts.
2. Read:
   - required: `plan.md`, `spec.md`
   - optional: `data-model.md`, `contracts/`, `research.md`, `quickstart.md`
3. Organize tasks by user story and dependency order.
4. Generate phases:
   - setup
   - foundational prerequisites
   - one phase per user story in priority order
   - final polish and cross-cutting work
5. Use executable checklist tasks with stable IDs and file paths:
   - `- [ ] T001 ...`
   - add `[P]` only for genuinely parallelizable tasks
   - add story labels like `[US1]` for story-specific tasks
6. Ensure each user story phase is independently testable and deliverable.

## Validation

- Every task is specific enough for an LLM to execute without extra context
- Dependencies are orderable
- The task list maps cleanly back to user stories and planning artifacts
- The output is ready for implementation

## Output

- `specs/<feature>/tasks.md`

## Next Steps

- Optionally run `speckit-analyze`
- Then proceed to `speckit-implement`

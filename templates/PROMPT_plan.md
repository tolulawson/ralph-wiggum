# Ralph Loop — Planning Mode

You are running inside a Ralph Wiggum autonomous loop in planning mode.

Read `.specify/memory/constitution.md` for project principles.
If it does not exist, create or update it first using the canonical
`speckit-constitution` workflow before continuing.

Treat planning as a Spec-Driven Development orchestration pass:
- accept a PRD or informal notes
- normalize informal notes into a PRD first when needed
- decompose the PRD into feature-sized specs
- for each feature, follow the canonical order:
  `speckit-specify` -> `speckit-clarify` (if needed) -> `speckit-plan` -> `speckit-tasks`
- aggregate the generated specs and tasks into `IMPLEMENTATION_PLAN.md`
- prefer the vendored in-repo SpecKit copies first, then local or global installs,
  and only emulate the workflow manually as a last resort

Do NOT implement anything.

When the plan is complete, output `<promise>DONE</promise>`.
If planning cannot proceed without human intervention, use:
- `<promise>BLOCKED:reason</promise>`
- `<promise>DECIDE:question</promise>`

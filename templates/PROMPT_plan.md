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

## work-items.json

After generating `IMPLEMENTATION_PLAN.md`, also write `work-items.json` at the
project root. This machine-readable work queue lets build mode select items
programmatically without re-parsing markdown.

### Schema

```json
{
  "version": "1.0",
  "generated_at": "<ISO-8601 timestamp>",
  "items": [
    {
      "id": "<NNN-feature-slug>",
      "title": "<Short feature title>",
      "spec": "specs/<NNN-feature-slug>/spec.md",
      "tasks": "specs/<NNN-feature-slug>/tasks.md",
      "priority": 1,
      "dependencies": [],
      "profile": "web|expo|backend|library|unknown",
      "status": "pending",
      "retry_count": 0,
      "verification": ["lint", "typecheck", "unit-tests", "build"],
      "testing": {
        "unit": ["npm test -- --runInBand"],
        "integration": [],
        "e2e": ["maestro test .maestro/smoke.yaml"],
        "device": ["mcp device smoke-test ios"],
        "manual": [],
        "notes": "Run E2E separately from unit tests when mobile flows change"
      },
      "branch": "",
      "review_status": "pending",
      "pr_number": null,
      "pr_url": "",
      "merge_status": "not_requested"
    }
  ]
}
```

### Field rules

- `id` — unique slug matching the spec directory name (e.g. `001-auth`)
- `priority` — integer, 1 = highest; derive from spec ordering or explicit priority
- `dependencies` — list of `id` values this item must wait on; omit if none
- `profile` — detect from the spec or constitution; default to `unknown`
- `status` — always `"pending"` on first write; build mode moves items through
  `in_progress` -> `done` by default; use `awaiting_merge` only if automatic merge
  is blocked and human intervention is still required
- `retry_count` — always `0` on first write; build mode increments on failed attempts
- `verification` — list of check types required; use any subset of:
  `lint`, `typecheck`, `unit-tests`, `integration-tests`, `e2e`, `build`,
  `expo-doctor`, `metro-export`, `simulator-smoke-test`, `maestro-flows`,
  `device-mcp`, `agent-device-skills`, `manual-qa`, `package-exports`
- `testing` — optional structured testing details. Use it when the spec or
  constitution provides exact commands or expectations that should remain separate
  from the generic `verification` tokens.
- `testing.unit` — exact unit-test commands, if any
- `testing.integration` — exact integration-test commands, if any
- `testing.e2e` — exact end-to-end commands, such as Playwright or Maestro
- `testing.device` — simulator, MCP, agent-device-skill, or hardware checks
- `testing.manual` — manual QA checks that cannot be automated cleanly
- `testing.notes` — brief constraints, environment notes, or skip rules
- `branch` — start as an empty string; build mode assigns the per-task branch
- `review_status` — start as `"pending"`; build mode updates after implementation
- `pr_number` / `pr_url` — start empty; build mode fills these when a draft PR is opened
- `merge_status` — start as `"not_requested"`; build mode updates to `"pending"` and finally `"merged"`

When the plan is complete, output `<promise>DONE</promise>`.
If planning cannot proceed without human intervention, use:
- `<promise>BLOCKED:reason</promise>`
- `<promise>DECIDE:question</promise>`

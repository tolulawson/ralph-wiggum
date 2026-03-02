# Ralph Loop Architecture Review

## Plan

- [x] Inspect the external `/Users/tolu/Desktop/dev/ralph-loop` implementation.
- [x] Compare the external loop to this repo's current loop scripts.
- [x] Synthesize recommendations for a combined, more robust loop design.
- [x] Document review notes and suggested next steps.

## Review

- The external loop is stronger on runtime UX and operator feedback: structured promise tags, step timing, streamed previews, preflight checks, and explicit exit codes.
- This repo is stronger on portability across AI providers and on keeping behavior in the constitution rather than hard-coding workflow detail.
- The biggest gaps in this repo are duplicated loop logic, missing integration of existing helper libraries, prompt-file side effects, and limited runtime state handling beyond simple DONE detection.
- The highest-value direction is a shared loop engine with provider adapters plus pluggable project profiles for web and Expo/mobile verification.

## Review Hardening Follow-Up

- [x] Make build-mode preflight fail when `.specify/memory/constitution.md` is missing, while keeping plan mode as a warning-only path.
- [x] Allow task-branch switching when only untracked runtime artifacts are present; still block on tracked changes.
- [x] Align the manual install path with the modern constitution contract and document `.gitignore` handling for runtime artifacts.

### Review Hardening Verification

- `bash tests/test_preflight.sh`
- `bash tests/test_work_items.sh`
- `bash tests/test_smoke.sh`
- `bash tests/run_tests.sh`

## Planning Phase Notes

- External planning is front-loaded and explicit: create a PRD, generate a task lookup table, then execute one task at a time from `.agent/tasks.json`.
- This repo's planning mode is intentionally lighter: specs are the primary source of truth, and `plan` mode only creates an `IMPLEMENTATION_PLAN.md` when needed.
- The current repo's planning intent is stronger in templates than in runtime implementation; the shell scripts only pass a minimal planning prompt and rely on the constitution for the real workflow.
- The best hybrid approach is a layered planner:
  1. Specs remain the canonical user-facing requirements.
  2. Optional plan generation produces a machine-friendly work queue.
  3. Large or blocked specs can be decomposed into executable subtasks without replacing the original specs.

## Implementation

- [x] Add a shared planning/prompt builder library for plan-mode input handling.
- [x] Teach all provider loop scripts to accept `plan --prd`, `plan --notes`, and `plan --brief`.
- [x] Replace root-level generated plan prompts with template-backed prompt files written to `logs/`.
- [x] Upgrade the planning prompt to orchestrate the canonical SpecKit sequence.
- [x] Vendor the planning-related SpecKit skill files into this repository.
- [x] Make planning prefer vendored in-repo SpecKit assets before local/global installs.
- [x] Update docs and templates to document the new planning behavior.
- [x] Run shell syntax checks and prompt-builder smoke tests.

## Verification

- `bash -n scripts/lib/prompt_builder.sh scripts/ralph-loop.sh scripts/ralph-loop-codex.sh scripts/ralph-loop-gemini.sh scripts/ralph-loop-copilot.sh`
- `./scripts/ralph-loop.sh --help`
- `./scripts/ralph-loop-codex.sh --help`
- `source scripts/lib/prompt_builder.sh && ... build_runtime_prompt plan ...`

## External Loop Integration Roadmap

### Phase 1: Core Runtime Consolidation

- [x] Extract the duplicated loop control flow from all provider scripts into a shared runtime library.
- [x] Define a single loop state machine with explicit states:
  `RUNNING`, `DONE`, `BLOCKED`, `DECIDE`, `MAX_ITERATIONS`, `FAILED_PREFLIGHT`, `FAILED_PROVIDER`.
- [x] Convert provider scripts into thin adapters that only define:
  CLI command shape, model flags, output capture mode, and provider-specific parsing.
- [x] Remove root-level prompt file generation everywhere and standardize on ephemeral prompt artifacts in `logs/`.
- [x] Normalize spec discovery across providers (same recursion rules, same precedence between `IMPLEMENTATION_PLAN.md` and `specs/`).

### Phase 2: Promise Tags And Human Escalation

- [x] Adopt richer semantic promise handling inspired by the external loop:
  support `DONE`/`ALL_DONE`, `BLOCKED:<reason>`, and `DECIDE:<question>`.
- [x] Implement shared parsing helpers for completion and help-needed signals.
- [x] Surface `BLOCKED` and `DECIDE` as first-class loop exits with distinct exit codes.
- [x] Print actionable resume instructions when the loop exits for human help.
- [x] Update docs and prompts so all runtimes use the same promise contract.

### Phase 3: Preflight And Environment Validation

- [x] Add a shared preflight module that runs before any iteration.
- [x] Validate:
  git repo presence, required planning files, constitution presence, and provider CLI availability.
- [x] Add profile-aware preflight checks for:
  `web`, `expo`, `backend`, and `library`.
- [x] For `expo`, check for relevant tooling such as `node`, `watchman`, `xcodebuild`/`simctl`, `adb`, and `npx expo-doctor` when applicable.
- [x] Fail fast with clear messages instead of letting the provider burn iterations on missing environment prerequisites.

### Phase 4: Runtime Observability And Operator UX

- [x] Port the strongest external runtime UX concepts into shared modules:
  rolling output preview, live status labeling, and timing summaries.
- [x] Reuse the existing `timing` ideas but move them into a common runtime path instead of provider-specific duplication.
- [x] Standardize session and per-iteration logs for all providers.
- [x] Add a concise end-of-iteration summary section that persists after each loop.
- [x] Keep the UX layer optional and non-blocking so headless runs stay simple.

### Phase 4 Review

- Added `scripts/lib/observability.sh` as a dedicated shared UX module containing:
  `format_duration`, `get_elapsed`, `print_iter_summary`, `append_iter_to_summary_log`,
  `print_session_summary`, `watch_latest_output`, `print_latest_output`.
- `watch_latest_output` now accepts `iteration`, `max_iterations`, and `iter_start_epoch`
  parameters, giving the live preview a labeled status line (e.g. "iter 3/10 +12s").
- `print_iter_summary` prints a persistent boxed summary after every iteration showing
  status (color-coded), duration, files changed, optional signal detail, and wall time.
- `append_iter_to_summary_log` writes one machine-readable line per iteration to a
  dedicated `logs/*_summary_*.log` file for post-session analysis.
- `print_session_summary` prints a final summary banner with total iterations, elapsed
  time, and done/no-signal/failed counts.
- `ralph-loop.sh` now tracks `SESSION_START_TIME`, `ITER_START_TIME`, `DONE_COUNT`,
  `NO_SIGNAL_COUNT`, and `FAILED_COUNT` and wires them through the unified loop.
- The rolling live preview and static tail preview were removed from `ralph-loop.sh`
  and consolidated into the shared `observability.sh` module.
- All UX output is guarded by TTY checks; headless/pipe runs are unaffected.

### Phase 4 Verification

- `bash -n scripts/lib/observability.sh scripts/ralph-loop.sh`
- `bash -c 'source scripts/lib/observability.sh && print_iter_summary 1 DONE 42 5'`
- `bash -c 'source scripts/lib/observability.sh && print_session_summary 5 300 2 2 1 "Claude Code"'`
- `./scripts/ralph-loop.sh --help`

### Phase 5: Stuck-Loop Protection

- [x] Integrate the existing `nr_of_tries` tracking into real loop execution.
- [x] Increment attempt counters for specs or work items on failed completion cycles.
- [x] When an item exceeds the retry threshold, mark it as “needs split” and trigger replanning guidance instead of blind retries.
- [x] Integrate the existing circuit breaker module into the shared runtime.
- [x] Halt execution when repeated no-progress or repeated-error patterns indicate the agent is stuck.

### Phase 6: Structured Work Queue

- [x] Keep `specs/` as the canonical user-facing requirements.
- [x] Keep `IMPLEMENTATION_PLAN.md` as the human-readable execution index.
- [x] Add a machine-readable `work-items.json` generated by planning.
- [x] Make build mode consume `work-items.json` when present, with fallback to `IMPLEMENTATION_PLAN.md` and then direct spec execution.
- [x] Support item metadata such as:
  id, parent spec, priority, dependencies, retry count, profile, and verification requirements.

### Phase 7: Verification Profiles (Web + Expo First)

- [x] Introduce explicit execution/verification profiles:
  `web`, `expo`, `backend`, `library`.
- [x] For `web`, define the default validation stack:
  lint, typecheck, unit tests, browser/e2e verification, and screenshots when relevant.
- [x] For `expo`, define a mobile-aware validation stack:
  `expo-doctor`, Metro startup checks, simulator/emulator smoke tests, and optional Maestro flows.
- [x] Make planning assign a profile to each generated work item so build mode knows which validation path to run.
- [x] Ensure profile selection is visible in logs and summaries.

### Phase 8: Direct SpecKit Script Execution

- [x] Move beyond prompt-driven planning by calling local `.specify/scripts/bash/*.sh` helpers directly when present.
- [x] Prefer vendored in-repo SpecKit assets first, then project-local `.specify`, then global installs, then manual emulation.
- [x] Add wrapper helpers for:
  feature creation, prerequisite checks, plan setup, and agent context updates.
- [x] Keep prompt-driven emulation only as a fallback, not the primary path.

### Phase 8 Review

- Added `scripts/lib/speckit_runner.sh` with `discover_speckit_scripts`, `run_speckit_feature_create`, `run_speckit_prereqs`, `run_speckit_plan_setup`, and `run_speckit_context_update` helpers.
- `ralph-loop.sh` sources the new library and, in plan mode, directly calls `check-prereqs.sh` and `update-context.sh` when present before the AI is invoked.
- `prompt_builder.sh` sources `speckit_runner.sh` and includes a `speckit_runner_prompt_block` in the plan prompt — when scripts exist the AI is instructed to call them directly (via Bash tool); otherwise it uses prompt-driven emulation.
- The startup banner in plan mode now shows the SpecKit script runner status.
- All scripts pass `bash -n` syntax checks.

### Phase 8 Verification

- `bash -n scripts/lib/speckit_runner.sh scripts/lib/prompt_builder.sh scripts/ralph-loop.sh`
- `source scripts/lib/speckit_runner.sh && discover_speckit_scripts "$(pwd)" && echo "$SPECKIT_RUNNER_STATUS"`
- `./scripts/ralph-loop.sh --help`

### Phase 9: Tests And Regression Coverage

- [x] Add shell tests for:
  argument parsing, prompt generation, promise parsing, preflight failures, and profile selection.
- [x] Add tests for stuck-loop handling (`nr_of_tries` and circuit breaker).
- [x] Add tests for plan/build precedence between:
  `work-items.json`, `IMPLEMENTATION_PLAN.md`, and direct specs.
- [x] Add smoke tests that verify all provider wrappers still invoke the shared runtime correctly.

### Phase 9 Review

- Added `tests/lib/test_helpers.sh` with shared assert helpers (`assert_equals`, `assert_true`,
  `assert_false`, `assert_contains`, `assert_file_exists`, `assert_cmd_succeeds`, `assert_cmd_fails`).
- Added 7 test files covering:
  - `test_runtime_helpers.sh`: promise parsing, DONE/ALL_DONE/BLOCKED/DECIDE detection, file-based
    signal extraction (27 assertions).
  - `test_preflight.sh`: git-repo check, constitution check, work-source check, profile auto-detection
    for expo/web/backend/unknown, explicit profile via constitution, plan mode skip (27 assertions).
  - `test_nr_of_tries.sh`: get/increment/reset counters, is_spec_stuck, get_stuck_specs (15 assertions).
  - `test_circuit_breaker.sh`: init, can_execute, no-progress threshold, progress reset, same-error
    threshold, reset (16 assertions).
  - `test_prompt_builder.sh`: argument parsing (--prd/--notes/--brief), missing-value errors,
    validate_plan_mode_arguments (18 assertions).
  - `test_work_items.sh`: task selection, dependency ordering, state transitions, retry count,
    PR title/body builders (19 assertions).
  - `test_smoke.sh`: bash -n syntax for all scripts, --help output, configure_runtime for all four
    runtimes, unknown-runtime error, work-source precedence (41 assertions).
- Added `tests/run_tests.sh` as the single test runner entry point with optional name filter.
- Fixed two macOS-portability bugs discovered by the new tests:
  - `nr_of_tries.sh`: replaced `grep -oP` (unsupported on BSD grep) with `grep -oE` plus a
    `grep -oE '[0-9]+$'` pipeline; replaced `sed -i` (no extension on macOS) with a temp-file pattern.
  - `preflight.sh`: moved `tr '[:upper:]' '[:lower:]'` before `sed` and replaced `\s*` with
    `[[:space:]]*` in the sed pattern so mixed-case profile declarations parse correctly.
- All 148 assertions across 7 test files pass: `./tests/run_tests.sh`

### Phase 9 Verification

- `./tests/run_tests.sh`
- `./tests/run_tests.sh smoke`
- `./tests/run_tests.sh circuit`
- `bash -n tests/lib/test_helpers.sh tests/test_*.sh tests/run_tests.sh`

### Suggested Sequencing

- [x] Build in this order:
  Phase 1 -> Phase 2 -> Phase 3 -> Phase 5 -> Phase 6 -> Phase 7 -> Phase 8 -> Phase 4 -> Phase 9
- [x] Reason:
  correctness and shared architecture first, then state handling and safeguards, then structured execution, then richer UX, and finally broader regression coverage.

## Current Integration Slice

- [x] Add a shared runtime helper for promise parsing and common post-iteration git behavior.
- [x] Wire all provider loops to use shared promise detection for `DONE`, `BLOCKED`, and `DECIDE`.
- [x] Update prompts/docs so the richer promise contract is part of the public interface.
- [x] Run syntax and smoke-test verification for the new runtime slice.

### Current Slice Verification

- `bash -n scripts/lib/prompt_builder.sh scripts/lib/runtime_helpers.sh scripts/ralph-loop.sh scripts/ralph-loop-codex.sh scripts/ralph-loop-gemini.sh scripts/ralph-loop-copilot.sh`
- `source scripts/lib/runtime_helpers.sh && parse_promise_signal_from_text "...<promise>BLOCKED:..."`
- `source scripts/lib/runtime_helpers.sh && parse_promise_signal_from_text "...<promise>DECIDE:..."`
- `./scripts/ralph-loop.sh --help`

## Single Runtime Review

### Plan

- [x] Compare the current provider-specific loop scripts and isolate the real runtime differences.
- [x] Decide whether a single `ralph-loop.sh` with `--runtime` and optional `--model` is practical.
- [x] Record the recommendation and tradeoffs.

### Review

- A single loop entrypoint is practical in this repo because most control flow is already duplicated rather than genuinely different.
- The real provider differences are limited to adapter concerns:
  invocation syntax, provider-specific preflight/auth checks, model flag mapping, and how terminal output is captured for promise parsing.
- A unified script should use one shared runtime plus provider adapters, not one flat block of conditionals spread across the loop body.
- A generic `--model` flag is viable, but it should be interpreted per runtime because each CLI exposes model selection differently and some may ignore it.

## Single Runtime Implementation

### Plan

- [x] Add a shared provider adapter library for runtime-specific config, preflight, and invocation.
- [x] Refactor `scripts/ralph-loop.sh` into the single supported entrypoint with `--runtime` and optional `--model`.
- [x] Normalize shared behavior inside the unified loop (recursive spec discovery, shared log naming, shared promise parsing).
- [x] Remove redundant provider-specific top-level loop scripts.
- [x] Update docs/templates to reflect the new single-entrypoint workflow.
- [x] Run syntax checks and CLI help verification.

### Review

- `scripts/ralph-loop.sh` is now the only supported loop entrypoint, with runtime selection handled by `--runtime`.
- Provider-specific differences now live in `scripts/lib/provider_adapters.sh`, which handles runtime config, preflight, and command invocation.
- The unified loop now applies one shared control flow across Claude, Codex, Gemini, and Copilot, including shared promise parsing and shared recursive spec discovery.
- `--model` is now a generic runtime option, but it is only passed through for runtimes with explicit model flags in this wrapper (Gemini and Copilot). Claude and Codex currently warn and ignore it.
- The old top-level provider wrapper scripts were removed.

### Verification

- `chmod +x scripts/ralph-loop.sh`
- `bash -n scripts/lib/prompt_builder.sh scripts/lib/runtime_helpers.sh scripts/lib/provider_adapters.sh scripts/ralph-loop.sh`
- `./scripts/ralph-loop.sh --help`
- `rg -n "ralph-loop-codex.sh|ralph-loop-gemini.sh|ralph-loop-copilot.sh" README.md templates scripts -g '!logs/**'`

## Setup Docs Hardening

### Plan

- [x] Update the AI-guided setup flow so it installs the full harness, not just `scripts/ralph-loop.sh`.
- [x] Update the manual install guide to mirror the same full-harness bootstrap.
- [x] Update the README so the “tell an LLM to set it up” workflow points at this fork and matches the new bootstrap behavior.
- [x] Verify the updated docs no longer advertise the incomplete one-file install path.

### Review

- The AI-guided install flow in `INSTALLATION.md` now clones this fork to a temporary directory and copies the full local harness: the unified loop, helper libraries, prompt templates, and vendored SpecKit planning assets.
- The manual install guide in `INSTALL.md` now mirrors that same full-harness bootstrap instead of advertising the old one-file curl flow.
- The README now points the “Set up Ralph Wiggum…” prompt at this fork and explicitly explains that the guided setup installs the full harness.
- I also aligned the local `skills/ralph-wiggum/SKILL.md` setup example so it does not send an LLM to the upstream repo by mistake.

### Verification

- `rg -n "Set up Ralph Wiggum.*tolulawson/ralph-wiggum|Install The Full Harness|scripts/lib/prompt_builder.sh|vendor/speckit-agent-skills" README.md INSTALL.md INSTALLATION.md skills/ralph-wiggum/SKILL.md`
- `rg -n "Set up Ralph Wiggum.*fstandhartinger/ralph-wiggum" README.md INSTALL.md INSTALLATION.md skills/ralph-wiggum/SKILL.md`
- `bash -n scripts/ralph-loop.sh scripts/lib/prompt_builder.sh scripts/lib/runtime_helpers.sh scripts/lib/provider_adapters.sh`

## README + Manual Docs Alignment

### Plan

- [x] Update `README.md` so it reflects the current single-entrypoint architecture and points users at this fork consistently.
- [x] Remove or reframe stale README examples that no longer match the unified loop interface.
- [x] Update `INSTALL.md` so the manual install guide clearly describes the full harness layout and current runtime model.
- [x] Verify `README.md` and `INSTALL.md` no longer contain stale upstream or deprecated loop-wrapper references.

### Review

- `README.md` now describes the current architecture explicitly: one unified loop entrypoint, runtime selection via `--runtime`, shared helpers in `scripts/lib/`, prompt templates in `templates/`, and vendored planning assets in `vendor/speckit-agent-skills/`.
- The README now points setup and skill-install examples at this fork (`tolulawson/ralph-wiggum`) instead of the upstream repo.
- The README’s stale Telegram flag examples were replaced with a clearer note: notification helpers still exist, but they are not wired into the unified loop by default.
- `INSTALL.md` now describes the installed harness layout after the bootstrap copy step and explicitly documents the runtime-switching model.

### Verification

- `rg -n "fstandhartinger/ralph-wiggum|ralph-loop-codex.sh|ralph-loop-gemini.sh|ralph-loop-copilot.sh" README.md INSTALL.md`
- `rg -n -- "--telegram-audio|--no-telegram" README.md INSTALL.md`

## PR + Merge Workflow

### Plan

- [x] Add shared helpers for `work-items.json` state transitions, task selection, and merge reconciliation.
- [x] Add release workflow helpers for task branches and draft PR creation/update via `gh`.
- [x] Refactor the loop so `work-items.json` drives one-task-at-a-time branching, push, PR, and merge waiting.
- [x] Change build-mode prompts/schema so the runtime, not the agent, owns release-state transitions after implementation succeeds.
- [x] Update docs/templates to describe the new task branch and merge workflow.
- [x] Run syntax checks plus focused smoke tests for the new work-item and PR helpers.

### Review

- Added `scripts/lib/work_items.sh` to make `work-items.json` a real execution checklist with task selection, retry tracking, release-state transitions, and merge reconciliation.
- Added `scripts/lib/release_workflow.sh` to manage per-task branches, draft PR creation/update via `gh`, and consistent “awaiting merge” messaging.
- `scripts/ralph-loop.sh` now treats `work-items.json` as a one-task-at-a-time release queue: it reconciles merged tasks, selects the next actionable work item, switches to that task branch, and only pushes/opens a draft PR after the agent finishes a successful implementation pass.
- The build prompt and planning schema now reflect the new contract: the agent creates a local review-ready commit, while the runtime owns push, PR, and merge-state updates.
- Fixed a merge-reconciliation bug for manually merged tasks without a PR number; those items now advance from `awaiting_merge` to `done` when their task branch is detected as merged into the base branch.
- Fixed the local shell-test temp-dir helper so command-substitution-based fixtures are no longer deleted before the tests can use them.
- Updated README and install docs so they no longer describe the old “agent commits and pushes directly after each spec” model.

### Verification

- `bash -n scripts/ralph-loop.sh scripts/lib/runtime_helpers.sh scripts/lib/work_items.sh scripts/lib/release_workflow.sh scripts/lib/prompt_builder.sh`
- `./scripts/ralph-loop.sh --help`
- `bash tests/test_work_items.sh`
- `bash tests/test_runtime_helpers.sh`
- Smoke test: `select_next_work_item` correctly prefers an `in_progress` item and preserves empty-field parsing for `branch` / `pr_number`
- Smoke test: `find_awaiting_merge_item` correctly reads an `awaiting_merge` item with an empty `pr_number`
- Smoke test: `reconcile_merged_pull_requests` now marks a manually merged branch-only task as `done`

## Installation + Telegram Docs Alignment

### Plan

- [x] Update `INSTALLATION.md` so the AI-guided setup flow describes optional notification/logging features accurately under the unified loop.
- [x] Update `TELEGRAM_SETUP.md` so it no longer advertises deprecated unified-loop CLI flags.
- [x] Reframe Telegram support as helper-library functionality unless the user wires it into a custom loop wrapper.
- [x] Verify the setup docs no longer promise removed Telegram loop flags.

## Default Runtime: Codex

### Plan

- [x] Change the unified loop's default runtime from Claude to Codex.
- [x] Update help text and README examples to match the new default runtime.
- [x] Verify the script help output reflects the new default.

### Review

- `scripts/ralph-loop.sh` now defaults to `codex` when `--runtime` and `RALPH_RUNTIME` are not provided.
- The CLI help output now labels Codex as the default runtime and updates the `--runtime` option description accordingly.
- `README.md` now explicitly says that bare `./scripts/ralph-loop.sh` runs Codex by default and includes a matching runtime-selection example.

### Verification

- `bash -n scripts/ralph-loop.sh`
- `./scripts/ralph-loop.sh --help`

## Skill Asset Location Clarity

### Plan

- [x] Make the install docs explicit that client projects keep one local copy of planning assets under `vendor/speckit-agent-skills/`.
- [x] Clarify that the repo's top-level `skills/` directory is only for publishing/installing Ralph as an agent skill package and should not be copied into client projects.
- [x] Fix stale upstream installer references in `skills/ralph-wiggum/SKILL.md`.
- [x] Verify the updated docs consistently describe the single-location rule.

### Review

- `INSTALL.md` and `INSTALLATION.md` now explicitly say that client projects should keep planning assets only under `vendor/speckit-agent-skills/` and should not copy the repo's top-level `skills/` directory.
- `README.md` now explains the difference between the copied project harness (`vendor/speckit-agent-skills/`) and the installer-facing `skills/` package.
- `skills/ralph-wiggum/SKILL.md` now points installer commands at this fork and states that the skill package is separate from the client-project harness.

### Verification

- `rg -n "Do not also copy this repo's top-level|Do not also copy this repository's top-level|single local copy|installer-facing|tolulawson/ralph-wiggum" README.md INSTALL.md INSTALLATION.md skills/ralph-wiggum/SKILL.md`

## Automatic Merge Workflow

### Plan

- [x] Replace the default human-merge handoff with an automatic merge attempt after successful implementation.
- [x] Keep `awaiting_merge` only as a fallback state when automatic merge is blocked by permissions or repo rules.
- [x] Update prompts and docs so the release workflow now describes automatic merge as the default.
- [x] Add focused verification for the local automatic-merge fallback path.
- [x] Capture the workflow preference change in `tasks/lessons.md`.

### Review

- `scripts/ralph-loop.sh` now tries to complete the release immediately after a successful work-item implementation: push branch, create or inspect the PR, then attempt an automatic merge.
- If the runtime encounters an already-pending `awaiting_merge` item on the next run, it now tries that merge again before stopping.
- `scripts/lib/release_workflow.sh` now includes `merge_work_item_release`, which merges via `gh pr merge` when possible and falls back to a local base-branch merge plus push when PR tooling is unavailable.
- `awaiting_merge` remains in the state model only for blocked merges, so human intervention is now the exception rather than the default path.
- `tasks/lessons.md` was added to capture the new rule: prefer configurable automation over hard-coded human merge gates.

### Verification

- `bash -n scripts/ralph-loop.sh scripts/lib/release_workflow.sh scripts/lib/work_items.sh templates/PROMPT_build.md templates/PROMPT_plan.md`
- `bash tests/test_work_items.sh`
- `bash tests/test_runtime_helpers.sh`
- `rg -n "attempts to merge|Automatic merge is blocked|attempt to merge it automatically" README.md INSTALL.md INSTALLATION.md templates/PROMPT_build.md templates/PROMPT_plan.md templates/constitution-template.md scripts/ralph-loop.sh`

## Testing Policy Controls

### Plan

- [x] Add a dedicated `Testing Policy` section to the constitution template so users can specify unit, integration, E2E, and device-testing details separately.
- [x] Teach prompt generation to surface explicit testing policy details from the constitution into both planning and build mode.
- [x] Expand `work-items.json` guidance so planning can store structured testing details separate from high-level `verification` tokens.
- [x] Surface work-item-specific testing details in the active work item context during build mode.
- [x] Update docs to explain how project owners can declare custom testing workflows (including Maestro, Agent Device Skills, and MCP-driven/device testing).
- [x] Add focused tests for the new testing-policy prompt plumbing.

### Review

- Added a first-class `## Testing Policy` contract to the constitution template and the setup interview so projects can declare exact unit, integration, E2E, and device-testing expectations separately.
- `scripts/lib/prompt_builder.sh` now extracts the constitution's `## Testing Policy` section and appends it to both build and plan prompts, with clear precedence rules over generic profile defaults.
- Planning guidance in `templates/PROMPT_plan.md` now supports an optional structured `testing` object in each work item so exact commands for E2E and device checks stay separate from the high-level `verification` categories.
- `scripts/lib/work_items.sh` now carries forward a compact testing summary for the active work item and includes it in the authoritative runtime-appended work-item context.
- `scripts/lib/verification_profiles.sh` now recognizes richer mobile verification defaults, including Maestro plus MCP / agent-device-skill driven device checks.
- Updated README and install docs so users know where to put custom testing policy and how to express mobile-specific E2E/device requirements.

### Verification

- `bash -n scripts/lib/prompt_builder.sh scripts/lib/work_items.sh scripts/lib/verification_profiles.sh`
- `bash tests/test_prompt_builder.sh`
- `bash tests/test_work_items.sh`
- `bash tests/test_runtime_helpers.sh`

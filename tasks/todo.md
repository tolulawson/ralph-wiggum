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

- [ ] Extract the duplicated loop control flow from all provider scripts into a shared runtime library.
- [ ] Define a single loop state machine with explicit states:
  `RUNNING`, `DONE`, `BLOCKED`, `DECIDE`, `MAX_ITERATIONS`, `FAILED_PREFLIGHT`, `FAILED_PROVIDER`.
- [ ] Convert provider scripts into thin adapters that only define:
  CLI command shape, model flags, output capture mode, and provider-specific parsing.
- [ ] Remove root-level prompt file generation everywhere and standardize on ephemeral prompt artifacts in `logs/`.
- [ ] Normalize spec discovery across providers (same recursion rules, same precedence between `IMPLEMENTATION_PLAN.md` and `specs/`).

### Phase 2: Promise Tags And Human Escalation

- [ ] Adopt richer semantic promise handling inspired by the external loop:
  support `DONE`/`ALL_DONE`, `BLOCKED:<reason>`, and `DECIDE:<question>`.
- [ ] Implement shared parsing helpers for completion and help-needed signals.
- [ ] Surface `BLOCKED` and `DECIDE` as first-class loop exits with distinct exit codes.
- [ ] Print actionable resume instructions when the loop exits for human help.
- [ ] Update docs and prompts so all runtimes use the same promise contract.

### Phase 3: Preflight And Environment Validation

- [ ] Add a shared preflight module that runs before any iteration.
- [ ] Validate:
  git repo presence, required planning files, constitution presence, and provider CLI availability.
- [ ] Add profile-aware preflight checks for:
  `web`, `expo`, `backend`, and `library`.
- [ ] For `expo`, check for relevant tooling such as `node`, `watchman`, `xcodebuild`/`simctl`, `adb`, and `npx expo-doctor` when applicable.
- [ ] Fail fast with clear messages instead of letting the provider burn iterations on missing environment prerequisites.

### Phase 4: Runtime Observability And Operator UX

- [ ] Port the strongest external runtime UX concepts into shared modules:
  rolling output preview, live status labeling, and timing summaries.
- [ ] Reuse the existing `timing` ideas but move them into a common runtime path instead of provider-specific duplication.
- [ ] Standardize session and per-iteration logs for all providers.
- [ ] Add a concise end-of-iteration summary section that persists after each loop.
- [ ] Keep the UX layer optional and non-blocking so headless runs stay simple.

### Phase 5: Stuck-Loop Protection

- [ ] Integrate the existing `nr_of_tries` tracking into real loop execution.
- [ ] Increment attempt counters for specs or work items on failed completion cycles.
- [ ] When an item exceeds the retry threshold, mark it as “needs split” and trigger replanning guidance instead of blind retries.
- [ ] Integrate the existing circuit breaker module into the shared runtime.
- [ ] Halt execution when repeated no-progress or repeated-error patterns indicate the agent is stuck.

### Phase 6: Structured Work Queue

- [ ] Keep `specs/` as the canonical user-facing requirements.
- [ ] Keep `IMPLEMENTATION_PLAN.md` as the human-readable execution index.
- [ ] Add a machine-readable `work-items.json` generated by planning.
- [ ] Make build mode consume `work-items.json` when present, with fallback to `IMPLEMENTATION_PLAN.md` and then direct spec execution.
- [ ] Support item metadata such as:
  id, parent spec, priority, dependencies, retry count, profile, and verification requirements.

### Phase 7: Verification Profiles (Web + Expo First)

- [ ] Introduce explicit execution/verification profiles:
  `web`, `expo`, `backend`, `library`.
- [ ] For `web`, define the default validation stack:
  lint, typecheck, unit tests, browser/e2e verification, and screenshots when relevant.
- [ ] For `expo`, define a mobile-aware validation stack:
  `expo-doctor`, Metro startup checks, simulator/emulator smoke tests, and optional Maestro flows.
- [ ] Make planning assign a profile to each generated work item so build mode knows which validation path to run.
- [ ] Ensure profile selection is visible in logs and summaries.

### Phase 8: Direct SpecKit Script Execution

- [ ] Move beyond prompt-driven planning by calling local `.specify/scripts/bash/*.sh` helpers directly when present.
- [ ] Prefer vendored in-repo SpecKit assets first, then project-local `.specify`, then global installs, then manual emulation.
- [ ] Add wrapper helpers for:
  feature creation, prerequisite checks, plan setup, and agent context updates.
- [ ] Keep prompt-driven emulation only as a fallback, not the primary path.

### Phase 9: Tests And Regression Coverage

- [ ] Add shell tests for:
  argument parsing, prompt generation, promise parsing, preflight failures, and profile selection.
- [ ] Add tests for stuck-loop handling (`nr_of_tries` and circuit breaker).
- [ ] Add tests for plan/build precedence between:
  `work-items.json`, `IMPLEMENTATION_PLAN.md`, and direct specs.
- [ ] Add smoke tests that verify all provider wrappers still invoke the shared runtime correctly.

### Suggested Sequencing

- [ ] Build in this order:
  Phase 1 -> Phase 2 -> Phase 3 -> Phase 5 -> Phase 6 -> Phase 7 -> Phase 8 -> Phase 4 -> Phase 9
- [ ] Reason:
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

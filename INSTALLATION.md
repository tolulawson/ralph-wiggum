# AI Agent: Ralph Wiggum Setup

> **You're an AI coding agent.** Follow these instructions to set up Ralph Wiggum.
>
> **Actually execute these steps** — don't just describe them.

---

## Overview: What You'll Do

1. **Quick Setup** — Create directories and install the full Ralph harness (1-2 minutes)
2. **Project Interview** — Learn about the user's project vision (3-5 minutes)
3. **Constitution** — Create the project's guiding document
4. **Next Steps** — Explain how to create specs and start Ralph

The goal: Make this feel **lightweight, pleasant, and professional**. Focus on understanding the *project*, not interrogating about technical minutiae.

---

## Phase 1: Create Structure

```bash
mkdir -p .specify/memory specs scripts scripts/lib templates vendor logs history completion_log .cursor/commands .claude/commands
```

---

## Phase 2: Install The Full Harness

Clone this repository to a temporary directory, then copy the runtime assets into
the user's project. Do **not** install only `scripts/ralph-loop.sh` anymore; the
loop now depends on helper libraries, prompt templates, and vendored planning assets.

If the user explicitly told you to set Ralph up using a specific repository URL,
use that exact URL. Otherwise, default to this repository:

```bash
RALPH_REPO_URL="https://github.com/tolulawson/ralph-wiggum.git"
RALPH_BOOTSTRAP_DIR="$(mktemp -d)"

git clone --depth 1 "$RALPH_REPO_URL" "$RALPH_BOOTSTRAP_DIR/repo"

cp "$RALPH_BOOTSTRAP_DIR/repo/scripts/ralph-loop.sh" scripts/ralph-loop.sh
cp "$RALPH_BOOTSTRAP_DIR/repo/scripts/lib/"*.sh scripts/lib/

cp "$RALPH_BOOTSTRAP_DIR/repo/templates/PROMPT_build.md" templates/PROMPT_build.md
cp "$RALPH_BOOTSTRAP_DIR/repo/templates/PROMPT_plan.md" templates/PROMPT_plan.md
cp "$RALPH_BOOTSTRAP_DIR/repo/templates/AGENTS.md" templates/AGENTS.md
cp "$RALPH_BOOTSTRAP_DIR/repo/templates/constitution-template.md" templates/constitution-template.md

rm -rf vendor/speckit-agent-skills
cp -R "$RALPH_BOOTSTRAP_DIR/repo/vendor/speckit-agent-skills" vendor/speckit-agent-skills

chmod +x scripts/ralph-loop.sh

rm -rf "$RALPH_BOOTSTRAP_DIR"
```

After this step, the project has the complete local harness needed for:
- unified runtime selection via `--runtime`
- template-backed prompt generation
- deterministic planning via the vendored SpecKit planning assets
- task-by-task branch / pull-request release handling driven by `work-items.json`

---

## Phase 3: Get Version Info

```bash
git ls-remote https://github.com/tolulawson/ralph-wiggum.git HEAD | cut -f1
```

Store the commit hash for the constitution.

---

## Phase 4: Project Interview

### Introduction

Start with a warm, brief introduction:

> "I'll ask a few quick questions to understand your project. This creates a **constitution** — a short document that helps me stay aligned with your goals across all future sessions.
>
> Don't worry about getting everything perfect — we can always refine it later."

### The Questions

Present these conversationally, one at a time. **Keep it lightweight.**

---

#### 1. Project Name
> "What's the name of your project?"

---

#### 2. Project Vision (MOST IMPORTANT)

> "Tell me about your project — what is it, what problem does it solve, who is it for?
>
> This is the most important question. The more I understand your vision, the better I can help build it."

**Note to AI:** This is the heart of the interview. Encourage the user to share context. A few sentences to a paragraph is ideal.

---

#### 3. Core Principles

> "What 2-3 principles should guide development? Think about what matters most.
>
> Examples: 'User experience first', 'Keep it simple', 'Security above all', 'Move fast', 'Quality over speed'"

**Note to AI:** If the user struggles, offer to suggest principles based on their project description.

---

#### 4. Technical Stack (OPTIONAL)

> "What's the tech stack? (Or should I figure it out from the codebase?)"

**Note to AI:** For existing projects, analyze the codebase yourself. Don't pressure the user.

---

#### 5. Autonomy Settings

> "Two quick settings:
>
> **YOLO Mode** (recommended): Execute commands, modify files, run tests without asking each time.
>
> **Git Autonomy** (recommended): Create local commits automatically; the loop runtime pushes task branches and opens draft PRs when work items are ready.
>
> Enable both? (yes/no)"

**Note to AI:** Default to YES for both if the user seems agreeable.

---

#### 6. Optional Features

These are optional helper capabilities. The unified loop works without them.
If the user enables them, explain that they may require custom wiring in the
constitution or a project-specific wrapper around the loop.

Present as a quick yes/no checklist:

> "A couple of optional features:"

**a) Telegram Notifications** — Progress updates sent via helper functions in `scripts/lib/notifications.sh`.

> "Want Telegram notifications? (yes/no)"

If yes, ask for `TG_BOT_TOKEN` and `TG_CHAT_ID` (env vars, never put tokens in files).
Also explain that the current unified loop does not enable Telegram flags by default;
it requires wiring the helper library into a custom wrapper or project workflow.

**b) GitHub Issues** — Work on GitHub issues in addition to spec files.

> "Should Ralph also work on GitHub Issues? (yes/no)"

If yes, ask for the repository (e.g. `owner/repo`) and whether issues need approval first.

**c) Completion Logs** — Keep optional completion artifacts in `completion_log/`.

> "Keep a completion log? (yes/no)"

---

### Interview Complete

> "That's all I need. Let me set up your project..."

---

## Phase 5: Create Constitution

Create `.specify/memory/constitution.md` using the interview answers.

The constitution must be **concise**. It's the single source of truth — the agent reads it every iteration.

**Template** (fill in bracketed values, include optional sections only if user opted in):

```markdown
# {PROJECT_NAME} Constitution

> {PROJECT_VISION}

---

## Context Detection

**Ralph Loop Mode** (started by `./scripts/ralph-loop.sh`):
- Pick highest priority incomplete spec from `specs/`
- Implement, test, and create a review-ready local commit
- If `work-items.json` exists: let the runtime push the task branch, open/update a draft PR, and wait for merge before the next task
- Output `<promise>DONE</promise>` only when 100% complete
- Output `<promise>ALL_DONE</promise>` when no work remains
- Output `<promise>BLOCKED:reason</promise>` when human help is required
- Output `<promise>DECIDE:question</promise>` when a human decision is required

**Interactive Mode** (normal conversation):
- Be helpful, guide decisions, create specs

---

## Core Principles

{List the user's principles, one per line}

---

## Technical Stack

{List or "Detected from codebase"}

---

## Autonomy

YOLO Mode: {ENABLED/DISABLED}
Git Autonomy: {ENABLED/DISABLED}

---

## Specs

Specs live in `specs/` as markdown files. Pick the highest priority incomplete spec (lower number = higher priority). A spec is incomplete if it lacks `## Status: COMPLETE`.

Spec template: https://raw.githubusercontent.com/github/spec-kit/refs/heads/main/templates/spec-template.md

When all specs are complete, re-verify a random one before signaling done.

---

## NR_OF_TRIES

Track attempts per spec via `<!-- NR_OF_TRIES: N -->` at the bottom of the spec file. Increment each attempt. At 10+, the spec is too hard — split it into smaller specs.

---

## History

Append a 1-line summary to `history.md` after each spec completion. For details, create `history/YYYY-MM-DD--spec-name.md` with lessons learned, decisions made, and issues encountered. Check history before starting work on any spec.

---

## Completion Signal

All acceptance criteria verified, tests pass, changes committed locally, branch left clean and review-ready → output `<promise>DONE</promise>`. Never output this until truly complete.

If `work-items.json` is active, the loop runtime handles the release workflow after `<promise>DONE</promise>`:
push the task branch, open or update a draft PR, and pause until that PR is merged.

If human help is required, output `<promise>BLOCKED:reason</promise>`.
If a human decision is required, output `<promise>DECIDE:question</promise>`.
```

### Optional Sections (add to constitution only if user opted in)

#### If Telegram: YES

```markdown
---

## Telegram Notifications

Send progress via Telegram using env vars `TG_BOT_TOKEN` and `TG_CHAT_ID`.
These notifications are powered by helper functions in `scripts/lib/notifications.sh`.
The unified `./scripts/ralph-loop.sh` does not enable them automatically; wire them
into a project-specific wrapper or custom workflow if you want them active.

After completing a spec:
  curl -s -X POST "https://api.telegram.org/bot$TG_BOT_TOKEN/sendMessage" \
    -d chat_id="$TG_CHAT_ID" -d parse_mode=Markdown \
    -d text="✅ *Completed:* {spec name}%0A{one-line summary}"

Also notify on: 3+ consecutive failures, stuck specs (NR_OF_TRIES >= 10).
```

#### If GitHub Issues: YES

```markdown
---

## GitHub Issues

Work on issues from `{OWNER/REPO}` in addition to specs. Use `gh` CLI:
  gh issue list --repo {OWNER/REPO} --state open
  gh issue close <number> --repo {OWNER/REPO}

{If approval required: Only work on issues approved by **{APPROVER}**.}
```

#### If Completion Logs: YES

```markdown
---

## Completion Logs

Create `completion_log/YYYY-MM-DD--HH-MM-SS--spec-name.md` with a brief summary
when your project-specific workflow chooses to capture completion artifacts.
```

---

## Phase 6: Create Agent Entry Files

### AGENTS.md (project root)

```markdown
# Agent Instructions

**Read:** `.specify/memory/constitution.md`

That file is your source of truth for this project.
```

### CLAUDE.md (project root)

Same content as AGENTS.md.

---

## Phase 7: Explain Next Steps

> **Ralph Wiggum is ready!**
>
> **To create a spec:** Describe what you want built. I'll create a spec file in `specs/` with acceptance criteria.
>
> **To start the loop:** `./scripts/ralph-loop.sh`
>
> Ralph picks one task at a time, implements it, verifies acceptance criteria, creates a local review-ready commit, then pushes a task branch and opens or updates a draft PR when `work-items.json` is active.
>
> After you merge that PR and rerun the loop from the base branch, Ralph marks the task done and starts the next one.

| Task | Command |
|------|---------|
| Start building | `./scripts/ralph-loop.sh` |
| Use Codex | `./scripts/ralph-loop.sh --runtime codex` |
| Use Gemini | `./scripts/ralph-loop.sh --runtime gemini --model gemini-2.5-pro` |
| Use Copilot | `./scripts/ralph-loop.sh --runtime copilot --model gpt-5.2` |
| Limit iterations | `./scripts/ralph-loop.sh 20` |

Ready to create your first specification?

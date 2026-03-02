# 🧠 Ralph Wiggum

> Autonomous AI coding with spec-driven development

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

⚠️ **Use at your own risk.** This tool grants AI agents significant autonomy over your codebase and system. Review all changes and use in isolated environments when possible.

## Quick Start

### Install as Agent Skill (Optional)

```bash
# If you are installing this fork as an agent skill
npx add-skill tolulawson/ralph-wiggum

openskills install tolulawson/ralph-wiggum
```

### Full Setup with Interview

**AI Agent? Start Here:**
> Read and execute [INSTALLATION.md](INSTALLATION.md) for a guided setup with interactive interview.

**Human Developer? Start Here:**
> Read [INSTALL.md](INSTALL.md) for manual setup instructions.

---

## What is Ralph Wiggum?

Ralph Wiggum (in this flavour) combines **Geoffrey Huntley's original iterative bash loop** with **SpecKit-style specifications** for fully autonomous AI-assisted software development.

### Key Features

- 🔄 **Iterative Self-Correction** — Each loop picks ONE task, implements it, verifies, and commits
- 📋 **Spec-Driven Development** — Professional specifications with clear acceptance criteria
- 🎯 **Completion Verification** — Agent only outputs `<promise>DONE</promise>` when criteria are 100% met
- 🧠 **Fresh Context Each Loop** — Every iteration starts with a clean context window
- 📝 **Shared State on Disk** — Specs, plans, logs, and history live in the repo between iterations

### Current Architecture

- One unified loop entrypoint: `./scripts/ralph-loop.sh`
- Runtime selection via `--runtime claude|codex|gemini|copilot`
- Shared runtime helpers in `scripts/lib/`
- Prompt templates in `templates/`
- Vendored planning assets in `vendor/speckit-agent-skills/`

---

## How It Works

Based on [Geoffrey Huntley's methodology](https://github.com/ghuntley/how-to-ralph-wiggum):

```
┌─────────────────────────────────────────────────────────────┐
│                     RALPH LOOP                              │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐  │
│  │    Orient    │───▶│  Pick Task   │───▶│  Implement   │  │
│  │  Read specs  │    │  from Plan   │    │   & Test     │  │
│  └──────────────┘    └──────────────┘    └──────────────┘  │
│                                                   │         │
│         ┌────────────────────────────────────────┘         │
│         ▼                                                   │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐  │
│  │   Verify     │───▶│   Commit     │───▶│  Output DONE │  │
│  │  Criteria    │    │   & Push     │    │  (if passed) │  │
│  └──────────────┘    └──────────────┘    └──────────────┘  │
│                                                   │         │
│         ┌────────────────────────────────────────┘         │
│         ▼                                                   │
│  ┌──────────────────────────────────────────────────────┐  │
│  │ Bash loop checks for <promise>DONE</promise>         │  │
│  │ If found: next iteration | If not: retry             │  │
│  └──────────────────────────────────────────────────────┘  │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### The Magic Phrase

The agent outputs `<promise>DONE</promise>` **ONLY** when:
- All acceptance criteria are verified
- Tests pass
- Changes are committed and pushed

The bash loop checks for this phrase. If not found, it retries.

Additional runtime signals:
- `<promise>BLOCKED:reason</promise>` when human help is required
- `<promise>DECIDE:question</promise>` when a human decision is required

---

## Two Modes

| Mode | Purpose | Command |
|------|---------|---------|
| **build** (default) | Pick spec/task, implement, test, commit | `./scripts/ralph-loop.sh` |
| **plan** (optional) | Orchestrate SpecKit planning from a PRD, notes, or existing specs | `./scripts/ralph-loop.sh plan` |

### Planning is OPTIONAL

Most projects work fine **directly from specs**. The agent simply:
1. Looks at `specs/` folder
2. Picks the highest priority incomplete spec
3. Implements it completely

Use `plan` mode when you want Ralph to orchestrate the SpecKit planning pipeline:
1. Accept a detailed PRD, informal notes, or existing repo context
2. Normalize notes into a PRD when needed
3. Decompose that input into feature-sized specs
4. Run the canonical order for each feature:
   `speckit-specify -> speckit-clarify (if needed) -> speckit-plan -> speckit-tasks`
5. Aggregate the results into `IMPLEMENTATION_PLAN.md`
6. Prefer the vendored in-repo SpecKit skill copies; fall back to project-local or
   user-global installs only when the vendored copies are unavailable

**Tip:** Delete `IMPLEMENTATION_PLAN.md` to return to working directly from specs.

---

## Installation

### For AI Agents (Recommended)

Point your AI agent to this repo and say:

> "Set up Ralph Wiggum in my project using https://github.com/tolulawson/ralph-wiggum"

The agent will read [INSTALLATION.md](INSTALLATION.md) and guide you through a **lightweight, pleasant setup**:

1. **Quick Setup** (~1-2 min) — Create directories and install the full harness
2. **Project Interview** (~3-5 min) — Focus on your **vision and goals**, not technical minutiae
3. **Constitution** — Create a guiding document for all future sessions
4. **Next Steps** — Clear guidance on creating specs and starting Ralph

The interview prioritizes understanding *what you're building and why* over interrogating you about tech stack details. For existing projects, the agent can detect your stack automatically.
The guided install now copies the complete local harness:
`scripts/ralph-loop.sh`, `scripts/lib/*.sh`, `templates/`, and the vendored
SpecKit planning assets under `vendor/speckit-agent-skills/`.

### Manual Setup

See [INSTALL.md](INSTALL.md) for step-by-step manual instructions.

---

## Usage

### 1. Create Specifications

Tell your AI what you want to build, or use `/speckit.specify` in Cursor:

```
/speckit.specify Add user authentication with OAuth
```

This creates `specs/001-user-auth/spec.md` with:
- Feature requirements
- **Clear, testable acceptance criteria** (critical!)
- Completion signal section

**The key to good specs:** Each spec needs acceptance criteria that are **specific and testable**. Not "works correctly" but "user can log in with Google and session persists across page reloads."

### 2. (Optional) Run Planning Mode

```bash
./scripts/ralph-loop.sh plan
./scripts/ralph-loop.sh --runtime codex plan
./scripts/ralph-loop.sh plan --prd docs/PRD.md
./scripts/ralph-loop.sh plan --notes docs/ideas.md
./scripts/ralph-loop.sh plan --brief "Build an Expo app for field sales"
```

Creates or updates feature specs plus `IMPLEMENTATION_PLAN.md` by orchestrating the
SpecKit planning phases. **This step is optional** — most projects still work fine
directly from specs.

The planning loop now vendors the canonical planning-related SpecKit skill
definitions under `vendor/speckit-agent-skills/skills/`, so planning remains
deterministic even when the machine does not have SpecKit installed globally.

### 3. Run Build Mode

```bash
./scripts/ralph-loop.sh        # Unlimited iterations
./scripts/ralph-loop.sh 20     # Max 20 iterations
./scripts/ralph-loop.sh --runtime codex
./scripts/ralph-loop.sh --runtime gemini --model gemini-2.5-pro
./scripts/ralph-loop.sh --runtime copilot --model gpt-5.2
```

Each iteration:
1. Picks the highest priority task
2. Implements it completely
3. Verifies acceptance criteria
4. Outputs `<promise>DONE</promise>` only if criteria pass
5. Bash loop checks for the phrase
6. Context cleared, next iteration starts

### Logging (All Output Captured)

Every loop run writes **all output** to log files in `logs/`:

- **Session log:** `logs/ralph_*_session_YYYYMMDD_HHMMSS.log` (entire run, including CLI output)
- **Iteration logs:** `logs/ralph_*_iter_N_YYYYMMDD_HHMMSS.log` (per-iteration CLI output)
- **Codex last message:** `logs/ralph_codex_output_iter_N_*.txt` (only when `--runtime codex` is used)

If something gets stuck, these logs contain the full verbose trace.

### NR_OF_TRIES Tracking

Each spec tracks how many times it has been attempted. After 10 attempts without completion, the spec is flagged as "stuck" and should be split into smaller specs.

```bash
# Check stuck specs
source scripts/lib/nr_of_tries.sh
print_stuck_specs_summary
```

The counter is stored as a comment in the spec file:
```markdown
<!-- NR_OF_TRIES: 5 -->
```

### Optional Notification Helpers

The repo still includes helper functions for Telegram notifications and completion
logs in `scripts/lib/notifications.sh`, plus setup notes in [TELEGRAM_SETUP.md](TELEGRAM_SETUP.md).

Those helpers are **not wired into the unified loop by default**. The current
`./scripts/ralph-loop.sh` interface supports runtime selection and planning
options, but it does not expose the old `--telegram-audio` or `--no-telegram`
flags directly.

### Selecting a Runtime

```bash
./scripts/ralph-loop.sh --runtime claude
./scripts/ralph-loop.sh --runtime codex
./scripts/ralph-loop.sh --runtime gemini --model gemini-2.5-pro
./scripts/ralph-loop.sh --runtime copilot --model gpt-5.2
```

---

## File Structure

```
project/
├── .specify/
│   └── memory/
│       └── constitution.md       # Single source of truth for all agent behavior
├── specs/
│   └── NNN-feature-name.md       # Feature specifications
├── scripts/
│   ├── ralph-loop.sh             # Unified loop entrypoint
│   └── lib/                      # Shared runtime, prompt, and provider helpers
├── templates/
│   ├── PROMPT_build.md
│   ├── PROMPT_plan.md
│   └── constitution-template.md
├── vendor/
│   └── speckit-agent-skills/     # Vendored planning assets for deterministic plan mode
├── AGENTS.md                     # Points to constitution
└── CLAUDE.md                     # Points to constitution
```

The **constitution** is the single source of truth. Optional features (Telegram, GitHub Issues, completion logs) are configured there — not baked into the scripts.

---

## Core Principles

### 1. Fresh Context Each Loop
Each iteration gets a clean context window. The agent reads files from disk each time.

### 2. Shared State on Disk
`IMPLEMENTATION_PLAN.md` persists between loops. Agent reads it to pick tasks, updates it with progress.

### 3. Backpressure via Tests
Tests, lints, and builds reject invalid work. Agent must fix issues before the magic phrase.

### 4. Completion Verification
Agent only outputs `<promise>DONE</promise>` when acceptance criteria are 100% verified. The bash loop enforces this.

### 5. Let Ralph Ralph
Trust the AI to self-identify, self-correct, and self-improve. Observe patterns and adjust prompts.

---

## Alternative Spec Sources

During installation, you can choose:

1. **SpecKit Specs** (default) — Markdown files in `specs/`
2. **GitHub Issues** — Fetch from a repository
3. **Custom Source** — Your own mechanism

The constitution and prompts adapt accordingly.

---

## Agent Skills Compatibility

Ralph Wiggum follows the [Agent Skills specification](https://agentskills.io) and is compatible with:

| Installer | Command |
|-----------|---------|
| [Vercel add-skill](https://github.com/vercel-labs/add-skill) | `npx add-skill tolulawson/ralph-wiggum` |
| [OpenSkills](https://github.com/numman-ali/openskills) | `openskills install tolulawson/ralph-wiggum` |
| [Skillset](https://github.com/climax-tools/skillset) | `skillset add tolulawson/ralph-wiggum` |

Works with: **Claude Code**, **Cursor**, **Codex**, **Windsurf**, **Amp**, **OpenCode**, and more.

---

## Credits

This approach builds upon:

- [Geoffrey Huntley's how-to-ralph-wiggum](https://github.com/ghuntley/how-to-ralph-wiggum) — The original methodology
- [Original Ralph Wiggum technique](https://awesomeclaude.ai/ralph-wiggum) — By the Claude community
- [Claude Code Ralph Wiggum plugin](https://github.com/anthropics/claude-code/tree/main/plugins/ralph-wiggum)
- [SpecKit](https://github.com/github/spec-kit) by GitHub — Spec-driven development

Our contribution: Combining the bash loop approach with SpecKit-style specifications and a smooth AI-driven installation process.

---

## License

MIT License — See [LICENSE](LICENSE) for details.

---

**Repository**: [github.com/tolulawson/ralph-wiggum](https://github.com/tolulawson/ralph-wiggum)
  
**Website**: [ralph-wiggum-web.onrender.com](https://ralph-wiggum-web.onrender.com)

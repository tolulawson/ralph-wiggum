---
name: speckit-specify
description: Create or update a feature specification from a natural language feature description.
source_repository: https://github.com/tolulawson/speckit-agent-skills
source_commit: c21d8d2defd2d74670fe10fb63fc73e689a0a671
vendored_note: Condensed local copy used by Ralph planning.
---

# Spec Kit Specify Skill

## Purpose

Turn a feature description into a concrete feature spec suitable for planning.

## Inputs

- A natural-language feature description
- `.specify/templates/spec-template.md`
- `.specify/scripts/bash/create-new-feature.sh` when available

## Workflow

1. Derive a short feature name (2-4 words) from the request.
2. Determine the next available numbered feature slot by checking:
   - matching branches
   - matching spec directories
3. Prefer running `.specify/scripts/bash/create-new-feature.sh --json ...` to create
   the feature directory and spec file.
4. Load the spec template and write `specs/<feature>/spec.md`.
5. Fill the spec with:
   - user scenarios
   - functional requirements
   - measurable success criteria
   - key entities when relevant
   - assumptions for unspecified but reasonable defaults
6. Avoid implementation details in the spec:
   - no framework choices
   - no API or code structure details
   - focus on what and why
7. Limit unresolved markers to genuinely critical ambiguities only.
8. Create a spec quality checklist at `specs/<feature>/checklists/requirements.md`
   and update the spec until it is ready for clarification or planning.

## Validation

- The spec is technology-agnostic
- Requirements are testable and unambiguous
- Success criteria are measurable
- Scope is bounded
- The feature is ready for `speckit-clarify` or `speckit-plan`

## Outputs

- `specs/<feature>/spec.md`
- `specs/<feature>/checklists/requirements.md`

## Next Steps

- Run `speckit-clarify` if material ambiguity remains
- Otherwise proceed to `speckit-plan`

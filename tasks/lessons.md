# Lessons

## Workflow Preferences

- Prefer configurable release automation over hard-coded human gates. If the user wants tighter control, use loop limits or explicit runtime settings instead of forcing manual merge as the default.
- Treat this repository as a reference harness unless the user says otherwise. Client-project requirements (like a required `.specify/memory/constitution.md`) should be enforced in installed projects, but not treated as a defect in the reference repo itself.
- Do not conflate build-mode fallback mechanics with the user's reported execution path. When a user describes a build-mode release failure, inspect the actual release-state transition before assuming the work-source fallback path is relevant.

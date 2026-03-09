---
name: Feature
about: Propose a new feature or enhancement
title: "[FEATURE] "
labels: enhancement
assignees: ""
---

## Summary
<!-- 1-2 sentences describing what to build. Be specific: what capability is missing, what user need does it address? -->

Example: "Add support for language X. This enables new analysis capabilities for projects using X."

## Context
<!-- Why does this matter? What depends on it? Link to parent issues, roadmap, or design docs. Help agents understand the broader system impact. -->

- What problem does this solve?
- Which users or workflows benefit?
- Links to related issues, discussions, or architecture docs
- Any blocking dependencies?

Example: "Language X is the 2nd most-requested feature (issue #1). Implementing it unblocks roadmap phase N and enables testing of the abstraction before phase N+1."

## Prerequisites
<!-- List any issues that must be completed first. Use "Depends on: #N" format. -->

- Depends on: #N (if applicable)

## Implementation Notes
<!-- The meat of the issue. Agents parse this to understand exactly what to build. Include code examples, API references, verified versions, design decisions, and integration points. -->

### Strategy
<!-- Numbered approaches or key decisions. Reference architecture docs where relevant. -->

1. **First approach or dependency**
   - Where to add: `src/module/submodule.rs`
   - Verified version: check lock file for installed version
   - API pattern: show expected usage
   - Integration: where and how to register/integrate

2. **Second approach or component**
   - Reference existing implementation: `src/module/existing.rs` (lines 50-100 for pattern)
   - Key considerations or queries needed
   - Use standard patterns and conventions

### Code Examples
<!-- Show expected patterns, API usage, and integration points. -->

```
<code example showing the expected implementation pattern>
```

Example:
```rust
let handler = SomeHandler {
    config: value,
    nested: field,
};
```

### Integration Notes
- Error handling: use thiserror for custom errors
- Logging: use tracing macros, not println
- Testing: add tests covering happy path and edge cases
- Performance: note any performance considerations

### API References
- Link to relevant docs or crates
- Architecture docs: section or file reference
- Related code: file paths and line ranges for patterns

## Acceptance Criteria
<!-- Checkbox list of verifiable outcomes. Agents use this to validate completion. -->

- [ ] Feature implemented per specification
- [ ] Code follows project conventions
- [ ] All existing tests pass
- [ ] Linting/formatting checks pass (if applicable)
- [ ] Integration tests cover happy path and edge cases
- [ ] Error handling in place with no panics in library code
- [ ] Documentation updated (if applicable)
- [ ] Commit GPG signed and DCO signed-off

## Not In Scope
<!-- Explicit boundaries to prevent scope creep. -->

- Feature or phase X (planned for later)
- Performance optimization (planned separately)
- Support for other variants or languages
- Changes to public API or interfaces beyond what's specified

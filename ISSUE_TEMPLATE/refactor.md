---
name: Refactor
about: Improve code quality, maintainability, or performance
title: "[REFACTOR] "
labels: refactor
assignees: ""
---

## Summary
<!-- 1-2 sentences: what to improve and why. Be specific about the pain point. -->

Example: "Extract duplicate logic into a shared utility. Reduces code duplication and improves maintainability."

## Motivation
<!-- Why now? What pain point triggered this? What will improve? -->

- Current pain point: describe the problem (code duplication, performance bottleneck, maintainability issue)
- Triggered by: link to related issue or observation
- Expected benefit: what improves (performance, readability, testability, etc.)

Example: "Module X duplicates logic that also appears in module Y. A shared utility would eliminate this duplication. Expected benefit: easier to maintain, fewer bugs from inconsistent implementations."

## Current State
<!-- Show the problem with code references. Include file paths, line ranges, and code snippets. -->

File: `src/module/file1.rs` (lines 10-30)
```
<code snippet showing current pattern>
```

File: `src/module/file2.rs` (lines 15-35)
```
<code snippet showing same pattern repeated>
```

Problem: <describe what makes this a problem>

Example:
File: `src/language/rust.rs` (lines 10-30)
```rust
fn analyze(&self, source: &str) -> Result<Overview> {
    let mut query = self.grammar.query(QUERY_STRING)?;  // Pattern repeated elsewhere
    // ... analysis logic
}
```

File: `src/language/python.rs` (lines 15-35)
```rust
fn analyze(&self, source: &str) -> Result<Overview> {
    let mut query = self.grammar.query(QUERY_STRING)?;  // Same pattern
    // ... analysis logic
}
```

Problem: This pattern is duplicated across all language handlers.

## Proposed Changes
<!-- What to change and how. Reference design patterns and architecture. -->

1. **Create new module or extract logic** with clear responsibility
   - File: `src/module/new_file.rs` (new file)
   - Purpose: <what this module/function does>
   - Integration: update existing code to use the new abstraction

2. **Update existing code** to use the new abstraction
   - File: `src/module/file1.rs` (lines 10-30)
   - File: `src/module/file2.rs` (lines 15-35)
   - Change: replace duplicated code with call to new utility

### Design Pattern
<!-- Reference design patterns or architecture principles. -->

Reference: <pattern name> (see docs or existing code examples)

Example: "Singleton pattern with lazy initialization (see `std::sync::OnceLock` docs)"

### Integration Notes
- No public API changes; refactoring is internal only
- Backward compatible: behavior unchanged, only structure improves
- Thread-safety: describe concurrency considerations if applicable

## Constraints
<!-- What must NOT change. Backward compatibility, public APIs, behavior. -->

- Public API must remain unchanged
- Behavior must be identical: same results, same error handling
- No breaking changes to interfaces or protocol
- Existing tests must pass without modification

## Acceptance Criteria
<!-- Checkbox list of verifiable outcomes. -->

- [ ] Refactoring implemented per specification
- [ ] All existing tests pass without modification
- [ ] Linting/formatting checks pass (if applicable)
- [ ] No behavior changes: results and error handling identical
- [ ] New/updated code follows project conventions
- [ ] Performance verified (if performance was a goal)
- [ ] Code reviewed for clarity and maintainability
- [ ] Commit GPG signed and DCO signed-off

## Not In Scope
<!-- Explicit boundaries to prevent scope creep. -->

- Feature additions beyond the refactoring
- Performance optimization (unless specified above)
- Changes to other modules or interfaces
- Bug fixes not directly related to this refactoring

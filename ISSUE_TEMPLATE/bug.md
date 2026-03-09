---
name: Bug
about: Report a defect or unexpected behavior
title: "[BUG] "
labels: bug
assignees: ""
---

## Summary
<!-- 1-2 sentences: what is broken? Be specific about the symptom, not the suspected cause. -->

Example: "Tool crashes when processing files with syntax errors. Expected graceful error handling, got panic."

## Steps to Reproduce
<!-- Numbered list of exact steps to trigger the bug. Include file paths, command-line flags, and input data. -->

1. Create a file with a syntax error
2. Run the tool with the problematic file
3. Observe the unexpected behavior

Example:
1. Create a file with malformed syntax
2. Run: `command --flag path/to/file`
3. Observe: panic or crash in stderr

## Expected Behavior
<!-- What should happen? -->

The tool should handle invalid input gracefully and return an error result with a descriptive message.

## Actual Behavior
<!-- What actually happens? Include error messages, stack traces, or unexpected output. -->

```
<paste full error output or stack trace here>
```

Example:
```
thread 'main' panicked at 'called `Result::unwrap()` on an `Err` value'
stack trace:
  at src/module.rs:42
  at src/main.rs:15
```

## Environment
<!-- Provide context for reproduction. -->

- OS: macOS / Linux / Windows (specify version)
- Runtime/Language version: `--version` output
- Relevant dependency versions: check lock file (Cargo.lock, package-lock.json, etc.)
- Command used: exact CLI invocation
- Input file: describe or attach the problematic file

Example:
- OS: macOS 14.2
- Rust version: `rustc 1.75.0`
- Crate versions: check `Cargo.lock`
- Command: `cargo run -- --mode analyze path/to/broken.rs`

## Logs / Error Output
<!-- Full error message, panic backtrace, or relevant log output. Use code block. -->

```
<paste full error output here>
```

## Root Cause Analysis
<!-- Optional: if you have a hypothesis about what's wrong, include it here. Reference file paths and line ranges. -->

Example: "Suspected cause: `src/module.rs` line 42 calls `.unwrap()` on a `Result` that can fail with invalid input. Should use `?` operator or explicit error handling instead."

## Fix Direction
<!-- Optional: suggested approach or pattern to follow. -->

Example: "Replace `.unwrap()` with `?` operator. Use thiserror to define a custom error type. Ensure all error paths return Err instead of panicking."

## Acceptance Criteria
<!-- Checkbox list of verifiable outcomes. -->

- [ ] Bug is reproducible with provided steps
- [ ] Root cause identified and documented
- [ ] Fix implemented and verified
- [ ] All existing tests pass
- [ ] Linting checks pass (if applicable)
- [ ] Code formatted correctly (if applicable)
- [ ] Regression test added covering the bug scenario
- [ ] Commit GPG signed and DCO signed-off

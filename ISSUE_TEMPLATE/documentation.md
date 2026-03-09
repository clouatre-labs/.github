---
name: Documentation
about: Improve documentation or add new docs
title: "[DOCS] "
labels: documentation
assignees: ""
---

## Summary
<!-- 1-2 sentences: what documentation to create or improve and why. Be specific about the gap. -->

Example: "Add API reference documentation for the analyzer module. Current README lacks detail about function signatures and error types."

## Location
<!-- Where does this documentation go? File path, section in existing doc, or new file? -->

Example:
- New file: `docs/API.md`
- Or: Update section "Configuration" in `README.md`
- Or: Add to existing `docs/architecture.md` (line 50)

## Current State
<!-- What exists today? What is missing or incomplete? -->

Example: "README.md mentions the analyzer tool but doesn't explain how to use different modes. Users often ask how to choose between Overview and FileDetails modes."

Current documentation (if any):
```
<quote from existing docs>
```

Gap: <specific missing information>

Example:
Current: "Run the tool with `command <file>`"
Gap: No explanation of analysis modes, configuration options, or output formats

## Proposed Changes
<!-- What to add or update? Include the new content structure and key topics to cover. -->

### Content to Add/Update
- Section/heading: <what should be documented>
- Key topics: list of important points to cover
- Target audience: developers, users, operators, maintainers
- Format: narrative prose, API reference, tutorial, FAQ, etc.

Example:

### Content to Add
- New section: "Analysis Modes"
- Key topics:
  - Overview mode: directory-level analysis, when to use
  - FileDetails mode: semantic extraction, when to use
  - Mode selection: how to choose which mode for your use case
- Format: tutorial with examples for each mode

### Structure
```
## Analysis Modes

### Overview Mode
<explanation and example>

### FileDetails Mode
<explanation and example>

### Choosing a Mode
<guidance table or flowchart>
```

## Acceptance Criteria
<!-- Checkbox list of verifiable outcomes. -->

- [ ] Documentation is clear and complete
- [ ] Examples are accurate and tested (if applicable)
- [ ] Target audience can follow instructions without external reference
- [ ] Formatting is consistent with existing docs (styling, headings, code blocks)
- [ ] Links and references are correct
- [ ] Spell-checked and grammar-checked
- [ ] No outdated or broken references
- [ ] Commit GPG signed and DCO signed-off

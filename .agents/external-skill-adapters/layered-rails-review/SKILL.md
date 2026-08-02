---
name: layered-rails-review
description: Use when reviewing Rails code changes for layered architecture violations, callback health, concern health, service boundaries, or anemic domain models.
---

# Layered Rails Review

1. Read `references/upstream-review.md` completely before reviewing code.
2. Determine the requested diff or file scope. If none is specified, review uncommitted changes.
3. Apply the upstream process, checklist, severity levels, and output format.
4. Report only findings supported by the reviewed code. Include the file path and tight line range for every finding.
5. If no violations are found, state that explicitly and identify any testing or inspection gaps.

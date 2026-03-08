# Development Philosophy: Spec-Driven Development

## Overview

This project follows **Spec-Driven Development (SDD)** — a methodology where formal specifications serve as the authoritative source of truth and the primary artifact from which implementation, testing, and documentation are derived. Code is a derived artifact; specs are what we maintain.

> "With AI-generated code, a code issue is an outcome of a gap in the specification."

## Core Principles

### 1. Specifications Are the Source of Truth

Specifications are not documentation — they are the system's authoritative definition. When specs and code disagree, the spec wins. We fix specs, not symptoms.

- Specs define **what** the system does (behavior, contracts, constraints)
- Code expresses **how** it does it in a particular language/framework
- Maintaining software means evolving specifications

### 2. Human Governance, Machine Enforcement

Humans own domain semantics, risk tolerance, safety boundaries, and evolutionary direction. Machines handle enforcement and generation. This is bounded autonomy, not full automation.

- Every spec requires human review before implementation begins
- AI agents generate code within spec-defined constraints
- CI/CD validates that implementation conforms to specs

### 3. Architectural Determinism Over Emergent Behavior

System behavior should be mechanically enforced by specifications, not emergent from accumulated code. Drift detection corrects specification authority and triggers controlled regeneration.

### 4. Test-Driven Implementation

All implementation follows strict test-driven development:

1. Define behavior in the spec
2. Generate tests that encode that behavior
3. Review and approve tests
4. Generate implementation that passes those tests

Tests are derived from specs. If a test can't be traced to a spec, it shouldn't exist. If a spec isn't covered by tests, the spec is incomplete.

### 5. Debug Specs, Not Code

When issues arise, the first question is: "Is the spec wrong or incomplete?" Fixing the spec propagates the fix to all future generated output. Patching code without updating the spec creates drift.

## Workflow

### Phase 1: Specify

Write formal, structured specifications that define:

- **Acceptance criteria** — machine-readable validation rules
- **API contracts** — endpoint definitions, data schemas, constraints
- **Architectural constraints** — cross-component patterns, security requirements
- **Edge cases and invariants** — preconditions, postconditions, error handling

Use domain-oriented language describing business intent. Employ Given/When/Then structure for behavioral scenarios. Balance completeness with conciseness — cover critical paths without enumerating every case.

### Phase 2: Plan

Translate specs into an implementation plan:

- Map requirements to technology choices (frameworks, libraries, patterns)
- Define service boundaries and component contracts
- Identify dependencies and ordering constraints
- Create an audit trail linking every decision back to a spec

### Phase 3: Decompose

Break the plan into independently testable tasks:

- Each task is implementable and verifiable in isolation
- Tasks have clear inputs, outputs, and acceptance criteria
- Dependencies between tasks are explicit

### Phase 4: Implement

Generate or write code within specification constraints:

- Write tests first, derived from the spec
- Implement to pass those tests
- Build fails automatically if implementation violates specs

### Phase 5: Validate and Iterate

- Run continuous conformance checks against specs
- When bugs are found, determine if it's a spec gap or implementation defect
- Update specs first, then regenerate/fix implementation

## Spec Structure

Specs live in `docs/specs/` and follow this hierarchy:

```
docs/
  specs/
    overview.md              # System-level spec (architecture, boundaries)
    <feature>/
      spec.md                # Feature specification
      api.md                 # API contract (if applicable)
      test-scenarios.md      # Given/When/Then scenarios
```

Each spec file should include:

- **Context** — why this feature exists, what problem it solves
- **Requirements** — numbered, testable requirements (MUST/SHOULD/MAY per RFC 2119)
- **Constraints** — architectural, security, performance boundaries
- **Acceptance criteria** — concrete, verifiable conditions for done
- **Open questions** — unresolved decisions (tracked, not ignored)

## Anti-Patterns to Avoid

| Anti-Pattern | Why It's Harmful | What to Do Instead |
|---|---|---|
| Vibe coding | Ad-hoc prompting produces unmaintainable code | Write a spec first, then implement |
| Spec drift | Specs diverge from reality, losing authority | Enforce specs in CI; update specs before code |
| Over-specification | Specs become so detailed they're slower than writing code | Spec behavior and contracts, not implementation details |
| Waterfall specs | Giant upfront specs with no iteration | Iterate in short cycles: spec → implement → validate → refine |
| Untraceable tests | Tests exist without connection to requirements | Every test traces to a numbered spec requirement |
| Patching without spec updates | Quick code fixes that bypass the spec | Always update the spec first |

## Guiding Heuristics

1. **If you can't spec it, you don't understand it yet.** Writing the spec is the thinking work.
2. **Specs should be boring.** If a spec is surprising, it needs discussion.
3. **Prefer small, focused specs** over monolithic documents. One feature per spec.
4. **Version control your specs** with the same rigor as code. They are reviewed in PRs.
5. **When in doubt, make constraints explicit.** Implicit assumptions are where bugs hide.
6. **Iterate quickly.** A spec doesn't need to be perfect to be useful — it needs to be better than no spec.

## References

- [Thoughtworks: Spec-Driven Development (2025)](https://www.thoughtworks.com/en-us/insights/blog/agile-engineering-practices/spec-driven-development-unpacking-2025-new-engineering-practices)
- [InfoQ: When Architecture Becomes Executable](https://www.infoq.com/articles/spec-driven-development/)
- [GitHub Spec Kit](https://github.com/github/spec-kit/blob/main/spec-driven.md)
- [Augment Code: Complete Guide to SDD](https://www.augmentcode.com/guides/what-is-spec-driven-development)
- [arXiv: From Code to Contract in the Age of AI Coding Assistants](https://arxiv.org/abs/2602.00180)
- [Red Hat: How SDD Improves AI Coding Quality](https://developers.redhat.com/articles/2025/10/22/how-spec-driven-development-improves-ai-coding-quality)

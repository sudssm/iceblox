You are reviewing code changes on the current branch to ensure they conform to the project's specifications. This project follows Spec-Driven Development — specs are the source of truth.

## Review process

### Step 1: Understand the changes

Run `git diff main...HEAD` and `git log main..HEAD --oneline` to see all changes on this branch.

### Step 2: Identify relevant specs

For each changed file, determine which spec governs it:

| Path pattern | Spec file |
|---|---|
| `server/**` | `docs/specs/server/spec.md` |
| `ios/**` | `docs/specs/mobile-app/spec.md` + `docs/specs/ios/structure.md` |
| `android/**` | `docs/specs/mobile-app/spec.md` + `docs/specs/android/structure.md` |
| `models/**` | `docs/specs/mobile-app/license_plate_detection.md` |
| `scripts/**` | `docs/specs/testing.md` |

Read each relevant spec file in full.

### Step 3: Check each change against its spec

For every behavioral change in the diff, determine:

1. **Does this change align with the spec?** If yes, no action needed.
2. **Does this change diverge from the spec?** If yes, determine the intent:

#### Intentional divergence (the change is correct, the spec is outdated)

This applies when:
- The code implements a better approach than what the spec describes
- The spec was written before a constraint was discovered
- The commit message or context makes clear this was a deliberate design decision

**Action**: Update the spec to match the code. Preserve the requirement number (REQ-S-*, REQ-M-*) but revise the description. Add a brief note about what changed and why if the reason isn't obvious.

#### Inadvertent divergence (the spec is correct, the code drifted)

This applies when:
- The code accidentally omits a required behavior
- A refactor broke a spec-mandated invariant
- The change contradicts an explicit constraint without explanation

**Action**: Fix the code to match the spec. Stage and commit the fix.

### Step 4: Update todo.md

Read `docs/todo.md` and ensure it reflects reality:
- If code on this branch completes a todo item, check it off (`[x]`).
- If code on this branch reverts or breaks a previously completed item, uncheck it (`[ ]`).
- If a spec was updated in step 3, and that affects todo items, update them accordingly.
- Do not check off items that aren't fully implemented.

### Step 5: Commit any changes

If you updated specs or todo.md:
- Commit spec changes with a message like "Update <spec> to reflect <change>"
- Commit todo.md changes with a message like "Update todo.md to reflect <change>"
- These can be combined into one commit if they're related.

If you fixed code to match a spec:
- Commit the code fix with a message like "Fix <issue> to match spec REQ-X-N"

### Step 6: Report

Summarize what you reviewed:
- Which specs were checked
- Any divergences found (intentional or inadvertent)
- What was updated or fixed
- If everything was clean, say so

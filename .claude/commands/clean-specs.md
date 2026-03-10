You are auditing and cleaning up the project's specification files in `docs/`. The goals are: reduce sprawl, eliminate duplication, ensure internal consistency, and verify specs match the actual codebase. Prefer minimal changes — do not rewrite specs or reorganize the directory structure without explicit user approval.

## Spec inventory

These are the known spec files. Read ALL of them before proceeding:

| File | Governs |
|---|---|
| `docs/specs/overview.md` | System architecture, privacy model, data flow |
| `docs/specs/server/spec.md` | Server API, database, push notifications |
| `docs/specs/mobile-app/spec.md` | Mobile app behavior (both platforms) |
| `docs/specs/mobile-app/license_plate_detection.md` | ML detection pipeline |
| `docs/specs/mobile-app/license_plate_ocr.md` | OCR pipeline |
| `docs/specs/mobile-app/test-scenarios.md` | Mobile test cases |
| `docs/specs/android/structure.md` | Android code structure |
| `docs/specs/android/debug.md` | Android debug features |
| `docs/specs/ios/structure.md` | iOS code structure |
| `docs/specs/ios/debug.md` | iOS debug features |
| `docs/specs/testing.md` | Testing strategy and E2E framework |
| `docs/development-philosophy.md` | Development methodology |
| `docs/future/yolo_model_improvements.md` | Future model improvements |
| `docs/todo.md` | Spec-vs-code gap tracker |

## Step 1: Read all specs

Read every file listed above in full. Take careful note of:
- Requirement IDs (REQ-S-*, REQ-M-*, etc.) and their definitions
- Cross-references between specs
- Terminology and naming conventions
- Overlapping content between files

## Step 2: Check internal consistency

Analyze the specs for these issues:

**Requirement ID conflicts**: Are any REQ IDs defined in more than one file? Are there gaps in numbering that suggest deleted requirements? Are all REQ IDs referenced elsewhere actually defined?

**Cross-reference integrity**: When one spec references another (e.g., "see REQ-S-5" or "see server/spec.md"), does the target exist and say what the reference implies?

**Terminology consistency**: Are the same concepts called the same thing across specs? (e.g., "pepper" vs "HMAC key", "target plate" vs "watchlist plate", "offline queue" vs "upload queue")

**Contradictions**: Do any two specs make conflicting claims about the same behavior? (e.g., different batch sizes, different API endpoints, different error handling behavior)

Collect all issues found. Do not fix anything yet.

## Step 3: Check for duplication

Identify places where two or more specs describe the same behavior in detail instead of one spec owning the definition and others cross-referencing it. Common duplication areas:
- Hashing scheme described in overview.md AND mobile-app/spec.md AND server/spec.md
- API endpoints described in server/spec.md AND mobile-app/spec.md
- Detection/OCR pipeline described in mobile-app/spec.md AND the dedicated detection/OCR specs
- Debug features described in platform structure files AND debug files

For each case, determine which file should be the canonical owner and which should cross-reference.

## Step 4: Verify specs against code

Launch parallel subagents (one per area) to check whether the code matches the specs. Use `general-purpose` subagent type for each. The agents should search the codebase — NOT make changes.

1. **Server agent** — prompt:
   ```
   Read docs/specs/server/spec.md and docs/specs/overview.md in the repo at <cwd>. Then search the server/ directory to verify the spec matches the code. Check: API endpoints and their request/response shapes, database schema and migrations, push notification implementation, hashing/pepper logic, SIGHUP reload behavior, environment variables. For each requirement (REQ-S-*), report whether the code matches, diverges, or the requirement is unimplemented. Do NOT make any changes. Report your findings.
   ```

2. **iOS agent** — prompt:
   ```
   Read docs/specs/mobile-app/spec.md, docs/specs/ios/structure.md, docs/specs/ios/debug.md, docs/specs/mobile-app/license_plate_detection.md, and docs/specs/mobile-app/license_plate_ocr.md in the repo at <cwd>. Then search the ios/ directory to verify the specs match the code. Check: camera pipeline, detection model loading, OCR pipeline, hashing logic, API client, offline queue, batch upload, debug overlay, push notifications. For each requirement (REQ-M-*), report whether the code matches, diverges, or is unimplemented. Do NOT make any changes. Report your findings.
   ```

3. **Android agent** — prompt:
   ```
   Read docs/specs/mobile-app/spec.md, docs/specs/android/structure.md, docs/specs/android/debug.md, docs/specs/mobile-app/license_plate_detection.md, and docs/specs/mobile-app/license_plate_ocr.md in the repo at <cwd>. Then search the android/ directory to verify the specs match the code. Check: camera pipeline, detection model loading, OCR pipeline, hashing logic, API client, offline queue, batch upload, debug overlay, push notifications. For each requirement (REQ-M-*), report whether the code matches, diverges, or is unimplemented. Do NOT make any changes. Report your findings.
   ```

4. **Testing agent** — prompt:
   ```
   Read docs/specs/testing.md and docs/specs/mobile-app/test-scenarios.md in the repo at <cwd>. Then search the e2e/, server/ (for test files), ios/ (for test files), and android/ (for test files) directories to verify the testing specs match actual test coverage. Check: which test scenarios from the spec are implemented, which are missing, whether the E2E framework described matches reality. Do NOT make any changes. Report your findings.
   ```

Wait for all agents to finish.

## Step 5: Compile findings and triage

Organize all issues into three categories:

### A. Safe fixes (make these directly)
- Broken cross-references (fix the link)
- Typos in requirement IDs
- Minor terminology inconsistencies (align to the dominant usage)
- Adding missing cross-references where content is duplicated (add "See <file> for details" and remove the duplicated paragraph)

### B. Spec-code divergences (surface to user)
For each case where code has diverged from spec but the code seems correct (e.g., an improved API shape, a renamed field, an added feature not in the spec), present to the user:
- The spec requirement (ID and text)
- What the code actually does
- Your recommendation (update spec to match code, or flag for further investigation)

Ask the user to validate before making changes.

### C. Structural suggestions (surface to user)
If any spec file is excessively large (>1000 lines) or covers too many concerns, or if the directory structure could be improved, describe the proposed change and ask for approval. Do NOT reorganize without permission.

## Step 6: Apply approved changes

After the user responds to categories B and C:
- Apply all safe fixes from category A
- Apply user-approved spec updates from category B
- Apply user-approved structural changes from category C

For duplication removal: keep the full definition in the canonical owner file and replace the duplicate with a brief summary and cross-reference (e.g., "The hashing scheme uses HMAC-SHA256 with a shared pepper. See [System Overview](../overview.md#hashing-scheme) for details.").

## Step 7: Update todo.md

If any spec changes affect items in `docs/todo.md`, update them accordingly. If new gaps were discovered (unimplemented requirements), add them as unchecked items in the appropriate section.

## Step 8: Commit

Stage and commit changes in logical groups:
- Cross-reference fixes and deduplication: "Clean up spec cross-references and remove duplication"
- Spec updates to match code: "Update specs to reflect current implementation"
- Structural changes (if any): "Reorganize <spec> per user approval"
- todo.md updates: "Update todo.md with spec audit findings"

## Step 9: Report

Summarize:
- Total issues found (by category)
- Safe fixes applied
- Spec-code divergences found and how they were resolved
- Duplication removed
- Structural changes made (if any)
- New todo items added (if any)
- Any unresolved issues that need further attention

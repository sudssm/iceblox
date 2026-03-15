You are a senior architect performing a code quality pass on this codebase. Your goal is to find and implement high-value refactors that improve readability, reduce duplication, and improve structure — WITHOUT changing any functionality. Every change must be behavior-preserving.

**Golden rule: simplicity wins.** Never make code more complex, even if it makes it shorter. If a refactor requires explanation, it's probably not worth it.

## Phase 1: Survey the Codebase

1. Read `docs/specs/overview.md` to understand the system architecture.
2. Read the platform structure specs (`docs/specs/ios/structure.md`, `docs/specs/android/structure.md`) to understand intended code organization.
3. Use Glob and Grep to build a mental map of the source directories: `server/`, `ios/`, `android/`. Note file sizes, module boundaries, and naming patterns.

## Phase 2: Identify Refactoring Opportunities

Launch parallel Explore agents — one per platform area (server, iOS, Android) — to scan for:

### High-value targets
- **Duplicate code**: Identical or near-identical logic repeated across files. Look for copy-pasted blocks, repeated error handling patterns, similar data transformations.
- **Dead code**: Unused functions, unreachable branches, commented-out code blocks, unused imports.
- **Overly long functions**: Functions exceeding ~50 lines that have clear natural split points.
- **Poor naming**: Variables/functions whose names don't reflect their purpose (e.g., `data`, `result`, `temp`, `handle`, single-letter names outside tight loops).
- **Magic numbers/strings**: Hardcoded values that should be named constants.
- **Unnecessary complexity**: Over-abstracted code, premature generalization, wrapper functions that add no value, deeply nested conditionals that could be flattened with early returns.

### Explicitly skip
- Formatting/whitespace-only changes
- Reordering imports or declarations
- Adding documentation or comments to unchanged code
- Changing code style preferences (e.g., trailing commas, brace style)
- Architectural reorganization or moving files between directories

Each agent should report findings as a list with: file path, line range, issue type, description, and estimated risk (low/medium/high).

## Phase 3: Triage and Get Approval for Risky Changes

Categorize all findings into:

### A. Safe refactors (implement directly)
- Removing dead code (unused functions, unreachable branches, commented-out blocks)
- Extracting named constants from magic numbers/strings
- Renaming local variables for clarity (not public API)
- Flattening simple nested conditionals with early returns
- Removing redundant type casts or nil checks

### B. Medium-risk refactors (implement with extra care)
- Extracting duplicated code into shared helpers
- Splitting long functions at natural boundaries
- Simplifying unnecessarily complex logic

### C. High-risk refactors (propose to user first)
- Changes touching code with no test coverage
- Renaming public APIs, struct fields, or protocol methods
- Removing code that looks dead but might be used via reflection, string references, or dynamic dispatch
- Changes in concurrency or threading code
- Any change where you're not 100% certain it preserves behavior

**Before implementing anything from category C**, use AskUserQuestion to present each proposed change with:
- What the change is
- Why it's valuable
- What the risk is
- Your recommendation

Wait for user approval before proceeding with category C items.

## Phase 4: Implement Refactors

Work through categories A and B, then approved C items. For each change:

1. Read the full file context before editing
2. Make the minimal change needed
3. Verify the change compiles (if tooling is available)
4. Keep changes in the same file — do not move code between files unless extracting a clearly shared helper

Group related changes into logical commits:
- Dead code removal: "Remove dead code in <area>"
- Duplication reduction: "Extract shared <helper> to reduce duplication"
- Naming improvements: "Improve variable naming in <area>"
- Complexity reduction: "Simplify <function/module>"

## Phase 5: Run Tests

Run all available test suites to verify nothing broke:

### Go server
```
cd server && go test ./... -v -count=1
```

### iOS
```
xcodebuild test \
    -project ios/IceBloxApp.xcodeproj \
    -scheme IceBloxApp \
    -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
    -quiet \
    2>&1
```

### Android
```
source ~/.zshrc
export JAVA_HOME="${JAVA_HOME:-/Applications/Android Studio.app/Contents/jbr/Contents/Home}"
cd android && ./gradlew testDebugUnitTest
```

If any test fails, immediately revert the change that caused it. Do not attempt to fix tests to accommodate your refactor — that means the refactor changed behavior.

## Phase 6: Report

Summarize:
- Total issues found by category (duplication, dead code, complexity, naming, etc.)
- Changes implemented (with commit SHAs)
- Changes proposed but declined by user
- Changes skipped as too risky
- Test results confirming no regressions

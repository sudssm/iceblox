IMPORTANT: This skill must ONLY be invoked when the user has EXPLICITLY asked to ship, merge, or create a PR using clear language like "/ship", "ship it", "create a PR", "merge it", etc. Do NOT invoke this skill based on inferred intent — e.g., the user saying "looks good" or asking about a merged PR does NOT mean "ship my branch". If you are unsure whether the user wants to ship, ASK first. Never auto-ship.

You are finishing a feature branch and shipping it to main. Follow these steps exactly:

## Step 0: Commit uncommitted changes

Run `git status` to check for uncommitted changes. If there are staged or unstaged changes to tracked files, or untracked files that belong in the repo (source code, configs, docs, tests, etc.), stage and commit them with a descriptive message. Use your judgment to exclude files that should NOT be committed: secrets (.env, credentials, API keys), .code-workspace files, build artifacts, or anything in .gitignore. If unsure whether a file should be committed, ask the user.

If the working tree is already clean, skip this step.

## Step 1: Update local main and merge into branch

Run `git fetch origin main` to get the latest remote main. Then update the local main branch: if main is checked out elsewhere (worktree), run `cd <main-worktree-path> && git pull origin main`; otherwise run `git branch -f main origin/main`. Then merge main into the current branch with `git merge main`. If there are merge conflicts, resolve them and commit the merge. This ensures the branch is up to date with main and that `git diff main HEAD` only shows changes from this branch.

## Step 2: Understand the changes

Run `git diff main HEAD` and `git log main..HEAD --oneline` to understand all changes on this branch compared to main. Use `main HEAD` (two-dot) for diffs — NOT `main...HEAD` (three-dot). The three-dot form diffs from the merge base, which inflates results after squash merges.

## Step 3: Run review skills

First, count the number of changed lines: `git diff main HEAD --numstat | awk '{s+=$1+$2} END {print s+0}'`. This sums added and deleted lines (excluding context/headers). If the result is **50 lines or fewer**, skip the review agents entirely — the change is small enough to review by eye. Proceed directly to Step 4.

Otherwise, launch TWO subagents in parallel using the Agent tool:

1. **PR Review agent** — use subagent_type `general-purpose` with this prompt:
   ```
   Run the /review-pr skill on this repository. The working directory is <cwd>. Review all changes on the current branch vs main, fix any issues you find, and report what you reviewed and fixed.
   ```

2. **Spec Review agent** — use subagent_type `general-purpose` with this prompt:
   ```
   Run the /review-spec skill on this repository. The working directory is <cwd>. Check all changes on the current branch vs main against the specs in docs/specs/, fix any divergences, update docs/todo.md, and report what you reviewed and fixed.
   ```

Wait for both agents to complete. Review their reports. If either agent made commits, incorporate them — do NOT undo their work.

If either agent reports unfixable issues (e.g., a spec ambiguity that needs human input), STOP and report the issue to the user. Do not proceed until resolved.

## Step 4: Lint changed code

Look at the files changed in the diff from step 2 and run ONLY the linters for areas that were modified. Run whichever apply in parallel:

- If any `server/**` files changed: `cd server && golangci-lint run ./...`
- If any `ios/**` files changed: `cd ios && swiftlint --strict`
- If any `android/**` files changed: `cd android && ktlint`

Skip linters for areas with no code changes. If a linter fails, fix the issues and re-run. If you cannot fix a lint failure, STOP and report it to the user.

## Step 5: Run relevant tests

Look at the files changed in the diff from step 2 and run ONLY the test suites for areas that were modified. Run whichever apply in parallel:

- If any `server/**` files changed: `cd server && go test ./...`
- If any `ios/**` files changed: `cd ios && xcodebuild test -project IceBloxApp.xcodeproj -scheme IceBloxApp -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -quiet 2>&1 | tail -20`
- If any `android/**` files changed: `cd android && ./gradlew test --quiet 2>&1 | tail -20`

Skip test suites for areas with no code changes. If a test suite fails, fix the issue and re-run. If you cannot fix a test failure, STOP and report it to the user.

## Step 5b: Run CI checks locally

Run the full CI test suite locally to catch failures before pushing. Run all of the following that apply based on the changed files (in parallel where possible):

- If any `server/**` files changed: `make server-lint` and `make server-test-db` (integration tests with a real database — requires local PostgreSQL)
- If any `ios/**` files changed: `cd ios && swiftlint --strict`
- If any `android/**` files changed: `cd android && ktlint` and `make android-unit-test`

This mirrors what GitHub Actions runs. If any check fails, fix the issue and re-run. If you cannot fix a failure, STOP and report it to the user.

## Step 6: Commit remaining code changes

Stage and commit any remaining code changes (non-docs) with a descriptive commit message summarizing the feature. Do NOT commit .code-workspace files.

If the review agents already committed everything, skip this step.

## Step 7: Commit doc changes

If there are any remaining doc updates not already committed by the spec review agent, stage and commit them separately with a message like "Update docs to reflect <feature> implementation".

If docs are already up to date, skip this step.

## Step 8: Push and create PR

Push the branch to origin and create a pull request targeting `main` using `gh pr create`. The PR title should be concise. The body should summarize what was implemented and what spec requirements were addressed.

## Step 9: Merge the PR

After the PR is created, merge it using `gh pr merge --squash`. Do NOT use `--delete-branch` — it fails when `main` is checked out in another worktree. If merge fails (e.g., due to checks), report the error and stop.

## Step 10: Fast-forward local main after merge

Run `git fetch origin main` and fast-forward local `main` to the merge commit (same approach as Step 1). This keeps future branches and diffs based on the latest `main`, and ensures the local repo state matches the merged PR. If this workspace cannot check out `main` because it is checked out in another worktree, update `main` in that worktree and then fast-forward the current branch to `origin/main` so this workspace also reflects the merged repo state.

Report the merged PR URL when done.

IMPORTANT: This skill must ONLY be invoked when the user has EXPLICITLY asked to ship, merge, or create a PR using clear language like "/ship", "ship it", "create a PR", "merge it", etc. Do NOT invoke this skill based on inferred intent — e.g., the user saying "looks good" or asking about a merged PR does NOT mean "ship my branch". If you are unsure whether the user wants to ship, ASK first. Never auto-ship.

You are finishing a feature branch and shipping it to main. Follow these steps exactly:

## Step 1: Understand the changes

Run `git diff main...HEAD` and `git log main..HEAD --oneline` to understand all changes on this branch compared to main.

## Step 2: Run review skills

Launch TWO subagents in parallel using the Agent tool:

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

## Step 3: Run relevant tests

Look at the files changed in the diff from step 1 and run ONLY the test suites for areas that were modified. Run whichever apply in parallel:

- If any `server/**` files changed: `cd server && go test ./...`
- If any `ios/**` files changed: `cd ios && xcodebuild test -project CamerasApp.xcodeproj -scheme CamerasApp -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -quiet 2>&1 | tail -20`
- If any `android/**` files changed: `cd android && ./gradlew test --quiet 2>&1 | tail -20`

Skip test suites for areas with no code changes. If a test suite fails, fix the issue and re-run. If you cannot fix a test failure, STOP and report it to the user.

## Step 4: Commit remaining code changes

Stage and commit any remaining code changes (non-docs) with a descriptive commit message summarizing the feature. Do NOT commit .code-workspace files.

If the review agents already committed everything, skip this step.

## Step 5: Commit doc changes

If there are any remaining doc updates not already committed by the spec review agent, stage and commit them separately with a message like "Update docs to reflect <feature> implementation".

If docs are already up to date, skip this step.

## Step 6: Push and create PR

Push the branch to origin and create a pull request targeting `main` using `gh pr create`. The PR title should be concise. The body should summarize what was implemented and what spec requirements were addressed.

## Step 7: Merge the PR

After the PR is created, merge it using `gh pr merge --squash --delete-branch`. If merge fails (e.g., due to checks), report the error and stop.

Report the merged PR URL when done.

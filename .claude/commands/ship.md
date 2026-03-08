IMPORTANT: This skill must ONLY be invoked when the user has EXPLICITLY asked to ship, merge, or create a PR using clear language like "/ship", "ship it", "create a PR", "merge it", etc. Do NOT invoke this skill based on inferred intent — e.g., the user saying "looks good" or asking about a merged PR does NOT mean "ship my branch". If you are unsure whether the user wants to ship, ASK first. Never auto-ship.

You are finishing a feature branch and shipping it to main. Follow these steps exactly:

## Step 1: Understand the changes

Run `git diff main...HEAD` and `git log main..HEAD --oneline` to understand all changes on this branch compared to main.

## Step 2: Verify docs are up to date

Read `docs/todo.md` and compare it against the actual code changes from step 1. Ensure:
- Every completed item in todo.md that corresponds to code on this branch is checked off (`[x]`).
- No items are checked off that don't have corresponding code.
- If any updates are needed, edit `docs/todo.md` to reflect reality.

Also check if any spec files in `docs/specs/` need updates based on the code changes (e.g., if the implementation deviated from the spec in a meaningful way). Only update specs if there's a real deviation — don't make cosmetic changes.

## Step 3: Commit code changes

Stage and commit all code changes (non-docs) with a descriptive commit message summarizing the feature. Do NOT commit .code-workspace files.

## Step 4: Commit doc changes

If there were any doc updates in step 2, stage and commit them separately with a message like "Update docs to reflect <feature> implementation".

If docs were already up to date, skip this step.

## Step 5: Push and create PR

Push the branch to origin and create a pull request targeting `main` using `gh pr create`. The PR title should be concise. The body should summarize what was implemented and what spec requirements were addressed.

## Step 6: Merge the PR

After the PR is created, merge it using `gh pr merge --squash --delete-branch`. If merge fails (e.g., due to checks), report the error and stop.

Report the merged PR URL when done.

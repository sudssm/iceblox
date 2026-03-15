You are performing periodic maintenance on the project. This runs four passes sequentially, then produces a combined summary.

Steps 1–3 have data dependencies (each may modify `docs/todo.md` or source files the next step reads), so they run **sequentially**. Step 4 tests the final state and must run last.

For each step, launch a `general-purpose` Agent with the prompt provided. Wait for it to complete before starting the next step.

---

## Step 1: Clean todo.md

Launch an Agent (subagent_type: `general-purpose`, name: `clean-todo`) with this prompt:

```
Run the /clean-todo skill.
```

---

## Step 2: Clean specs

Launch an Agent (subagent_type: `general-purpose`, name: `clean-specs`) with this prompt:

```
Run the /clean-specs skill.
```

---

## Step 3: Clean code

Launch an Agent (subagent_type: `general-purpose`, name: `clean-code`) with this prompt:

```
Run the /clean-code skill.
```

---

## Step 4: QA report

Launch an Agent (subagent_type: `general-purpose`, name: `qa-report`) with this prompt:

```
Run the /qa-report skill.
```

---

## Step 5: Summary

After all four agents complete, provide a combined summary covering:
- **Todo**: items removed, items remaining
- **Specs**: issues found, fixed, and flagged; new todo items added
- **Code**: refactors implemented, proposals declined, test results
- **QA**: test coverage gaps, test results, bugs found/fixed, open issues, manual E2E findings

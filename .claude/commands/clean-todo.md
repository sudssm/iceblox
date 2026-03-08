You are cleaning up `docs/todo.md` by removing completed items that have been verified against the actual codebase and specs.

## Process

### Step 1: Read the todo and specs

Read `docs/todo.md` in full. Identify all checked (`[x]`) items grouped by section.

Each section should reference its governing spec (e.g., via a `Spec:` link). Read the relevant spec files for sections that have checked items. If a section doesn't link to a spec, look in `docs/specs/` for the most relevant file based on the section name.

### Step 2: Verify completed items against code

For each checked item, verify it is actually implemented by checking the codebase. Launch parallel Explore agents — one per major section — to verify all checked items in that section against the actual source files. Each agent should use Glob and Grep to confirm the key files, classes, functions, and behaviors described in the todo item exist.

If a checked item is NOT actually implemented, uncheck it and add a note like "Not yet implemented — unchecked".

### Step 3: Verify remaining items against specs

For each unchecked (`[ ]`) item, cross-reference the spec to confirm:
- The description accurately reflects what the spec requires
- The REQ reference is correct
- No important details are missing

Fix any inaccurate descriptions.

### Step 4: Remove verified completed items

Rewrite `docs/todo.md` keeping:
- The header and intro text
- Section headers (but only for sections that still have unchecked items)
- All unchecked items with their descriptions
- Sub-section headers only if they contain unchecked items

Remove:
- All verified checked items
- Sub-section headers that contained only checked items
- Section dividers for empty sections

### Step 5: Commit

Stage and commit `docs/todo.md` with a message like:
```
Clean up todo.md by removing verified completed items
```

### Step 6: Report

Summarize:
- How many completed items were verified and removed
- How many items remain
- Any items that were unchecked because they weren't actually done
- Any description corrections made to remaining items

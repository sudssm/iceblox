You are reviewing code changes on the current branch before shipping. Run `git diff main...HEAD` to see all changes, then review them against the language-specific best practices below.

## Review process

1. Run `git diff main...HEAD` to get the full diff.
2. Review ONLY the code that appears in the diff hunks. Do not read or review unchanged parts of touched files. Pre-existing issues outside the diff are out of scope.
3. For each diff hunk, apply the relevant language checklist below.
4. If you find issues in the changed code, fix them directly — do not just report them. Stage and commit fixes with a message like "Fix <issue> found in PR review".
5. After fixing, re-run `git diff main...HEAD` to confirm the fixes are clean.
6. When done, report a summary of what you reviewed and what you fixed (if anything).

## Swift (iOS) — `ios/**/*.swift`

- **Optionals**: No force-unwraps (`!`) outside of `IBOutlet`. Use `guard let`, `if let`, or nil-coalescing.
- **Memory management**: Capture lists in closures (`[weak self]`). No retain cycles in delegates or callbacks.
- **Concurrency**: Use `@MainActor` or `DispatchQueue.main` for UI updates from background threads. No data races on shared state.
- **AVFoundation**: `AVCaptureSession` configuration wrapped in `beginConfiguration()`/`commitConfiguration()`. Outputs removed before dealloc.
- **CryptoKit/Security**: No hardcoded secrets. Pepper must be obfuscated, never plaintext in source.
- **SwiftUI**: Views should be lightweight — heavy logic belongs in view models. Avoid side effects in `body`.
- **Error handling**: Use `do/catch` or `Result` — don't silently ignore errors. Log failures.
- **Naming**: Types are `PascalCase`, functions/variables are `camelCase`, constants are `camelCase`. No abbreviations unless universally understood (URL, ID, GPS).
- **Access control**: Prefer `private` over `internal`. Only expose what's needed.
- **No `print()` in production paths**: Use `os.Logger` or `#if DEBUG` guards for debug output.

## Kotlin (Android) — `android/**/*.kt`

- **Nullability**: No `!!` assertions. Use `?.let`, `?:`, or safe casts. Nullable types must be handled explicitly.
- **Coroutines**: Structured concurrency — launch in appropriate scope (`viewModelScope`, `lifecycleScope`). No `GlobalScope`. Cancel-safe operations.
- **Compose**: Composable functions should be side-effect-free in the composition phase. Side effects go in `LaunchedEffect`, `DisposableEffect`, or callbacks. `remember` and `rememberSaveable` for state.
- **Lifecycle**: Camera and location must respect lifecycle (start on `STARTED`, stop on `STOPPED`). No leaked observers.
- **Room**: DAOs return `Flow` or `suspend` functions. No blocking calls on main thread.
- **CameraX**: ImageAnalysis analyzer must close `ImageProxy` in all paths (including error paths).
- **Security**: No hardcoded secrets. Pepper obfuscated, same as iOS.
- **Memory**: Bitmap recycling. Reuse buffers in tight loops (frame analysis). No allocation in `analyze()` hot path.
- **Naming**: Types `PascalCase`, functions/variables `camelCase`, constants `SCREAMING_SNAKE_CASE`. Packages lowercase.
- **Access control**: Prefer `private` over `internal`. `data class` for value types.
- **No `Log.d`/`println` in production paths**: Use `BuildConfig.DEBUG` guards.

## Go (Server) — `server/**/*.go`

- **Error handling**: Every error must be checked. No `_` for errors unless explicitly documented why. Wrap errors with `fmt.Errorf("context: %w", err)` for stack context.
- **Goroutine safety**: Shared state must be protected by `sync.Mutex` or channels. No concurrent map access.
- **HTTP handlers**: Validate input (method, content-type, required fields). Return appropriate status codes. Set `Content-Type` header on responses.
- **SQL/pgx**: Use parameterized queries — no string concatenation for SQL. Close rows in `defer`. Handle `pgx.ErrNoRows` explicitly.
- **Resource cleanup**: `defer` for closing files, connections, response bodies. Defers run LIFO — order matters.
- **Context propagation**: Pass `context.Context` through the call chain. Use `r.Context()` in HTTP handlers.
- **Naming**: Exported = `PascalCase`, unexported = `camelCase`. Acronyms are all-caps (`ID`, `URL`, `HTTP`). Package names are lowercase, singular.
- **Imports**: Group stdlib, then third-party, then local — separated by blank lines.
- **No `log.Fatal` in library code**: Only in `main()`. Libraries return errors.
- **Graceful shutdown**: Signal handling for `SIGINT`/`SIGTERM`. Drain in-flight requests.
- **Security**: Constant-time comparison for sensitive values (`crypto/subtle`). No secrets in logs.

## Python (ML) — `models/**/*.py`

- **Type hints**: Function signatures should have type annotations for parameters and return values.
- **Imports**: stdlib, then third-party, then local — separated by blank lines. No wildcard imports.
- **Path handling**: Use `pathlib.Path`, not string concatenation for file paths.
- **Error handling**: Catch specific exceptions, not bare `except:`. Log failures with context.
- **Naming**: Functions/variables `snake_case`, classes `PascalCase`, constants `SCREAMING_SNAKE_CASE`.
- **Reproducibility**: Set random seeds where applicable. Pin dependency versions.

## Shell (Scripts) — `scripts/**/*.sh`

- **Quoting**: All variable expansions must be quoted (`"$var"`, not `$var`). No word splitting bugs.
- **Error handling**: `set -euo pipefail` at the top. Check command exit codes.
- **Portability**: Use POSIX-compatible constructs where possible. Document bash-specific features.
- **Naming**: Variables `SCREAMING_SNAKE_CASE`, functions `snake_case`.

## Markdown (Docs) — `docs/**/*.md`

- **Accuracy**: Code examples and file paths must match the actual codebase.
- **Requirement references**: REQ-S-* and REQ-M-* references must point to real requirements.
- **Formatting**: Consistent heading levels, no broken links, proper list indentation.

## Cross-cutting concerns

- **Privacy**: No plaintext license plates in logs, comments, test fixtures (except the pepper-unrelated test plates in `testdata/`). No analytics SDKs. No image data leaving the device unhashed.
- **Secrets**: No API keys, peppers, passwords, or credentials in source. Check string literals and comments.
- **Test quality**: Tests should assert behavior, not implementation. No comments that just repeat the code. Meaningful test names.
- **Dead code**: No commented-out code blocks, unused imports, or unreachable branches.
- **Consistency**: Changes should follow existing patterns in the file. Don't introduce new patterns without justification.

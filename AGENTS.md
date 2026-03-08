# Contributing Guide for Agents

## 1. Spec-Driven Development

Specs are the source of truth. Humans review specs, not code. All code is a derived artifact of the specs.

**Workflow:** Always update specs first, then make the code conform to what the specs say.

- Methodology: [`docs/development-philosophy.md`](docs/development-philosophy.md)
- System architecture: [`docs/specs/overview.md`](docs/specs/overview.md)
- Mobile app spec: [`docs/specs/mobile-app/spec.md`](docs/specs/mobile-app/spec.md)
- Server spec: [`docs/specs/server/spec.md`](docs/specs/server/spec.md)
- iOS structure: [`docs/specs/ios/structure.md`](docs/specs/ios/structure.md)
- Android structure: [`docs/specs/android/structure.md`](docs/specs/android/structure.md)
- Spec-vs-code gap tracker: [`docs/todo.md`](docs/todo.md)

## 2. Test-Driven Development

Everything must be automatically testable. Write tests alongside (or before) implementation.

- **Unit tests:** Each platform has its own test target (Xcode tests for iOS, JUnit for Android, `go test` for server).
- **E2E tests:** Shell-based test scripts that exercise the full pipeline.
  - Android E2E: [`e2e/android/`](e2e/android/) — run with `e2e/android/run.sh`
  - iOS simulator toolkit: [`scripts/simulator/`](scripts/simulator/) — see [`docs/specs/testing.md`](docs/specs/testing.md)
  - Test scenarios: [`docs/specs/mobile-app/test-scenarios.md`](docs/specs/mobile-app/test-scenarios.md)

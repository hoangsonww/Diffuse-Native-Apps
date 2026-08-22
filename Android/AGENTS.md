# Android

Native Kotlin/Jetpack Compose app. It intentionally does not depend on or modify the Swift application targets.

- `domain/` owns the schema-v1 Kotlin model, diff, privacy, storage, retention, search, and reports.
- `collectors/` is the only place Android platform observation APIs belong.
- Every collected property must have an explicit privacy classification in its descriptor.
- No account, network upload, telemetry, analytics, advertising identifier, hardware identifier, or cloud backup of snapshots.
- Existing `Fixtures/` are the cross-language contract. Never weaken them to make Kotlin tests pass.
- Release signing configuration and keystores stay outside the repository.

Commands:

```bash
cd Android
./gradlew testDebugUnitTest
./gradlew assembleDebug
./gradlew bundleRelease
```

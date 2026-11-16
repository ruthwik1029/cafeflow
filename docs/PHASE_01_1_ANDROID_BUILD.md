# Phase 01.1 — Android build recovery

Date: 14 November 2026. Scope: Android release verification only; no Phase 02 work.

## Cause and evidence

The failure occurs in Java's NIO selector initialization, before Android compilation:

```text
Gradle SocketConnection$SocketInputStream
  -> Selector.open
  -> WEPollSelectorImpl
  -> PipeImpl$Initializer$LoopbackConnector
  -> UnixDomainSockets.connect0
java.net.SocketException: Invalid argument: connect
java.io.IOException: Unable to establish loopback connection
```

The selector creates a Unix-domain socket pair to wake its event loop. On this
Windows host, endpoints created in the inherited TEMP directory bind but cannot
be connected to. Both the short `ADMINI~1` spelling and its canonical full path
fail. This is not simply a short-path spelling issue, a blocked TCP loopback port,
or an Android compilation error.

A standalone Java probe using the **same installed runtime** isolated the behavior:

| Probe | Inherited configuration | Project socket directory |
| --- | --- | --- |
| TCP loopback | Pass | Pass |
| Default `WEPollSelectorImpl` | Fails with the reported exception | Pass |
| Automatic Unix-domain endpoint | Connect fails | Pass |
| Explicit endpoint in inherited TEMP, short/full path | Both fail | Both still fail when tested explicitly |
| Explicit endpoint under CafeFlow | Pass | Pass |

The JDK's `UnixDomainSocketsUtil.getTempDir()` uses `jdk.net.unixdomain.tmpdir` when
provided; otherwise it uses `TEMP`, then `java.io.tmpdir`. This was confirmed by
inspecting the installed JDK's bytecode with `javap`. Changing only that one path
makes the original selector work; no fallback selector or networking/security
feature is disabled. Windows also reports error 1920 when accessing the failed
socket reparse-point files under TEMP. The lower-level Windows component causing
that location-specific behavior has not been identified; no driver, permissions,
firewall or security changes were attempted.

The previous successful project at `C:\Users\Administrator\Desktop\cafeflow_environment_test`
uses the same Gradle, AGP and Kotlin versions. Its daemon log confirms earlier builds
using the same Android Studio JDK. This supports retaining the existing toolchain,
and does not establish when or why TEMP's socket behavior changed.

## Inspected configuration

| Component | Value |
| --- | --- |
| Flutter / Dart | 3.47.9 / 3.13.7 |
| Gradle wrapper | 9.3.1 |
| Android Gradle Plugin | 9.1.0 |
| Project Kotlin plugin | 2.4.0 |
| Gradle's embedded Kotlin | 2.2.21; distinct from the Android plugin |
| Java launcher and daemon | Android Studio JBR 25.0.4, JetBrains |
| Java path | `C:\Program Files\Android\Android Studio\jbr` |
| Java/Kotlin bytecode target | 17 |
| Selected NDK | Flutter default, 28.2.13676358 |
| Original JVM options | 8 GB heap, 4 GB metaspace, 512 MB code cache, heap dump on OOM |

There is no project `org.gradle.java.home` override. Flutter doctor reports a working
Android toolchain and accepted licenses. The environment initially had no
`JAVA_HOME`, `JAVA_TOOL_OPTIONS`, `JDK_JAVA_OPTIONS` or `GRADLE_OPTS` override.

## Smallest correction

`tool/build_android.ps1` creates the ignored `build/java-sockets` directory and
temporarily adds its absolute path as `jdk.net.unixdomain.tmpdir` through the current
process's `JAVA_TOOL_OPTIONS`. This reaches both Gradle's launcher and its build JVM.
The helper preserves existing JVM options, restores the original environment and
working directory in `finally`, and propagates the build exit code. A helper smoke
check verifies restoration for both successful and failed child commands.

The helper executes:

```powershell
flutter build apk --release -t lib/main_android.dart
```

Run it from the CafeFlow workspace:

```powershell
./tool/build_android.ps1
# For a diagnostic build with Flutter's full Gradle stacktrace/info output:
./tool/build_android.ps1 -VerboseBuild
```

`tool/verify.ps1` now routes only its Android step through this helper. Windows and
Web commands are unchanged. A bare Flutter command in a shell that still inherits
the problematic TEMP socket location may reproduce the error; the helper is the
repeatable, scoped correction, not a machine-wide environment change.

No Flutter/Android Studio/Java/Gradle reinstall or version change was made. No SDK
or NDK was removed. Gradle automatically fetched missing dependency artifacts and
Android SDK Platform 35 required by the existing dependencies; the installed
platforms and NDKs were preserved. Application source, Android Gradle configuration,
dependency lockfile, and Windows/Web configuration were verified against hashes
captured before recovery.

## Verification

| Check | Result |
| --- | --- |
| `flutter analyze` | Passed, no issues |
| `flutter test` | Passed, all 28 tests |
| `dart format --output=none --set-exit-if-changed lib test` | Passed, 30 files, 0 changes |
| Android verbose release build | Passed, `BUILD SUCCESSFUL`, 228 tasks, exit 0 |
| Normal Android release build through helper | Passed, exit 0 |
| Actual build environment/working directory restoration | Both verified true |
| Helper smoke checks | Six passing cases: absent/empty/populated JVM options, successful/failing child commands |
| Protected source/configuration hashes | No changes |

The initial corrected build took approximately 5 minutes 19 seconds, including
new dependency/platform downloads. The final incremental release Gradle step took
5.9 seconds. Both used the explicit Android entry point. No JVM selector override,
version downgrade, security disablement, or compilation bypass flag was used.

Generated APK:

```text
C:\Users\Administrator\OneDrive\Desktop\CafeFlow\build\app\outputs\flutter-apk\app-release.apk
54,880,407 bytes
52.34 MiB / 54.88 decimal MB (Flutter displays 52.3MB)
SHA-256: 979DF6DD5D11288F1FB79EC06E634C257E47E3C67EB0BDB8339A8F6CFD9ECD91
```

The APK uses the project's existing debug signing configuration for release-build
verification. Production signing and device installation/runtime testing remain
outside this recovery task. Windows/Web were not rebuilt because their source and
configuration hashes are unchanged; their earlier successful build results stand.

Non-fatal notices remain visible in logs: Java's native-access warning, dependency
Gradle/Kotlin deprecations, newer incompatible Dart package versions, and the
existing icon-font tree-shaking notices. None prevented release generation, and
no warnings were hidden using suppression flags.

## Files changed

- `tool/build_android.ps1`: scoped Android release build helper.
- `tool/verify.ps1`: use the helper for Android only, with the explicit Android entry point.
- `README.md`: current Android build instructions and recovery status.
- `docs/PHASE_01_REPORT.md`: link the original blocked result to this follow-up.
- `docs/FILE_MANIFEST.md`: include the two new source/documentation files.
- `docs/PHASE_01_1_ANDROID_BUILD.md`: this investigation and verification report.

Local diagnostic sources, probes, logs, hashes and results are under the Git-ignored
`artifacts/phase01_1/` directory. Selected evidence:

- `android-verbose.log`: original reproduction, including full Gradle stack trace.
- `socket-probe-confirmed.log`: isolated failure with inherited TEMP.
- `socket-probe-project-temp.log`: selector and socket success with only the directory changed.
- `android-recovery-verbose.log`: corrected release build with verbose logging.
- `android-release.log`, `android-release-result.json`, `apk-metadata.json`: final release, restoration checks and APK size/hash.
- `analyze.log`, `test.log`, `helper-smoke.log`: regression/helper checks.
- `source-before.json`, `source-changes.json`: unchanged source/configuration evidence.

Some failed diagnostic endpoints in the inherited TEMP directory could not be
removed through normal filesystem calls (the same Windows error 1920). No forced
reparse-point or permissions repair was attempted. Project-directory probes were
cleaned up normally. Git also detects the repository's earlier sandbox-user ownership;
no `safe.directory` exception or ownership/security change was added.

Phase 02 remains gated on developer approval.

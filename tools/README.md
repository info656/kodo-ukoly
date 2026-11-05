# Kodo Úkoly — developer notes

Fork: https://github.com/info656/kodo-ukoly · upstream Zest (MIT), base `9b2d2631f036dec13b3062025cec9ce68f191551`.

Keep the original Zest task screens, colors and layout. The extra entry points are normal Kodo login/MFA, OS sharing and links to existing attachments. No file upload is enabled.

## Source of truth

`client_tasks` and `task_inbox` in the existing Kodo Supabase project. Clients are existing organizations; Inbox is the unassigned inbox. Production migration: `20261105103512_kodo_tasks_app` (local SQL file is the reviewed source). The two guarded RPCs `kodo_tasks_app_read` and `kodo_tasks_app_write` require an existing, active Kodo admin session, including the portal MFA guard. No service-role credential is in the application.

`kodo_task_app_metadata` stores only owner-specific Zest display settings (order, colors, due dates, priority, tags and subtask relationships). It is not a second set of business tasks. It has no direct authenticated table grants. Each write checks a version of its source record and metadata, so a stale editor cannot overwrite a change from the portal silently. Deletes use the portal's existing soft-trash functions. App writes do not invoke the portal email-sending APIs.

Isar is a replaceable rendering cache. Writes wait for server confirmation. No background offline outbox exists. An in-memory identifier preserves a retried task creation if a network response was lost; it is never dispatched automatically. Signing out clears the cached task records. Original local restore/reset features cannot import or delete the shared database.

Read refresh: at login, on foreground and every 15 seconds. Existing attachments get short-lived authenticated Storage links. The existing portal Storage policies remain in place.

New categories can expose an existing client by its exact unique name; new company identities should be created in the portal. Inbox assignments use the portal's existing assignment RPC. Moving an assigned client task back into Inbox is deliberately rejected rather than discarding its comments/attachment history. Client-to-client moves are supported.

## Local build

- Flutter 3.44.1 / Dart 3.12.1 (official tag `924134a44c189315be2148659913dda1671cbe99`).
- CocoaPods 1.16.2; system Ruby 2.6 uses `RUBYOPT=-rlogger` with pinned compatible gem dependencies.
- Xcode 27.2. macOS target 12+, arm64 for this Mac. Xcode 27's `lipo -verify_arch` rejected the combined universal check, hence the explicit single architecture. No Flutter SDK source patch was used.
- Create ignored `.local/build-config.json` with the existing public project URL and publishable key named `KODO_SUPABASE_URL` and `KODO_SUPABASE_KEY`. Never put a privileged server key in it or commit actual account configuration.

```sh
CI=true FLUTTER_SUPPRESS_ANALYTICS=true RUBYOPT=-rlogger PATH="$HOME/.gem/ruby/2.6.0/bin:$PATH" "$HOME/.codex/tools/flutter-sdk/bin/flutter" build macos --release --dart-define-from-file=.local/build-config.json --build-name=0.1.0 --build-number=1
```

The internal executable name is ASCII `KodoUkoly`; the displayed name and installed bundle are `Kodo Úkoly`. The stable installation is `/Users/pava/Applications/Kodo Úkoly.app`. Preserve one installation. Build apps are staging products, not extra user installations.

The Mac build has a local ad-hoc signature, no paid Apple team or new certificate. The app stores its own Supabase session in the encrypted login Keychain (legacy macOS API supported without a developer team). It does not copy another application's credentials or session. A synthetic write/read/delete checks Keychain availability at startup.

## Share

macOS `com.apple.share-services` extension accepts a single web URL or plain text, no files. It hands a bounded payload to `kodoukoly://share`, then the original Zest task editor confirms saving to Inbox. Receiving a custom URL alone never writes a task. Pending pre-login input stays only in memory. Android `ACTION_SEND text/plain` uses the same editor. Physical iOS distribution and its Share extension require a separately provisioned Apple build; the Mac installation does not install an app on an iPhone.

## Checks

```sh
flutter analyze --no-pub --no-fatal-infos
flutter test test/sharing_test.dart
node tests/database.mjs
```

The database tests run against local in-memory PGlite with synthetic identities and data, never against the connected project. Set `PGLITE_MODULE` to an installed PGlite module. Fixtures use the existing task RPC definitions read on 2026-11-05. The test runner needs no Supabase credentials. Tests cover source CRUD, idempotency, stale versions, parent cycles/cross-client parents, soft trash, admin/frozen/session checks and table/API grants. A live anonymous HTTP check verifies both production RPCs reject access. A full live authenticated round trip still requires the owner's normal login/MFA; do not manufacture claims or reuse another app's session to test it.

## Android is the primary target (Pava clarified 2026-11-05)

GitHub Actions builds a universal release APK on Ubuntu with the official pinned Flutter SDK and Java 17. Only the public Supabase client URL and publishable key are repository build variables. No account session, customer data, signing identity or service-role credential is uploaded. The build artifact is unsigned and retained for seven days. Signing and verification happen locally with Android's official `apksigner.jar` from the runner's installed SDK, after explicit authorization to create or use an app signing identity.

Planned private signing location: `/Users/pava/.codex/app-signing/kodo-ukoly/`, outside this repository. Creation is pending the owner's explicit approval; it must not be substituted with an ephemeral CI/debug identity. Preserve the approved key for future upgrades and make an authorized encrypted backup. Neither its password nor private key belong in GitHub, logs, notes or chat. Planned final artifact filename: `outputs/Kodo-Ukoly-0.1.0.apk`.

Android requires Internet access, accepts `ACTION_SEND text/plain` both at cold launch and while running, and queues pre-login share input only in memory. Login uses Android encrypted secure storage, OS backup is disabled, and no file sharing/upload is enabled. Physical phone login and sharing must be verified with the owner's account; do not claim a real phone was tested from the Mac build or Flutter unit tests.

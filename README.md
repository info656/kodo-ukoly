# Kodo Úkoly

Kodo's online task application based on [Zest](https://github.com/darkmoonight/Zest), preserving the original Zest screens, themes and task controls. **Android is the primary target.** A companion Mac build uses the same task records.

Client companies are groups, with a separate Inbox. Android's system **Share → Kodo Úkoly** accepts web links and plain text and opens the existing task editor with the item prepared for Inbox. Saving waits for the server; a failed save keeps the input. Existing attachments can be opened, with no file upload feature added.

The application connects to the existing Kodo Supabase tasks with normal user authentication and MFA. The current integration is for an authorized Kodo administrator. It is online only; local Isar is a replaceable display cache.

See [developer and build notes](tools/README.md) for server RPCs, tested behavior, Android APK preparation, signing, Mac installation and current boundaries. Private build configuration and signing identities are never committed. The GitHub workflow produces an unsigned build; an explicitly approved local signing identity is required before installation.

## Development

Flutter 3.44.1 / Dart 3.12.1. Run `flutter pub get`, `flutter analyze --no-pub --no-fatal-infos` and `flutter test`. The separate synthetic database tests use PGlite and require no connected-project credentials.

## License

[MIT](LICENSE). Original Zest copyright and license notices are retained.

# Swift code style

- All Swift code must follow the project's configured SwiftLint and SwiftFormat rules (typical config files: `.swiftlint.yml` / `.swiftformat`)
- On rule conflicts the auto-fixer wins: if the project's lint-fix command changed the code style, obey it, do not revert
- Do not use `// swiftlint:disable ...` to bypass a rule unless the reason is clear and written in a comment

> The mandatory `<your project's lint-check command>` before push / opening a PR is backstopped by a PreToolUse hook (if you configured one); this rule does not restate the steps.

# AGENTS.md

Start with [`README.md`](README.md) — it explains what this is, the architecture, and how to build. This file only adds what an agent needs to work here safely.

## Golden rules

- **Markdown is verbatim.** A note's body and frontmatter are committed to GitHub literally, including raw markdown and MDX/JSX. Never normalize, reflow, or "tidy" note content — only `FrontmatterSerializer` shapes it.
- **The Xcode project is generated.** `project.yml` is the source of truth (XcodeGen); the `.xcodeproj` is gitignored. After adding, moving, or renaming source files, run `xcodegen generate`.
- **Stay green before declaring done:** `swiftformat .`, then `swiftlint` (0 violations), then build, then `xcodebuild test`.
- **Tests use no network or GitHub.** Keep them pure; if logic needs a network call, factor out a pure function and test that (see `LinkMetadataService.parse`).
- The maintainer handles git commits — don't commit unless asked.

## Commands

```sh
xcodegen generate
xcodebuild build -scheme NotesApp -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO
xcodebuild test  -scheme NotesApp -destination 'platform=iOS Simulator,name=iPhone 17' CODE_SIGNING_ALLOWED=NO
swiftformat . && swiftlint
```

## Conventions

- Swift 6 language mode, iOS 17+ deployment target, SwiftUI + SwiftData.
- New unit tests use **Swift Testing** (`import Testing`), in `Tests/`.
- Code shared with the Share Extension goes in `Shared/` (compiled into both targets).
- Signing/App Groups need the maintainer's paid Apple account; simulator builds need no profile.

## Planning docs

`docs/tasks-todo/` and `docs/tasks-done/` hold work logs and design records.

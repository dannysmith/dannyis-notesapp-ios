# iOS Notes App Experiment

My website https://danny.is is an Astro site at https://github.com/dannysmith/dannyis-astro (available locally at `~/dev/dannyis-astro`). It has two primary content collections, notes and articles. The site is statically built using a GitHub action and then deployed to Vercel, So it can be deployed anywhere because it just produces static files. My workflow for publishing articles is to simply work on them usually against the main branch but with a draft flag set in the front matter which means they won't be published as part of the build. And I often do the same thing for notes. 

My notes are often short little individual thoughts and comments on things I've found on the internet (with a `sourceURL`). It would be great if I had a mobile app where I could create draft notes, especially one which supports share sheet sharing. So if I'm on a website I think is cool, I can create a note from it. And I would also like to be able to publish those notes directly from the iOS app. 

Now it seems to me the best way of doing this would be to build a very simple editing interface that used the GitHub API and allowed me to create and edit new notes only in the GH repo. However, the more complicated thing here is the challenge about how we should commit these. Should these be on separate branches etc. Because if I'm actually publishing a note then I think it's that's just gonna be its own commit, right? I guess an option here would be that I can have drafts in the GitHub repo. But there's like another type of draft that is just in the data of the mobile app that hasn't actually been "uploaded" yet.

Anyway, this is an app that is only going to be used by me. But it would be interesting to explore possibilities here. 

---

# Decisions, Research & Architecture

This section records what we decided and why, the research that informed it, and how the app is built. It's the source of truth for the project.

## The key insight: no Git on the device

The instinct ("it's a GitHub repo, so I need git/clone/commit/push on iOS") is wrong for this use case. We only ever touch **one file per change**, and GitHub's **Contents API** does exactly that in a single authenticated HTTP request:

```
PUT /repos/dannysmith/dannyis-astro/contents/src/content/notes/<file>.md
{ "message": "...", "content": "<base64>", "branch": "main", "sha": "<only when editing>" }
```

- Create a new file → omit `sha`, returns `201`.
- Edit an existing file → include its current blob `sha` (one `GET` to fetch it), returns `200`.
- There's a matching `DELETE`. Limit is 1 MB/file (irrelevant for text notes).

So the entire "backend" is `URLSession` + JSON. No libgit2, no clone, no working copy, no merge logic. This is what makes native Swift/SwiftUI almost trivial here — the hard part doesn't exist.

## Decisions

| Area | Decision | Why |
|---|---|---|
| **Platform** | Native Swift / SwiftUI, SwiftData for local storage | User has Xcode + Apple Developer account; the Contents API removes all git complexity |
| **Auth** | Fine-grained Personal Access Token in the Keychain | Single-user app — OAuth/PKCE exists to avoid shipping secrets to *many untrusted users*, which doesn't apply. Scope the PAT to `dannyis-astro` only, Contents: read & write. Revocable, rotatable. (OAuth+PKCE is the upgrade path if this ever ships to others — GitHub added PKCE support July 2025.) |
| **Commit model** | Direct commits to `main`, controlled by the frontmatter `draft` flag | Mirrors the existing by-hand workflow exactly. No branches/PRs. "Publish" = a Contents-API update flipping `draft: true` → `false`. |
| **Three draft states** | Local-only (SwiftData, never pushed) → Repo draft (`draft: true` on main) → Published (`draft: false` on main) | Clean mapping of the "two kinds of draft" problem from the brief |

## Research findings

- **CI / formatting (important):** `.prettierignore` in the Astro repo ignores `*.md`, `*.mdx`, `*.yml`, `*.yaml` ("Content files — managed manually"). So **prettier never checks notes** — the serializer only has to satisfy the zod schema, not prettier formatting. The only remaining CI gate on a note commit is the vitest/playwright suite, which won't care about a new note unless a test counts/snapshots them (low risk; verify if a deploy ever fails).
- **Build/deploy:** Push to `main` triggers `.github/workflows/deploy.yml` → runs `check:all` → builds → deploys to Vercel. A commit lands even if CI fails; it just won't deploy. No local pre-commit hooks. A post-deploy workflow syncs published (non-draft) posts to standard.site (AT Protocol).
- **Auth landscape:** `ASWebAuthenticationSession` + authorization-code + PKCE is the documented "best practice" for *distributed* iOS apps; device flow is discouraged for mobile (phishing surface). For a personal tool, a scoped PAT is the appropriate choice, not a shortcut.

## Notes content schema (from `src/content.config.ts`)

Files live in `src/content/notes/`, named `YYYY-MM-DD-<slug>.md` (or `.mdx`). Frontmatter:

| Field | Type | Required | Notes |
|---|---|---|---|
| `title` | string | **yes** | |
| `pubDate` | date | **yes** | coerced; emitted as `YYYY-MM-DD` |
| `sourceURL` | url | no | original URL for link posts |
| `slug` | string | no | custom URL slug; defaults to filename |
| `draft` | boolean | no | defaults `false`; `true` = excluded from production build |
| `description` | string | no | |
| `tags` | string[] | no | emitted as a flow array `["a", "b"]` |
| `styleguide` | boolean | no | excluded from RSS/indexes (not used by this app) |

## App architecture

```
NotesApp/
  AppConfig.swift              # repo owner/name/branch/notesDir constants
  NotesAppApp.swift            # @main, SwiftData ModelContainer
  Models/
    Note.swift                 # @Model: local draft + cache of a remote note (remotePath/remoteSha)
    FrontmatterSerializer.swift # serialize Note ↔ frontmatter+markdown; slug/date helpers; minimal parser
  Networking/
    GitHubClient.swift         # async URLSession wrapper over the Contents API
    GitHubModels.swift         # Codable DTOs + GitHubError
  Storage/
    KeychainStore.swift        # the PAT, in the Keychain
  Views/
    NoteListView.swift         # list local+remote notes, "Pull from GitHub", new/settings
    NoteEditorView.swift       # edit fields; Save locally / Push as draft / Publish / Delete
    SettingsView.swift         # paste + validate the PAT
```

Project is generated with **XcodeGen** from `project.yml` (not committed: `.xcodeproj`). Bundle id `is.danny.notesapp`, deployment target iOS 17 (SwiftData).

## Build & run

```sh
xcodegen generate                 # regenerate NotesApp.xcodeproj from project.yml
open NotesApp.xcodeproj            # then set your signing Team and run on device/sim
```

First launch: tap the gear → paste a fine-grained PAT scoped to `dannyis-astro` (Contents: read & write) → Save & Validate. Then write a note and Push as draft / Publish. "Pull from GitHub" imports existing notes for editing.

## Tooling & conventions

- **XcodeGen** (`project.yml`) is the source of truth for the Xcode project. The `.xcodeproj` is **not** committed — run `xcodegen generate` after cloning or whenever you add/move files. Deployment target is iOS 17 (the floor for SwiftData, Observation, and `ContentUnavailableView`); Swift 6 language mode.
- **SwiftFormat** (`.swiftformat`) handles layout. Run `swiftformat .` before committing.
- **SwiftLint** (`.swiftlint.yml`) handles style/correctness rules. It runs automatically as a pre-build phase in Xcode (warnings show inline), or run `swiftlint` manually. `ENABLE_USER_SCRIPT_SANDBOXING` is `NO` so the build phase can read the source tree.
- Both tools are installed via Homebrew: `brew install swiftlint swiftformat`.
- The repo is git-initialised on `main`. `.gitignore` covers Xcode/SPM artifacts, the generated `.xcodeproj`, and `.claude/settings.local.json`.

## Roadmap

### 1. M1 (done)

PAT auth, list/pull/create/edit/publish/delete notes direct to `main`. Builds clean.

### 2. Tweaks

- [x] We should completely exclude any notes with `styleguide: true` (usually just the one)
- [x] When creating new notes we should auto-generate the custom slug in a similar way to the filename but without the date prepended. We may also want to remove certain common filler words and limit its length?
- [x] The custom slug field should be clearable with a clear button on the right - we should use whatever the iOS design standard for this is.
- [x] The edit view should have the current status of a note shown clearly at the top
- [x] The save buttons should work like this:
  - [x] For a local-only draft we should have "Push draft to GitHub" and "Publish to GitHub". We should not need a "Save locally" button because we should be auto-persisting all changes to local drafts as they are made.
  - [x] For ALL notes pushed to GitHub we should perhaps not be persisting changes locally as we type and require an explicit "Save changes locally" to be pressed and warn if we try to go back with unsaved changes. The other option here is auto-saving local changes and making sure we are extremely clear when a note on GH ALSO has local changes which have not been pushed. I actually think this second thing might be a better option. But there should be a way for me to easily in this case easily say hey get me the version of this note from GitHub and overwrite anything which I've changed locally. **→ Chose auto-save everywhere (no save button); GitHub-backed notes show a "Local changes not pushed" indicator (editor header + list row dot); "Reload from GitHub" discards local edits and re-fetches the remote version.**
  - [x] For Drafts on GH we should show "Update draft on GitHub" and "Publish on GitHub". For Published notes on GH we should show "Revert to draft on GH" and "Update published note on GH". All actions which will change or create a published note should have a confirmation.

### 3. Resiliance and Safety
- [ ] Conflict handling on `sha` mismatch (remote changed since pull)
- [ ] Ensure any local drafts/changs are properly saved locally if the app is suddenly closed or navgated away from.

### 4. Markdown Editor

The body field should support normal markdown editing features (ideally GFM) - there must be an implementation of this we could reuse or use as a reference.

### 5. SourceURL Preview

It'd be awesome if when a sourceURL is present we can show a nice preview of it with it's OG image, title, URL etc. We should only do this if we can grab that info. I wonder if there is a library or reference implementation for this anywhere sine it feels like a common thing to want to do.

### 6. Share Extension target

- [ ] Grab URL + selected text from share source → prefill `sourceURL` + body. (This is the original motivation.)
- [ ] Consider how we could handle other types of share
  - [ ] text only > blockquote
  - [ ] image > upload to assets dir with appropriate rename etc
- [ ] 

### 7. Cleaning up

- [ ] Unit tests for the serializer and anything else.
- [x] Code linting tools like swiftlint and format etc?

## Known limitations

- The frontmatter parser handles flat single-line fields (what this app emits + common existing notes); it does not parse arbitrary YAML (block scalars, nested maps). Fine for round-tripping our own files.
- No conflict detection yet: if a note is edited on GitHub after being pulled, an in-app edit will fail the `sha` check (GitHub returns 409) — surfaced as an error, not auto-merged.
- `.mdx` notes containing JSX components will round-trip as plain text (body preserved verbatim), which is correct, but the editor has no MDX awareness.

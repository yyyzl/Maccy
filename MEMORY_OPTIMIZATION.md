# Maccy image-memory experiment

Based on upstream Maccy tag `2.6.1`. This is an experimental source change, not a built or installed application.

## Changes

- Query universal-clipboard markers separately when loading history. The icon cache can use this hint instead of traversing every item's contents. A failed query or an ambiguous duplicate marker falls back to the original lookup.
- Generate thumbnails and previews using a short-lived `ModelContext` for saved, unchanged items. Unsaved or deleted items use the original context so edits are not read from a stale store.
- Render downsized images into independent bitmaps instead of a drawing closure that retains the source image. Release cached images when a history row disappears and allow them to be regenerated.
- The original clipboard content and storage schema are unchanged. This change does not migrate or delete data.

## Command-line validation

The scripts below use only synthetic data and the macOS Command Line Tools. They do not access the system clipboard or the user's Maccy database.

```sh
sh tests-cli/clipboard-metadata/run.sh
sh tests-cli/image-resize/run.sh
sh tests-cli/image-loader/run.sh
sh tests-cli/decorator/run.sh
sh tests-cli/swiftdata-load/run.sh
sh tests-cli/image-loader-benchmark/run.sh
```

The SwiftData tests use the actual system SwiftData runtime, with manually implemented synthetic models because the installed Command Line Tools lack the `SwiftDataMacros` plugin. The synthetic model has a child-to-parent relationship rather than Maccy's exact inverse to-many relationship. The decorator test uses test doubles for the third-party `Defaults` and `Sauce` modules.

An example run with 10 synthetic image payloads totaling 40 MiB measured approximately 45 MiB for the legacy all-content scan and 5 MiB for the marker-only lookup. Separate rendered-thumbnail runs measured approximately 21–32 MiB before and 15–17 MiB after; before rendering, eager rasterization can instead use more memory. Numbers fluctuate with macOS memory compression and do not establish the memory usage of the full Maccy app.

## GitHub Actions

`.github/workflows/memory-optimization.yml` builds on GitHub's `macos-26` runner and runs the isolated regression tests. Pushing a branch named `memory-optimization/...` triggers it; `workflow_dispatch` is also configured. Manual dispatch requires the workflow to exist on the repository's default branch. Only source and synthetic tests are involved; no clipboard database is included. The uploaded artifact is unsigned and experimental, not a replacement for the installed app. The workflow has not yet been run remotely.

## Known limitations

- The full Maccy app and its original test suite have not been built or run. `xcodebuild`, `SwiftDataMacros`, and `FoundationMacros` are absent from the installed Command Line Tools. SourceKit also reports unresolved project types and the `Defaults` module without the project build configuration. Syntax checks and isolated tests are not a substitute for an integration build.
- Clipboard restoration is unchanged: `Clipboard.copy` still uses the original context. Duplicate detection and parts of the preview UI can also traverse full content, so image data may still be retained after copying, pasting, or opening a preview. The patch does not yet establish a complete load-on-paste lifecycle.
- No real pasteboard integration test has run. Keep the installed Maccy and its history untouched until a full integration build and an isolated end-to-end test pass.

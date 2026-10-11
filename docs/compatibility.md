# MC Manger - Compatibility & Status Matrix

Status key: **Written** = source exists; **Unit-tested (CI)** = tests written, not yet run
by the author; **Verified** = actually executed. As of this commit NOTHING Dart/Kotlin has
been compiled or executed by the author (no Flutter/Android SDK in the authoring
environment). Only `tools/make_fixture.py` has been run.

| Feature | Status | Tests | Real Bedrock 1.26.x verified | Notes |
|---|---|---|---|---|
| SAF folder pick + read-only copy (Kotlin) | Written | none (needs device) | No | Original is only read. Works on a copy in app storage. |
| Common-path scan | Written | partial | No | On Android 11+ most paths are blocked; real errors are shown. |
| World scanner | Written | Unit-tested (CI) | No | Never writes, never follows symlinks. |
| NBT reader/writer (LE) | Written | Unit-tested (CI) | No | Bounds/depth/size limits; duplicate keys rejected. |
| level.dat header + fields | Written | Fixture is **synthetic** | **No** | Field names are community-documented, unverified for 1.26.x. |
| Backup / verify / restore | Written | Unit-tested (CI) | n/a | Directory + SHA-256 manifest; restore to NEW folder only. |
| Backup consistency | Partial | Unit-tested (CI) | n/a | Always labelled `unverified_snapshot`; fails if a source file changes mid-copy. |
| LevelDB reader (pure Dart, read-only) | Written | Unit-tested (CI), synthetic fixture | **No** | Tables + logs, CRC32C, raw-zlib/zlib/Snappy. MANIFEST NOT parsed: highest sequence wins per key. No native lib, no ABI issues. |
| Bedrock key classifier | Written | Unit-tested (CI) | **No** | Pattern-only; tag numbers/names community-documented, unverified for 1.26.x. |
| Sub-chunk decoder (v1/8/9) + top-down map | Written | Unit-tested (CI), synthetic | **No** | Layer 0 only, block states ignored, colours approximate, 128x128-chunk window. Heightmap/biome not used. |
| File explorer (hash, preview, export copy) | Written | not tested | n/a | Read-only; export writes a copy under app storage, never overwrites. |
| Database explorer UI + player summary | Written | player summary tested | **No** | Isolate index build; lazy value read; keys held in RAM (limit 5M entries). |
| Players / inventory / entities / chunks | **Not implemented** | - | - | Need real fixtures first. |
| level.dat editor + pre-write transaction gateway | Written | test added; not run locally | No | Creates and verifies a SHA-256 backup before atomic-ish replacement; unknown NBT fields are preserved. Device verification still required.\n| DB record editor | Draft-only | test not applicable | No | Edits raw record bytes into a local draft JSON only. It does NOT write the world database. A MANIFEST-aware Bedrock LevelDB writer is still required before DB edits can be applied.\n| .mcworld export | Written | test added; not run locally | No | ZIP with world-relative paths; source world remains unchanged; share sheet offers import route.\n| Block/item icon catalog | Written | not tested | n/a | Offline emoji/color fallbacks, not official Minecraft sprite textures. | App is read-only. |
| Packs, comparison, .mcworld import | **Not implemented** | - | - | |
| ar/en + RTL | Written | not tested on device | - | Custom delegate; paths/hashes forced LTR. |

## Mutation safety\n\nAll actual world-file writes must go through `WorldMutationService`. It first creates a directory backup and verifies every SHA-256 entry before writing the target. The backup is labelled `unverified_snapshot` because the app cannot detect whether Minecraft is concurrently writing; close Minecraft first. The DB record editor is explicitly draft-only: it cannot yet apply edits to the world because raw SSTable/log changes without a MANIFEST-aware LevelDB writer are unsafe. `.mcworld` export includes only files currently in the world folder; it does not apply DB draft JSON files.\n\n## Known limitations
- Free-space pre-check, incremental backups, retention policies, archive (.zip) backups: not done.
- Rename of a directory is used to publish backups/restores; it is atomic only on one local filesystem.
- Debug builds include the INTERNET permission added by Flutter tooling; release does not.

## Requirements
Flutter 3.27.4 (Dart 3.6), JDK 17, Android SDK via the CI workflow. Run `tools/make_fixture.py`
then `tools/apply_android_overlay.sh` (generates `android/`, sets applicationId
`com.mcmanger.android`, installs the Kotlin SAF bridge).

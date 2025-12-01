# Open WebUI RAG Sync: Basename → Path Migration and Cleanup Guide

This document explains the problem we encountered with our original RAG sync process, the design and implementation of the fix, the one-time cleanup needed to reconcile the knowledge base, and day-2 operations guidance for maintainers. It is intended as a reference for other teams that want to adopt the same approach.

## Summary

- Problem: Our RAG sync keyed files by basename (e.g., `kustomization.yaml`), causing collisions when multiple files shared the same name in different paths.
- Symptoms: The sync logs reported a high “Already synced” count (e.g., 160) while Open WebUI’s knowledge base only showed a smaller number of files (e.g., 87). Duplicates collided and were effectively shadowed.
- Fix: Store and track files using their repository-relative paths (e.g., `apps/foo/kustomization.yaml`) instead of basenames.
- Cleanup: A one-time purge removes legacy basename-only entries from Open WebUI that don’t map to actual top-level repo files.
- Outcome: The knowledge base accurately represents all unique repo files included by sync patterns, and future runs correctly detect changes.

---

## Background

Our repository contains many files that share common basenames (especially `kustomization.yaml`). The initial RAG sync script uploaded files to Open WebUI and tracked them by basename. When two or more files had the same basename in different directories, the sync logic considered later files “already synced” because it matched by basename rather than path. This caused:

- Fewer visible files in Open WebUI vs. the number reported by the sync summary.
- Updates overwriting or skipping unintended files.
- Confusing drift between repo changes and the knowledge base state.

---

## Design Goals

- Unique identity: Every file in scope should be uniquely identified by its relative path from the repo root.
- Idempotent sync: Re-running the sync should result in zero-op when nothing changed, and precise uploads when changes occur.
- Safe cleanup: A one-time, opt-in cleanup step should remove legacy entries without affecting legitimate top-level files.
- Minimal operational friction: CI should drive the sync safely using cluster-internal routing and secrets.

---

## What Changed

1) Path-based identity

- Each uploaded file is now sent to Open WebUI with its repo-relative path encoded as the uploaded filename.
- The script maintains a map of knowledge-base entries keyed by that path-like name (or `meta.name` if present, otherwise `filename`).

2) Upload semantics

- If a path-keyed entry already exists, the script deletes it first and uploads the new version, then re-attaches it to the target knowledge base.
- This ensures updates don’t collide with unrelated files that share a basename.

3) Cleanup (one-time, optional)

- The script supports a new flag `CLEANUP_LEGACY_BASENAME=true` to scan the knowledge base for entries with basename-only names (no `/`).
- If a basename-only entry does not correspond to an actual top-level file in the repo but does exist as nested files, it is considered a legacy artifact and is deleted.
- Top-level files (e.g., `README.md` at the repo root) are preserved.

---

## Environment Variables

- `OPEN_WEBUI_API_KEY` (required): API key from Open WebUI Settings → Account.
- `OPEN_WEBUI_KNOWLEDGE_ID` (required): Knowledge base ID to which files are added.
- `OPEN_WEBUI_URL` (optional): Base URL (defaults to internal cluster URL).
- `LAST_SYNC_COMMIT` (optional): SHA used to detect changes since last sync; otherwise marker file or `HEAD~1`.
- `FORCE_FULL_SYNC` (optional): If `true`, uploads all matching files regardless of change detection.
- `CLEANUP_LEGACY_BASENAME` (optional): If `true`, performs the one-time cleanup described above.

---

## CI Integration

We run the RAG sync in GitHub Actions on `main` after CI passes, using an internal cluster URL to bypass Authentik forward auth.

- Location: `.github/workflows/ci.yaml` → `rag-sync` job
- Secrets: `OPEN_WEBUI_API_KEY`, `OPEN_WEBUI_KNOWLEDGE_ID`
- Temp one-time cleanup flag: `CLEANUP_LEGACY_BASENAME: "true"` (remove after the first successful run)

Why set it in CI temporarily?

- Ensures the cleanup executes in the same environment as the regular sync and has access to the same credentials and cluster routing.
- Keeps local developer runs simple and focused on incremental syncs.

---

## Migration Procedure

1) Merge the PR containing the path-based sync changes and the temporary cleanup flag.
2) Let CI run on `main`. It will:
   - Execute the legacy cleanup once (purging only basename-only entries that aren’t real top-level files).
   - Perform the path-based sync.
3) Verify in Open WebUI:
   - Knowledge base file names include paths (e.g., `apps/foo/kustomization.yaml`).
   - The total number of files matches expectations (subtracting excluded or oversized files).
4) Remove `CLEANUP_LEGACY_BASENAME: "true"` from the workflow (or merge the follow-up commit that removes it).

Rollback

- If unexpected deletions occur (unlikely based on the conservative logic), turn off the cleanup flag, re-run the sync, and re-upload any affected files. Because files are sourced from the repository, state is reproducible.

---

## File Scope and Exclusions

Included (default):

- `*.md`
- `apps/**/kustomization.yaml`, `apps/**/*.yaml`
- `infrastructure/**/kustomization.yaml`, `infrastructure/**/*.yaml`
- `.github/workflows/*.yaml`

Excluded:

- `*sealed-secret*` (sealed key material should not be replicated)
- `*.env*`
- `*AGENTS.md*`

Size limit:

- Files larger than ~500 KB are skipped to keep ingestion fast and predictable.

Note: You can adjust these patterns centrally in `scripts/sync-rag.sh` to fit your org.

---

## Operational Runbook

Common operations:

- Force a full sync (once, if debugging):
  - `FORCE_FULL_SYNC=true ./scripts/sync-rag.sh`
- Clean up legacy basename-only entries locally (if needed):
  - `CLEANUP_LEGACY_BASENAME=true ./scripts/sync-rag.sh`
- Inspect last sync commit marker:
  - `.rag-sync-commit` at the repo root stores the last successful synced commit.

Expected logs:

- “Found N files in knowledge base” on load.
- “===== Sync Summary =====” with counts for uploaded, already synced, deleted, skipped (size), failed.
- On success, “Saved sync marker: <sha>”.

Troubleshooting:

- Missing environment variables → script exits with a clear error pointing to required vars.
- `jq` missing → install it on the runner; the script requires it to parse JSON.
- Network/auth issues → verify `OPEN_WEBUI_URL` and `OPEN_WEBUI_API_KEY` correctness; use internal service URL in cluster.
- Large file skipped → either reduce size or split content; current limit is ~500 KB.

---

## Security Considerations

- Never sync plaintext Kubernetes Secrets; use SealedSecrets or other encrypted approaches.
- Restrict RAG sync access by scoping API keys and using internal routing.
- Review included patterns to ensure no sensitive content is being ingested.

---

## FAQ

Q: Why not deduplicate by content hash instead of path?

A: Content hashing alone can mask legitimate duplication across files and doesn’t help with change attribution or provenance. Path identity ensures correct mapping to repo lineage while still enabling content-aware behaviors later if desired.

Q: What if Open WebUI displays only filenames instead of paths?

A: We pass the relative path via the upload’s `filename` and prefer `meta.name` when present. If your Open WebUI setup renders only basenames, you can still rely on sync correctness (deletion + upload) because we track by the stored name; consider opening a feature request upstream if full paths are desired in the UI.

Q: Can we run the cleanup multiple times?

A: It is safe but unnecessary. After the first run, your KB should be path-based. Leave the flag off in subsequent runs to avoid redundant API calls.

Q: How do we include more types of files?

A: Edit the `SYNC_PATTERNS` array in `scripts/sync-rag.sh` and tune `EXCLUDE_PATTERNS` as needed.

---

## Implementation Notes (for developers)

- We now track KB files in two associative arrays:
  - `KB_FILES_BY_PATH`: `path → file_id`
  - `KB_FILES_BY_HASH`: `hash → file_id` (reserved for potential future optimizations)
- Upload uses: `-F "file=@$file_path;filename=$relative_path"` to preserve path identity.
- Cleanup logic only purges names without `/` that are not actual top-level files and that appear in nested paths.
- The marker file `.rag-sync-commit` records the last successful sync commit to drive change detection.

---

## Status

- Change implemented in `scripts/sync-rag.sh`.
- CI hardened for `kubectl` installation using explicit output filename and OS detection.
- `rag-sync` job temporarily enables cleanup: remove `CLEANUP_LEGACY_BASENAME` after first successful run on `main`.

---

If you adopt this pattern, start by enabling path-based identity, validate your UI behavior in Open WebUI, then run the one-time cleanup through CI. This sequence minimizes surprises and keeps the KB consistent with your repository structure.


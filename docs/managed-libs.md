# Managed Libraries and Patch Workflow

JA4 Spoofer keeps upstream TLS and client projects as Git submodules under
`libs/`. Project-specific changes are stored as patch files under `patches/`.
The patch files are the source of truth; patched submodule working trees are
local build state.

## Managed Submodules

| Path | Purpose |
|---|---|
| `libs/openssl` | OpenSSL runtime patch target |
| `libs/boringssl` | BoringSSL runtime patch target |
| `libs/nss` | NSS runtime patch target |
| `libs/ja4` | JA4 reference material |
| `libs/nginx` | Nginx integration target |
| `libs/ja4-nginx-module` | JA4 Nginx module integration target |

## Patch Sets

| Path | Applies to |
|---|---|
| `patches/openssl/` | OpenSSL |
| `patches/boringssl/` | BoringSSL |
| `patches/nss/` | NSS |

Each patch directory may contain a `BASE_REF` file. The patch application script
resets the matching submodule to that ref before applying the patch stack.

## Packaged Runtime

The installable GUI does not ship the large `libs/*` source trees. It ships only
the project runtime files under `assets/bundled-runtime/`:

- `scripts/`
- `configs/`
- `patches/boringssl`, `patches/nss`, `patches/openssl`

On first use, the app extracts those files to
`~/.ja4-spoofer/runtime/<version>/`. When a build needs a TLS library source
tree and it is missing, `scripts/apply_patches.sh --only <name>` clones the
upstream repository listed in `configs/managed-libs.env`, checks out
`patches/<name>/BASE_REF`, creates `my-changes`, and applies the patch stack.
That keeps releases small while still making the installed app self-contained
from a workflow perspective.

## Rules

- Do not commit modified upstream source trees directly in the root repository.
- Commit JA4 changes as patch files under `patches/`.
- Change a submodule pointer only when intentionally moving to a new upstream
  baseline.
- Treat generated binaries, build directories and dirty submodule worktrees as
  disposable local state.

## Typical Workflow

Initialize the submodules:

```bash
git submodule update --init --recursive
```

Apply the checked-in patch stacks:

```bash
scripts/apply_patches.sh
```

Make changes inside a submodule and commit them locally:

```bash
cd libs/openssl
# edit files
git add <files>
git commit -m "Add JA4 OpenSSL tweak"
cd ../..
```

Refresh the root patch files from those local submodule commits:

```bash
scripts/refresh_patches.sh
```

Commit the refreshed files in the root repository:

```bash
git add patches/openssl
git commit -m "Update OpenSSL JA4 patch stack"
```

## Updating an Upstream Baseline

1. Move the submodule to the desired upstream commit.
2. Update the corresponding `patches/<name>/BASE_REF`.
3. Re-apply the patch stack with `scripts/apply_patches.sh`.
4. Resolve conflicts inside the submodule.
5. Commit the resolved submodule changes locally.
6. Run `scripts/refresh_patches.sh`.
7. Commit the updated `BASE_REF`, patch files and submodule pointer.

## Drift Check

Upstream BoringSSL/NSS/OpenSSL occasionally rebase or rewrite history,
which can silently invalidate the patch stack against the pinned
`BASE_REF`. The dry-run mode catches this before users hit it at build
time:

```bash
# Local: against the current libs/<name> checkout.
scripts/apply_patches.sh --only openssl --check
```

A temporary git worktree is created at `BASE_REF`, every `*.patch` is
fed through `git apply --check`, and the worktree is removed. Your
`libs/<name>` checkout and the `my-changes` branch are not touched.

For a fresh-clone validation that mirrors what an end user would
experience, trigger the workflow:

```bash
gh workflow run upstream-drift-check.yml
```

It matrix-clones BoringSSL/NSS/OpenSSL upstream, checks out each
`BASE_REF`, and runs `scripts/apply_patches.sh --only <lib> --check`
against the fresh tree. The job goes red on the first failing patch,
with the full conflict trace in the log.

## Patch Internals

Implementation notes for reviewers live in:

- [BoringSSL patch internals](patches/boringssl-internals.md)
- [NSS patch internals](patches/nss-internals.md)
- [OpenSSL patch internals](patches/openssl-internals.md)

Runtime configuration is documented in:

- [BoringSSL JA4 runtime hook](boringssl-ja4-config.md)
- [NSS JA4 runtime hook](nss-ja4-config.md)
- [OpenSSL JA4 runtime hook](openssl-ja4-config.md)

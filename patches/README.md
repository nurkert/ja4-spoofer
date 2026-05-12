# Patch workflow

This repo tracks local changes to upstream SSL libraries as patch sets.
The upstream sources live as git submodules in `libs/`.
Only patch files and submodule pointers are stored in this repo.

## Refresh patches after making changes

1. Make your changes inside the submodule (e.g. `libs/openssl`).
2. Commit them inside the submodule.
3. Run:

```bash
scripts/refresh_patches.sh
```

This exports commit patches into `patches/<lib>/`.

To also export uncommitted submodule diffs alongside the patches:

```bash
scripts/refresh_patches.sh --include-wip
```

That additionally writes `.diff` files:

- `9998-wip-working-tree.diff`
- `9999-wip-index.diff`

## Apply patches on top of updated upstream

1. Update submodules:

```bash
git submodule update --init --remote
```

2. Re-apply patches:

```bash
scripts/apply_patches.sh
```

To also apply the `.diff` WIP snapshots on top:

```bash
scripts/apply_patches.sh --with-wip
```

The script aborts if `my-changes` carries commits beyond the current patch
set or has a dirty working tree — pass `--force` to override.

If a patch fails, fix conflicts inside the submodule and re-run
`scripts/refresh_patches.sh` to update the patch set.

# Smartsort

Organize files in a directory using flexible sorting modes.
Supports undo history, extensions, time, size, and semantic kinds.

## Functions

- `smartsort`: Sort files by mode and maintain undo history.

## Aliases

- None.

## Loading and tests

With CBC's `cbc_lazy_register` helper, `cbc-module.sh` exposes `smartsort`
immediately and loads `smartsort.sh` on first use. Older CBC versions and
standalone sourcing load the same implementation eagerly. Reloading the
entrypoint resets the wrapper; subsequent calls use the loaded function.

Run the regression check from this repository root:

```bash
bash tests/test_loading.sh
```

Set `CBC_TEST_SCRIPT` to the absolute path of a CBC script providing
`cbc_lazy_register` to include lazy integration. The test compares eager and
lazy help output and exercises first-use sorting and undo with temporary
files and an isolated state directory.

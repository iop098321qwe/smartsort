#!/usr/bin/env bash
# Run from the module root. Set CBC_TEST_SCRIPT to test lazy integration.
set -eo pipefail
module_root="$PWD"
fixture="$(mktemp -d)"
trap 'rm -rf -- "$fixture"' EXIT
export HOME="$fixture" CBC_CONFIG_DIR="$fixture/config"
export CBC_MODULE_ROOT="$fixture/modules"
export SMARTSORT_STATE_DIR="$fixture/state"
mkdir -p "$CBC_CONFIG_DIR" "$CBC_MODULE_ROOT" "$fixture/files"
printf '%s\n' 'CBC_SHOW_BANNER=false' 'CBC_USE_GUM=false' \
  'CBC_SOURCE_BASH_ALIASES=false' >"$CBC_CONFIG_DIR/cbc.config"
: >"$HOME/.cbc_aliases.sh"
cbc_style_box() { shift; printf '%s\n' "$@"; printf '\n'; }
cbc_style_message() { shift; printf '%s\n' "$@"; }
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
source ./cbc-module.sh
smartsort -h >"$fixture/eager-help"
if smartsort --invalid >/dev/null 2>&1; then fail 'Bad option succeeded.'; fi

if [ -n "${CBC_TEST_SCRIPT:-}" ]; then
  source "$CBC_TEST_SCRIPT"
  source "$module_root/cbc-module.sh"
  [[ "$(declare -f smartsort)" == *cbc_lazy_invoke* ]] ||
    fail 'Implementation was parsed at startup.'
  smartsort -h >"$fixture/lazy-help"
  cmp "$fixture/eager-help" "$fixture/lazy-help"
  source "$module_root/cbc-module.sh"
else
  printf '%s\n' 'SKIP: lazy integration (set CBC_TEST_SCRIPT)'
fi

# Exercise real state and file operations on the first lazy invocation.
cbc_confirm() { return 0; }
printf '%s\n' 'alpha contents' >"$fixture/files/alpha file.txt"
printf '%s\n' 'beta contents' >"$fixture/files/beta.txt"
cd "$fixture/files"
smartsort size >/dev/null
[[ -f 'small/alpha file.txt' && -f small/beta.txt ]] ||
  fail 'First-use sorting failed.'
[[ "$(declare -f smartsort)" != *cbc_lazy_invoke* ]] ||
  fail 'First use did not promote the command.'
smartsort undo >/dev/null
[[ "$(<"alpha file.txt")" == 'alpha contents' &&
  "$(<beta.txt)" == 'beta contents' ]] || fail 'Undo lost file data.'
[[ ! -d small ]] || fail 'Undo did not remove the created directory.'
printf '%s\n' 'PASS: eager fallback, lazy help/reload, first-use sort, and undo'

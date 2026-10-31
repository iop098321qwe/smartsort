#!/usr/bin/env bash

# Keep command discovery immediate without parsing the implementation in
# every terminal. Older CBC versions and standalone sourcing stay eager.
if declare -F cbc_lazy_register >/dev/null; then
  cbc_lazy_register "${BASH_SOURCE[0]%cbc-module.sh}smartsort.sh" smartsort
else
  source "${BASH_SOURCE[0]%cbc-module.sh}smartsort.sh"
fi

#!/bin/bash
set -eu -o pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../scripts/common.sh
source "$HERE/../../scripts/common.sh"
load_distro "$(basename "$HERE")"
boot_vm

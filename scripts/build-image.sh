#!/bin/bash
set -eu -o pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$HERE/common.sh"
load_distro "${1:?usage: build-image.sh <distro>}"
build_image

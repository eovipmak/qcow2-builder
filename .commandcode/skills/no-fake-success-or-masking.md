# No Mocks, Faked Success, or Masking Failures

- **No mocks, stubs, or fake success.** If a build step can't be tested locally, say so; never pretend `boot-test.sh` passed or tests ran if they didn't.
- **No error handling for impossible scenarios.** A script can't run its "secure boot check" fallback if the firmware doesn't exist — fail loudly with `set -euo pipefail` semantics instead.
- **No fallbacks that mask failures.** If a package is required, install it; do not add `|| true` to hide a broken hook or a missing file.
- **No backward-compat shims.** Update all distros that use a changed element or hook and delete the old names.
- Do not tell the process what to do and declare victory without confirming. The process should actually work in reality.
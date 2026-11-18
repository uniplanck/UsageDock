#!/bin/bash
# On the Mac, run bash scripts/install-agy-wrappers.sh from this checkout.
# Register the slots in UsageDock Settings, then run agy-0 acp --login (through agy-5).
# Use ~/.local/bin/agy-0 if ~/.local/bin is outside PATH.
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "$0")" && pwd)"
bin_dir="$HOME/.local/bin"
helper=".usagedock-agy-profile"
mkdir -p "$bin_dir"

for slot in {0..5}; do
    wrapper="$bin_dir/agy-$slot"
    if [[ -e "$wrapper" || -L "$wrapper" ]]; then
        if [[ ! -L "$wrapper" || "$(readlink "$wrapper")" != "$helper" ]]; then
            printf '%s\n' "Already exists: $wrapper" >&2
            exit 1
        fi
    fi
done

install -m 755 "$script_dir/../UsageDock/Resources/agy-profile.pl" "$bin_dir/$helper"
for slot in {0..5}; do
    wrapper="$bin_dir/agy-$slot"
    if [[ ! -L "$wrapper" ]]; then
        ln -s "$helper" "$wrapper"
    fi
done

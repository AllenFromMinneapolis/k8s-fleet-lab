#!/usr/bin/env bash
# Builds the whole lab in one go. Set up for an 8 GB Docker Desktop: ONE store.
# Usage: ./scripts/up.sh
set -euo pipefail
cd "$(dirname "$0")/.."

./scripts/create-cluster.sh store-001 east

# --- Second store (needs about 12 GB of Docker Desktop memory) ---------------
# Two stores on 8 GB starve each other: both slow down and time out.
# To try it, raise Docker memory to 12 GB or more, then remove the "#" below.
# ./scripts/create-cluster.sh store-002 west
# -----------------------------------------------------------------------------

echo
echo "Argo CD needs about 10 more minutes to install everything from Git."
echo "Check progress with:  ./scripts/status.sh   (want 7/7 and 2/2)"
echo "Then open the screens: ./scripts/open-ui.sh store-001"

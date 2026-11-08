#!/usr/bin/env bash
# Removes every lab cluster, Vault and the Docker network.
set -uo pipefail
for c in $(k3d cluster list --no-headers | awk '{print $1}'); do
  k3d cluster delete "$c"
done
docker rm -f fleet-vault >/dev/null 2>&1
docker network rm fleet-lab >/dev/null 2>&1
echo "Lab removed."

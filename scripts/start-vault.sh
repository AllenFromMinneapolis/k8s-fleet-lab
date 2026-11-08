#!/usr/bin/env bash
# Starts ONE central HashiCorp Vault (in Docker) that every store cluster reads secrets from.
# Lab only: dev mode, in-memory, root token "root". Never do this in production.
set -euo pipefail
docker network inspect fleet-lab >/dev/null 2>&1 || docker network create fleet-lab >/dev/null
if ! docker ps --format '{{.Names}}' | grep -qx fleet-vault; then
  docker rm -f fleet-vault >/dev/null 2>&1 || true
  docker run -d --name fleet-vault --network fleet-lab -p 8200:8200 \
    -e VAULT_DEV_ROOT_TOKEN_ID=root -e VAULT_DEV_LISTEN_ADDRESS=0.0.0.0:8200 \
    hashicorp/vault:2.2.1 >/dev/null
  sleep 3
fi
docker exec -e VAULT_ADDR=http://127.0.0.1:8200 -e VAULT_TOKEN=root fleet-vault \
  vault kv put secret/store-app api_key="${API_KEY:-demo-key-12345}" >/dev/null
echo "Vault is running at http://localhost:8200 (token: root) with secret/store-app"

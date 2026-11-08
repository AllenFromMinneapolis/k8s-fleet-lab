# k8s-fleet-lab

A small, laptop-sized copy of how companies run thousands of Kubernetes clusters
(for example, one cluster per store). You build one "store" cluster from a template,
then a second one, and you can see that the only extra effort is one more command.

Runs on Docker Desktop (Mac, including Apple silicon). No cloud account needed.

## What's in the box

| Piece | Tool | Real-world job |
|---|---|---|
| Cluster template | k3d + K3s (`cluster-template/k3d-cluster.yaml`) | Every store cluster is built the same way |
| GitOps | Argo CD (`fleet/root`) | Git says what each cluster runs; Argo CD makes it so |
| Policy | Kyverno (`fleet/policies`) | Company rules enforced automatically |
| Secrets | HashiCorp Vault + External Secrets (`fleet/secret-store`) | One central Vault; clusters fetch secrets, nothing is stored in Git |
| Monitoring | Prometheus + Grafana (kube-prometheus-stack) | Health and metrics for every cluster |
| The app | `fleet/apps/store-app` | The business app each store runs |

How it fits together:

```
GitHub repo (this one)  ---->  Argo CD in each cluster  ---->  Kyverno, External Secrets,
                                                                Prometheus/Grafana, store app
Central Vault (Docker)  <----  External Secrets in each cluster fetches the API key
```

## Needs

- Docker Desktop with **at least 8 GB memory** (Settings > Resources). Each cluster uses about 3 GB.
- `brew install k3d kubectl helm k9s`
- Stop Minikube while you use this to free memory: `minikube stop`

## Use it

```
./scripts/create-cluster.sh store-001 east     # about 5 minutes
./scripts/status.sh                            # fleet summary
./scripts/open-ui.sh store-001                 # Argo CD, Grafana, app, Vault in the browser
kubectl --context k3d-store-001 apply -f examples/bad-pod.yaml   # watch the policy block it
./scripts/create-cluster.sh store-002 west     # a second store, same template
./scripts/delete-everything.sh                 # clean up
```

Change the fleet: edit `fleet/apps/store-app/values.yaml`, commit and push. Every
cluster picks it up within about 3 minutes.

## Lab only

Vault runs in dev mode with the token `root`, and the passwords are simple. That's fine
on a laptop, never in production.

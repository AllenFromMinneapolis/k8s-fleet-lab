# k8s-fleet-lab

A small, laptop-sized copy of how companies run thousands of Kubernetes clusters
(for example, one cluster per store). You build one "store" cluster from a template,
and you can see that a second one (or the 2,000th) is just one more command.

Runs on Docker Desktop (Mac, including Apple silicon). No cloud account needed.

## What's in the box

| Piece | Tool | Real-world job |
|---|---|---|
| Cluster template | k3d + K3s (`cluster-template/k3d-cluster.yaml`) | Every store cluster is built the same way |
| GitOps | Argo CD (`fleet/root`) | Git says what each cluster runs; Argo CD makes it so |
| Policy | Kyverno (`fleet/policies`) | Company rules enforced automatically |
| Secrets | HashiCorp Vault + External Secrets (`fleet/secret-store`) | One central Vault; clusters fetch secrets, nothing is stored in Git |
| Monitoring | Prometheus + Grafana (kube-prometheus-stack) | Health and metrics for every cluster |
| Telemetry | OpenTelemetry Collector + Grafana Tempo (`fleet/root/templates/20-otel.yaml`, `fleet/otel`) | Apps send metrics and traces to one agent, which forwards them |
| The app | `fleet/apps/store-app` | The business app each store runs |
| Instrumented app | `fleet/apps/orders-app` (Python + OpenTelemetry) | An API that sends its own metrics and traces |

How it fits together:

```
GitHub repo (this one)  ---->  Argo CD in each cluster  ---->  Kyverno, External Secrets,
                                                                Prometheus/Grafana, store app
Central Vault (Docker)  <----  External Secrets in each cluster fetches the API key
```

## Needs

- Docker Desktop memory (Settings > Resources): **8 GB = one store**, 12 GB or more = two stores.
  Each cluster uses about 3.5 GB.
- `brew install k3d kubectl helm k9s`
- Stop Minikube while you use this to free memory: `minikube stop`

## Use it (one store, set up for an 8 GB Mac)

```
cd ~/Documents/k8s-fleet-lab
./scripts/up.sh                                # builds store-001 (about 5 minutes)
./scripts/status.sh                            # after ~10 minutes: 10/10 apps, 2/2 pods
./scripts/open-ui.sh store-001                 # links + logins; leave it running
kubectl --context k3d-store-001 apply -f examples/bad-pod.yaml   # Kyverno blocks it
./scripts/delete-everything.sh                 # clean up
```

`up.sh` just runs `./scripts/create-cluster.sh store-001 east`. Run it once; to rebuild,
run `delete-everything.sh` first.

Web screens (from `open-ui.sh`):

| Screen | Link | Login |
|---|---|---|
| Argo CD | http://localhost:8082 (not 8080, which Jenkins often uses) | admin / password printed by the script |
| Grafana | http://localhost:3000 | admin / fleetlab |
| Prometheus | http://localhost:9090 | none |
| Store app | http://localhost:8081 | none |
| Vault | http://localhost:8200 | token `root` |

### Second store (commented out: needs about 12 GB of Docker memory)

```
# ./scripts/create-cluster.sh store-002 west   # same template, only name and region change
# ./scripts/status.sh                          # two lines: store-001 east, store-002 west
# ./scripts/open-ui.sh store-002               # one open-ui at a time (they share ports)
```

`up.sh` has the same line commented out. `create-cluster.sh` refuses a second cluster
when Docker has less than about 12 GB (`FORCE=1` to try anyway).

## Things to try

1. **Argo CD matches Git.** Click `root` in Argo CD. The short code next to "Synced to
   main" is the same as the latest commit code on the GitHub repo page.
2. **Prometheus is healthy.** Prometheus > Status > Target health: everything UP.
   Status > TSDB status shows its storage.
3. **Policy.** The `bad-pod.yaml` command above is rejected for two reasons: no `team`
   label, and an image tagged `:latest`.
4. **Self-heal (Git always wins).** Scale the app by hand and Argo CD puts it back to 2:
   ```
   kubectl --context k3d-store-001 -n store-apps scale deploy store-app --replicas=5
   kubectl --context k3d-store-001 -n store-apps get events --sort-by=.lastTimestamp | tail -10
   ```
5. **Roll out a change from Git.** On GitHub, edit `fleet/apps/store-app/values.yaml`,
   change the `message` line and commit. Within about 3 minutes (or click Refresh in
   Argo CD) Argo CD shows the new commit code and http://localhost:8081 shows the new
   text. With more stores, every one of them updates.
6. **OpenTelemetry.** Grafana > Dashboards > **Orders app (OpenTelemetry)**. Top row:
   request rate, p95 latency and error % (from auto-instrumentation). Middle row: orders
   per minute and average order value (custom metrics in the code). Bottom: click any
   Trace ID to see one request step by step (`check_inventory`, `charge_card`). The
   `orders-shopper` pod sends about one order a second, so there is always data.
   Free-form: Grafana > Explore > Tempo > TraceQL `{status = error}`.

   How the data flows:
   ```
   orders-app (Python)  --OTLP-->  OTel Collector (otel namespace)  --> Tempo       (traces)
     app/app.py                     20-otel.yaml                    --> Prometheus  (metrics, scrapes :8889)
                                                                    Grafana reads both
   ```
   The code to read: `fleet/apps/orders-app/app/app.py` (spans and metrics),
   `fleet/apps/orders-app/templates/all.yaml` (the `OTEL_*` settings) and
   `fleet/root/templates/20-otel.yaml` (the Collector's receivers, processors, exporters).

## Lab only

Vault runs in dev mode with the token `root`, and the passwords are simple. That's fine
on a laptop, never in production.

## If something goes wrong

- **Two clusters on 8 GB:** the first one shows `0/0` with no region in `status.sh` and
  the second one times out. Delete the second one: `k3d cluster delete store-002`.
  The first one recovers on its own in a couple of minutes.
- **A link stops loading** ("can't connect"): the tunnels closed. In the `open-ui.sh`
  window press Ctrl+C, then run `./scripts/open-ui.sh store-001` again. Or open just one,
  e.g. `kubectl --context k3d-store-001 -n store-apps port-forward svc/store-app 8081:80`.
- **Something else is on a port:** Argo CD's port can be changed:
  `ARGO_PORT=8090 ./scripts/open-ui.sh store-001`.
- **Argo CD password again:**
  `kubectl --context k3d-store-001 -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo`
- **Done for the day:** just quit Docker Desktop. The cluster starts again when you reopen it.

- A third cluster never becomes ready ("Waiting for containerd startup" in
  `docker logs k3d-<name>-server-0`): the Docker VM has run out of inotify instances.
  Two clusters is plenty for this lab. Delete the extra one with `k3d cluster delete <name>`.
- An Argo CD app shows `Unknown`: in Argo CD click the app, then **Refresh > Hard Refresh**.
- Grafana trace boxes say **"Datasource tempo was not found"**: Grafana missed the Tempo
  setting (usually because the cluster was overloaded while it installed). Make Argo CD
  re-apply it, then restart Grafana and its port-forward:
  ```
  kubectl --context k3d-store-001 -n argocd annotate application monitoring argocd.argoproj.io/refresh=hard --overwrite
  kubectl --context k3d-store-001 -n monitoring rollout restart deploy/monitoring-grafana
  ```

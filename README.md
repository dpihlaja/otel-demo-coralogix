# otel-demo

The [OpenTelemetry demo](https://opentelemetry.io/docs/demo/) running on minikube (docker driver),
sending logs, metrics and traces to Coralogix (`cx498.coralogix.com`) through Coralogix's
`otel-integration` Helm chart.

## Layout

| File | What it is |
|---|---|
| `setup.sh` | Starts minikube with enough memory, creates the key secret, installs both charts |
| `port-forward.sh` | Forwards `localhost:8080` to the demo's frontend proxy (keeps reconnecting) |
| `values.yaml` | Values for `coralogix/otel-integration` (agent, cluster collector, operator) |
| `demo-values.yaml` | Values for `open-telemetry/opentelemetry-demo` |
| `.env` | Coralogix keys (gitignored, create it yourself) |

## Setup

```bash
cat > .env <<'EOF'
CORALOGIX_PRIVATE_KEY=<send-your-data key>
EOF
./setup.sh
./port-forward.sh   # shop at http://localhost:8080, also /feature and /loadgen
```

Tear down with `minikube delete`.

## How telemetry flows

```
demo services ──OTLP──▶ Coralogix agent (DaemonSet, hostPort 4317/4318 on node IP) ──▶ Coralogix
                        Coralogix cluster collector (k8s events, cluster metrics) ──▶ Coralogix
```

The demo chart's own collector is disabled: it is also a DaemonSet that claims hostPorts
4317/4318, so on a single-node cluster it blocks the Coralogix agent from scheduling.
Services find the agent through `OTEL_COLLECTOR_NAME`, which is set to the pod's
`status.hostIP`.

## Gotchas

- **minikube memory.** minikube's default 4 GiB container is far too small. The kubelet still
  reports the whole Docker VM's memory, so pods get scheduled anyway and the node thrashes
  (API server crashes, `kubectl` hangs). `setup.sh` uses `--memory=10g --cpus=6`; Docker
  Desktop needs at least ~12 GiB. Memory can't be changed on an existing cluster, so run
  `minikube delete` first.
- **`docker: command not found`.** Docker Desktop's CLI lives in `~/.docker/bin`, which
  `~/.zprofile` adds to PATH. Open a new terminal or run `exec zsh -l`.
- **First start is slow.** Every image gets pulled fresh after `minikube delete`. Pods waiting
  on `flagd`/`kafka` sit in `Init`/`PodInitializing` until those are up.

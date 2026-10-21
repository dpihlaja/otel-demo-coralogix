# otel-demo

The [OpenTelemetry demo](https://opentelemetry.io/docs/demo/) running on minikube (vfkit VM driver),
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

- **Driver: vfkit.** `setup.sh` defaults to `--driver=vfkit` (`brew install vfkit`). On a
  16 GB Mac, quit Docker Desktop first: its VM and a 10 GB minikube VM don't fit together.
  `MINIKUBE_DRIVER=docker ./setup.sh` also works.
- **No eBPF profiling locally.** Neither driver can run the Coralogix eBPF profiler. Docker
  driver: the node is a container, and the profiler's kernel self-check fails on the nested
  PID namespace ("system analysis request was not handled"). vfkit driver: the minikube ISO
  kernel is built without kprobes/ftrace ("load program: invalid argument"). It needs a node
  with a standard distro kernel (k3s on an Ubuntu VM, or managed Kubernetes).
- **minikube memory.** minikube's 4 GiB default is far too small; on the docker driver the
  kubelet even reports the whole Docker VM's memory, so the node thrashes (API server crashes,
  `kubectl` hangs). `setup.sh` uses `--memory=10g --cpus=6`. Memory can't be changed on an
  existing cluster, so run `minikube delete` first.
- **eBPF auto-instrumentation is off.** Every demo service already has OTel SDK
  instrumentation; eBPF only added duplicate spans and `IP:port` service-map nodes.
- **APM looks empty?** Check the APM environment picker: this cluster reports
  `deployment.environment.name=production`.
- **First start is slow.** Every image gets pulled fresh after `minikube delete`. Pods waiting
  on `flagd`/`kafka` sit in `Init`/`PodInitializing` until those are up.

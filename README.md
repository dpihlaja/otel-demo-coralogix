# otel-demo

The [OpenTelemetry demo](https://opentelemetry.io/docs/demo/) running on minikube (vfkit VM driver),
sending logs, metrics, traces and Kubernetes infrastructure metrics to Coralogix
(`cx498.coralogix.com`, US2) through Coralogix's `otel-integration` Helm chart, plus Coralogix RUM
in the shop's frontend.

## Deliverables

Account: <https://dpihlaja.app.cx498.coralogix.com> · Deck: [Coralogix evaluation](https://docs.google.com/presentation/d/1kRBaczyqn1Q2FFFudkNQUE6uZALAzxmxoidSXpqpUrE/edit?usp=sharing) · Written reflection: [Coralogix Onboarding Writeup](https://docs.google.com/document/d/158UCAPmFUB9eVdJbbFzXHzGEQMc7br7Ujm4qNxMpEmw/edit?usp=sharing)

| Item | In Coralogix | In this repo |
|---|---|---|
| Deployment | — | `setup.sh`, `values.yaml`, `demo-values.yaml`, `rum/` |
| Parsing rules | [Data Flow → Parsing Rules](https://dpihlaja.app.cx498.coralogix.com/rules) ("Frontend-proxy: parse Envoy logs", "Fix logRecord.body type conflict") | [`coralogix/parsing-rules.md`](coralogix/parsing-rules.md) |
| Enrichments | [Data Flow → Data Enrichment](https://dpihlaja.app.cx498.coralogix.com/enrichments) (service-catalog, product-catalog) | [`coralogix/enrichments.md`](coralogix/enrichments.md), `coralogix/*.csv` |
| Events2Metrics | [Data Flow → Events2Metrics](https://dpihlaja.app.cx498.coralogix.com/tco/metrics) (`shop_orders`, `proxy_requests`) | [`coralogix/events2metrics-and-slos.md`](coralogix/events2metrics-and-slos.md) |
| SLOs | [SLO Center](https://dpihlaja.app.cx498.coralogix.com/slo) | [`coralogix/events2metrics-and-slos.md`](coralogix/events2metrics-and-slos.md) |
| Dashboards | One per pillar, each opening on errors · latency · saturation · throughput: [Infra](https://dpihlaja.app.cx498.coralogix.com/dashboards/qzoR6PmYBR2f9ZqFJkP13) · [Requests](https://dpihlaja.app.cx498.coralogix.com/dashboards/EpGYoQkqLthy2FpVZJ2Y4) · [Workflows](https://dpihlaja.app.cx498.coralogix.com/dashboards/pbJSJ5KjkrgfW7cMhxPf2) · [Experience](https://dpihlaja.app.cx498.coralogix.com/dashboards/6Zv9SC5Su14DsfLpwOWyk) · [Business](https://dpihlaja.app.cx498.coralogix.com/dashboards/lVBBrXTKXPJxtIowPSaoj); plus a team slice, [Team Catalog: product-catalog](https://dpihlaja.app.cx498.coralogix.com/dashboards/iPpxRYWcRDpldWJ4FDevT) | `coralogix/dashboards/*.json` |
| Alerts | [Alerts](https://dpihlaja.app.cx498.coralogix.com/alerts) (7) | [`coralogix/alerts.md`](coralogix/alerts.md) |
| Written reflection | [Coralogix Onboarding Writeup](https://docs.google.com/document/d/158UCAPmFUB9eVdJbbFzXHzGEQMc7br7Ujm4qNxMpEmw/edit?usp=sharing) | — |

## Layout

| File | What it is |
|---|---|
| `setup.sh` | Starts minikube, creates the key secret, builds the RUM frontend, installs both charts |
| `values.yaml` | Values for `coralogix/otel-integration`: agent, cluster collector, and all collector-side processing (noise filters, severity, route normalization, enrichment keys, tail sampling) |
| `demo-values.yaml` | Values for `open-telemetry/opentelemetry-demo` |
| `rum/` | Frontend rebuilt with Coralogix RUM: patch on the demo's `src/frontend` + `build.sh` |
| `coralogix/` | Coralogix-side config: parsing rules, enrichments, Events2Metrics, SLOs, alerts, dashboards (`dashboards/*.json` are the Coralogix MCP dashboard documents, with their IDs) |
| `coralogix/ops-events.sh` | Deployment markers in APM, one per service per helm release (run by `setup.sh`) |
| `port-forward.sh` | Forwards `localhost:8080` to the demo's frontend proxy (keeps reconnecting) |
| `chaos.sh` | `on` / `off` / `status`: the demo's failure scenarios (flagd flags), for showing detection |

## Setup

```bash
cp .env.example .env   # fill in the keys; only CORALOGIX_PRIVATE_KEY is required
./setup.sh
./port-forward.sh      # shop at http://localhost:8080, also /feature and /loadgen
```

`ADDRESS=0.0.0.0 ./port-forward.sh` makes the shop reachable from other machines on the LAN.
Tear down with `minikube delete`.

## How telemetry flows

```
demo services ──OTLP──▶ Coralogix agent (DaemonSet, hostPort 4317/4318 on node IP) ──▶ Coralogix
                        Coralogix cluster collector (k8s events, cluster metrics) ──▶ Coralogix
browser (RUM SDK) ─────────────────────────────────────────────────────────────────▶ Coralogix
```

The demo chart's own collector is disabled: it is also a DaemonSet that claims hostPorts
4317/4318, so on a single-node cluster it blocks the Coralogix agent from scheduling.
Services find the agent through `OTEL_COLLECTOR_NAME`, which is set to the pod's
`status.hostIP`.

Span metrics are computed from 100% of spans; only exported traces are sampled, by tail sampling
in the agent: every trace with an error, slower than 2s, or started in a browser (so RUM sessions
link to complete backend traces), plus 10% of the rest. This relies on a single node (all spans of
a trace reach one agent).

## Real User Monitoring (RUM)

`setup.sh` builds the demo frontend from source (tag `3.1.0`) with the
[`@coralogix/browser`](https://www.npmjs.com/package/@coralogix/browser) SDK, inside the minikube
VM, and points the chart's `frontend` at that image. Everything else uses upstream images.

- `rum/frontend-coralogix-rum.patch` adds `utils/telemetry/CoralogixRum.ts`, wires it into
  `_app.tsx`, and passes its settings through `window.ENV` in `_document.tsx`. Application name
  and domain come from `.env` and are baked into the image; the public key comes from the
  `coralogix-rum` secret.
- RUM owns the browser's `traceparent` header, so RUM sessions link to backend traces; the demo's
  own browser tracer is skipped.
- Session replay is on, with all inputs masked. URLs are blueprinted to the same templates as
  `http.route` (`/product/{productId}`).
- Source maps are uploaded during the build with `rum-cli` (key passed as a BuildKit secret), then
  deleted from the image. The version is `3.1.0-cx.<patch hash>`, the same for the SDK and the
  source maps; changing the patch produces a new image and a new upload.

## Gotchas

- **Driver: vfkit.** `setup.sh` defaults to `--driver=vfkit` (`brew install vfkit`). On a
  16 GB Mac, quit Docker Desktop first: its VM and a 10 GB minikube VM don't fit together.
  `MINIKUBE_DRIVER=docker ./setup.sh` also works. To resume a stopped cluster, pass the driver
  again (`minikube start --driver=vfkit`): plain `minikube start` picks docker and refuses.
- **minikube memory.** minikube's 4 GiB default is far too small. `setup.sh` uses
  `--memory=10g --cpus=6`. Memory can't be changed on an existing cluster, so run
  `minikube delete` first.
- **No eBPF profiling locally.** Neither driver can run the Coralogix eBPF profiler (docker: the
  node is a container; vfkit: the minikube ISO kernel has no kprobes/ftrace). It needs a node with
  a standard distro kernel, so it is disabled in `values.yaml`.
- **eBPF auto-instrumentation is off.** Every demo service already has OTel SDK
  instrumentation; eBPF only added duplicate spans and `IP:port` service-map nodes.
- **APM looks empty?** Check the APM environment picker: this cluster reports
  `deployment.environment.name=production`.
- **First start is slow.** Every image gets pulled fresh after `minikube delete`. Pods waiting
  on `flagd`/`kafka` sit in `Init`/`PodInitializing` until those are up.

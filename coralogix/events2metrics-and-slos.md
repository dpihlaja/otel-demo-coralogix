# Events2Metrics and SLOs

Created in the Coralogix account (cx498) through the API. IDs are for lookup in
Data Flow → Events2Metrics and in the SLO Center.

## Events2Metrics

E2M names each field metric after the field key alone (no E2M prefix), so field keys are
prefixed by hand to stay clear of span metrics such as `duration_ms_*`. The event counter is
`<e2m name>_cx_docs_total`. It's a **per-interval count, not a running counter**: use
`sum_over_time()`, not `rate()` / `increase()`.

### `shop_orders` (`d3ef87b1-7891-4c4c-904c-20ec440fe5bb`)

Source: checkout's `order placed` log (subsystem `checkout`, Lucene `message:"order placed"`).
One event per order.

| Metric | From | Use |
|---|---|---|
| `shop_orders_cx_docs_total` | event count | orders |
| `shop_order_value_cx_{sum,avg,max,count}` | `attributes.demo.order.amount` | revenue, average order value |
| `shop_order_items_cx_{sum,avg}` | `attributes.demo.order.items.count` | items per order |
| `shop_order_shipping_cx_{sum,avg}` | `attributes.demo.shipping.amount` | shipping cost |

Amounts are in the shopper's currency; the log has no currency field (about 13% of orders are
in CAD). Treat revenue as approximate.

```promql
sum(sum_over_time(shop_orders_cx_docs_total[5m]))       # orders in the last 5 min
sum(sum_over_time(shop_order_value_cx_sum[1h]))         # revenue, last hour
```

### `proxy_requests` (`0918520e-96eb-45b8-8502-1b259826ec28`)

Source: Envoy access logs (subsystem `frontend-proxy`, `_exists_:envoy_access.response_code`).
Depends on the "Frontend-proxy: parse Envoy logs" parsing rule for the `envoy_access.*` fields
and on the collector for a normalized `http.route` (no product IDs or query strings).

Labels: `route`, `method`, `status_code`, `upstream`, `response_flags` (Envoy's own failure
reason: `UT` upstream timeout, `UF` upstream connect failure, `DI` injected delay, `DC` client
disconnect).

| Metric | From |
|---|---|
| `proxy_requests_cx_docs_total` | request count |
| `proxy_duration_ms_cx_{bucket,avg,max,count}` | `envoy_access.duration_ms` (buckets 10ms–30s) |
| `proxy_bytes_sent_cx_{sum,avg,max,bucket}` | `envoy_access.bytes_sent`: response size (buckets 100B–1MB) |
| `proxy_bytes_received_cx_{sum,avg,max,bucket}` | `envoy_access.bytes_received`: request body size (buckets 0–100KB) |

```promql
# 5xx share per route, last 5 min
sum by (route) (sum_over_time(proxy_requests_cx_docs_total{status_code=~"5.."}[5m]))
  / sum by (route) (sum_over_time(proxy_requests_cx_docs_total[5m]))
```

## SLOs (7-day windows, so budget burn is visible in a demo)

| SLO | ID | SLI | Target |
|---|---|---|---|
| Checkout availability | `197330c5-04ff-4537-94f6-16ffb66364a5` | APM error rate, service `checkout` | 99.5% |
| Storefront latency p95 < 1s | `81dba437-3ddf-4e79-8474-d6236cb2e642` | APM p95 latency, service `frontend`, 5-min windows ≤ 1000ms | 99% |
| Edge availability (non-5xx) | `a1d451d0-7c04-4862-b2cc-7329f88d129a` | `proxy_requests` E2M, non-5xx / all | 99.5% |

- Latency uses `frontend`, not `frontend-proxy`: the proxy also carries flagd's 10-minute
  streaming connections, which would skew any latency SLI.
- Request-based SLI queries must include a time operator; the E2M count is a gauge, so they use
  `sum(sum_over_time(...[1m]))`.

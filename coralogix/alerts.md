# Alerts

No notification destinations yet; incidents show under Alerts → Incidents.

| Alert | ID | Priority | Type | Fires when |
|---|---|---|---|---|
| Business: no orders in 15 minutes | `6b02ec46-470c-479e-aacb-44db0d89110d` | P1 | metric | `shop_orders` count < 1 over 15 min |
| Business: checkout failure rate over 5% | `4f5f5e02-86a6-40fe-8009-581cf2dc6334` | P2 | metric | PlaceOrder error share > 5% over 10 min |
| HTTP error ratio by route (4xx+5xx) | `fb437e4b-4f9b-438c-9d87-4e0d361560e9` | P2 | metric | > 5% of a route's edge requests return 4xx/5xx for all of the last 5 min |
| Performance: API p95 over 2s by route | `beaf05d1-444e-4a76-9460-8fa931cfc350` | P2 | metric | edge p95 of an `/api/*` route > 2s for 10 min |
| Infra: container restarting | `e01521b8-46c5-4ffe-ab5c-bd697951b386` | P2 | metric | any restart in 10 min, per container |
| Infra: container memory over 90% of limit | `e9c6babe-b96a-4ee0-902f-23079bd6f360` | P3 | metric | working set > 90% of limit for 10 min, per container |
| Frontend: failed browser API calls over 5% | `92d94683-5288-4f7e-9f16-c685820b60a2` | P3 | logs ratio | 4xx/5xx share of `/api/*` calls from browser user agents > 5% over 10 min |

Queries:

```promql
# Business: orders in the last 15 min (vector(0) so "no orders" is 0, not no data)
sum(sum_over_time(shop_orders_cx_docs_total[15m])) or vector(0)

# Business: checkout failure share
(sum(increase(calls_total{service_name="checkout", span_name="oteldemo.CheckoutService/PlaceOrder", span_kind="SPAN_KIND_SERVER", status_code="STATUS_CODE_ERROR"}[10m]))
  or 0 * sum(increase(calls_total{service_name="checkout", span_name="oteldemo.CheckoutService/PlaceOrder", span_kind="SPAN_KIND_SERVER"}[10m])))
/ sum(increase(calls_total{service_name="checkout", span_name="oteldemo.CheckoutService/PlaceOrder", span_kind="SPAN_KIND_SERVER"}[10m]))

# HTTP error ratio by route (proxy_requests E2M, from Envoy access logs)
(sum by (route) (sum_over_time(proxy_requests_cx_docs_total{status_code=~"[45].."}[5m]))
  or 0 * sum by (route) (sum_over_time(proxy_requests_cx_docs_total[5m])))
/ sum by (route) (sum_over_time(proxy_requests_cx_docs_total[5m]))

# Performance: API p95 by route
histogram_quantile(0.95, sum by (route, le) (sum_over_time(proxy_duration_ms_cx_bucket{route=~"/api/.*"}[5m])))

# Infra: container restarting
sum by (k8s_namespace_name, k8s_pod_name, k8s_container_name) (increase(k8s_container_restarts__restart_[10m]))

# Infra: memory vs limit
max by (k8s_namespace_name, k8s_pod_name, k8s_container_name) (container_memory_working_set_By)
  / on (k8s_namespace_name, k8s_pod_name, k8s_container_name)
  max by (k8s_namespace_name, k8s_pod_name, k8s_container_name) (k8s_container_memory_limit_By)
```

Frontend alert (Lucene, subsystem `frontend-proxy`):

- numerator: `envoy_access.user_agent:Mozilla* AND envoy_access.path:\/api\/* AND envoy_access.response_code:[400 TO 599]`
- denominator: `envoy_access.user_agent:Mozilla* AND envoy_access.path:\/api\/*`

Notes:

- **Ratios use an `or 0 * …` fallback**: with no errors the numerator has no series, so a plain
  ratio returns nothing and the alert sees "no data" instead of 0%.
- E2M counts use `sum_over_time`, not `rate`: the E2M count is a per-interval gauge.
- Undetected-values handling can't be set on a `more_than` metric alert (the API rejects it).
- **The frontend alert is a stand-in for a true RUM alert.** RUM events live only in the
  `rum.events` dataset (not logs, no metrics), and alerting on a dataset needs DataPrime
  ("analytics") alerts, which this account doesn't have: the API returns 412 "enable the
  `alerts-dataprime` feature". Once support enables it, this is the RUM version (analytics
  threshold, 10 min, `useRowsAsPermutations`, target `failure_rate` > 0.05):

  ```
  source rum.events | filter $l.applicationName == 'Web-Client' && $d.event_context.type == 'network-request'
  | groupby $d.network_request_context.fragments:string as path
    aggregate sum(if($d.network_request_context.status_code:number >= 400, 1, 0)) as failed, count() as total
  | filter total >= 10 | create failure_rate from failed / total
  ```
- The performance alert's inferred group keys include `le`; the API rejects an explicit
  `["route"]`. Harmless: `histogram_quantile` drops `le`, so incidents are per route.
- Envoy response code `0` (client closed the connection, e.g. a load-generator tab) is outside
  400–599, so it doesn't count as a failure.

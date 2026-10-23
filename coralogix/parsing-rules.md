# Coralogix parsing rules

Managed in the Coralogix UI/API (Data Flow → Parsing Rules). Evaluation order matters:

| # | Rule group | Scope | What it does |
|---|---|---|---|
| 1 | Frontend-proxy: parse Envoy logs | all (regexes only match Envoy's formats) | Access log line → `logRecord.envoy_access.*`; server log line → `logRecord.envoy.*` |
| 2 | Fix logRecord.body type conflict | all | String bodies → `message`, map bodies → `body_map` (avoids a mapping exception) |
| 3 | k8s Opentelemetry parsing | all | Coralogix extension pack |
| 4 | Severity Rules | all | Default severity extraction |

Rule 1 must run before rule 2, because rule 2 renames `logRecord.body`.

**Parse rules see the field JSON-escaped.** In `logRecord.body` a quote is `\"` and a newline is
the two characters `\n`, so the regexes below match `\\"` and an optional trailing `\\n`. A regex
written for the raw Envoy line (bare `"`) never matches.

Severity for access logs (5xx → Error, 4xx → Warning) is set in the collector
(`transform/log_severity` in `values.yaml`), not here.

The k8s extension pack then flattens `logRecord.*` to the root, so in Explore the fields are
`$d.envoy_access.*`, `$d.envoy.*`, `$d.attributes[...]` and `$d.message` (no `logRecord.` prefix).

## Envoy access log fields (`$d.envoy_access`)

`start_time, method, path, protocol, response_code, response_flags, response_code_details,
connection_termination_details, upstream_transport_failure_reason, bytes_received, bytes_sent,
duration_ms, upstream_service_time_ms, x_forwarded_for, user_agent, request_id, authority,
upstream_host, upstream_cluster, upstream_local_address, downstream_local_address,
downstream_remote_address, requested_server_name, route_name`

Regex (Envoy's default access log format):

```
^\[(?P<start_time>[^\]]+)\] \\"(?P<method>[A-Z]+) (?P<path>\S*) (?P<protocol>[^\\"]*)\\" (?P<response_code>\d+) (?P<response_flags>\S+) (?P<response_code_details>\S+) (?P<connection_termination_details>\S+) \\"(?P<upstream_transport_failure_reason>[^\\"]*)\\" (?P<bytes_received>\d+) (?P<bytes_sent>\d+) (?P<duration_ms>\d+) (?P<upstream_service_time_ms>\S+) \\"(?P<x_forwarded_for>[^\\"]*)\\" \\"(?P<user_agent>[^\\"]*)\\" \\"(?P<request_id>[^\\"]*)\\" \\"(?P<authority>[^\\"]*)\\" \\"(?P<upstream_host>[^\\"]*)\\" (?P<upstream_cluster>\S+) (?P<upstream_local_address>\S+) (?P<downstream_local_address>\S+) (?P<downstream_remote_address>\S+) (?P<requested_server_name>\S+) (?P<route_name>[^\s\\]+)(?:\\n)?\s*$
```

## Envoy server log fields (`$d.envoy`)

```
^\[(?P<timestamp>[^\]]+)\]\[(?P<thread>\d+)\]\[(?P<level>\w+)\]\[(?P<component>[^\]]+)\] \[(?P<source>[^\]]+)\] (?P<message>[\s\S]*?)(?:\\n)?\s*$
```

## Notes

- The trial account caps the total number of rules; the k8s extension pack uses most of them.
- frontend (Next.js) logs need no rule: they arrive over OTLP with `url.path`,
  `http.request.method`, etc. already in `logRecord.attributes`.
- frontend logs also get `http.route` / `http.endpoint` attributes from the collector.
- Normalized `http.route` / `http.endpoint` for frontend and frontend-proxy is done in the collector (see `values.yaml`,
  `spanMetrics.transformStatements`), because parsing rules only apply to logs, not spans.

## Reserved fields (Data Flow → Schema Manager → Reserved Fields)

The frequent-search logs index maps at most 1,000 fields per daily index (resets 00:00 UTC),
first come, first served. Fields that arrive after the cap are stored but can't be filtered,
grouped or aggregated. Reserve the fields we build on so they always get a slot:

| Field | Type |
|---|---|
| `attributes.http.endpoint` | string |
| `attributes.http.route` | string |
| `attributes.http.request.method` | string |
| `attributes.http.response.status_code` | number |
| `envoy_access.method` | string |
| `envoy_access.path` | string |
| `envoy_access.response_code` | number |
| `envoy_access.response_flags` | string |
| `envoy_access.duration_ms` | number |
| `envoy_access.upstream_service_time_ms` | number |
| `envoy_access.bytes_sent` | number |
| `envoy_access.upstream_cluster` | string |
| `envoy_access.request_id` | string |

After saving, use the once-per-day manual index reset so they apply immediately instead of at
the next midnight split. Check usage under Settings → Mapping Stats.

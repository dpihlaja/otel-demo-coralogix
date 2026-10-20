# Coralogix parsing rules

Managed in the Coralogix UI/API (Data Flow → Parsing Rules). Evaluation order matters:

| # | Rule group | Scope | What it does |
|---|---|---|---|
| 1 | Frontend-proxy: parse Envoy logs | subsystem `frontend-proxy` | Access log line → `logRecord.envoy_access.*`; server log line → `logRecord.envoy.*` |
| 2 | Fix logRecord.body type conflict | all | String bodies → `message`, map bodies → `body_map` (avoids a mapping exception) |
| 3 | k8s Opentelemetry parsing | all | Coralogix extension pack |
| 4 | Severity Rules | all | Default severity extraction |

Rule 1 must run before rule 2, because rule 2 renames `logRecord.body`.

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
^\[(?P<start_time>[^\]]+)\] "(?P<method>[A-Z]+) (?P<path>\S*) (?P<protocol>[^"]*)" (?P<response_code>\d+) (?P<response_flags>\S+) (?P<response_code_details>\S+) (?P<connection_termination_details>\S+) "(?P<upstream_transport_failure_reason>[^"]*)" (?P<bytes_received>\d+) (?P<bytes_sent>\d+) (?P<duration_ms>\d+) (?P<upstream_service_time_ms>\S+) "(?P<x_forwarded_for>[^"]*)" "(?P<user_agent>[^"]*)" "(?P<request_id>[^"]*)" "(?P<authority>[^"]*)" "(?P<upstream_host>[^"]*)" (?P<upstream_cluster>\S+) (?P<upstream_local_address>\S+) (?P<downstream_local_address>\S+) (?P<downstream_remote_address>\S+) (?P<requested_server_name>\S+) (?P<route_name>\S+)\s*$
```

## Envoy server log fields (`$d.envoy`)

```
^\[(?P<timestamp>[^\]]+)\]\[(?P<thread>\d+)\]\[(?P<level>\w+)\]\[(?P<component>[^\]]+)\] \[(?P<source>[^\]]+)\] (?P<message>[\s\S]*?)\s*$
```

## Notes

- The trial account caps the total number of rules; the k8s extension pack uses most of them.
- frontend (Next.js) logs need no rule: they arrive over OTLP with `url.path`,
  `http.request.method`, etc. already in `logRecord.attributes`.
- frontend logs also get `http.route` / `http.endpoint` attributes from the collector.
- Normalized `http.route` / `http.endpoint` for frontend and frontend-proxy is done in the collector (see `values.yaml`,
  `spanMetrics.transformStatements`), because parsing rules only apply to logs, not spans.

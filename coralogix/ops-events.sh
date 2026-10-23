#!/usr/bin/env zsh
# Send one Coralogix ops event per demo service for the current helm release, so APM shows a
# deployment marker (Annotations) for each service. Run by setup.sh after the demo install.
# Requires CORALOGIX_OPS_EVENTS_KEY in .env: a Send-Your-Data key with the "OpsEvents" role
# preset (other keys get 403). Without it the script prints a note and exits.
set -euo pipefail
cd "${0:A:h}/.."

[[ -f .env ]] && set -a && source .env && set +a
if [[ -z "${CORALOGIX_OPS_EVENTS_KEY:-}" ]]; then
  echo "ops-events: CORALOGIX_OPS_EVENTS_KEY not set, skipping deployment events"
  exit 0
fi

# cx498 = US2. Must match the agent's deployment.environment.name (values.yaml).
OPS_EVENTS_URL="${CORALOGIX_OPS_EVENTS_URL:-https://api.us2.coralogix.com/v1/ops-events}"
ENVIRONMENT="${CORALOGIX_ENVIRONMENT:-production}"
RELEASE=my-otel-demo
NAMESPACE=default

release=$(helm list -n "$NAMESPACE" -f "^${RELEASE}\$" -o json | jq -c '.[0]')
revision=$(jq -r .revision <<<"$release")
chart=$(jq -r .chart <<<"$release")
now=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# One event per instrumented deployment. service.name = the component label (what the demo
# passes as OTEL_SERVICE_NAME); version = service.version from OTEL_RESOURCE_ATTRIBUTES,
# falling back to the image tag.
kubectl get deploy -n "$NAMESPACE" -l app.kubernetes.io/part-of=opentelemetry-demo -o json | jq -c '
  .items[]
  | .spec.template.spec.containers[0] as $c
  | ([$c.env[]? | select(.name == "OTEL_RESOURCE_ATTRIBUTES") | .value][0] // "") as $attrs
  | select([$c.env[]? | .name] | index("OTEL_SERVICE_NAME"))
  | {
      service: .metadata.labels["app.kubernetes.io/component"],
      image: $c.image,
      version: (($attrs | capture("service\\.version=(?<v>[^,]+)").v) // ($c.image | split(":") | last))
    }' |
while read -r svc; do
  name=$(jq -r .service <<<"$svc")
  version=$(jq -r .version <<<"$svc")
  # Helm isn't one of the CD_SYSTEM_* values, so this is a custom event (listed under
  # "Custom events" in APM annotations) with the release details in attributes.additional.
  body=$(jq -n --arg ts "$now" --arg name "$name" --arg env "$ENVIRONMENT" \
    --arg version "$version" --arg image "$(jq -r .image <<<"$svc")" \
    --arg release "$RELEASE" --arg revision "$revision" --arg chart "$chart" '{
      opsEvent: {
        timestamp: $ts,
        description: "\($name) \($version) deployed (helm \($release) rev \($revision))",
        attributes: {
          service: { name: $name },
          environment: $env,
          additional: { cdSystem: "helm", release: $release, revision: $revision,
                        chart: $chart, image: $image, version: $version }
        },
        customEvent: {}
      }
    }')
  if curl -sS --fail-with-body -o /dev/null -X POST "$OPS_EVENTS_URL" \
      -H "Authorization: Bearer $CORALOGIX_OPS_EVENTS_KEY" -H 'Content-Type: application/json' \
      --data-binary "$body"; then
    echo "ops-events: $name $version"
  else
    echo "ops-events: failed for $name" >&2
  fi
done

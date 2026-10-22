#!/usr/bin/env zsh
# Rebuild the minikube cluster and install the OTel demo + Coralogix otel-integration.
# Requires: Docker Desktop running, CORALOGIX_PRIVATE_KEY exported (Send-Your-Data key).
set -euo pipefail
cd "${0:A:h}"

export PATH="$PATH:$HOME/.docker/bin"

[[ -f .env ]] && set -a && source .env && set +a
: "${CORALOGIX_PRIVATE_KEY:?set CORALOGIX_PRIVATE_KEY (Send-Your-Data API key) in .env}"
: "${CORALOGIX_API_KEY:=$CORALOGIX_PRIVATE_KEY}"

# vfkit runs the node as a real VM, which the eBPF profiler needs (on the docker driver the
# node is a container and the profiler can't start). Quit Docker Desktop first on a 16 GB Mac.
# MINIKUBE_DRIVER=docker still works for everything except profiling.
MINIKUBE_DRIVER="${MINIKUBE_DRIVER:-vfkit}"
# minikube's 4 GiB default is far too small for the demo + Coralogix.
MINIKUBE_MEMORY="${MINIKUBE_MEMORY:-10g}"
MINIKUBE_CPUS="${MINIKUBE_CPUS:-6}"

if ! minikube status >/dev/null 2>&1; then
  minikube start --driver="$MINIKUBE_DRIVER" --memory="$MINIKUBE_MEMORY" --cpus="$MINIKUBE_CPUS"
fi

helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts >/dev/null 2>&1 || true
helm repo add coralogix https://cgx.jfrog.io/artifactory/coralogix-charts-virtual >/dev/null 2>&1 || true
helm repo update >/dev/null

kubectl create namespace coralogix --dry-run=client -o yaml | kubectl apply -f -
kubectl create secret generic coralogix-keys -n coralogix \
  --from-literal=PRIVATE_KEY="$CORALOGIX_PRIVATE_KEY" \
  --dry-run=client -o yaml | kubectl apply -f -

# Coralogix first, so the agent owns hostPorts 4317/4318 before demo apps start sending.
helm upgrade --install otel-coralogix-integration coralogix/otel-integration \
  --version 0.0.361 -n coralogix -f values.yaml \
  --set coralogix-operator.secret.data.apiKey="$CORALOGIX_API_KEY" \
  --wait --timeout 10m

# Coralogix RUM: public key as a secret, frontend image built from source inside minikube.
if [[ -n "${CORALOGIX_RUM_KEY:-}" ]]; then
  kubectl create secret generic coralogix-rum -n default \
    --from-literal=PUBLIC_KEY="$CORALOGIX_RUM_KEY" \
    --dry-run=client -o yaml | kubectl apply -f -
fi
RUM_TAG=$(rum/build.sh --print-tag)
if ! minikube image ls | grep -q "otel-demo-frontend-rum:${RUM_TAG}"; then
  rum/build.sh
fi

helm upgrade --install my-otel-demo open-telemetry/opentelemetry-demo \
  --version 0.42.4 -f demo-values.yaml \
  --set components.frontend.imageOverride.tag="$RUM_TAG" --timeout 15m

# Deployment markers in Coralogix APM (needs CORALOGIX_OPS_EVENTS_KEY; skipped otherwise).
coralogix/ops-events.sh

kubectl get pods -A

#!/usr/bin/env zsh
# Rebuild the minikube cluster and install the OTel demo + Coralogix otel-integration.
# Requires: Docker Desktop running, CORALOGIX_PRIVATE_KEY exported (Send-Your-Data key).
set -euo pipefail
cd "${0:A:h}"

export PATH="$PATH:$HOME/.docker/bin"

[[ -f .env ]] && set -a && source .env && set +a
: "${CORALOGIX_PRIVATE_KEY:?set CORALOGIX_PRIVATE_KEY (Send-Your-Data API key) in .env}"
: "${CORALOGIX_API_KEY:=$CORALOGIX_PRIVATE_KEY}"

# minikube defaults to a 4 GiB container, far less than the demo + Coralogix need.
# Docker Desktop's VM has ~12 GiB; leave ~2 GiB for Docker itself.
MINIKUBE_MEMORY="${MINIKUBE_MEMORY:-10g}"
MINIKUBE_CPUS="${MINIKUBE_CPUS:-6}"

if ! minikube status >/dev/null 2>&1; then
  minikube start --driver=docker --memory="$MINIKUBE_MEMORY" --cpus="$MINIKUBE_CPUS"
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

helm upgrade --install my-otel-demo open-telemetry/opentelemetry-demo \
  --version 0.42.4 -f demo-values.yaml --timeout 15m

kubectl get pods -A

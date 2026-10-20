#!/usr/bin/env zsh
# Expose the demo at http://localhost:8080 (shop, /feature, /loadgen).
# minikube's docker driver on macOS isn't routable from the host, so a port-forward is required.
# Loops because port-forwards die whenever the target pod restarts.
export PATH="$PATH:$HOME/.docker/bin"
PORT="${PORT:-8080}"
while true; do
  kubectl port-forward svc/frontend-proxy "$PORT":8080
  echo "port-forward exited, reconnecting in 2s..." >&2
  sleep 2
done

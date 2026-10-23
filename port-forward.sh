#!/usr/bin/env zsh
# Expose the demo at http://localhost:8080 (shop, /feature, /loadgen).
# The minikube node isn't routable from the host, so a port-forward is required.
# Loops because port-forwards die whenever the target pod restarts.
#
# kubectl only listens on 127.0.0.1 by default. To reach the shop from other machines
# on the LAN (http://<this-mac's-ip>:8080), run:  ADDRESS=0.0.0.0 ./port-forward.sh
# That also exposes the flag UI (/feature) and load generator (/loadgen) to the LAN.
PORT="${PORT:-8080}"
ADDRESS="${ADDRESS:-127.0.0.1}"
while true; do
  kubectl port-forward --address "$ADDRESS" svc/frontend-proxy "$PORT":8080
  echo "port-forward exited, reconnecting in 2s..." >&2
  sleep 2
done

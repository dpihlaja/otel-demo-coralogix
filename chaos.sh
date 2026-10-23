#!/usr/bin/env zsh
# Turn the demo's failure scenarios (flagd feature flags) on or off.
#   ./chaos.sh on      set the scenario flags below
#   ./chaos.sh off     set every flag to "off" (healthy baseline)
#   ./chaos.sh status  list flags that aren't off
# Edits the same file as the flag UI at /feature (shared with flagd, which reloads it on change).
#
# Some flags are targeted rather than set by defaultVariant: productCatalogFailure ships as
# {"if": [<product_id == OLJCESPC7Z>, "off", "off"]} and the UI turns it on by changing the
# first branch. For those, "on" sets that branch and "off" resets every branch.
set -euo pipefail

# flag=variant set by "on".
SCENARIO=(
  adFailure=on
  adHighCpu=on
  cartFailure=90%
  emailMemoryLeak=1000x
  failedReadinessProbe=on
  imageSlowLoad=10sec
  intlShippingSlowdown=10sec
  kafkaQueueProblems=on
  paymentFailure=90%
  paymentUnreachable=on
  productCatalogFailure=on
  productCatalogLockContention=on
  recommendationCacheFailure=on
)

FILE=/app/data/demo.flagd.json
read_flags() { kubectl exec deploy/flagd -c flagd-ui -- cat "$FILE"; }
write_flags() { kubectl exec -i deploy/flagd -c flagd-ui -- sh -c "cat > $FILE"; }
# A flag is "on" when its default isn't off, or a targeting branch picks something other than off.
show() {
  read_flags | jq -r '.flags | to_entries[]
    | (.value.targeting.if // [null, "off", "off"]) as $if
    | if .value.defaultVariant != "off" then "\(.key)=\(.value.defaultVariant)"
      elif ($if[1] != "off" or $if[2] != "off") then "\(.key)=\($if[1]) (targeted)"
      else empty end'
}

case "${1:-}" in
  off|on)
    # Read fully before writing: a read | write pipeline would truncate the file mid-read.
    current=$(read_flags)
    if [[ $1 == off ]]; then
      new=$(jq '.flags |= map_values(
        .defaultVariant = "off"
        | if (.targeting.if | type) == "array" then .targeting.if[1] = "off" | .targeting.if[2] = "off" else . end)' <<<"$current")
    else
      sets=$(printf '%s\n' "${SCENARIO[@]}" | jq -R 'split("=") | {(.[0]): .[1]}' | jq -s add)
      # Fail on a typo'd flag or variant rather than writing a file flagd rejects.
      new=$(jq --argjson s "$sets" '
        reduce ($s | to_entries[]) as $e (.;
          if (.flags[$e.key].variants // {} | has($e.value) | not) then
            error("unknown flag/variant: \($e.key)=\($e.value)")
          elif (.flags[$e.key].targeting.if | type) == "array" then .flags[$e.key].targeting.if[1] = $e.value
          else .flags[$e.key].defaultVariant = $e.value end)' <<<"$current")
    fi
    write_flags <<<"$new"
    show
    [[ $1 == off ]] && echo "all flags off" || true ;;
  status) show ;;
  *) echo "usage: $0 on|off|status" >&2; exit 1 ;;
esac

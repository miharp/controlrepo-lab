#!/bin/bash
# A disposable x86 Hetzner server that runs a voxpupuli/controlrepo node
# role in public: real DNS names, real ACME, real federation. The Vagrant
# lab next door cannot do those three; everything else is the same loop.
#
#   ./lab.sh address     # reserve the address only, so DNS can be set up first
#   ./lab.sh up          # create the server (address, firewall and key persist)
#   ./lab.sh dns         # the record to create, and whether both names resolve
#   ./lab.sh converge    # sync the controlrepo checkout and apply it
#   ./lab.sh smoke       # client-flow test over TLS from this machine (--from-server: from the server)
#   ./lab.sh federation  # ask the public federation tester about the lab
#   ./lab.sh ssh [cmd]   # shell on the server (user lab, sudo without password)
#   ./lab.sh status      # what exists and what it costs to keep
#   ./lab.sh down        # delete the server; billing for it stops
#   ./lab.sh down --all  # also release the address, firewall and key
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
tf="$here/terraform"
node_fqdn="matrix01.voxpupu.li"
overrides="$here/overrides/${node_fqdn}.yaml"
state="$here/.lab-state"

[ -f "$here/lab.env" ] || { echo "copy lab.env.example to lab.env and fill it in" >&2; exit 1; }
set -a; . "$here/lab.env"; set +a
for v in HCLOUD_TOKEN LAB_SERVER_NAME LAB_MATRIX_DOMAIN; do
  [ -n "${!v:-}" ] || { echo "lab.env: $v is empty" >&2; exit 1; }
done
case "$LAB_SERVER_NAME $LAB_MATRIX_DOMAIN" in
  *voxpupuli.party*|*voxpupu.li*) echo "lab.env: use your own names, not Vox Pupuli's" >&2; exit 1 ;;
esac
controlrepo="$(cd "$here" && cd "${LAB_CONTROLREPO:-../../voxpupuli_controlrepo}" && pwd)"
pubkey="${LAB_SSH_PUBKEY:-$HOME/.ssh/id_ed25519.pub}"
pubkey="${pubkey/#\~/$HOME}"

export TF_VAR_hcloud_token="$HCLOUD_TOKEN"
TF_VAR_ssh_public_key="$(cat "$pubkey")"
export TF_VAR_ssh_public_key
export TF_VAR_node_fqdn="$node_fqdn"
[ -z "${LAB_LOCATION:-}" ] || export TF_VAR_location="$LAB_LOCATION"
[ -z "${LAB_SERVER_TYPE:-}" ] || export TF_VAR_server_type="$LAB_SERVER_TYPE"

terraform_() { terraform -chdir="$tf" "$@"; }
ip() { terraform_ output -raw ipv4; }
ssh_() {
  ssh -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile="$here/.known_hosts" \
    -o LogLevel=ERROR -o ConnectTimeout=10 -o ServerAliveInterval=5 -o ServerAliveCountMax=3 \
    "lab@$(ip)" "$@"
}
# SSH is only open to the address this machine has right now.
admin_cidrs() {
  local me; me="$(curl -fsS -4 https://api.ipify.org)"
  export TF_VAR_admin_cidrs="[\"${me}/32\"]"
}
# Names from lab.env plus fresh secrets, once; the result is yours to edit.
render_overrides() {
  [ -f "$overrides" ] && return
  local line
  while IFS= read -r line; do
    line="${line//@SERVER_NAME@/$LAB_SERVER_NAME}"
    line="${line//@MATRIX_DOMAIN@/$LAB_MATRIX_DOMAIN}"
    line="${line//@RANDOM@/$(openssl rand -hex 32)}"
    printf '%s\n' "$line"
  done < "${overrides}.tmpl" > "$overrides"
  chmod 600 "$overrides"
  echo "wrote $overrides"
}
# Ask the zone's own nameserver, not the local resolver: a resolver that
# was asked before the record existed keeps saying "no such name" for up
# to the zone's negative TTL, and ACME does not use this machine's cache.
auth_ns() {
  local d="$1" ns
  while [[ "$d" == *.* ]]; do
    ns="$(dig +short NS "$d" | head -1)"
    [ -n "$ns" ] && { echo "$ns"; return; }
    d="${d#*.}"
  done
}
lookup() { dig +short A "$1" "@$(auth_ns "$1")" | tail -1; }
resolves() { [ "$(lookup "$1")" = "$2" ]; }
dns() {
  local addr rc=0; addr="$(ip)"
  for name in "$LAB_SERVER_NAME" "$LAB_MATRIX_DOMAIN"; do
    if resolves "$name" "$addr"; then
      echo "ok       $name  A  $addr"
    else
      echo "MISSING  $name  A  $addr   (resolves to: $(lookup "$name"))"; rc=1
    fi
  done
  # One wildcard under LAB_WILDCARD_PARENT covers both names, and the next
  # run's names too, with a single record made by hand.
  if [ $rc -ne 0 ] && [ -n "${LAB_WILDCARD_PARENT:-}" ]; then
    echo "one record covers both:  *.${LAB_WILDCARD_PARENT}  A  $addr"
  fi
  return $rc
}

cmd="${1:-}"; shift || true
case "$cmd" in
  up)
    admin_cidrs
    terraform_ init -input=false >/dev/null
    terraform_ apply -input=false -auto-approve -var server_enabled=true
    render_overrides
    echo; dns || echo "create the records above, then: ./lab.sh converge"
    ;;
  address)
    admin_cidrs
    terraform_ init -input=false >/dev/null
    terraform_ apply -input=false -auto-approve -var server_enabled=false
    echo; dns || true
    ;;
  down)
    admin_cidrs
    if [ "${1:-}" = "--all" ]; then
      terraform_ destroy -input=false -auto-approve
      rm -f "$state" "$here/.known_hosts"
    else
      terraform_ apply -input=false -auto-approve -var server_enabled=false
      rm -f "$here/.known_hosts"
      echo "server deleted; the address $(ip) is kept (about 0.50 EUR a month). ./lab.sh down --all releases it."
    fi
    ;;
  dns)
    dns
    ;;
  converge)
    [ -n "${LAB_ACME_EMAIL:-}" ] || { echo "lab.env: LAB_ACME_EMAIL is empty" >&2; exit 1; }
    dns || { echo "ACME cannot work until both names resolve to the server" >&2; exit 1; }
    render_overrides
    ssh_ 'sudo install -d -o lab /opt/lab /opt/lab/controlrepo /opt/lab/scripts /opt/lab/overrides'
    rsh="ssh -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=$here/.known_hosts -o LogLevel=ERROR"
    rsync -a --delete -e "$rsh" --exclude='.git' --exclude='vagrant' --exclude='.vendor' \
      --exclude='site/profiles/vendor' --exclude='site/profiles/spec/fixtures' --exclude='site/profiles/.bundle' \
      "$controlrepo/" "lab@$(ip):/opt/lab/controlrepo/"
    rsync -a --delete -e "$rsh" "$here/scripts/" "lab@$(ip):/opt/lab/scripts/"
    rsync -a --delete -e "$rsh" "$overrides" "lab@$(ip):/opt/lab/overrides/"
    ssh_ "[ -f /opt/lab/.bootstrapped ] || sudo /opt/lab/scripts/bootstrap"
    # The apply runs as its own unit and is followed from short-lived
    # connections: the first time nftables loads, it rejects the replies
    # of every SSH session that was already open, so a session that ran
    # the apply directly goes silent halfway through.
    ssh_ "sudo systemctl reset-failed lab-apply 2>/dev/null; sudo systemd-run --quiet --unit=lab-apply --collect \
      -p StandardOutput=truncate:/opt/lab/apply.log -p StandardError=inherit \
      /opt/lab/scripts/apply '$LAB_ACME_EMAIL'"
    seen=0
    while :; do
      sleep 5
      out="$(ssh_ "sudo tail -n +$((seen + 1)) /opt/lab/apply.log; systemctl is-active --quiet lab-apply || echo __LAB_APPLY_DONE__" 2>/dev/null)" || continue
      [ -z "$out" ] && continue
      lines="$(printf '%s\n' "$out" | grep -v '^__LAB_APPLY_DONE__$' || true)"
      if [ -n "$lines" ]; then printf '%s\n' "$lines"; seen=$((seen + $(printf '%s\n' "$lines" | wc -l))); fi
      case "$out" in *__LAB_APPLY_DONE__*) break ;; esac
    done
    ssh_ "sudo tail -n +$((seen + 1)) /opt/lab/apply.log" || true
    ssh_ "sudo grep -q '^puppet apply exit code: [02]\$' /opt/lab/apply.log"
    ;;
  smoke)
    # Two throwaway accounts with a password that only lives in .lab-state.
    [ -f "$state" ] || { umask 077; echo "SMOKE_PASSWORD=$(openssl rand -hex 16)" > "$state"; }
    # shellcheck disable=SC1090
    . "$state"
    for u in alice bob; do
      a=--no-admin; [ "$u" = alice ] && a=--admin
      ssh_ "sudo docker exec synapse-main register_new_matrix_user -c /config/homeserver.yaml -u $u -p '$SMOKE_PASSWORD' $a http://localhost:8008 2>&1 | tail -1" || true
    done
    env="SMOKE_BASE=https://$LAB_MATRIX_DOMAIN SMOKE_HOST=$LAB_MATRIX_DOMAIN SMOKE_SERVER_NAME=$LAB_SERVER_NAME SMOKE_PASSWORD=$SMOKE_PASSWORD SMOKE_ADMIN_EXPECT=403"
    if [ "${1:-}" = "--from-server" ]; then
      # Same public URLs, but resolved and requested by the server: for
      # when this machine's resolver still has the names cached as missing.
      ssh_ "$env python3 -" < "$here/scripts/smoke.py"
    else
      # shellcheck disable=SC2086
      env $env python3 "$here/scripts/smoke.py"
    fi
    ;;
  federation)
    curl -fsS "https://federationtester.matrix.org/api/report?server_name=$LAB_SERVER_NAME" |
      python3 -c 'import json,sys; r=json.load(sys.stdin); print("FederationOK:", r.get("FederationOK")); [print(" ", k, v.get("Checks", {}).get("AllChecksOK")) for k, v in r.get("ConnectionReports", {}).items()]; [print("  error:", k, v) for k, v in r.get("ConnectionErrors", {}).items()]'
    ;;
  ssh)
    ssh_ "$@"
    ;;
  status)
    terraform_ output 2>/dev/null || true
    HCLOUD_TOKEN="$HCLOUD_TOKEN" hcloud server list -o columns=name,status,ipv4,type,age 2>/dev/null || true
    ;;
  *)
    sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'
    exit 1
    ;;
esac

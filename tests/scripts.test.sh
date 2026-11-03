#!/usr/bin/env bash
# power-shutdown and power-wake: targets stop in order then this host; wake only above the charge threshold.
# Stubs ssh, ping, logger, upsc, wakeonlan and the poweroff on PATH; nothing leaves the machine.
# shellcheck disable=SC2016  # stub bodies expand at their own run time
set -euo pipefail

REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
F=$REPO/files
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
mkdir "$WORK/bin"
for c in ssh logger wakeonlan poweroff; do printf '#!/bin/sh\necho "%s $*" >> "$STUB_DIR/calls"\n' "$c" > "$WORK/bin/$c"; done
printf '#!/bin/sh\nexit 1\n' > "$WORK/bin/ping"
printf '#!/bin/sh\ncat "$STUB_DIR/charge"\n' > "$WORK/bin/upsc"
chmod +x "$WORK/bin/"*
export STUB_DIR=$WORK PATH="$WORK/bin:$PATH" POWER_POWEROFF="poweroff now" POWER_WAKE_POLL_SEC=0
fails=0
ok() { echo "ok   $1"; }
ko() { echo "FAIL $1" >&2; fails=$((fails + 1)); }
calls() { grep -E "^($1) " "$WORK/calls" | cut -d' ' -f1-2 | paste -sd' ' || true; }

printf 'wait 1\ntarget hv02 2222 shutdown\n# comment\ntarget hv01 2222 shutdown\n' > "$WORK/shutdown.conf"
: > "$WORK/calls"; POWER_SHUTDOWN_CONF=$WORK/shutdown.conf "$F/power-shutdown" > /dev/null
order=$(grep -oE '^(ssh .*@hv0[12]|poweroff)' "$WORK/calls" | sed 's/.*@//' | paste -sd,)
if [[ $order == hv02,hv01,poweroff ]]; then ok "targets in order, then this host"; else ko "shutdown order ($order)"; fi
if grep -q -- '-p 2222' "$WORK/calls"; then ok "the target's port is used"; else ko "port"; fi

printf 'wait 1\n' > "$WORK/shutdown.conf"
: > "$WORK/calls"; POWER_SHUTDOWN_CONF=$WORK/shutdown.conf "$F/power-shutdown" > /dev/null
if [[ $(calls 'ssh|poweroff') == "poweroff now" ]]; then ok "no target: this host only"; else ko "empty target list"; fi

printf 'ups ups-cluster\ncharge 50\ntimeout 1\nbroadcast\nmac aa:bb:cc:dd:ee:01\nmac aa:bb:cc:dd:ee:02\n' > "$WORK/wake.conf"
echo 80 > "$WORK/charge"; : > "$WORK/calls"
"$F/power-wake" "$WORK/wake.conf" > /dev/null
if grep -qx 'wakeonlan aa:bb:cc:dd:ee:01 aa:bb:cc:dd:ee:02' "$WORK/calls"; then ok "charge above the threshold wakes every MAC"; else ko "wake above threshold"; fi
echo 49.5 > "$WORK/charge"; : > "$WORK/calls"
if "$F/power-wake" "$WORK/wake.conf" > /dev/null 2>&1; then ko "below the threshold exits 0"; else ok "below the threshold fails after the timeout"; fi
if grep -q wakeonlan "$WORK/calls"; then ko "woke below the threshold"; else ok "nothing woken below the threshold"; fi
printf 'ups ups-cluster\ncharge 50\ntimeout 1\nbroadcast 192.0.2.255\nmac aa:bb:cc:dd:ee:01\n' > "$WORK/wake.conf"
echo 50 > "$WORK/charge"; : > "$WORK/calls"
"$F/power-wake" "$WORK/wake.conf" > /dev/null
if grep -qx 'wakeonlan -i 192.0.2.255 aa:bb:cc:dd:ee:01' "$WORK/calls"; then ok "at the threshold, to the broadcast address"; else ko "broadcast"; fi
printf 'ups ups-cluster\ncharge 50\n' > "$WORK/wake.conf"; : > "$WORK/calls"
"$F/power-wake" "$WORK/wake.conf" > /dev/null
if [[ ! -s $WORK/calls ]]; then ok "no MAC: nothing to do"; else ko "no MAC"; fi

if [[ $fails -gt 0 ]]; then echo "$fails failed" >&2; exit 1; fi
echo "all passed"

#!/usr/bin/env bash
# power-shutdown, power-wake, power-notify, power-upssched and nut-check: targets stop in order then this host; wake only above the charge
# threshold, delay apart; events reach upssched (timer) and the command (filtered).
# Stubs ssh, ping, logger, upsc, wakeonlan, upssched and the poweroff on PATH; nothing leaves the machine.
# shellcheck disable=SC2016  # stub bodies expand at their own run time
set -euo pipefail

REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
F=$REPO/files
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
mkdir "$WORK/bin"
for c in logger wakeonlan poweroff upssched sudo; do printf '#!/bin/sh\necho "%s $*" >> "$STUB_DIR/calls"\n' "$c" > "$WORK/bin/$c"; done
# ssh fails for a host named down-ssh; ping exits with the code in $STUB_DIR/ping (1 = no reply)
printf '#!/bin/sh\necho "ssh $*" >> "$STUB_DIR/calls"\ncase "$*" in *down-ssh*) exit 255 ;; esac\n' > "$WORK/bin/ssh"
printf '#!/bin/sh\nexit "$(cat "$STUB_DIR/ping")"\n' > "$WORK/bin/ping"
echo 1 > "$WORK/ping"
printf '#!/bin/sh\necho "upsc $*" >> "$STUB_DIR/calls"\ncase "$2" in ups.status) [ -s "$STUB_DIR/status" ] || exit 1; cat "$STUB_DIR/status" ;; *) cat "$STUB_DIR/charge" ;; esac\n' > "$WORK/bin/upsc"
chmod +x "$WORK/bin/"*
export STUB_DIR=$WORK PATH="$WORK/bin:$PATH" POWER_WAKE_POLL_SEC=0 POWER_SHUTDOWN_POLL_SEC=0
fails=0
ok() { echo "ok   $1"; }
ko() { echo "FAIL $1" >&2; fails=$((fails + 1)); }
has() { grep -qx -- "$1" "$WORK/calls"; }

# --- power-shutdown ---
printf 'wait 1\nkey /etc/power/custom_key\npoweroff poweroff now\ntarget srv-b 2200 halt\n# comment\ntarget srv-a 2200 halt\n' > "$WORK/shutdown.conf"
: > "$WORK/calls"; POWER_SHUTDOWN_CONF=$WORK/shutdown.conf "$F/power-shutdown" > /dev/null
order=$(grep -oE '^(ssh .*@srv-[ab]|poweroff)' "$WORK/calls" | sed 's/.*@//' | paste -sd,)
if [[ $order == srv-b,srv-a,poweroff ]]; then ok "targets in order, then this host"; else ko "shutdown order ($order)"; fi
if grep -q -- '-p 2200 .*halt@srv-b' "$WORK/calls"; then ok "the target's port and user are used"; else ko "port or user"; fi
if has 'poweroff now'; then ok "the configured poweroff command runs last"; else ko "poweroff command"; fi
if grep -q -- '-i /etc/power/custom_key ' "$WORK/calls"; then ok "the configured key is used"; else ko "key path"; fi

printf 'wait 1\npoweroff poweroff  --halt  now\ntarget down-ssh 22 halt\ntarget srv-c 22 halt\n' > "$WORK/shutdown.conf"
: > "$WORK/calls"; out=$(POWER_SHUTDOWN_CONF=$WORK/shutdown.conf "$F/power-shutdown")
if grep -q 'down-ssh: ssh failed' <<< "$out" && grep -q '@srv-c' "$WORK/calls"; then ok "a failed ssh is logged and the next target still stops"; else ko "ssh failure path"; fi
if has 'poweroff --halt now'; then ok "a poweroff command with options"; else ko "poweroff with options"; fi
echo 0 > "$WORK/ping"
printf 'wait 1\npoweroff poweroff now\ntarget srv-up 22 halt\n' > "$WORK/shutdown.conf"
: > "$WORK/calls"; out=$(POWER_SHUTDOWN_CONF=$WORK/shutdown.conf "$F/power-shutdown")
if grep -q 'srv-up: still up after 1s, going on' <<< "$out" && has 'poweroff now'; then ok "a target still up after the wait: logged, then this host"; else ko "still-up path"; fi
echo 127 > "$WORK/ping"; start=$SECONDS
: > "$WORK/calls"; out=$(POWER_SHUTDOWN_CONF=$WORK/shutdown.conf "$F/power-shutdown")
if grep -q 'ping cannot tell (exit 127), waited 1s' <<< "$out" && (( SECONDS - start >= 1 )); then ok "no ping: waits the full time, never assumes down"; else ko "ping 127 path"; fi
echo 1 > "$WORK/ping"

printf 'wait 1\npoweroff poweroff now\n' > "$WORK/shutdown.conf"
: > "$WORK/calls"; POWER_SHUTDOWN_CONF=$WORK/shutdown.conf "$F/power-shutdown" > /dev/null
if [[ $(grep -c '^ssh ' "$WORK/calls" || true) == 0 ]] && has 'poweroff now'; then ok "no target: this host only"; else ko "empty target list"; fi

# --- power-wake ---
printf 'ups pdu@localhost\ncharge 70\ntimeout 1\ndelay 0\nbroadcast\nmac 02:00:00:00:aa:01\nmac 02:00:00:00:aa:02\n' > "$WORK/wake.conf"
echo 90 > "$WORK/charge"; : > "$WORK/calls"
"$F/power-wake" "$WORK/wake.conf" > /dev/null
if has 'upsc pdu@localhost battery.charge'; then ok "the charge is read from the configured target"; else ko "upsc target"; fi
if has 'wakeonlan 02:00:00:00:aa:01' && has 'wakeonlan 02:00:00:00:aa:02'; then ok "charge above the threshold wakes every MAC"; else ko "wake above threshold"; fi
echo 69.5 > "$WORK/charge"; : > "$WORK/calls"
if "$F/power-wake" "$WORK/wake.conf" > /dev/null 2>&1; then ko "below the threshold exits 0"; else ok "below the threshold fails after the timeout"; fi
if grep -q wakeonlan "$WORK/calls"; then ko "woke below the threshold"; else ok "nothing woken below the threshold"; fi
printf 'ups pdu@backup.example:3493\ncharge 70\ntimeout 1\ndelay 1\nbroadcast 198.51.100.255\nmac 02:00:00:00:aa:01\nmac 02:00:00:00:aa:02\n' > "$WORK/wake.conf"
echo 70 > "$WORK/charge"; : > "$WORK/calls"
start=$SECONDS; "$F/power-wake" "$WORK/wake.conf" > /dev/null
if has 'upsc pdu@backup.example:3493 battery.charge' && has 'wakeonlan -i 198.51.100.255 02:00:00:00:aa:01'; then ok "a remote UPS, at the threshold, to the broadcast address"; else ko "remote or broadcast"; fi
if (( SECONDS - start >= 1 )); then ok "the delay separates two hosts"; else ko "no delay between hosts"; fi
printf 'ups pdu@localhost\ncharge 70\n' > "$WORK/wake.conf"; : > "$WORK/calls"
"$F/power-wake" "$WORK/wake.conf" > /dev/null
if [[ ! -s $WORK/calls ]]; then ok "no MAC: nothing to do"; else ko "no MAC"; fi

# --- power-notify ---
printf 'timer 1\nevents ONBATT LOWBATT\ncmd echo "notified $NOTIFYTYPE $UPSNAME $1" >> "$STUB_DIR/calls"\n' > "$WORK/notify.conf"
export POWER_NOTIFY_CONF=$WORK/notify.conf
: > "$WORK/calls"; NOTIFYTYPE=ONBATT UPSNAME=pdu@localhost "$F/power-notify" "on battery"
if has 'upssched on battery' && has 'notified ONBATT pdu@localhost on battery'; then ok "ONBATT reaches upssched and the command"; else ko "ONBATT dispatch"; fi
: > "$WORK/calls"; NOTIFYTYPE=ONLINE UPSNAME=pdu@localhost "$F/power-notify" "on line"
if has 'upssched on line' && ! grep -q '^notified' "$WORK/calls"; then ok "ONLINE reaches upssched, not the command (not in events)"; else ko "ONLINE dispatch"; fi
: > "$WORK/calls"; NOTIFYTYPE=COMMBAD UPSNAME=pdu@localhost "$F/power-notify" "lost"
if [[ ! -s $WORK/calls ]]; then ok "an event outside both is ignored"; else ko "COMMBAD dispatch"; fi
printf 'timer 0\nevents ONBATT\ncmd echo "notified $NOTIFYTYPE" >> "$STUB_DIR/calls"\n' > "$WORK/notify.conf"
: > "$WORK/calls"; NOTIFYTYPE=ONBATT UPSNAME=pdu@localhost "$F/power-notify" "on battery"
if ! grep -q '^upssched' "$WORK/calls" && has 'notified ONBATT'; then ok "lowbatt mode: no upssched"; else ko "upssched outside timer mode"; fi

# --- power-upssched ---
: > "$WORK/calls"; "$F/power-upssched" onbatt-pdu
if has 'sudo -n /usr/sbin/upsmon -c fsd'; then ok "the onbatt timer forces the shutdown"; else ko "upssched onbatt"; fi
: > "$WORK/calls"; "$F/power-upssched" onbatt
if ! grep -q '^sudo' "$WORK/calls"; then ok "another timer does nothing"; else ko "upssched other"; fi

# --- nut-check ---
check() { printf "%s" "$2" > "$WORK/status"; : > "$WORK/calls"; out=$("$F/nut-check" "$1"); rc=$?; }
set +e
check pdu "OL CHRG"; if (( rc == 0 )) && has 'upsc pdu@localhost ups.status'; then ok "nut-check: on mains passes, a name means localhost"; else ko "nut-check OL"; fi
for st in "OB DISCHRG" "OL LB" "OL RB"; do
  check pdu@198.51.100.4:3493 "$st"; if (( rc == 1 )) && [[ $out == "pdu@198.51.100.4:3493: $st" ]]; then ok "nut-check: $st fails with the state"; else ko "nut-check $st"; fi
done
check pdu ""; if (( rc == 1 )) && [[ $out == *COMMBAD* ]]; then ok "nut-check: no data fails as COMMBAD"; else ko "nut-check COMMBAD"; fi
set -e

if [[ $fails -gt 0 ]]; then echo "$fails failed" >&2; exit 1; fi
echo "all passed"

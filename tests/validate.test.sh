#!/usr/bin/env bash
# The role's input checks: each bad input fails before anything changes, the good ones pass.
# Runs tasks/validate.yml on localhost; needs ansible-playbook on PATH, no host.
set -euo pipefail

REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
mkdir "$WORK/roles"
ln -s "$REPO" "$WORK/roles/power"
cat > "$WORK/play.yml" <<'PLAY'
- name: Validate power inputs
  hosts: localhost
  gather_facts: false
  tasks:
    - name: Validate
      ansible.builtin.include_role:
        name: power
        tasks_from: validate.yml
PLAY
fails=0
run() { ANSIBLE_ROLES_PATH=$WORK/roles ansible-playbook -i localhost, -c local \
  -e '{"power_ups": [{"name": "u", "driver": "dummy-ups", "port": "u.dev"}], "power_feeding_ups": ["u"]}' \
  -e "$1" "$WORK/play.yml" > "$WORK/out" 2>&1; }
good() { if run "$2"; then echo "ok   accepted: $1"; else echo "FAIL rejected a good input: $1" >&2; tail -5 "$WORK/out" >&2; fails=$((fails + 1)); fi; }
# Rejected by an assert, never by a templating crash: that would pass for the wrong reason.
bad() {
  if run "$2"; then echo "FAIL accepted: $1" >&2; fails=$((fails + 1))
  elif grep -qE '"assertion"|Action failed: ' "$WORK/out"; then echo "ok   rejected: $1"
  else echo "FAIL failed without an assertion: $1" >&2; grep -m3 -E 'ERROR|fatal' "$WORK/out" >&2; fails=$((fails + 1)); fi
}

good "one UPS, defaults" '{}'
good "a UPS with a driver flag and no feed" '{"power_ups": [{"name": "u", "driver": "d", "options": {"ignorelb": true}}], "power_feeding_ups": []}'
good "full cycle" '{"power_feeding_ups": ["u"], "power_listen": ["127.0.0.1"], "power_clients": [{"name": "nas", "role": "secondary"}], "power_shutdown_targets": [{"host": "192.0.2.21", "port": 22, "user": "shutdown"}], "power_wake_hosts": [{"mac": "02:00:00:00:00:01", "ups": "u"}, {"mac": "02:00:00:00:00:02", "ups": "u", "min_charge": 95, "broadcast": "192.0.2.255"}], "power_wake_broadcast": "192.0.2.255"}'
bad "no UPS" '{"power_ups": []}'
bad "UPS list as a string" '{"power_ups": "u"}'
bad "an unknown UPS key" '{"power_ups": [{"name": "u", "driver": "d", "bus": "001"}]}'
bad "a quote in an option" '{"power_ups": [{"name": "u", "driver": "d", "options": {"desc": "a\"b"}}]}'
bad "a duplicate UPS name" '{"power_ups": [{"name": "u", "driver": "d"}, {"name": "u", "driver": "d"}]}'
bad "a feeding UPS that does not exist" '{"power_feeding_ups": ["x"]}'
bad "the reserved client name" '{"power_clients": [{"name": "upsmon-local", "role": "secondary"}]}'
bad "a client role other than primary or secondary" '{"power_clients": [{"name": "nas", "role": "admin"}]}'
bad "a target as a string" '{"power_shutdown_targets": ["host"]}'
bad "an unknown target key" '{"power_shutdown_targets": [{"host": "h", "prt": 22}]}'
bad "a target port that is not a number" '{"power_shutdown_targets": [{"host": "h", "port": "ssh"}]}'
bad "a bad MAC" '{"power_wake_hosts": [{"mac": "02:00:00:00:00", "ups": "u"}]}'
bad "a wake UPS that does not exist" '{"power_wake_hosts": [{"mac": "02:00:00:00:00:01", "ups": "x"}]}'
bad "a host to wake with no UPS" '{"power_wake_hosts": [{"mac": "02:00:00:00:00:01"}]}'
bad "a host to wake listed twice" '{"power_wake_hosts": [{"mac": "02:00:00:00:00:01", "ups": "u"}, {"mac": "02:00:00:00:00:01", "ups": "u"}]}'
bad "an unknown key on a host to wake" '{"power_wake_hosts": [{"mac": "02:00:00:00:00:01", "ups": "u", "delay": 5}]}'
bad "a per-host charge above 100" '{"power_wake_hosts": [{"mac": "02:00:00:00:00:01", "ups": "u", "min_charge": 101}]}'
bad "hosts to wake as a string" '{"power_wake_hosts": "02:00:00:00:00:01"}'
bad "a charge that is not a number" '{"power_wake_min_charge": "abc"}'
bad "a charge above 100" '{"power_wake_min_charge": 150}'
good "a supplied client password" '{"power_clients": [{"name": "nas", "role": "secondary", "password": "s3cret-pass"}]}'
bad "a short client password" '{"power_clients": [{"name": "nas", "role": "secondary", "password": "short"}]}'
bad "a quote in a client password" '{"power_clients": [{"name": "nas", "role": "secondary", "password": "abc\"defgh"}]}'
good "timer, notify, settings, no killpower" '{"power_shutdown_on": "timer", "power_shutdown_after_sec": 120, "power_notify_cmd": "logger ups", "power_notify_events": ["ONBATT", "ONLINE"], "power_upsmon_settings": {"DEADTIME": 25}, "power_ups_globals": {"pollinterval": 2}, "power_upsd_settings": {"MAXAGE": 25}, "power_killpower": false, "power_wake_delay_sec": 30, "power_poweroff_cmd": "systemctl poweroff"}'
bad "an unknown mode" '{"power_mode": "standalone"}'
bad "an unknown shutdown trigger" '{"power_shutdown_on": "never"}'
bad "a zero timer" '{"power_shutdown_on": "timer", "power_shutdown_after_sec": 0}'
bad "an unknown event" '{"power_notify_events": ["ONFIRE"]}'
bad "an upsmon key the role writes" '{"power_upsmon_settings": {"SHUTDOWNCMD": "/bin/true"}}'
bad "a lower-case upsmon key" '{"power_upsmon_settings": {"deadtime": 25}}'
bad "LISTEN in upsd settings" '{"power_upsd_settings": {"LISTEN": "0.0.0.0"}}'
good "a power race wait" '{"power_poweroff_wait": "5m"}'
bad "a power race wait that is not a duration" '{"power_poweroff_wait": "five minutes"}'
bad "killpower as a string" '{"power_killpower": "yes"}'
bad "remote UPS in netserver mode" '{"power_remote_ups": [{"name": "u", "host": "srv", "user": "c", "password": "abcdefgh"}]}'
good "netclient with a password" '{"power_mode": "netclient", "power_ups": [], "power_remote_ups": [{"name": "pdu", "host": "198.51.100.7", "port": 3493, "user": "lab", "password": "abcdefgh", "feeds": true}], "power_wake_hosts": [{"mac": "02:00:00:00:00:01", "ups": "pdu"}]}'
good "netclient reading the password from its server" '{"power_mode": "netclient", "power_ups": [], "power_remote_ups": [{"name": "pdu", "host": "198.51.100.7", "user": "lab", "password_from": "localhost"}]}'
bad "netclient with no remote UPS" '{"power_mode": "netclient", "power_ups": []}'
bad "netclient with local UPS too" '{"power_mode": "netclient", "power_remote_ups": [{"name": "pdu", "host": "h", "user": "lab", "password": "abcdefgh"}]}'
bad "a remote UPS with no password" '{"power_mode": "netclient", "power_ups": [], "power_remote_ups": [{"name": "pdu", "host": "h", "user": "lab"}]}'
bad "a remote UPS with both password and password_from" '{"power_mode": "netclient", "power_ups": [], "power_remote_ups": [{"name": "pdu", "host": "h", "user": "lab", "password": "abcdefgh", "password_from": "localhost"}]}'
bad "password_from a host not in the inventory" '{"power_mode": "netclient", "power_ups": [], "power_remote_ups": [{"name": "pdu", "host": "h", "user": "lab", "password_from": "nowhere"}]}'
bad "feeds as a string" '{"power_mode": "netclient", "power_ups": [], "power_remote_ups": [{"name": "pdu", "host": "h", "user": "lab", "password": "abcdefgh", "feeds": "yes"}]}'
bad "a bad listen address" '{"power_listen": ["0.0.0.0 3493"]}'
bad "a space in a UPS port" '{"power_ups": [{"name": "u", "driver": "d", "port": "/dev/a b"}]}'
bad "an upper-case ups.conf global" '{"power_ups_globals": {"POLLINTERVAL": 2}}'
bad "a quote in a ups.conf global" '{"power_ups_globals": {"pollinterval": "2\""}}'
bad "a quote in an upsd setting" '{"power_upsd_settings": {"MAXAGE": "1\""}}'
bad "a newline in the notify command" '{"power_notify_cmd": "a\nb"}'
bad "an empty poweroff command" '{"power_poweroff_cmd": ""}'
bad "a wait that is not a number" '{"power_shutdown_wait_sec": "5m"}'
bad "a wake timeout that is not a number" '{"power_wake_timeout_sec": "1h"}'
bad "a wake delay that is not a number" '{"power_wake_delay_sec": "1m"}'
bad "a bad broadcast" '{"power_wake_broadcast": "all"}'
bad "a duplicate client" '{"power_clients": [{"name": "nas", "role": "secondary"}, {"name": "nas", "role": "primary"}]}'
bad "a secret dir with a space" '{"power_secret_dir": "/etc/nut/my secrets"}'
bad "a relative key path" '{"power_key": "id_ed25519"}'
bad "timer with no feeding UPS" '{"power_feeding_ups": [], "power_shutdown_on": "timer"}'
bad "a duplicate remote name" '{"power_mode": "netclient", "power_ups": [], "power_remote_ups": [{"name": "pdu", "host": "a", "user": "lab", "password": "abcdefgh"}, {"name": "pdu", "host": "b", "user": "lab", "password": "abcdefgh"}]}'
bad "a remote port that is not a number" '{"power_mode": "netclient", "power_ups": [], "power_remote_ups": [{"name": "pdu", "host": "h", "port": "nut", "user": "lab", "password": "abcdefgh"}]}'
bad "a primary role on a UPS that does not feed this host" '{"power_mode": "netclient", "power_ups": [], "power_remote_ups": [{"name": "pdu", "host": "h", "user": "lab", "password": "abcdefgh", "role": "primary", "feeds": false}, {"name": "feed", "host": "h", "user": "lab", "password": "abcdefgh"}]}'
bad "a netclient wake UPS that is not watched" '{"power_mode": "netclient", "power_ups": [], "power_remote_ups": [{"name": "pdu", "host": "h", "user": "lab", "password": "abcdefgh"}], "power_wake_hosts": [{"mac": "02:00:00:00:00:01", "ups": "other"}]}'

if [[ $fails -gt 0 ]]; then echo "$fails failed" >&2; exit 1; fi
echo "all passed"

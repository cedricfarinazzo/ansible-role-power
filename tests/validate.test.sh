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
  -e '{"power_ups": [{"name": "u", "driver": "dummy-ups", "port": "u.dev"}]}' -e "$1" "$WORK/play.yml" > /dev/null 2>&1; }
good() { if run "$2"; then echo "ok   accepted: $1"; else echo "FAIL rejected a good input: $1" >&2; fails=$((fails + 1)); fi; }
bad() { if run "$2"; then echo "FAIL accepted: $1" >&2; fails=$((fails + 1)); else echo "ok   rejected: $1"; fi; }

good "one UPS, defaults" '{}'
good "full cycle" '{"power_feeding_ups": ["u"], "power_listen": ["127.0.0.1"], "power_clients": [{"name": "nas", "role": "secondary"}], "power_shutdown_targets": [{"host": "192.0.2.21", "port": 22, "user": "shutdown"}], "power_wake_macs": ["02:00:00:00:00:01"], "power_wake_ups": "u", "power_wake_broadcast": "192.0.2.255"}'
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
bad "a bad MAC" '{"power_wake_macs": ["02:00:00:00:00"], "power_wake_ups": "u"}'
bad "a wake UPS that does not exist" '{"power_wake_macs": ["02:00:00:00:00:01"], "power_wake_ups": "x"}'
bad "a charge that is not a number" '{"power_wake_min_charge": "abc"}'
bad "a charge above 100" '{"power_wake_min_charge": 150}'

if [[ $fails -gt 0 ]]; then echo "$fails failed" >&2; exit 1; fi
echo "all passed"

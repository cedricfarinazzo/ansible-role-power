# 🔋 Ansible Role: power

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Ansible Galaxy](https://img.shields.io/badge/Ansible%20Galaxy-cedricfarinazzo.power-blue)](https://galaxy.ansible.com/cedricfarinazzo/power)

> **The full power cycle of hosts on UPS with [Network UPS Tools](https://networkupstools.org/): watch the UPS, shut the dependent hosts down in order on low battery or after a time on battery, then wake them by Wake-on-LAN once power is back and the battery is charged enough.**

One role for both sides: the host the UPS is plugged into (`netserver`) and the hosts that follow it over the network (`netclient`).

## 🚀 Quick Start

```yaml
# The host the UPS is plugged into (inventory host ups-server)
- hosts: ups-server
  become: true
  roles:
    - role: cedricfarinazzo.power
      vars:
        power_ups:
          - name: ups
            driver: usbhid-ups
        power_feeding_ups: [ups]
        power_listen: [0.0.0.0]
        power_clients:
          - {name: web, role: secondary}

# A host on the same UPS, stopped by NUT
- hosts: web
  become: true
  roles:
    - role: cedricfarinazzo.power
      vars:
        power_mode: netclient
        power_remote_ups:
          - {name: ups, host: ups-server.example, user: web, password_from: ups-server}
```

The role will:
- ✅ **netserver:** install NUT, serve every UPS of `power_ups` (`upsd`) and watch it (`upsmon`); generate a password on the host for every NUT login
- ✅ **netclient:** watch UPS on other hosts, reading the password on the server (`password_from`) or taking it from a variable
- ✅ On the low battery of a feeding UPS, or after `power_shutdown_after_sec` on battery (`power_shutdown_on: timer`): stop each of `power_shutdown_targets` in order over SSH, wait until it is down, then stop this host
- ✅ netserver: power the feeding UPS off after the shutdown (`power_killpower`), so it restarts the hosts when mains returns; a watched-only UPS gets `sdorder: "-1"`, so it is never powered off
- ✅ At every boot: wait until the battery charge reaches `power_wake_min_charge`, then wake `power_wake_macs` by Wake-on-LAN, `power_wake_delay_sec` apart
- ✅ Run your command on UPS events (`power_notify_cmd`), e.g. to post to a chat
- ✅ Install `nut-check <ups>` for your monitoring: it fails on battery (OB), low battery (LB), battery to replace (RB) or no data

## 📋 Requirements

| Component | Requirement |
|-----------|-------------|
| **Operating System** | Debian, Ubuntu (see below), systemd |
| **Ansible** | ansible-core 2.15+ (CI tests the version pinned in `requirements-dev.txt`) |
| **Collections** | `community.crypto` (`requirements.yml`) |
| **Privileges** | Root or sudo access on the target hosts |

### Supported Distributions

Each is tested in CI with Molecule: a server with two simulated UPS (NUT's `dummy-ups` driver) and a client following them, through a timer shutdown and a low-battery shutdown.

| Distribution | Versions |
|--------------|----------|
| **Debian** | 12, 13 |
| **Ubuntu** | 24.04, 26.04 |

#### Platform notes

- **Two UPS of one model:** many report the same serial, so `serial` cannot tell them apart. Select each by its USB port with `bus` and `busport` (find them with `sudo nut-scanner -U`), then keep the cables in their sockets. `busport` needs NUT 2.8.1+ (Debian 13, Ubuntu 24.04+); NUT 2.8.0 (Debian 12) refuses the option.
- **NUT's shutdown hook** powers off every UPS whose driver has no `sdorder: "-1"`. The role adds it to every UPS outside `power_feeding_ups` when `power_killpower` is on.
- **Several feeding UPS:** every feed is required (`MINSUPPLIES` = their number): the low battery, or the timer, of any one of them shuts the host down. Redundant supplies, where the host runs on as long as one feed holds, are not supported.
- **Shutdown targets:** the wait relies on ping, so a target must answer ICMP. When ping cannot tell (ICMP filtered), the script waits the full `power_shutdown_wait_sec` for that target. With N targets the worst case is N × `power_shutdown_wait_sec` before this host stops: keep it within the runtime the UPS has left at low battery.
- **Timer mode** installs `sudo` and lets the nut user run `upsmon -c fsd` (upssched runs as nut, and the upsmon process to signal is root's).

## ⚙️ Configuration

Every input is checked before anything changes: a wrong type or an unknown key fails the play.

### Mode

```yaml
# netserver: the UPS is attached here; netclient: follow power_remote_ups on other hosts.
# Moving a host to netclient stops and disables its upsd and drivers.
power_mode: netserver
```

### netserver

```yaml
# Each UPS: {name, driver, port (auto), desc, options}; options are ups.conf keys
# (vendorid, productid, serial, bus, busport, sdorder, override.battery.charge.low...); true = a bare flag
power_ups: []
# UPS that feed this host: any of them starts the shutdown. Any other UPS is watched only (power value 0,
# monitored as secondary: a primary that shuts down sets FSD on every UPS it is primary of, which would
# stop that UPS's own clients)
power_feeding_ups: []
# Addresses upsd listens on (port 3493); empty = localhost only
power_listen: []
# NUT network clients, each {name, role: primary|secondary, password (optional)}; without a password one is
# generated on the host. Either way it is kept in power_secret_dir/<name> (root, 0600)
power_clients: []
power_secret_dir: /etc/nut/secrets
# Global ups.conf settings and extra upsd.conf settings
power_ups_globals:
  maxretry: 3
power_upsd_settings: {}            # e.g. {MAXAGE: 25}
```

### netclient

```yaml
# Each {name, host, port (3493), user, password | password_from, role (secondary), feeds (true)}; name unique
# password_from: the inventory host running that upsd with this role; the password is read there
# feeds: false = watched only, its battery never stops this host, always secondary
# role must match the role of that user in the server's power_clients
power_remote_ups: []
```

### Shutdown

```yaml
# lowbatt: on the UPS's low battery; timer: after power_shutdown_after_sec on battery (upssched)
power_shutdown_on: lowbatt
power_shutdown_after_sec: 600
# Stopped in this order, each {host, port (22), user (root)}, then this host
power_shutdown_targets: []
power_shutdown_wait_sec: 300       # per target, until it stops answering ping
power_key: /etc/power/id_ed25519   # generated on the host; put its .pub in each target's authorized_keys
power_poweroff_cmd: /sbin/shutdown -h +0
# netserver: power the feeding UPS off after the shutdown (POWERDOWNFLAG); ignored on a netclient
power_killpower: true
# Extra upsmon.conf settings
power_upsmon_settings: {}          # e.g. {DEADTIME: 25, FINALDELAY: 0, HOSTSYNC: 30}
```

### Notifications

```yaml
# Run as the nut user on each event of power_notify_events, with NOTIFYTYPE and UPSNAME in the environment
# and the message as $1; empty = none
power_notify_cmd: ""
power_notify_events: [ONLINE, ONBATT, LOWBATT, FSD, COMMOK, COMMBAD, SHUTDOWN, REPLBATT, NOCOMM]
```

### Wake after power returns

```yaml
power_wake_macs: []
# A UPS of power_ups (or of power_remote_ups in netclient mode) whose battery.charge gates the wake
power_wake_ups: ""
power_wake_min_charge: 80            # 0 = wake at once, without reading the charge
power_wake_timeout_sec: 3600       # then power-wake.service fails, visibly
power_wake_delay_sec: 0            # between two hosts
power_wake_broadcast: ""           # empty = 255.255.255.255
```

## 🎯 Usage Examples

### Two UPS on one server, a backup box as NUT client

```yaml
power_ups:
  - name: rack
    driver: usbhid-ups
    options: {vendorid: "051d", productid: "0002", bus: "002", busport: "001"}
  - name: desk
    driver: usbhid-ups
    options: {vendorid: "051d", productid: "0002", bus: "002", busport: "002", sdorder: "-1"}
power_feeding_ups: [rack]
power_listen: [127.0.0.1, 198.51.100.4]
power_clients:
  - {name: backup, role: secondary}
```

The backup box logs in as `backup` with the password in `/etc/nut/secrets/backup` and stops itself on `desk`'s low battery; the server never stops it.

### Shut a rack down, wake it later

```yaml
power_shutdown_targets:
  - {host: 198.51.100.21, port: 22, user: halt}
  - {host: 198.51.100.22, port: 22, user: halt}
power_wake_macs: ["02:00:5e:10:00:21", "02:00:5e:10:00:22"]
power_wake_ups: rack
power_wake_min_charge: 90
power_wake_delay_sec: 60
power_wake_broadcast: 198.51.100.255
```

On each target, for the user `halt`:

```text
command="/usr/bin/sudo /usr/bin/systemctl poweroff",restrict ssh-ed25519 AAAA... power-shutdown@ups-server
```

`power-shutdown` never stops on one target's failure: it logs it (`journalctl -t power-shutdown`) and goes on.

### A client that stops after 5 minutes on battery

```yaml
power_mode: netclient
power_remote_ups:
  - {name: rack, host: 198.51.100.4, user: web, password: "{{ vault_nut_web_password }}"}
power_shutdown_on: timer
power_shutdown_after_sec: 300
power_killpower: false
```

Back on mains before the timer runs out cancels the shutdown.

### Post every UPS event to a webhook

```yaml
power_notify_cmd: >-
  curl -fsS -m 10 -H 'Content-Type: application/json'
  -d "{\"content\": \"$UPSNAME: $1\"}" https://chat.example/hooks/ups
power_notify_events: [ONBATT, ONLINE, LOWBATT, REPLBATT, COMMBAD]
```

### Use nut-check in your monitoring

```bash
nut-check rack || notify "$(nut-check rack)"          # a local UPS
nut-check rack@198.51.100.4 || notify "UPS on battery"   # a remote one
```

## 🧪 Testing

Molecule starts two Docker containers: a server with two simulated UPS and a client following them in `netclient` mode with the timer shutdown. It first runs the role in check mode on the fresh containers, then converges and checks the NUT config and services on both, the generated and supplied passwords, the `sdorder` added to the watched-only UPS, and the wake on and below the threshold. Then it simulates cuts: a short one cancels the client's timer; a long one stops the client while the server stays up and notifies; a forced shutdown on the server stops the client through FSD alone, with the UPS on mains; a low battery stops the server. The role is rerun for idempotence and verified again. `tests/scripts.test.sh` runs the scripts with every external command stubbed; `tests/validate.test.sh` feeds good and bad inputs to the role's checks. The tooling is pinned in `requirements-dev.txt`; `run-tests.sh` installs it into `.venv`.

```bash
# One distribution
./run-tests.sh debian13

# Every supported distribution
make molecule-test-all

# Lint, script and input tests
source .venv/bin/activate && yamllint . && ansible-lint && shellcheck files/* tests/*.sh && tests/scripts.test.sh && tests/validate.test.sh
```

## 🚢 Releases

Once CI passes on `main`, [semantic-release](https://github.com/semantic-release/semantic-release) cuts the version from [Conventional Commits](https://www.conventionalcommits.org/): `fix:` releases a patch, `feat:` a minor, a `!` or `BREAKING CHANGE:` footer a major. A squash merge lands the pull request title (checked in CI), a merge commit lands each branch commit, so both must follow the convention. Each release gets a bare semver tag (`1.2.3`) and GitHub release notes; Ansible Galaxy imports the new tag from the repository. [Renovate](https://docs.renovatebot.com/) keeps the tooling and the pinned GitHub Actions up to date.

## 📦 Dependencies

- ✅ **Ansible Core Modules** (built-in)
- ✅ **OS packages** `nut-server` (netserver), `nut-client`, `wakeonlan`, `netbase`, `sudo` (timer mode)
- ✅ **Collection** `community.crypto` (the shutdown key), from `requirements.yml`

## 👥 Authors & Contributors

**Cédric Farinazzo** ([@cedricfarinazzo](https://github.com/cedricfarinazzo)) - *Author and Maintainer*

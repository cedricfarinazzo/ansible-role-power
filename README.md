# 🔋 Ansible Role: power

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Ansible Galaxy](https://img.shields.io/badge/Ansible%20Galaxy-cedricfarinazzo.power-blue)](https://galaxy.ansible.com/cedricfarinazzo/power)

> **The full power cycle of a host on UPS: watch the UPS with [Network UPS Tools](https://networkupstools.org/), shut the dependent hosts down in order on low battery, then wake them by Wake-on-LAN once power is back and the battery is charged enough.**

Built for a small always-on host (a Raspberry Pi, a NAS, a router) that the UPS is plugged into and that is in charge of the other machines.

## 🚀 Quick Start

```yaml
- hosts: ups_host
  become: true
  roles:
    - role: cedricfarinazzo.power
      vars:
        power_ups:
          - name: ups
            driver: usbhid-ups
        power_feeding_ups: [ups]
```

The role will:
- ✅ Install NUT and serve every UPS of `power_ups` (`upsd`), watched by `upsmon`
- ✅ Generate a password on the host for every NUT login, never from the controller
- ✅ On the low battery of a UPS in `power_feeding_ups`: stop each of `power_shutdown_targets` in order over SSH, wait until it is down, then stop this host
- ✅ Power the UPS off after the shutdown, so it restarts the hosts when mains returns
- ✅ At every boot: wait until the battery is charged above `power_wake_min_charge`, then wake `power_wake_macs` by Wake-on-LAN
- ✅ Install `nut-check <ups>` for your monitoring: it fails on battery (OB), low battery (LB), battery to replace (RB) or no data

## 📋 Requirements

| Component | Requirement |
|-----------|-------------|
| **Operating System** | Debian, Ubuntu (see below), systemd |
| **Ansible** | ansible-core 2.15+ (CI tests the version pinned in `requirements-dev.txt`) |
| **Collections** | `community.crypto` (`requirements.yml`) |
| **Privileges** | Root or sudo access on the target host |

### Supported Distributions

Each is tested in CI with Molecule, against two simulated UPS (NUT's `dummy-ups` driver).

| Distribution | Versions |
|--------------|----------|
| **Debian** | 12, 13 |
| **Ubuntu** | 24.04, 26.04 |

#### Platform notes

- **Two UPS of one model:** many report the same serial, so `serial` cannot tell them apart. Select each by its USB port with `bus` and `busport` (find them with `sudo nut-scanner -U`), then keep the cables in their sockets. `busport` needs NUT 2.8.1+ (Debian 13, Ubuntu 24.04+); NUT 2.8.0 (Debian 12) refuses the option.
- **NUT's shutdown hook** powers off every UPS whose driver has no `sdorder: "-1"`. Give that option to a UPS that feeds other machines you do not stop.

## ⚙️ Configuration

### UPS monitoring

```yaml
# Each UPS: {name, driver, port (auto), desc, options}; options are ups.conf keys
# (vendorid, productid, serial, bus, busport, sdorder, override.battery.charge.low...)
power_ups: []
# UPS that feed this host: their low battery starts the shutdown. Any other UPS is watched only
# (power value 0, monitored as secondary: a primary that shuts down sets FSD on every UPS it is
# primary of, which would stop that UPS's own clients)
power_feeding_ups: []
# Addresses upsd listens on (port 3493); empty = localhost only
power_listen: []
# NUT network clients (another host's upsmon, a NAS), each {name, role: primary|secondary}.
# Their passwords are generated on the host, in power_secret_dir/<name>
power_clients: []
power_secret_dir: /etc/nut/secrets
```

### Ordered shutdown

```yaml
# Stopped in this order on low battery, each {host, port (22), user}, then this host
power_shutdown_targets: []
# Seconds to wait for a target to stop answering ping before the next
power_shutdown_wait_sec: 300
# ed25519 key generated on the host for these logins; put its .pub in each target's
# authorized_keys with a forced command, e.g. command="/usr/bin/systemctl poweroff",restrict
power_key: /etc/power/id_ed25519
```

### Wake after power returns

```yaml
power_wake_macs: []
# UPS whose battery.charge gates the wake, and the threshold in %
power_wake_ups: ""
power_wake_min_charge: 50
# Give up after this (power-wake.service then fails, visibly)
power_wake_timeout_sec: 3600
# Broadcast address for the magic packets; empty = 255.255.255.255
power_wake_broadcast: ""
```

Every input is checked before anything changes: a wrong type or an unknown key fails the play.

## 🎯 Usage Examples

### Two UPS, one feeding this host, a NAS as NUT client

```yaml
power_ups:
  - name: ups-servers
    driver: usbhid-ups
    options: {vendorid: "0463", productid: ffff, bus: "001", busport: "004"}
  - name: ups-network
    driver: usbhid-ups
    options: {vendorid: "0463", productid: ffff, bus: "001", busport: "003", sdorder: "-1"}
power_feeding_ups: [ups-servers]
power_listen: [127.0.0.1, 192.0.2.10]
power_clients:
  - {name: nas, role: secondary}
```

The NAS logs in as `nas` with the password in `/etc/nut/secrets/nas` and stops itself on `ups-network`'s low battery; this host never stops it.

### Shut the servers down, wake them later

```yaml
power_shutdown_targets:
  - {host: 192.0.2.21, port: 22, user: shutdown}
  - {host: 192.0.2.22, port: 22, user: shutdown}
power_wake_macs: ["02:00:00:00:00:21", "02:00:00:00:00:22"]
power_wake_ups: ups-servers
power_wake_min_charge: 60
power_wake_broadcast: 192.0.2.255
```

On each target, for the user `shutdown`:

```text
command="/usr/bin/sudo /usr/bin/systemctl poweroff",restrict ssh-ed25519 AAAA... power-shutdown@ups-host
```

`power-shutdown` never stops on one target's failure: it logs it (`journalctl -t power-shutdown`) and goes on.

### Use nut-check in your monitoring

```bash
nut-check ups-servers || notify "$(nut-check ups-servers)"
```

## 🧪 Testing

Molecule runs the role in a Docker container against two simulated UPS, checks the NUT config and services, simulates a power cut, runs the wake on and below the threshold, and reruns the role for idempotence. `tests/scripts.test.sh` runs the shutdown and wake scripts with every external command stubbed; `tests/validate.test.sh` feeds good and bad inputs to the role's checks. The tooling is pinned in `requirements-dev.txt`; `run-tests.sh` installs it into `.venv`.

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
- ✅ **OS packages** `nut-server`, `nut-client`, `wakeonlan`, `netbase`
- ✅ **Collection** `community.crypto` (the shutdown key), from `requirements.yml`

## 👥 Authors & Contributors

**Cédric Farinazzo** ([@cedricfarinazzo](https://github.com/cedricfarinazzo)) - *Author and Maintainer*

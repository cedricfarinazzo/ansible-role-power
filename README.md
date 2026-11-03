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
- ✅ Wake each host of `power_wake_hosts` by Wake-on-LAN once its own UPS is charged enough: at this host's boot, and each time that UPS is back on mains
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
# With killpower: reboot this long after commanding the UPS off, if the host is still up (POWEROFF_WAIT)
power_poweroff_wait: ""            # e.g. 5m; empty = halt and wait for the UPS
# Extra upsmon.conf settings
power_upsmon_settings: {}          # e.g. {DEADTIME: 25, FINALDELAY: 0, HOSTSYNC: 30}
```

#### What `power_killpower` does

It makes the UPS cut its own outputs at the very end of the shutdown. Without it, the hosts already stopped stay off when mains returns, because their power never went away. With it, the UPS powers them back on, and hosts set to boot on power (a Raspberry Pi, a BIOS "power on after AC loss") start by themselves.

1. A feeding UPS turns critical: low battery, the timer, or no data while on battery.
2. upsmon (primary) sets FSD on that UPS: its NUT clients start to stop. upsmon waits up to `HOSTSYNC` for them to log out.
3. upsmon writes the flag `/etc/killpower`, then runs `power-shutdown`: the targets in order, then this host.
4. systemd stops the services and remounts the disks read-only.
5. At the very end, NUT's systemd hook (`nutshutdown`) finds the flag (`upsmon -K`) and runs `upsdrvctl shutdown`. Every UPS driver whose `sdorder` is not `-1` tells its UPS to switch off after `offdelay` (20 s by default for `usbhid-ups`) and back on `ondelay` after mains returns.
6. The host halts; the UPS cuts its outputs after `offdelay`. With `power_poweroff_wait`, the hook first sleeps that long, then reboots the host.
7. When mains returns, the UPS waits `ondelay`, then powers its outputs: the hosts boot. upsmon clears a leftover flag when it starts. `power-wake` wakes the hosts that need Wake-on-LAN once the battery is charged enough.

**The power race:** mains can come back during steps 4 to 6. Some UPS models then ignore the off command, because they are on mains again: the host stays halted and nothing power-cycles it. `power_poweroff_wait` covers it. After the UPS command, the hook sleeps that long (longer than `offdelay`, e.g. `5m`), then reboots the host. If the UPS did cut, the host is already off and the sleep never ends. If it did not, the host comes back.

Two guards:
- Only a netserver with a feeding UPS writes the flag; a client never powers a UPS off.
- A watched-only UPS gets `sdorder: "-1"` and keeps its outputs on.

Set it to `false` when the UPS feeds machines this host does not stop, when you prefer to restart by hand, or when your UPS model mishandles the command: some stay off until a button press. Test it once.

### Notifications

```yaml
# Run as the nut user on each event of power_notify_events, with NOTIFYTYPE and UPSNAME in the environment
# and the message as $1; empty = none
power_notify_cmd: ""
power_notify_events: [ONLINE, ONBATT, LOWBATT, FSD, COMMOK, COMMBAD, SHUTDOWN, REPLBATT, NOCOMM]
```

### Wake after power returns

```yaml
# Each host: {mac, ups, min_charge (power_wake_min_charge), broadcast (power_wake_broadcast)}
# ups = a name of power_ups, or of power_remote_ups in netclient mode
power_wake_hosts: []
power_wake_min_charge: 80          # default threshold in %; 0 = wake at once, without reading the charge
power_wake_timeout_sec: 3600       # then that run fails, visibly
power_wake_delay_sec: 0            # between two hosts
power_wake_broadcast: ""           # default; empty = 255.255.255.255
```

A host is woken once **its own** UPS reaches **its own** `min_charge`:

- **At this host's boot** (`power-wake.service`), for every host: after a full power cut, when this host comes back first.
- **When a UPS is back on mains** (upsmon's `ONLINE`), for that UPS's hosts only: after a cut of one UPS while this host stayed up on another.

Hosts already up ignore the packet. A UPS that flaps on and off mains never starts two waits at once (one lock per UPS); the wait runs as the nut user, logs to `journalctl -t power-wake` and gives up after `power_wake_timeout_sec`.

## 🎯 Usage Examples

### Central SSH, client mode, or both

Two ways to stop the other machines on a UPS; they combine.

| | Central SSH (`power_shutdown_targets`) | Client mode (`power_mode: netclient`) |
|---|---|---|
| Who decides | The UPS server | Each host, from what it sees of its UPS |
| Order | Strict: one target at a time, each waited for | None: each client stops when its UPS is critical |
| On the target | SSH with the server's key, restricted to a poweroff command | This role in `netclient` mode |
| Server dead or unreachable during a cut | Nobody stops the targets | Each client stops itself (`DEADTIME` after it loses the data while on battery) |
| Per-host choice | One trigger, on the server | Each client picks `lowbatt` or `timer`, and which UPS feed it |
| Good for | Appliances and switches without NUT; a strict order (VMs, then cluster, then storage) | Ordinary Linux hosts |

**Both** is the safest: the clients protect themselves, and the server enforces the order when it is up.

```yaml
# The server
power_clients:
  - {name: hv1, role: secondary}
  - {name: hv2, role: secondary}
power_shutdown_targets:
  - {host: 198.51.100.21, user: halt}
  - {host: 198.51.100.22, user: halt}
```

Each host then stops at whichever comes first, the server's SSH command or its own NUT client; both are a poweroff, so the second is harmless.

Mind the order of events. The server, as primary, sets FSD as soon as its shutdown starts. It then waits up to its `HOSTSYNC` for the clients to log out, and only then runs the SSH sequence. So by default the NUT clients stop together, before the sequence. If the order matters, either:
- give those clients a `FINALDELAY` (their wait between FSD and their own poweroff, set in `power_upsmon_settings`) longer than the server's `HOSTSYNC` plus the time the sequence needs;
- or make the hosts that must stop in order SSH targets only.

### Several UPS, several hosts

Three UPS on one small server, `pi`, and three hosts that each follow the UPS they are plugged into:

| UPS | Feeds |
|-----|-------|
| `rack-a` | `pi`, `db` (first power supply) |
| `rack-b` | `db` (second power supply), `web` |
| `office` | `nas` |

`host_vars/pi.yml` — the server: every UPS is plugged into it, only `rack-a` feeds it.

```yaml
power_ups:
  - name: rack-a
    driver: usbhid-ups
    options: {vendorid: "051d", productid: "0002", serial: "AS1234500001"}
  - name: rack-b
    driver: usbhid-ups
    options: {vendorid: "051d", productid: "0002", serial: "AS1234500002"}
  - name: office
    driver: usbhid-ups
    options: {vendorid: "0764", productid: "0501"}
power_feeding_ups: [rack-a]
power_listen: [127.0.0.1, 198.51.100.4]
power_clients:
  - {name: db, role: secondary}
  - {name: web, role: secondary}
  - {name: nas, role: secondary}
# Back after a cut: wake each host on its own UPS; db, on two, follows rack-a
power_wake_hosts:
  - {mac: "02:00:5e:10:00:31", ups: rack-a, min_charge: 60}   # db
  - {mac: "02:00:5e:10:00:32", ups: rack-b}                   # web, at the default 80 %
power_wake_delay_sec: 30
```

`host_vars/db.yml` — two power supplies, so it follows two UPS:

```yaml
power_mode: netclient
power_remote_ups:
  - {name: rack-a, host: 198.51.100.4, user: db, password_from: pi}
  - {name: rack-b, host: 198.51.100.4, user: db, password_from: pi}
```

`host_vars/web.yml` — one supply on `rack-b`; it also watches `office` without ever stopping for it, and leaves after 5 minutes on battery:

```yaml
power_mode: netclient
power_remote_ups:
  - {name: rack-b, host: 198.51.100.4, user: web, password_from: pi}
  - {name: office, host: 198.51.100.4, user: web, password_from: pi, feeds: false}
power_shutdown_on: timer
power_shutdown_after_sec: 300
```

`host_vars/nas.yml`:

```yaml
power_mode: netclient
power_remote_ups:
  - {name: office, host: 198.51.100.4, user: nas, password_from: pi}
```

What happens:

| Event | Who stops |
|-------|-----------|
| `rack-a` low battery | `pi` and `db`. `pi` powers `rack-a` off afterwards, so everything on it restarts when mains returns |
| `rack-b` 5 minutes on battery | `web` (its timer) |
| `rack-b` low battery | `db` and `web`; back on mains, `pi` wakes `web` once `rack-b` is at 80 % (`db` waits for `rack-a`) |
| `office` low battery | `nas` only. `pi` watches `office` as secondary and gives it `sdorder -1`, so its own shutdown never stops or powers off `nas` |

- Every feed is required: `db` stops on the low battery of either of its UPS, never running on one supply alone (see Platform notes).
- The clients stop themselves through NUT, so `pi` needs no `power_shutdown_targets`. Use those instead for hosts that cannot run NUT (a switch, an appliance with SSH).
- `password_from: pi` reads each client's password on `pi`, so it never goes through the inventory. Converge `pi` before its clients.

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
power_wake_hosts:
  - {mac: "02:00:5e:10:00:21", ups: rack, min_charge: 90}
  - {mac: "02:00:5e:10:00:22", ups: rack, min_charge: 90}
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

### Notifications with power_notify_cmd

The command runs as the `nut` user, through `bash -c`, on each event of `power_notify_events`, with:

| | Value | Example |
|---|---|---|
| `$NOTIFYTYPE` | the event | `ONBATT` |
| `$UPSNAME` | the UPS, as upsmon names it | `rack@localhost`, `rack@198.51.100.4:3493` |
| `$1` | upsmon's message | `UPS rack@localhost on battery` |

It also runs on a netclient, for the UPS it follows. Use single quotes in YAML so the variables reach the shell.

To the system journal:

```yaml
power_notify_cmd: 'logger -t ups "$NOTIFYTYPE $UPSNAME: $1"'
```

A push notification through [ntfy](https://ntfy.sh), high priority on battery and low battery:

```yaml
power_notify_cmd: >-
  curl -fsS -m 10 -H "Title: $UPSNAME"
  -H "Priority: $([ "$NOTIFYTYPE" = ONBATT -o "$NOTIFYTYPE" = LOWBATT ] && echo high || echo default)"
  -d "$1" https://ntfy.example/ups
power_notify_events: [ONBATT, ONLINE, LOWBATT, REPLBATT, COMMBAD, COMMOK]
```

A Discord or Slack-style webhook: build the JSON with `jq`, so a quote in the message can never break it. Keep the webhook URL out of the inventory: put it in a file only the nut user can read, and read it in the command.

```yaml
power_notify_cmd: >-
  jq -cn --arg t "$NOTIFYTYPE" --arg m "$1" '{content: ($t + ": " + $m)}'
  | curl -fsS -m 10 -H 'Content-Type: application/json' -d @- "$(cat /etc/nut/webhook-url)"
power_notify_events: [ONBATT, ONLINE, LOWBATT, FSD, SHUTDOWN, REPLBATT, NOCOMM]
```

Your own script, which gets the same environment and argument:

```yaml
power_notify_cmd: /usr/local/bin/ups-event "$1"
```

The command runs while upsmon waits, so keep it short (`-m 10` above). It must also work without a network: on battery, the router may already be down.

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

# Every supported distribution, in parallel (logs in .molecule-logs/)
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

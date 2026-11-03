# CLAUDE.md — ansible-role-power

Orientation for Claude Code sessions in this repository. `AGENTS.md` is a symlink to this file.

## Purpose

Public Ansible role `cedricfarinazzo.power` (Ansible Galaxy): the power cycle of hosts on UPS, on the UPS host (`netserver`) and on the hosts following it (`netclient`). NUT watches the UPS; a feeding UPS's low battery (or a time on battery) stops dependent hosts in order over SSH, then this host; the next boot wakes them by Wake-on-LAN above a battery threshold. Generic by design: no reference to any downstream project, host, user or network in code, defaults, docs or commit messages.

## Layout

- `defaults/main.yml` — every user-facing variable (`power_*`), with its generic default.
- `vars/main.yml` — internal values: NUT event names, upsmon keys the role owns, `power_monitors` (each watched UPS as upsmon sees it, for both modes), the notify flags.
- `tasks/main.yml` — `validate.yml` (every input asserted before any change), then `cycle.yml` (wakeonlan, shutdown key, `/etc/power` settings, scripts, wake unit), then `nut.yml` (packages per mode; server passwords generated or supplied; client passwords read on their server with `delegate_to`; NUT config; the upssched sudoers rule in timer mode; upsd drop-in; `nut-check`; a netclient stops a leftover upsd and drivers; services per mode). The scripts come first so upsmon starts with a `SHUTDOWNCMD` that exists.
- `templates/` — NUT files (`nut.conf`, `ups.conf`, `upsd.conf`, `upsd.users`, `upsmon.conf`, `upssched.conf`, `power-notify.conf`), `wake.conf` (rendered to `/etc/nut/power-wake.conf`, `root:nut`, so the nut user reads it), `shutdown.conf`, `power-wake.service`, `power-wake-request.path` / `.service`; `/etc/tmpfiles.d/power-wake.conf` creates `/run/nut/power-wake-requests` (`root:nut 0770`).
- `files/` — `power-shutdown` (upsmon's `SHUTDOWNCMD`), `power-wake` (each host of `/etc/nut/power-wake.conf` once its own UPS is charged; all at boot, one UPS's hosts when it is back on mains), `power-notify` (upsmon's `NOTIFYCMD`, as nut: upssched in timer mode, a wake request file on ONLINE, the user's command), `power-wake-request` (root, from `power-wake-request.path`: one transient `power-wake-<id>` unit per UPS back on mains), `power-upssched` (upssched's `CMDSCRIPT`: `upsmon -c fsd`), `nut-check` (monitoring check).
- `handlers/main.yml` — daemon-reload, then the NUT restart chain (driver enumerator → driver target → upsd → upsmon).
- `meta/main.yml` — Galaxy metadata; `platforms` lists exactly what CI tests.
- `molecule/default/` — the one Molecule scenario (docker driver, `geerlingguy/docker-<distro>-ansible` images, one network): `server` with two `dummy-ups` UPS, `client` in `netclient` timer mode. `prepare/` writes the `.dev` files; `converge/` runs the server first (the client reads its password there); `verify/` (one play on the server, client steps delegated) checks both configs, secrets, the added `sdorder`, the wake, a short cut (timer cancelled), a long cut (client stops, server notifies and stays up), `upsmon -c fsd` on the server with mains on (FSD alone stops the client), a low battery (server stops), then restores mains and restarts NUT; the sequence runs `check` on fresh containers before `converge`; `collections.yml` holds test-only collections.
- `tests/scripts.test.sh` — the scripts with every external command stubbed on `PATH`; `tests/validate.test.sh` — good and bad inputs against `tasks/validate.yml` on localhost.
- `run-tests.sh` / `Makefile` — local Molecule entry points: `run-tests.sh <distro>`; several distros or `all` run in parallel, one log each in `.molecule-logs/` (git-ignored). Container names, network and Molecule state (`MOLECULE_EPHEMERAL_DIRECTORY`) carry the distro, so runs never collide; the playbooks address the containers by group (`servers`, `clients`).
- `requirements.yml` — collections the role needs at runtime (consumer-facing ranges).
- `requirements-dev.txt` — controller tooling, exact pins.
- `package.json`, `bun.lock`, `.releaserc.json` — semantic-release tooling only.
- `.github/workflows/` — `ci.yml` (lint, shellcheck, script and input tests, Molecule matrix), `pr-title.yml` (Conventional Commit title check), `release.yml` (semantic-release after `ci.yml` passes on `main`).
- `renovate.json` — dependency updates.

## Conventions

- **Conventional Commits** (`conventionalcommits` preset, so a `!` after the type is breaking). `feat:` → minor, `fix:` / `perf:` → patch, `!` or a `BREAKING CHANGE:` footer → major; `docs:` / `ci:` / `chore:` / `test:` / `refactor:` / `build:` release nothing. A squash merge lands the **PR title** (`pr-title.yml` checks it).
- **Breaking = a consumer must act.** Dropping a platform, renaming or removing a variable, changing a default that changes which UPS stops this host, when it stops (`power_shutdown_on`), which hosts are stopped or woken, whether the UPS is powered off, or which addresses upsd serves.
- **Tags are bare semver** (`1.2.3`, no `v`, `tagFormat` in `.releaserc.json`). Release notes live in GitHub Releases; no `CHANGELOG.md`, no release commit.
- **No ruleset or branch protection on `main`:** a ruleset blocks semantic-release. Changes still go through a PR with green CI, by discipline.
- **Variables:** every user-facing variable starts with `power_`, is defined in `defaults/main.yml`, asserted in `tasks/validate.yml` (with a case in `tests/validate.test.sh`) and documented in `README.md` in the same PR. Internal values (registered results, computed task vars) start with `power_` too (ansible-lint `var-naming[no-role-prefix]`).
- **Secrets stay on their hosts:** NUT passwords are generated on the server (`creates:`) unless supplied, a client reads its password on the server (`password_from`, `delegate_to`), every task touching one has `no_log`; the shutdown key is generated on the host (`openssh_keypair`).
- **Today's behaviour is the default:** a new option defaults to what the role did before it (lowbatt, killpower, no notify, no delay), so adding one is a `feat:`, not a breaking change.
- **Examples never copy a real deployment:** README and Molecule values use documentation addresses (198.51.100.0/24, 192.0.2.0/24), locally administered MACs (`02:...`) and made-up names.
- **Every input is asserted before any change:** a wrong type would render a different, valid NUT config.
- **Scripts never stop the sequence on one failure:** `power-shutdown` logs a target's failure and goes on, then stops this host.
- **GitHub Actions pinned by full commit SHA**, tag in a trailing comment. Resolve with `gh api repos/<owner>/<repo>/git/refs/tags/<tag> --jq .object.sha`.
- **Exact pins for tooling** (`requirements-dev.txt`, `package.json`, `molecule/default/collections.yml`); ranges only in `requirements.yml`.
- **License:** MIT.

## Supported platforms

`meta/main.yml` `platforms`, the CI matrix, the `README.md` table, `run-tests.sh --help` and the `Makefile` list the same set. End-of-life releases are dropped (a `feat!:` change).

### Adding a platform — checklist

1. Check a `geerlingguy/docker-<distro>-ansible:latest` image exists.
2. Its NUT must have `nut-driver-enumerator` and `nut-driver.target` (NUT 2.8.0+); state in the README whether it has `busport` (2.8.1+).
3. Add it to the CI matrix, `meta/main.yml`, `README.md`, `run-tests.sh` usage and the `Makefile`.
4. `./run-tests.sh <distro>` green locally.

## How releases work

1. A PR is squash-merged into `main` with a Conventional Commit title.
2. When `ci.yml` passes on the push to `main`, `release.yml` runs `bunx semantic-release`: tag, GitHub Release with notes, comments on the released PRs.
3. Ansible Galaxy imports each new tag by itself.

## Commands

- Lint: `source .venv/bin/activate && yamllint . && ansible-lint && shellcheck files/* tests/*.sh`
- Script and input tests: `tests/scripts.test.sh`, `tests/validate.test.sh`
- Molecule on one distro: `./run-tests.sh debian13` (creates `.venv` from `requirements-dev.txt`)
- All distros, in parallel: `make molecule-test-all` or `./run-tests.sh all`
- Install release tooling: `bun install --frozen-lockfile`

## Gotchas

- upsmon's `forceshutdown()` sets FSD on every UPS it is primary of: a UPS that does not feed this host must be monitored as `secondary`, or this host's shutdown stops that UPS's clients.
- Debian's NUT shutdown hook runs `upsdrvctl shutdown` on every driver: `sdorder: "-1"` keeps a UPS out of it.
- `busport` is the libusb port on the parent hub, formatted `%03d` (NUT 2.8.1 `drivers/libusb1.c`); NUT 2.8.0 drivers refuse it as an unknown variable.
- upsd binds each `LISTEN` address at start: `nut-server` waits for `network-online.target` (drop-in), or a reboot before DHCP leaves an address unbound.
- A Jinja string literal (inside `{{ }}`, a `when` or an `assert`) unescapes backslashes again: YAML `'[^\s"\\]'` reaches the regex as `[^\s"\]`, an unterminated class. Use an allow-list class without backslashes.
- `service_facts` also lists units another unit merely references, with status `not-found` (a netclient shows `nut-server.service`): test the status, not the key.
- upssched runs `CMDSCRIPT <timer name>`: the timers are `onbatt-<ups>`, so `power-upssched` matches `onbatt-*`. A test that calls the script with a name the template never renders passes for the wrong reason.
- Check mode on a fresh host: packages, `/etc/power` and the nut group do not exist yet. Tasks that need them carry `ignore_errors: "{{ ansible_check_mode }}"` or `when: not ansible_check_mode` (handlers included); Molecule's `check` step proves it.
- Anything the nut user runs (power-notify, upssched, power-wake on ONLINE) can read only `root:nut` files: its settings live in `/etc/nut`, never in `/etc/power` (root only). A file rendered there before the NUT packages exist fails on the missing group: render it in `nut.yml`.
- `setsid` does not leave the cgroup: a child of upsmon's NOTIFYCMD dies with every `nut-monitor` restart (`KillMode=control-group`). A long wait goes through a root path unit into its own transient unit.
- `exec 9> file 2>/dev/null` redirects stderr for the rest of the script, not for the exec: wrap it, `{ exec 9> file; } 2>/dev/null`.
- A lock file root creates is root's 0644: another user then cannot open it. Every power-wake run is root (boot unit, per-UPS units), so they share their locks.
- A netclient in timer mode, or a netserver in timer mode, ends with `upsmon -c fsd`: FSD on every UPS it is primary of. A netclient there must be secondary (validated); a netserver's timer stops all its clients.
- `dummy-ups` reads `/etc/nut/<port>` and rereads it when it changes: the Molecule verify edits it to simulate a cut, then restores it.
- `upsmon -c fsd` fails from upssched's `CMDSCRIPT`: the script runs as the nut user and the PID file belongs to the root upsmon process (written before it drops privileges, `clients/upsmon.c`). Timer mode installs `sudo` and a sudoers rule for that one command.
- upsmon exits after `SHUTDOWNCMD`, and upsd keeps FSD until the driver restarts: after a simulated cut, restart `nut-driver.target`, `nut-server` and `nut-monitor`.
- `${MOLECULE_DISTRO}` inside a `{...}` flow mapping in `molecule.yml` breaks yamllint (it reads the file before Molecule substitutes): write those entries in block style.
- Molecule expands `$VAR` inside `molecule.yml` (empty if unset): a shell variable meant for the role is written `$$VAR` there.
- `wakeonlan` fails with 'send : Invalid argument' and `$proto` uninitialized when `/etc/protocols` is missing (minimal images, e.g. the Debian 12 container): the role installs `netbase` with it.
- Molecule's docker connection: `wakeonlan` broadcasts from the container harmlessly; `power_poweroff_cmd: touch /tmp/powered-off` (`molecule.yml`) so a shutdown never stops a container.

## Self Improvement Loop

Keep `CLAUDE.md` and `README.md` accurate, in the same PR as the change. Update when:

- **A variable is added, renamed or removed:** `defaults/main.yml`, `tasks/validate.yml` and the `README.md` blocks.
- **A platform is added or dropped:** the checklist sets above.
- **A file or task file is added, removed or changes role:** Layout above.
- **A tool or Action is added:** pinned in its own file; never copy versions into prose.
- **A trap costs a debugging round:** one Gotchas line: the symptom, the cause, the fix.
- **A convention is established:** Conventions above.

New fact replaces the old clause; never append a changelog. Prefer small targeted edits over rewrites.

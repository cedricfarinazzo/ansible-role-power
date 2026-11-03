# CLAUDE.md — ansible-role-power

Orientation for Claude Code sessions in this repository. `AGENTS.md` is a symlink to this file.

## Purpose

Public Ansible role `cedricfarinazzo.power` (Ansible Galaxy): the power cycle of a host on UPS. NUT watches the UPS; a feeding UPS's low battery stops dependent hosts in order over SSH, then this host; the next boot wakes them by Wake-on-LAN above a battery threshold. Generic by design: no reference to any downstream project, host, user or network in code, defaults, docs or commit messages.

## Layout

- `defaults/main.yml` — every user-facing variable (`power_*`), with its generic default.
- `tasks/main.yml` — `validate.yml` (every input asserted before any change), then `cycle.yml` (wakeonlan, shutdown key, `/etc/power` settings, scripts, wake unit), then `nut.yml` (packages, passwords generated on the host, NUT config, `nut-check`, upsd drop-in, services). The scripts come first so upsmon starts with a `SHUTDOWNCMD` that exists.
- `templates/` — NUT files (`nut.conf`, `ups.conf`, `upsd.conf`, `upsd.users`, `upsmon.conf`), `shutdown.conf`, `wake.conf`, `power-wake.service`.
- `files/` — `power-shutdown` (upsmon's `SHUTDOWNCMD`), `power-wake` (boot unit), `nut-check` (monitoring check).
- `handlers/main.yml` — daemon-reload, then the NUT restart chain (driver enumerator → driver target → upsd → upsmon).
- `meta/main.yml` — Galaxy metadata; `platforms` lists exactly what CI tests.
- `molecule/default/` — the one Molecule scenario (docker driver, `geerlingguy/docker-<distro>-ansible` images) with two `dummy-ups` UPS; `prepare/` writes their `.dev` files, `verify/` checks services, config, secrets, a simulated cut and the wake; `collections.yml` holds test-only collections.
- `tests/scripts.test.sh` — the scripts with every external command stubbed on `PATH`; `tests/validate.test.sh` — good and bad inputs against `tasks/validate.yml` on localhost.
- `run-tests.sh` / `Makefile` — local Molecule entry points; `run-tests.sh <distro>`.
- `requirements.yml` — collections the role needs at runtime (consumer-facing ranges).
- `requirements-dev.txt` — controller tooling, exact pins.
- `package.json`, `bun.lock`, `.releaserc.json` — semantic-release tooling only.
- `.github/workflows/` — `ci.yml` (lint, shellcheck, script and input tests, Molecule matrix), `pr-title.yml` (Conventional Commit title check), `release.yml` (semantic-release after `ci.yml` passes on `main`).
- `renovate.json` — dependency updates.

## Conventions

- **Conventional Commits** (`conventionalcommits` preset, so a `!` after the type is breaking). `feat:` → minor, `fix:` / `perf:` → patch, `!` or a `BREAKING CHANGE:` footer → major; `docs:` / `ci:` / `chore:` / `test:` / `refactor:` / `build:` release nothing. A squash merge lands the **PR title** (`pr-title.yml` checks it).
- **Breaking = a consumer must act.** Dropping a platform, renaming or removing a variable, changing a default that changes which UPS stops this host, which hosts are stopped or woken, or which addresses upsd serves.
- **Tags are bare semver** (`1.2.3`, no `v`, `tagFormat` in `.releaserc.json`). Release notes live in GitHub Releases; no `CHANGELOG.md`, no release commit.
- **Variables:** every user-facing variable starts with `power_`, is defined in `defaults/main.yml`, asserted in `tasks/validate.yml` (with a case in `tests/validate.test.sh`) and documented in `README.md` in the same PR. Internal values (registered results, computed task vars) start with `power_` too (ansible-lint `var-naming[no-role-prefix]`).
- **No secret leaves the host:** NUT passwords and the shutdown key are generated on the host (`creates:` / `openssh_keypair`), read with `no_log`; the role never takes a password as a variable.
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
- All distros: `make molecule-test-all`
- Install release tooling: `bun install --frozen-lockfile`

## Gotchas

- upsmon's `forceshutdown()` sets FSD on every UPS it is primary of: a UPS that does not feed this host must be monitored as `secondary`, or this host's shutdown stops that UPS's clients.
- Debian's NUT shutdown hook runs `upsdrvctl shutdown` on every driver: `sdorder: "-1"` keeps a UPS out of it.
- `busport` is the libusb port on the parent hub, formatted `%03d` (NUT 2.8.1 `drivers/libusb1.c`); NUT 2.8.0 drivers refuse it as an unknown variable.
- upsd binds each `LISTEN` address at start: `nut-server` waits for `network-online.target` (drop-in), or a reboot before DHCP leaves an address unbound.
- A Jinja string literal (inside `{{ }}`, a `when` or an `assert`) unescapes backslashes again: YAML `'[^\s"\\]'` reaches the regex as `[^\s"\]`, an unterminated class. Use an allow-list class without backslashes.
- `dummy-ups` reads `/etc/nut/<port>` and rereads it when it changes: the Molecule verify edits it to simulate a cut, then restores it.
- `wakeonlan` fails with 'send : Invalid argument' and `$proto` uninitialized when `/etc/protocols` is missing (minimal images, e.g. the Debian 12 container): the role installs `netbase` with it.
- Molecule's docker connection: `wakeonlan` broadcasts from the container harmlessly; `power-shutdown` is run with `POWER_POWEROFF=true` so it never stops the container.

## Self Improvement Loop

Keep `CLAUDE.md` and `README.md` accurate, in the same PR as the change. Update when:

- **A variable is added, renamed or removed:** `defaults/main.yml`, `tasks/validate.yml` and the `README.md` blocks.
- **A platform is added or dropped:** the checklist sets above.
- **A file or task file is added, removed or changes role:** Layout above.
- **A tool or Action is added:** pinned in its own file; never copy versions into prose.
- **A trap costs a debugging round:** one Gotchas line: the symptom, the cause, the fix.
- **A convention is established:** Conventions above.

New fact replaces the old clause; never append a changelog. Prefer small targeted edits over rewrites.

---
title: 'Docker Hermes runtime without losing host state'
type: 'feature'
created: '2026-10-23'
status: 'done'
route: 'dispatch'
review_loop_iteration: 1
baseline_commit: 'd1bf5af866a0c09c0a00e6ef02b59b8ec633668a'
context:
  - '{project-root}/_bmad-output/planning-artifacts/architecture/architecture-Hermes-2026-10-18/ARCHITECTURE-SPINE.md'
  - '{project-root}/docs/02-deploy.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** Hermes on the VPS is a host venv plus the `hermes-gateway` user unit. The operator wants that install to run in Docker without losing `~/.hermes` config, sessions, memory, skills, cron, or logs, and without a second gateway writing the same data.

**Approach:** Add an official-image runtime (`nousresearch/hermes-agent`) that bind-mounts the existing host data directory. Do not move or delete host state. Never run the container and the systemd gateway against the same directory.

**Decisions:**
- Keep this spec whole, including health and update, despite the token overage.
- Cutover is opt-in. Default `make deploy` and `make update` keep the host venv and `hermes-gateway`. A new flag starts the container path only when set. AD-6, AD-10, and AD-12 stay true for the default path.
- Surface is messaging-only. No published ports. Dashboard off. No Caddy, DNS, or Open WebUI. Telegram and Discord stay long-poll.

## Boundaries & Constraints

**Always:**
- Image is `nousresearch/hermes-agent`. Data mount is the existing host `$HOME/.hermes` directory onto `/opt/data`. Never a single file (`auth.json`, `.env`, `config.yaml`).
- Do not `rm`, `rsync --delete`, or `docker compose down -v` anything under `~/.hermes`. Do not delete the host venv or `~/.hermes/hermes-agent` in this change.
- Refuse to start the container if `hermes-gateway` is active, or if another container already has that data directory mounted. Two writers corrupt `state.db`.
- Match the container user to the host owner (`PUID`/`PGID` or `HERMES_UID`/`HERMES_GID`). Do not `chown` the tree to UID 10000. Do not set `umask 0000`.
- Secrets stay mode 600. `build_runtime_env` remains the only runtime-env writer. Do not forward `TARGET_*`, `SSH_*`, `SKIP_*`, `PIN_CRON_FORCE`.
- This change does not SSH, deploy, or restart the live VPS. Laptop `TARGET_HOST` of localhost stays refused.
- `make lint` and `make test` stay the PR gate. No SSH, Docker, or network tests in `pr-checks.yml`.
- Update `README.md` and `docs/02-deploy.md` in the same change.

**Never:**
- A custom image (`pipx`, `python:3.12-slim`, or a hand-rolled `start.sh` that backgrounds the dashboard). Command is the image's `gateway run`.
- A single-file mount, a named volume in place of the host directory, or a mount of a fresh directory that is not the existing `$HOME/.hermes`.
- Running the container as root, `umask 0000`, or `chown` of the data tree to UID 10000.
- Publishing 8642 or 9119, Caddy, DNS, or Open WebUI.
- Bare `hermes update` as the upgrade path for the container. Image upgrades are pull-and-recreate. Re-apply `scripts/remote/patch-hermes-docker.sh` on the host tree only when that `docker.py` still exists.
- A named volume in place of the bind mount. A second gateway container on the same directory.
- Amending adopted AD-6, AD-10, or AD-12. The Docker path is opt-in, not the default install.
- Installing Hermes on this machine.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Default deploy | Opt-in flag unset | `make deploy` and `make update` do not start the container and do not stop `hermes-gateway` | N/A |
| Data present | Host `~/.hermes` has `.env`, `config.yaml`, sessions, memories, opt-in flag set | Container mounts that directory at `/opt/data`. Files stay in place. Host venv remains. | N/A |
| Gateway already up | systemd `hermes-gateway` active, or a container already mounts the same dir | Up script does not start a second writer and does not stop the unit | Exit non-zero. Name the running writer. Operator stops systemd before a retry. |
| Single-file mount | Compose or script bind-mounts one file under `.hermes` | Rejected | Test fails. No such mount in the committed compose. |
| Empty home | `~/.hermes` missing | Create the directory only. Do not seed secrets. Do not delete a later-appearing tree. | Exit non-zero if `.env` or `config.yaml` is missing when starting the gateway container. |
| Rollback | Container stopped, host venv still present, ownership unchanged | `hermes gateway start` on the host can use the same directory | Document the command. Do not automate host start in the same breath as container start. |

</frozen-after-approval>

## Code Map

- `scripts/remote/bootstrap.sh:42-77,131-166` — host installer, `_link_hermes_cli`, `hermes gateway install`, linger, start. Reuse the skip-if-present rule. Do not delete an existing venv.
- `scripts/deploy.sh:79-82,138-139,211-222` — `build_runtime_env` temp file, scp to `remote.env`, config-only replace of `.env` and `config.yaml`, host relink, gateway restart. Reuse the filter. Do not add a second env writer.
- `scripts/lib/runtime-env.sh:26` — only runtime-env writer. Never-forward list is locked by `tests/test_runtime_env.py`.
- `scripts/remote/hermes-update.sh` — host `hermes update` plus colon-path re-patch plus restart. Container upgrade must not call bare `hermes update` inside the image (`hermes update` refuses image-owned code).
- `scripts/remote/patch-hermes-docker.sh:15-21,67-77` — patches host `docker.py` only. Marker: `sandbox = get_sandbox_dir() / "docker" / _sanitize_label_value(task_id)`. Image `/opt/hermes` is immutable; this script cannot patch it. If the image lacks the marker, a derived image is required before Telegram sandboxes are claimed working.
- `scripts/remote/healthcheck.sh:25-37,68-103` — fails if host `hermes` is missing, `docker info` fails, `.env`/`config.yaml`/`USER.md` missing, or gateway status and `pgrep` both fail. A container PID is invisible to host `pgrep`. Do not make health upload or restart.
- `scripts/remote/install-artifacts.sh` — overwrites seeds only when the payload file exists. Missing seed is a skip. Do not add `--delete`.
- `config/config.yaml.example:13-45` — `terminal.backend: docker`, image `hermes-terminal:agent-reach`, volume sources are host paths (`/root/.hermes`, `/root/.agent-reach`). Dockerd resolves those on the host, not inside the Hermes container. Keep them as host paths.
- `firecrawl/docker-compose.yml` — SearXNG and Firecrawl stay on `127.0.0.1`. A bridge-network Hermes container cannot use those URLs. Linux `--network host` is the way to keep them without publishing gateway ports. Host network ignores `-p`.
- `extensions/agent-reach/docker/Dockerfile` — terminal sandbox image, not the agent image. `agent-reach-up.sh` `docker rm -f` on label `hermes-agent=1`. Do not put that label on the gateway container.
- `Makefile` — new target needs `.PHONY` and a `##` help line. Mutating targets are not run from this session.
- Official contract (2026-10-23): https://hermes-agent.nousresearch.com/docs/user-guide/docker — `nousresearch/hermes-agent`, `-v ~/.hermes:/opt/data`, `gateway run`, s6 supervision, runtime UID 10000 unless `PUID`/`PGID` is set, never two gateways on one data dir.

## Tasks & Acceptance

**Execution:**
- [x] `docker/hermes/docker-compose.yml` -- official image, `gateway run`, restart `unless-stopped`, directory mount of the host data dir to `/opt/data`, `network_mode: host`, no published ports, no dashboard env, `PUID`/`PGID` from the host user, docker socket mounted only so the existing terminal backend can reach the host daemon -- a file mount or a fresh volume would drop or hide the live tree
- [x] `scripts/remote/hermes-docker-up.sh` -- idempotent VPS script: create the data dir if missing, refuse a second writer, refuse a single-file mount, never delete host state, recreate without `--pull always` and without `down -v`. Set `XDG_RUNTIME_DIR` before `systemctl --user`. Treat `active`, `activating`, `reloading`, and `deactivating` as a live unit. If `systemctl` cannot be queried, exit non-zero. Also refuse a host `hermes` gateway process and a stopped container that mounts the data dir. Die if `/var/run/docker.sock` is missing. After the container is up, `systemctl --user disable hermes-gateway` without stopping it on the refuse path -- one writer across reboot
- [x] `scripts/lib/common.sh`, `scripts/remote/bootstrap.sh`, `scripts/deploy.sh` -- host start (`start_host_gateway` and the flag-unset branches) must refuse when container `hermes` is running. Opt-in bootstrap must not `hermes gateway install` or start the unit. Flag-unset deploy and update must not call the up script -- AD-1
- [x] `scripts/remote/hermes-update.sh` -- on the Docker path, pull then recreate; do not run bare `hermes update`; a host colon-patch failure warns and does not abort the recreate -- image code is immutable
- [x] `scripts/remote/healthcheck.sh` -- a running container counts only when its image is `nousresearch/hermes-agent` and its command is `gateway run`. If that container and the host unit or a host gateway process are both up, fail. Do not treat an unrelated container named `hermes` as the gateway. Do not restart. Do not print host `hermes gateway status` as the success line on the container path -- AD-19
- [x] `tests/test_hermes_docker.py` -- execute the branches, do not lock them with nearby-string checks: directory mount, single-file refuse, no `down -v`, uid 0 refuse, wrong `/opt/data` symlink refuse, systemd fail-closed, container-already-running refuse on host start, bootstrap skip, update pull vs host `hermes update`, health two-writer exit. `make test` must fail if those guards are inverted -- guarded decision
- [x] `docs/02-deploy.md` and `README.md` -- mount, rollback (`docker stop` and `docker rm` without `-v`, remove the symlink only if it points at `~/.hermes`, then `systemctl --user enable` and `hermes gateway start`), in-container data root is `/opt/data` not `~/.hermes`, Mnemosyne and Agent-Reach host venvs do not run in the image -- workflow page

**Acceptance Criteria:**
- Given a host `~/.hermes` with config and sessions, when the Docker up script runs, then those files are still on the host at the same paths and the container's `/opt/data` is that directory.
- Given `hermes-gateway` is active, when the up script runs without an explicit stop step, then it exits non-zero and the unit is still active.
- Given the host venv exists, when this change is applied, then `/usr/local/lib/hermes-agent` and `~/.hermes/hermes-agent` are not removed.
- Given `make test` and `make lint`, when they run, then both pass with no SSH and no Docker daemon.

## Implementation Notes

- Opt-in flag is exact `HERMES_DOCKER_RUNTIME=1`. It is not written by `build_runtime_env`. Default `make deploy` and `make update` do not call `scripts/remote/hermes-docker-up.sh`.
- A root-owned data directory is refused. The image cannot remap to uid 0 without falling back to UID 10000 and taking ownership. That refuse is the "do not chown" rule, not a delete.
- Telegram sandbox `docker run` from inside the container is not claimed. The host colon patch still runs only when host `docker.py` exists. No derived image.
- `make lint` and `make test` passed (76 tests) after re-derivation. No SSH. No Docker daemon.
- Single-writer guards live in `scripts/lib/hermes-docker.sh`. The up script disables the user unit only after the container is the official gateway, and dies if the unit is still enabled.

## Spec Change Log

- Trigger: review loop 1, single-writer holes. `systemctl --user` failure is treated as inactive, bootstrap still `hermes gateway install`s, and host start paths do not look for a running container. Reboot then starts both writers.
- Amended: Tasks and Design Notes. Fail closed when the unit cannot be queried. Disable the user unit only after the container is the writer. Host start refuses a running `hermes` container. Update pulls; ordinary recreate does not. Tests must execute these branches.
- Avoids: a green `make test` while `HERMES_DOCKER_RUNTIME=1 make deploy` or a later reboot runs systemd and the container against the same `~/.hermes`.
- KEEP: official image, `gateway run`, `network_mode: host`, no published ports, no dashboard, directory bind to `/opt/data`, no named volume, no single-file mount, no `down -v`, no `umask 0000`, no `chown` to UID 10000, refuse uid 0, exact flag `1` not forwarded, default deploy does not call the up script, host venv is not deleted, container is not labeled `hermes-agent=1`, `/opt/data` symlink only when the container starts and never retargeted, refuse path does not stop the unit.

## Review Triage Log

- high — blind: reboot starts both writers. `bootstrap.sh:134` still runs `hermes gateway install` when the flag is set; stop is not disable. Route: bad_spec.
- medium — blind: in-container `~` is `/opt/data`, so `~/.hermes/...` misses the mount. Upstream layout, not disproven. Route: bad_spec (document; no custom entrypoint).
- maybe-false — blind: image stage2 chowns and appends `API_SERVER_KEY`. Image is not in this tree. If true: high. Settle by reading the image `stage2-hook.sh`. Route: defer.
- medium — blind: `hermes-docker-up.sh:208` uses `--pull always` on every recreate. Route: bad_spec.
- low — blind: `docker inspect` Running is not s6 gateway health. Spec required inspect. Reject: everyday s6 restart, fix is a new probe.
- medium — blind: `docker ps -q` misses a stopped container with `restart: unless-stopped`. Route: bad_spec.
- false — blind: `sudo rm /opt/data` deletes the tree. `rm` without `-r` does not remove a directory; a symlink unlink does not delete the target.
- medium — blind: container success paths still run `hermes gateway status`. Route: bad_spec.
- maybe-false — blind: cron fires in UTC because compose does not set `TZ`. `.env` already has `TZ`. If true: medium. Settle by reading image cron timezone source. Route: defer.
- low — blind: compose omits `shm_size`. Browser in the gateway is not the messaging path. Reject: fix adds a new knob.
- medium — blind: tests are string windows. Same root as verification-gap. Route: bad_spec.
- medium — blind: missing socket warns, then compose can create a directory. `hermes-docker-up.sh:185-186`. Route: bad_spec.
- medium — blind: `docs/04-telegram-gateway.md` and `docs/troubleshooting.md` still say start the unit. Route: bad_spec (same as status-line group).
- high — edge: `hermes-docker-up.sh:146-151` treats systemctl failure and non-active transitional states as clear. Route: bad_spec.
- medium — edge: `docker ps` failure is skipped (`|| true` at line 170). Route: bad_spec.
- medium — edge: missing socket. Same as blind socket row.
- high — edge: `start_host_gateway` flag-unset starts systemd beside a running container. `common.sh:64-68`. Route: bad_spec.
- high — edge: bootstrap else and nohup can overlap the container. `bootstrap.sh:163-169`. Route: bad_spec.
- high — edge: artifacts and config-only else branches start the host gateway. `deploy.sh` flag-unset arms. Route: bad_spec.
- high — edge: firecrawl/mnemosyne/agent-reach/notion call `start_host_gateway`. Same root as the common.sh row.
- medium — edge: up script does not `pgrep` a nohup gateway. Route: bad_spec.
- medium — edge: a parent mount of the data dir is not refused. Route: bad_spec.
- low — edge: unit becomes active between check and `compose up`. Reject: TOCTOU, fix is a lock, unlikely in one deploy.
- medium — edge: compose checker does not expand `$HOME`. Committed compose uses `${HERMES_HOME}`. Route: bad_spec (checker).
- low — edge: `:ro` suffix not rejected. Committed compose has no `:ro`. Reject: extra parser, everyday file does not have it.
- low — edge: comment-only image/PUID could pass the substring check. Committed file has real keys. Reject: extra parser.
- medium — edge: health treats `activating` as not active. Route: bad_spec.
- medium — edge: any container named `hermes` skips the host check. `healthcheck.sh:110-117`. Route: bad_spec.
- high — edge claim: host start never inspects container `hermes`. Confirmed at `common.sh:64-68`. Route: bad_spec.
- high — edge claim: second-writer refuse fails open. Confirmed at `hermes-docker-up.sh:146-151`. Route: bad_spec.
- medium — edge claim: single-file refuse misses `$HOME` mounts. Checker hole, committed compose is clean. Route: bad_spec.
- medium — edge claim: flag-unset health ignores a down host gateway if any `hermes` container runs. Confirmed. Route: bad_spec.
- patch — verification: bootstrap skip untested. Moot under bad_spec; re-derive must execute it.
- patch — verification: `start_host_gateway` untested. Moot under bad_spec.
- patch — verification: update path locked by string order. Moot under bad_spec.
- patch — verification: healthcheck is a string check. Moot under bad_spec.
- patch — verification: deploy window accepts an inverted `if`. Moot under bad_spec.
- patch — verification: uid 0 refuse untested. Moot under bad_spec.
- patch — verification: wrong symlink refuse untested. Moot under bad_spec.
- medium — verification other: host colon-patch `die` aborts container update. `hermes-update.sh` calls the patch under `set -e`. Route: bad_spec.
- medium — verification other: `hermes gateway status` after container start prints a host failure. Same as the status-line row.

- medium — blind r2: first `make deploy` uses `--pull never` and never pulls. `recreate_hermes_container` at `hermes-docker.sh:338`. AC requires the container to start. Route: patch.
- high — blind r2: child mounts of `~/.hermes` (terminal sandboxes) fail the up script. `mount_covers_data` treats a child path as a second writer. Route: patch.
- carried maybe-false — blind r2: image stage2 chowns and appends `API_SERVER_KEY`. Same claim as loop 1. Code still does not call stage2. Do not patch or defer again.
- low — blind r2: socket mount not spelled out beside the data mount. Spec required the socket. Reject: docker group is already root-equivalent in the repo policy.
- medium — blind r2: `Config.Image` may be `docker.io/nousresearch/hermes-agent:latest`, which misses the matcher, so disable never runs. Route: patch.
- false — blind r2: `pgrep -af` self-match makes container health succeed. Container success uses `ps -eo args` and `container_is_official_gateway`, not that pgrep. The pgrep line is only the host fallback and is pre-existing.
- high — blind r2: post-start disable failure leaves the new container up. `disable_host_gateway_unit` dies without `docker stop`. Route: patch.
- false — blind r2: docker update must refresh Mnemosyne and Agent-Reach. Spec says those host venvs do not run in the image and are not solved here.
- medium — blind r2: `/opt/data` symlink is created before the refuse checks and has no sudo fallback. Route: patch.
- low — blind r2: other docs still say `hermes gateway start`. Required pages are `README.md` and `docs/02-deploy.md`. Reject: extra pages, not the opt-in path the operator is told to read.
- maybe-false — blind r2: host network plus stage2 binds `127.0.0.1:8642`. Image source is not in this tree. If true: medium. Settle by reading the image entrypoint. Route: defer.
- carried maybe-false — blind r2: cron fires in UTC. Same claim as loop 1. Do not patch or defer again.
- patch — verification r2: `refresh_gateway` is never executed. Filed disposition patch. Route: patch.
- patch — verification r2: deploy flag arms are never executed. Filed disposition patch. Route: patch.
- patch — verification r2: disable-still-enabled die is never executed. Filed disposition patch. Route: patch.
- patch — verification r2: health does not execute a host gateway process beside the container. Filed disposition patch. Route: patch.
- patch — verification r2: stopped official container is not executed in health. Filed disposition patch. Route: patch.
- false — edge r2: container argv in host `ps` blocks idempotent recreate. Compose does not set `pid: host`, so host `ps` does not list container processes.
- false — edge r2: nohup starts beside a stopped container. `start_host_gateway` calls `die` when the container exists, so the nohup fallback is not reached.
- medium — edge r2: post-start die does not stop the container. Same as the disable-failure row. Route: patch.
- medium — edge r2: non-root cannot `ln` `/opt/data`. Same as the symlink row. Route: patch.
- high — edge claim r2: up script is not idempotent because it sees its own process. False: no `pid: host`.
- high — edge claim r2: health fails a lone container because `ps` sees it. False: same PID namespace.
- high — edge claim r2: update cannot recreate a running container. False: same PID namespace; pull then up script does not see container argv.
- high — edge claim r2: disable failure leaves both writers configured. Confirmed. Route: patch.
- high — edge claim r2: first run never pulls. Confirmed. Route: patch.
- high — edge claim r2: compose starts the container, then a later die leaves it up. Confirmed. Route: patch.

## Design Notes

Durable layout, independent of any external write-up: code lives in the image at `/opt/hermes` and is immutable. Data lives only in the existing host `$HOME/.hermes`, mounted at `/opt/data`. The process is `gateway run` under the image supervisor. The runtime user is `hermes` (UID 10000) unless `PUID`/`PGID` matches the mount owner. A custom image, a root process, `umask 0000`, or a mount that is not that existing directory fights the live tree and the colon-path patch.

`~/.hermes` on this install is both data and, on the user-local layout, the source checkout (`hermes-agent/`). Mount the directory. Do not relocate it. Extra files are ignored by the image. A named volume would orphan the live files.

Terminal sandboxes talk to the host dockerd. Volume sources in `config.yaml` are host paths. Paths the process builds under `HERMES_HOME=/opt/data` are not host paths unless the host has `/opt/data` pointing at `$HOME/.hermes`. Create that symlink only when the container runtime is actually started, and remove it on rollback only when it points at that directory. Do not label the gateway container `hermes-agent=1`.

Inside the container, `HERMES_HOME` and `HOME` are `/opt/data`. A skill or cron line that expands `~/.hermes` does not see this tree. Do not add a custom entrypoint to alias it. Say so in the deploy doc.

`systemctl --user` over SSH often has no user bus. Query it with `XDG_RUNTIME_DIR` set, and fail closed if the query fails. Disable the user unit only after the container is up, so a reboot cannot start the unit beside `restart: unless-stopped`. The refuse path still does not stop or disable the unit.

Mnemosyne (`.mnemosyne/venv`) and Agent-Reach (`.agent-reach/venv`) are host Pythons. They do not run inside the official image. Opt-in leaves them on the systemd path. Default-switch leaves them broken until a later story. Do not solve that here.

Colon-path: before claiming Telegram `docker run` works from the container, check the image's `docker.py` for the sanitize marker. If absent, add a derived image that applies the existing patch at build time. Do not live-edit `/opt/hermes`.

## Verification

**Commands:**
- `make lint` -- expected: `bash -n` clean on `scripts/**/*.sh`
- `make test` -- expected: pytest pass via `uv run --no-env-file`, including `tests/test_hermes_docker.py`

**Manual checks (if no CLI):**
- Compose volume is a directory bind of the host Hermes home to `/opt/data`, not a file mount and not a named volume.
- Up script has no `rm -rf` of `~/.hermes`, no `docker compose down -v`, no `umask 0000`.

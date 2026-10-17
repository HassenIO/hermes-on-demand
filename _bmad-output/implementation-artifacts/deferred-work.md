- source_spec: `/Users/hassen/Workspace/Hermes/_bmad-output/implementation-artifacts/spec-unit-test-regressions.md`
  summary: Local cron validation still accepts a non-string id and a whitespace-only name that the VPS installer rejects.
  evidence: Pre-existing. `cron-push.sh` used `job.get("id")` and `job.get("name")` before this change. The spec said keep those error strings and leave `install-cron-jobs.sh` alone.

- source_spec: `/Users/hassen/Workspace/Hermes/_bmad-output/implementation-artifacts/spec-unit-test-regressions.md`
  summary: Runtime env lines are unquoted, so a value with a shell metacharacter can break a later source.
  evidence: Pre-existing. The inline block in `deploy.sh` echoed raw `KEY=value` the same way. This change moved that block into `build_runtime_env` without changing the format.

- source_spec: `/Users/hassen/Workspace/Hermes/_bmad-output/implementation-artifacts/spec-unit-test-regressions.md`
  summary: Pin output is tab-separated, so a tab or newline in a job id or name can shift fields.
  evidence: Pre-existing. The old inline printer in `pin-cron-models.sh` used the same `pin\tid\tname` format.

- source_spec: `/Users/hassen/Workspace/Hermes/_bmad-output/implementation-artifacts/spec-unit-test-regressions.md`
  summary: Skill unpack can fail when TMPDIR is a symlink because the staging dir is not resolved before relative_to.
  evidence: Pre-existing in `unpack-custom-skills.sh`. The spec said not to change that script. The test sets a resolved TMPDIR so the suite can run on macOS.

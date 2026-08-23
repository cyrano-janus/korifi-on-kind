# PR: fix(deploy-on-kind): make fresh deployments work reliably

**Title:** `fix(deploy-on-kind): make fresh deployments work reliably`

**Base:** `main` ← **Compare:** `cyrano-janus:pr/deploy-on-kind-fixes`

---

## Description

While deploying Korifi on a fresh kind cluster we hit several issues in
`scripts/deploy-on-kind.sh`. This PR fixes them incrementally (8 small
commits) and adds fail-fast preflight checks plus an end-to-end smoke test,
so failures surface with actionable messages instead of cryptic kpack/EOF
errors minutes later.

## Fixes

1. **chart_dir scope bug**: `helm upgrade` referenced `$chart_dir` /
   `$values_file` unconditionally, but both were only set inside the
   docker-build branch → script crashed when run with `SKIP_DOCKER_BUILD=1`.
   The chart dir is now always prepared; `SKIP_DOCKER_BUILD` only skips kbld
   image resolution and `kind load`.

2. **VERSION fallback**: `git describe --tags --long` fails on shallow
   clones or repos without tags, killing the script under `set -e`.
   Falls back to the short commit SHA.

3. **shellcheck SC2064**: single-quote the RETURN-trap command so
   `$chart_dir` expands at signal time, not at trap registration.

4. **set -u vs RETURN trap**: the trap variable must not be `local` — by the
   time the trap fires the local is gone and `set -u` aborts cleanup with
   `chart_dir: unbound`.

5. **shellcheck SC2155**: declare-and-assign separately for `VERSION` so a
   failing `git describe` cannot be masked by `export`'s exit code.

6. **Registry preflight**: after deploying the local registry, poll it from
   inside the kind node (`curl -u user:password http://127.0.0.1:30050/v2/`)
   and fail fast with a clear message instead of later kpack build failures.
   The kind node has no cluster DNS, hence `127.0.0.1`.

7. **Configurable API FQDN** (`API_SERVER_FQDN`, default `localhost`):
   feeds the Gateway https-api listener hostname, the API's externalFQDN and
   the generated ingress cert SAN. Reaching the API under any other name
   caused SNI mismatch / connection EOF. Also adds a DNS-resolution preflight
   that prints the exact `/etc/hosts` line when the name does not resolve.

8. **API smoke test**: at the end of the deploy, poll
   `https://<fqdn>:<port>/v3/info` through the kind hostPort mapping; on
   failure print concrete troubleshooting hints (Gateway listener hostname,
   TLSRoute, port mappings), on success print ready-to-use `cf api` /
   `cf auth` commands.

## Testing

- `bash -n`, shellcheck 0.10 (`-S warning`), `shfmt -d -i 2 -ci`: clean
- Fresh kind cluster from scratch with `SKIP_DOCKER_BUILD=1
  API_SERVER_FQDN=api.korifi.local ./scripts/deploy-on-kind.sh korifi`:
  exit 0, smoke test passed
- Full workflow verified end to end: `cf api` → `cf auth cf-admin admin` →
  `cf create-org/space` → `cf push` of a Go app → app reachable via route
- Idempotent re-run of the script against an existing cluster: exit 0

## Notes

- Default behaviour (`API_SERVER_FQDN=localhost`) is unchanged, so CI flows
  are unaffected.
- Happy to split this into separate PRs if preferred — commits are already
  logically grouped.

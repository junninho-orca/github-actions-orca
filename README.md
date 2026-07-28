# Orca Security Shift-Left — GitHub Actions Example

A drop-in reference for running Orca's shift-left scans on every PR and every push to `main`. Covers five scan types in a single workflow: **SAST, SCA (including malicious packages), IaC, Secrets, and Container Image**. Findings land in the PR as check annotations and in the repository's **Security → Code scanning** tab via SARIF upload.

This repo also ships a small `sample-app/` with intentional issues so the pipeline produces real findings on the first run. Strip that directory out before handing this pattern to your own teams.

## What you get

- `.github/workflows/orca-scan.yml` — one workflow, five scan jobs, a final required gate
- `sample-app/` — Python + Terraform + Dockerfile with planted issues across every scan type, plus a scanned-but-never-installed manifest for malicious packages
- `.gitignore` — keeps Terraform state and SARIF artifacts out of commits
- `examples/atlantis-terragrunt/` — the same IaC gate for customers who run Atlantis with Terragrunt instead of GitHub Actions

## Prerequisites

1. **Orca tenant** with AppSec enabled
2. **API token** with the *Shift Left User* role
   - Orca UI: **AppSec → Management → How to initiate a scan → API Token → Create Token**
   - Enable **Service Token** so it survives past your user session
   - Copy it immediately; it is not retrievable afterwards
3. **Project key** for this repo
   - Orca UI: **AppSec → Management → Projects → New**
   - Pick a stable key like `demo-shiftleft-project`. This value is safe to commit
4. **Policy** in Orca configured to fail on High + Critical (more on this under *Gating model* below)
5. **Malicious Packages policy attached to the project** — this is a hard prerequisite, not a tuning step. Without it the SCA scan refuses to run at all (see *Malicious packages* below)

## Setup

### 1. Add the API token to GitHub

```text
GitHub repo → Settings → Secrets and variables → Actions → New repository secret
  Name:  ORCA_SECURITY_API_TOKEN
  Value: <paste the token>
```

### 2. Drop the workflow in

Copy `.github/workflows/orca-scan.yml` into your repo and update two values at the top:

```yaml
env:
  ORCA_PROJECT_KEY: <your-project-key>
  IMAGE_NAME: <your-image-name>
```

### 3. Make the gate required

```text
Settings → Branches → Branch protection rules → main
  Require status checks to pass before merging: ON
  Required checks:
    - Orca Gate
```

The five scan jobs feed into a final `Orca Gate` job. Pointing branch protection at just the gate keeps your required-checks list stable even if you add or rename individual scan jobs later.

## Gating model

The gate is **driven by Orca policy, not by CLI flags in the YAML**. That means severity thresholds, exceptions, and waiver logic all live in one place (the Orca platform) and are consistent across every repo that points at the project.

Configure it once in Orca:

```text
AppSec → Policies → [select your project's policy]
  Fail build on:   High, Critical
  Allow waivers:   per your team's process
```

When any scan's policy decision is *fail*, the action exits with code `3`. The action's entrypoint captures that code and calls `core.setFailed()`, so the job fails, the `Orca Gate` job rolls that up, and branch protection blocks the merge. If a customer wants to pilot without blocking, flip the policy to *Warn only* in Orca — no YAML edits required.

Why not a `--fail-on-severity high` flag in the workflow? Two reasons:

1. **Policy drift.** If severity thresholds live in YAML, each repo can drift independently. Central policy in Orca stays consistent.
2. **Waivers and suppressions.** Those only work when Orca is the source of truth for the pass/fail decision.

The gate blocks on any result that is not a clean success — `failure`, `cancelled`, or `skipped`. A scan that never produced a verdict must not read as green on a required check.

## Malicious packages

Malicious package detection rides along with the SCA scan. The workflow passes `security_checks: vulns,license,malicious` explicitly so the intent is visible in review, though `malicious` is also the action default.

**Attaching the policy is a hard prerequisite, not a tuning step.** Enabling `malicious` without one doesn't silently skip the check — the scan aborts with:

```text
Error: in order to perform 'malicious' scan, a security policy should be
attached to '<your-project-key>' project
```

That's exit code 1, so no SARIF is written and the vulnerability and license results are lost along with it. Attach the policy first:

```text
AppSec → Management → Policies → Code Security
  → "Orca Built-in - Malicious Packages Policy"
  → ⋯ → Attach to Projects → [select your project] → Select
```

Once attached, enforcement modes are **Block** (default — fails the CI build and blocks the PR) or **Warn** (logs findings, doesn't block). Findings carry the `shiftleft:malicious_packages` label, so you can filter for them on the main alerts page.

The same applies more broadly: a project with no policies attached doesn't fail loudly, it reports clean. IaC and Secrets scans will run, print `Based on your defined policies, no controls to warn about`, and exit `0` with `[TOTAL: 0]` against planted findings. Container image scans are the exception — they evaluate against the built-in Container Image policies regardless. If scans come back green on a repo you know is dirty, check the project's attached policies before anything else.

### The demo manifest

Malicious packages are planted in a **separate manifest that nothing installs from**: [`sample-app/malicious-packages-demo/requirements.txt`](sample-app/malicious-packages-demo/requirements.txt).

They are deliberately *not* in `sample-app/requirements.txt`, because `sample-app/Dockerfile` runs `pip install -r requirements.txt` during the Container Image job — the planted package exfiltrates host information at install time, so that would execute it on the runner. Three things keep it inert:

1. The Dockerfile copies `requirements.txt` and `src/` only; the demo directory is never copied.
2. `sample-app/.dockerignore` excludes the demo directory from the build context, so a future `COPY . .` can't pull it in either.
3. The package was removed from PyPI, so `pip` can't resolve it today — a backstop, not the mechanism.

The scan still sees it: the SCA job scans `path: .` recursively and the file is named `requirements.txt`, so pip's analyzer picks it up with no `file_patterns` configuration needed.

The entry is a real record in OSV.dev — the primary upstream feed for Orca's knowledge base — so you can verify it without a tenant:

| Package | Advisory | What it is |
|---|---|---|
| `abseil-py==0.1.0` | [MAL-2026-10760](https://osv.dev/vulnerability/MAL-2026-10760) | Typosquat of `absl-py`; exfiltrates host information on install or import |

See [`sample-app/malicious-packages-demo/README.md`](sample-app/malicious-packages-demo/README.md) for the full walkthrough.

## What each job does

### SAST — `orcasecurity/shiftleft-sast-action@v1`
Static analysis across application source. Catches SQL injection, weak crypto, insecure deserialization, path traversal, secrets-in-code patterns.

### SCA — `orcasecurity/shiftleft-sca-action@v1`
Parses manifests (`requirements.txt`, `package.json`, `go.mod`, `pom.xml`, etc.) and flags vulnerable dependency versions, problem licenses, and malicious packages. Use this to drive version bumps in PRs.

> **Migration note:** this replaces `orcasecurity/shiftleft-fs-action`, which is deprecated. The underlying `orca-cli fs` command keeps working with a warning until **2026-07-15**, then fails. `fs` split into `orca-cli sca` (vulns + licenses) and `orca-cli secrets`, which is why SCA and Secrets are separate actions here. Migrating also needs orca-cli ≥ 1.97.1 if you invoke the CLI directly anywhere.

Keeping SCA and Secrets in separate jobs matters for more than tidiness: `shiftleft-fs-action` defaulted to `security_checks: vulns,secret`, so a workflow that ran both it *and* the dedicated secrets action reported every secret twice — once under each SARIF category, and twice as PR annotations.

### IaC — `orcasecurity/shiftleft-iac-action@v1`
Scans Terraform, CloudFormation, Kubernetes manifests, Helm charts, Dockerfiles, and ARM/Bicep. Flags things like public S3 buckets, open security groups, missing encryption, pods running as root.

### Secrets — `orcasecurity/shiftleft-secrets-action@v1`
Entropy and pattern matching across the working tree and git history.

`fetch-depth: 0` alone is not enough to scan history. It makes history *available*, but in CI the scan is baselined to the event's commits — PR commits on a `pull_request`, pushed commits on a `push`. The workflow sets `ignore_git_history_baseline: "true"` to force a full-history scan, which is what actually catches keys that were committed and rotated but never force-pushed out. Drop it if scan time on a large repo matters more.

### Container Image — `orcasecurity/shiftleft-container-image-action@v1`
Builds the Dockerfile, then scans OS packages, language packages baked into the image, secrets in layers, and image misconfigs.

Two behaviors worth knowing: this action has no annotator, so image findings surface only in the Security tab, never as PR annotations. And secret detection is on by default (`disable_secret: false`), so a secret in committed source that also gets copied into the image shows up under both `orca-secrets` and `orca-image` — same string, two genuinely different risks. Set `disable_secret: "true"` if you'd rather not have the overlap in a demo.

## Expected output

On a PR:

- Five check runs, one per scan type, plus the `Orca Gate` required check
- Annotations inline on changed lines where findings fall in the diff (all jobs except Container Image, which has no annotator)
- A findings table in each job's log — every job sets `console_output: table`, without which the actions write files only and the log comes back bare
- Full list under **Security → Code scanning**, filterable by tool category (`orca-sast`, `orca-sca`, `orca-iac`, `orca-secrets`, `orca-image`)

On a push to `main`:

- Same scans, same upload, same gate. Use this as the source of truth for "what ships." `cancel-in-progress` is scoped to PRs only, so no push to `main` gets cancelled by a later one.

## Demo walkthrough

The `sample-app/` directory is designed to produce findings across every category on the first run:

| Category | File | Planted issue |
|---|---|---|
| Secrets | `src/app.py` | Hardcoded AWS-looking keypair |
| Secrets | `terraform/main.tf` | RDS password as literal |
| SAST | `src/app.py` | SQL injection via string concatenation |
| SAST | `src/app.py` | MD5 used as hash |
| SAST | `src/app.py` | `debug=True` + `host=0.0.0.0` |
| SCA | `requirements.txt` | Flask 1.0.2, Jinja2 2.10, Werkzeug 0.14.1, requests 2.19.1, PyYAML 5.1 |
| IaC | `terraform/main.tf` | Public-read S3 ACL, no encryption |
| IaC | `terraform/main.tf` | Security group `0.0.0.0/0` on port 22 |
| IaC | `terraform/main.tf` | RDS publicly accessible, unencrypted at rest |
| Image | `Dockerfile` | Outdated base image, runs as root |
| Malicious packages | `malicious-packages-demo/requirements.txt` | `abseil-py==0.1.0` — separate manifest, never installed |

Push this as a PR. You should see the five checks run, a handful of annotations appear inline on the diff, and the `Orca Gate` check fail. Flip any one finding (for example, pin `Jinja2>=3.1.4`) and re-push — the corresponding annotation clears and the gate shrinks toward green.

## Other CI systems

[`examples/atlantis-terragrunt/`](examples/atlantis-terragrunt/) covers Atlantis with Terragrunt. Two things differ from this workflow beyond the CI system:

- **What gets scanned.** A `terragrunt.hcl` holds a module reference and a set of inputs, not resources, so scanning source files misses misconfigurations that only exist once Terragrunt merges the two. That example scans the rendered plan JSON instead.
- **Where the gate sits.** Here, the gate is the merge — branch protection blocks a PR until `Orca Gate` passes. In Atlantis, `atlantis apply` runs *before* the merge, so merge-time gating is too late to stop a deploy. That example uses Atlantis's `policy_check` phase and the non-overridable `policies_passed` apply requirement instead.

## Customizing for a customer

Realistic adjustments to mention in a POV working session:

- **Monorepo with multiple projects**: set `path:` per job to a subdirectory, or duplicate jobs with different `project_key` values so each product team gets its own Orca project
- **Matrix across languages**: SAST supports multiple languages in one run; no matrix needed. For SCA, a matrix over subdirectories is sometimes useful if manifests live in separate services
- **Self-hosted runners**: all five are Docker container actions, so they need a Linux runner with Docker available — not just the image-scan job
- **Tokens per environment**: use GitHub Environments (staging/prod) to scope the API token by branch
- **Waivers**: manage in Orca via AppSec → Findings → Waive. Keeping waivers out of YAML means ops can adjust without a code change

## Hardening notes

Things a security-conscious customer will ask about:

- **Least privilege.** The workflow grants `contents: read` at the top level. `security-events: write` and `actions: read` are granted per scan job; `Orca Gate` runs with `permissions: {}`. `pull-requests: read` is deliberately *not* granted — the annotators emit GitHub workflow commands via `@actions/core` and never call the GitHub API, so it buys nothing.
- **Timeouts.** Every job sets `timeout-minutes`. Without one, a hung scan holds a runner for the 6-hour default.
- **Action pinning.** The actions are referenced by the floating `@v1` tag, matching Orca's own documented usage, and `v1` currently tracks each action's newest release. For a workflow that gates merges, pinning to a full commit SHA (`uses: orcasecurity/shiftleft-sast-action@<sha> # v1.0.10`) is stricter — it just means you own the upgrades, ideally via Dependabot's `github-actions` ecosystem. Pick one deliberately.
- **No piped installers.** Earlier revisions installed `orca-cli` with `curl … install.sh | bash` from an unpinned `main`, with no checksum or signature check, even though the orca-cli repo publishes a cosign public key. The dedicated container image action removes that step entirely. If you do install the CLI directly, verify the download.

## Fork pull requests

Repository secrets are not exposed to `pull_request` runs triggered from a fork, so `secrets.ORCA_SECURITY_API_TOKEN` arrives empty and every scan job fails with `api_token must be provided`. `Orca Gate` then blocks the PR. This is safe-by-default but confusing if you don't expect it. Options:

- **Leave it.** Fine for repos where all PRs come from branches, not forks.
- **Skip scans on forks** by adding `if: github.event.pull_request.head.repo.full_name == github.repository` to each scan job — but note the gate treats `skipped` as a block, so you'd need to relax that too, and you lose coverage on exactly the PRs you trust least.
- **Run the scans on a `push` to a maintainer-controlled branch** after review, keeping the fork PR itself unscanned. Do not reach for `pull_request_target` — it runs with a privileged token against untrusted code.

## Troubleshooting

**`ORCA_SECURITY_API_TOKEN` missing or invalid**
Check the repo secret is set, that it has the *Shift Left User* role, and that the service-token flag was enabled so it didn't expire with the user session.

**All five jobs fail with `api_token must be provided`**
Either the secret isn't set, or the PR came from a fork. See *Fork pull requests* above.

**`ERROR: Output must be a folder (end with /)`**
Every action validates that `output` ends with `/`. `output: results/` is correct; `output: results` and `output: results/scan.sarif` both abort before scanning.

**Image job fails on `docker build`**
The workflow expects `sample-app/Dockerfile`. Point `working-directory` at your actual Dockerfile location.

**SARIF upload fails**
Confirm `security-events: write` is granted on the job. Some repos inherit a more restrictive default from org settings. Note the upload steps are guarded with `hashFiles(...) != ''`, so a scan that errored out before writing SARIF skips the upload rather than failing it with a misleading "path does not exist" — check the scan step's log for the real error.

**Scans report `[TOTAL: 0]` and pass on a repo you know is dirty**
Almost always no policies attached to the project. Look for `Based on your defined policies, no controls to warn about` in the job log — the scan found your code, then had nothing to evaluate it against. Fix it at **AppSec → Management → Policies**, not in the YAML.

**Orca Gate passes but you expected it to fail**
Same first check as above, then confirm the relevant policy is set to *Block*, not *Warn*. Gate follows policy decision, not raw finding count.

**`Error: --console-output contains an invalid value 'table'`**
Allowed values differ per scanner. SAST accepts `[cli,glsast,json,sarif]` and rejects `table`; IaC, Secrets, and Container Image all accept `table`. The scan aborts before writing SARIF, so the guarded upload step skips and the job fails with no findings — check the scan step, not the upload step.

**SCA fails with `a security policy should be attached to '<project>' project`**
`malicious` in `security_checks` requires an attached policy. See *Malicious packages* above — this takes the vulnerability and license results down with it, so it's worth fixing rather than working around.

## References

Docs are region-gated; sign in to your tenant first.

- SAST GitHub Action — docs.orcasecurity.io/sast-github-actions
- SCA GitHub Action — docs.orcasecurity.io/sca-github-action
- IaC GitHub Action — docs.orcasecurity.io/iac-scan-github-actions
- Container Image GitHub Action — docs.orcasecurity.io/container-image-scanning-integrating-orca-cli-with-github-actions
- Malicious Packages Detection — docs.orcasecurity.io/malicious-packages-detection
- Deprecating `orca-cli fs` — docs.orcasecurity.io/2026-04-10-deprecating-orca-cli-fs-command
- SCA via the Orca CLI — docs.orcasecurity.io/sca-via-the-orca-cli
- Git Secrets Detection via the Orca CLI — docs.orcasecurity.io/git-secrets-detection-via-orca-cli
- IaC scanning via Orca CLI — docs.orcasecurity.io/iac-scanning-via-orca-cli
- Orca CLI installation — docs.orcasecurity.io/orca-cli-installation
- Container image + GitHub Actions — docs.orcasecurity.io/container-image-scanning-integrating-orca-cli-with-github-actions
- Orca CLI installation — docs.orcasecurity.io/orca-cli-installation

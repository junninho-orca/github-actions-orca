# Orca Security Shift-Left — GitHub Actions Example

A drop-in reference for running Orca's shift-left scans on every PR and every push to `main`. Covers five scan types in a single workflow: **SAST, SCA, IaC, Secrets, and Container Image**. Findings land in the PR as check annotations and in the repository's **Security → Code scanning** tab via SARIF upload.

This repo also ships a small `sample-app/` with intentional issues so the pipeline produces real findings on the first run. Strip that directory out before handing this pattern to your own teams.

## What you get

- `.github/workflows/orca-scan.yml` — one workflow, five scan jobs, a final required gate
- `sample-app/` — Python + Terraform + Dockerfile with planted issues across every scan type
- `terragrunt/` — Terragrunt project (GCP, modules + live/dev) with IaC misconfigs across networking, storage, Cloud SQL, and IAM. The `iac-terragrunt` workflow job authenticates to GCP via Workload Identity Federation, runs `terragrunt plan` per module to generate real JSON plan files, then scans them with orca-cli.
- `.gitignore` — keeps Terraform state and SARIF artifacts out of commits

## Prerequisites

1. **GCP project** for the Terragrunt demo (the `iac-terragrunt` job runs real `terragrunt plan` using short-lived credentials)
   - Create a service account with `roles/viewer` + `roles/iam.securityReviewer` — read-only is enough for plan generation
   - Download a JSON key for that service account
   - Add two GitHub secrets: `GCP_SERVICE_ACCOUNT_KEY` (the full JSON key contents) and `GCP_PROJECT_ID`
   - Update `terragrunt/live/project.hcl` with your project ID (the workflow patches it at runtime, but keep the file in sync for local runs)

2. **Orca tenant** with AppSec enabled
2. **API token** with the *Shift Left User* role
   - Orca UI: **AppSec → Management → How to initiate a scan → API Token → Create Token**
   - Enable **Service Token** so it survives past your user session
   - Copy it immediately; it is not retrievable afterwards
3. **Project key** for this repo
   - Orca UI: **AppSec → Management → Projects → New**
   - Pick a stable key like `demo-shiftleft-project`. This value is safe to commit
4. **Policy** in Orca configured to fail on High + Critical (more on this under *Gating model* below)

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

When any scan's policy decision is *fail*, the action/CLI exits with code `3`, the job fails, the `Orca Gate` job rolls that up, and branch protection blocks the merge. If a customer wants to pilot without blocking, flip the policy to *Warn only* in Orca — no YAML edits required.

Why not a `--fail-on-severity high` flag in the workflow? Two reasons:

1. **Policy drift.** If severity thresholds live in YAML, each repo can drift independently. Central policy in Orca stays consistent.
2. **Waivers and suppressions.** Those only work when Orca is the source of truth for the pass/fail decision.

## What each job does

### SAST — `orcasecurity/orca-sast-action@v1`
Static analysis across application source. Catches SQL injection, weak crypto, insecure deserialization, path traversal, secrets-in-code patterns.

### SCA — `orcasecurity/orca-sca-action@v1`
Parses manifests (`requirements.txt`, `package.json`, `go.mod`, `pom.xml`, etc.) and flags vulnerable dependency versions plus problem licenses. Use this to drive version bumps in PRs.

### IaC — `orcasecurity/orca-iac-action@v1`
Scans Terraform, CloudFormation, Kubernetes manifests, Helm charts, Dockerfiles, and ARM/Bicep. Flags things like public S3 buckets, open security groups, missing encryption, pods running as root.

### Secrets — `orcasecurity/orca-secrets-action@v1`
Entropy and pattern matching across the working tree. Configured with `fetch-depth: 0` so the scan sees history — important for catching keys that were committed and rotated but never force-pushed out.

### Container Image — `orca-cli image scan`
Dedicated action doesn't exist for image scans, so the workflow builds the Dockerfile and calls the CLI directly. Scans OS packages, language packages baked into the image, secrets in layers, and Dockerfile misconfigs.

## Expected output

On a PR:

- Five check runs, one per scan type, plus the `Orca Gate` required check
- Annotations inline on changed lines where findings fall in the diff
- Full list under **Security → Code scanning**, filterable by tool category (`orca-sast`, `orca-sca`, `orca-iac`, `orca-secrets`, `orca-image`)

On a push to `main`:

- Same scans, same upload, same gate. Use this as the source of truth for "what ships."

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
| IaC | `terragrunt/modules/networking/main.tf` | Firewall rules open SSH/RDP/all to `0.0.0.0/0`; VPC flow logs disabled; compute instance with public IP, serial port on, no Shielded VM, cloud-platform scope |
| IaC | `terragrunt/modules/storage/main.tf` | GCS bucket with `allUsers` read/write; uniform bucket-level access off; public access prevention inherited; no versioning; no logging |
| IaC | `terragrunt/modules/database/main.tf` | Cloud SQL publicly accessible; SSL not required; backups disabled; `0.0.0.0/0` authorized network; deletion protection off |
| IaC | `terragrunt/modules/iam/main.tf` | `roles/owner` granted to `allAuthenticatedUsers`; primitive Editor role on SA; downloadable SA key; `sensitive=false` on key output |
| Secrets | `terragrunt/modules/database/main.tf` | Hardcoded Cloud SQL password |
| Image | `Dockerfile` | Outdated base image, runs as root |

Push this as a PR. You should see the five checks run, a handful of annotations appear inline on the diff, and the `Orca Gate` check fail. Flip any one finding (for example, pin `Jinja2>=3.1.4`) and re-push — the corresponding annotation clears and the gate shrinks toward green.

## Customizing for a customer

Realistic adjustments to mention in a POV working session:

- **Monorepo with multiple projects**: set `path:` per job to a subdirectory, or duplicate jobs with different `project_key` values so each product team gets its own Orca project
- **Matrix across languages**: SAST supports multiple languages in one run; no matrix needed. For SCA, a matrix over subdirectories is sometimes useful if manifests live in separate services
- **Self-hosted runners**: the dedicated actions run on any Linux runner. The image-scan job needs Docker available
- **Tokens per environment**: use GitHub Environments (staging/prod) to scope the API token by branch
- **Waivers**: manage in Orca via AppSec → Findings → Waive. Keeping waivers out of YAML means ops can adjust without a code change

## Troubleshooting

**`ORCA_SECURITY_API_TOKEN` missing or invalid**
Check the repo secret is set, that it has the *Shift Left User* role, and that the service-token flag was enabled so it didn't expire with the user session.

**Image job fails on `docker build`**
The workflow expects `sample-app/Dockerfile`. Point `working-directory` at your actual Dockerfile location.

**SARIF upload fails**
Confirm `permissions.security-events: write` is set in the workflow. Some repos inherit a more restrictive default from org settings.

**Orca Gate passes but you expected it to fail**
Check the policy in the Orca UI. Gate follows policy decision, not raw finding count.

## References

- IaC scanning via Orca CLI — docs.orcasecurity.io/iac-scanning-via-orca-cli
- SAST GitHub Action — docs.orcasecurity.io/sast-github-actions
- SCA GitHub Action — docs.orcasecurity.io/sca-github-action
- IaC GitHub Action — docs.orcasecurity.io/iac-scan-github-actions
- Container image + GitHub Actions — docs.orcasecurity.io/container-image-scanning-integrating-orca-cli-with-github-actions
- Orca CLI installation — docs.orcasecurity.io/orca-cli-installation

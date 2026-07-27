# Orca IaC scanning in Atlantis + Terragrunt

An Atlantis setup that runs an Orca IaC scan on every `plan` and blocks `apply` when the scan fails policy.

There is no Orca-documented Atlantis integration, so this is built from the documented primitives on both sides: Atlantis custom workflows, and Orca's support for Terraform plan JSON as a first-class IaC platform.

## The core idea

**Scan the rendered plan, not the source files.**

This is the whole design, and it matters more with Terragrunt than with plain Terraform. A `terragrunt.hcl` contains no resources — it names a module `source` and a set of `inputs`. The resources are in the module; the settings that decide whether those resources are safe are in the inputs. Neither file, read on its own, contains the misconfiguration.

Look at [`live/prod/s3-data/terragrunt.hcl`](live/prod/s3-data/terragrunt.hcl) and [`modules/s3-bucket/main.tf`](modules/s3-bucket/main.tf). The module's defaults are all secure. The prod unit overrides three of them. The public, unencrypted bucket only exists after Terragrunt merges the two — which is exactly what `terragrunt show -json` produces:

```bash
terragrunt init
terragrunt plan -out tf.plan
terragrunt show -json tf.plan > tf.json
orca-cli --project-key <KEY> iac scan --path tf.json
```

Orca parses the plan's `planned_values` and evaluates them as Terraform, with findings pointing at the plan file. Everything is already resolved at that point — no unresolved `var.` references, no guessing at what a module call expands to.

## What's here

| File | Purpose |
|---|---|
| [`atlantis.yaml`](atlantis.yaml) | Repo-level config: three projects and the gated workflow. Good for demos. |
| [`server-config/repos.yaml`](server-config/repos.yaml) | The same workflow defined server-side, where a PR can't edit it. **Use this to actually enforce.** |
| [`Dockerfile`](Dockerfile) | Atlantis image with `terragrunt` and `orca-cli` on PATH. |
| [`terragrunt.hcl`](terragrunt.hcl) | Root config: provider and state generation. |
| `live/dev/s3-data/` | Control case — takes the module's secure defaults, passes the gate. |
| `live/prod/s3-data/` | Public + unencrypted bucket, entirely via inputs. Fails the gate. |
| `live/prod/rds/` | Internet-facing unencrypted database, open CIDR, literal password. Fails the gate. |
| `modules/` | Two ordinary modules. Nothing wrong with either of them. |

## Prerequisites

1. A self-hosted Atlantis with permission to change its image and server config. Custom workflows are the integration point, so a managed Atlantis you can't configure won't work.
2. An Orca API token with the **Shift Left User** role, set as `ORCA_SECURITY_API_TOKEN` **in the Atlantis server's environment** — not in any repo file. `orca-cli` reads it from the environment automatically.
3. An Orca AppSec project key. The workflow uses `demo-atlantis-terragrunt`; change it.
4. A policy in Orca set to fail on the severities you care about. As with the GitHub Actions example in this repo, the pass/fail decision is Orca's, not a CLI flag's.

## Setup

**1. Build the image** and point your Atlantis deployment at it:

```bash
docker build -t your-registry/atlantis-orca:v0.46.0 examples/atlantis-terragrunt
```

**2. Install the server-side config.** Mount [`server-config/repos.yaml`](server-config/repos.yaml) into the container and set:

```text
ATLANTIS_REPO_CONFIG=/etc/atlantis/repos.yaml
ORCA_SECURITY_API_TOKEN=<token>
```

**3. Copy `atlantis.yaml` to your repo root** and adjust the `dir:` values to your own terragrunt layout. With the server-side config above, the repo file only needs the `projects:` block — the `workflows:` block is ignored once `allow_custom_workflows: false`.

**4. Make it required.** Atlantis reports plan status back to the PR as a check, so add that check to branch protection alongside your existing required checks.

## Demo script

The dev/prod split is built for a side-by-side walkthrough.

```text
atlantis plan -p dev-s3-data
```

Passes. The plan renders, the scan runs clean, apply is available.

```text
atlantis plan -p prod-s3-data
```

Fails. The PR comment shows the Orca findings table — public-read ACL, public access block disabled, no encryption at rest — and the workflow stops. There is no plan output, so `atlantis apply` has nothing to apply.

The point to make out loud at this stage: **open `live/prod/s3-data/terragrunt.hcl` and `modules/s3-bucket/main.tf` side by side and ask where the public bucket is.** It isn't in either file. A scanner pointed at HCL finds nothing; this one finds three things.

Then fix it live — set `acl = "private"`, `block_public_access = true`, `enable_encryption = true` — and re-run. The gate goes green in the same PR.

`atlantis plan -p prod-rds` adds a second angle: the IaC findings and a secrets finding (`master_password` as a literal) on the same file.

## How the gate works

`orca-cli` exits `3` when the policy decision is *fail*. Atlantis stops a workflow on any non-zero exit code. Those two facts are the entire mechanism:

- Scan fails → workflow stops → no plan output → nothing for `apply` to consume.
- The scan is in `plan`, not `apply`, on purpose. `apply` consumes the plan file the gated phase produced, so gating `plan` gates both. Re-scanning on apply would only add latency.

To pilot without blocking, flip the Orca policy to *Warn only* — no config change. If you need a per-repo escape hatch, `orca-cli --exit-code 0` makes the scan advisory, but put that in the server-side config so a repo can't set it for itself.

## Security notes

Two things worth being deliberate about.

**A repo-level workflow is not a control.** Anyone who can open a PR can edit `atlantis.yaml` — delete the Orca step, or add one that echoes `$ORCA_SECURITY_API_TOKEN` into a PR comment. Define the workflow in `server-config/repos.yaml` with `allow_custom_workflows: false`. The repo-level file in this directory is a demo convenience and says so at the top.

**The rendered plan can contain secrets in plaintext.** `terraform show -json` writes sensitive input values into the plan JSON. Atlantis workspaces persist on the server between runs, so the scan step writes `orca-plan.json` inside the project directory and removes it via a `trap ... EXIT` — which fires even when the scan exits 3 and the workflow stops. Don't change that to a separate cleanup step; a separate step never runs on the failure path. Don't upload the plan JSON as a build artifact either.

## Demo mode: no cloud credentials

[`terragrunt.hcl`](terragrunt.hcl) generates a provider with static dummy credentials and `skip_credentials_validation` / `skip_metadata_api_check` / `skip_requesting_account_id`, plus a `local` state backend. That renders a complete, scannable plan with no AWS access at all, which makes this demoable without asking anyone for cloud credentials.

Both are marked in the file. Remove the skips and swap the commented S3 backend in when you point this at a real account.

## If you can't run `plan` in CI

Plan-based scanning needs `terragrunt init`, which needs backend and provider access. If a customer won't grant that yet, scan the modules statically as an interim step — point `orca-cli iac scan --path modules/` at the Terraform directly, or use `orcasecurity/shiftleft-iac-action` in GitHub Actions the way the root of this repo does.

Be honest about what that buys: it catches hardcoded misconfigurations inside modules, and it will miss every finding in this example, because all of them come from inputs. It's a floor, not a substitute.

## Troubleshooting

**`terragrunt: command not found` in the plan output**
The Atlantis image doesn't have it. Use the [`Dockerfile`](Dockerfile) here rather than installing tools in a `run` step.

**The Orca step is skipped entirely**
The repo's `atlantis.yaml` is overriding the workflow. Check `allow_custom_workflows` and `allowed_overrides` in the server-side config.

**`Error: no configuration files` from `terragrunt show`**
`$PLANFILE` was never written, which means `terragrunt plan` failed earlier in the workflow. Read the plan step's output, not the scan step's.

**Scan runs but reports nothing on a unit you know is misconfigured**
Confirm it's scanning the plan JSON and not the HCL. `--path orca-plan.json`, not `--path .`.

**Findings appear but the plan still succeeds**
The Orca policy is in warn mode, or `--exit-code 0` is set somewhere.

## References

Docs are region-gated; sign in to your tenant first.

- IaC — Supported Platforms (Terragrunt and plan-JSON sections) — docs.orcasecurity.io/iac-supported-platforms
- IaC Security via the Orca CLI — docs.orcasecurity.io/iac-scanning-via-orca-cli
- Atlantis custom workflows — runatlantis.io/docs/custom-workflows.html
- Atlantis repo-level `atlantis.yaml` — runatlantis.io/docs/repo-level-atlantis-yaml.html
- Atlantis server-side repo config — runatlantis.io/docs/server-side-repo-config.html

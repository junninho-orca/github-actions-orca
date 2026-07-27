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
| [`atlantis.yaml`](atlantis.yaml) | Repo-level config: three projects and the gated workflow. Readable reference and quick demo. |
| [`server-config/repos.yaml`](server-config/repos.yaml) | The same workflow defined server-side, plus policy owners. **Use this to actually enforce.** |
| [`server-config/policies/`](server-config/policies/orca-iac-placeholder/README.md) | A placeholder policy set that exists only to satisfy Atlantis config validation. Conftest never runs. |
| [`Dockerfile`](Dockerfile) | Atlantis image with `terragrunt` and `orca-cli` on PATH. |
| [`terragrunt.hcl`](terragrunt.hcl) | Root config: provider and state generation. |
| `live/dev/s3-data/` | Control case — takes the module's secure defaults, passes the gate. |
| `live/prod/s3-data/` | Public + unencrypted bucket, entirely via inputs. Fails the gate. |
| `live/prod/rds/` | Internet-facing unencrypted database, open CIDR, literal password. Fails the gate. |
| `modules/` | Two ordinary modules. Nothing wrong with either of them. |

## Prerequisites

1. A self-hosted Atlantis with permission to change its image, server flags, and server config. Custom workflows and policy checks are the integration points, so a managed Atlantis you can't configure won't work.
2. **Policy checks enabled on the server** — `--enable-policy-checks` / `ATLANTIS_ENABLE_POLICY_CHECKS=true`. Without this the gate does not exist; see *How the gate works*.
3. An Orca API token with the **Shift Left User** role, set as `ORCA_SECURITY_API_TOKEN` **in the Atlantis server's environment** — not in any repo file. `orca-cli` reads it from the environment automatically.
4. An Orca AppSec project key. The workflow uses `demo-atlantis-terragrunt`; change it.
5. A policy in Orca set to fail on the severities you care about. As with the GitHub Actions example in this repo, the pass/fail decision is Orca's, not a CLI flag's.

## Setup

**1. Build the image** and point your Atlantis deployment at it:

```bash
docker build -t your-registry/atlantis-orca:v0.46.0 examples/atlantis-terragrunt
```

**2. Install the server-side config.** Mount [`server-config/repos.yaml`](server-config/repos.yaml) and the placeholder policy directory into the container, then set:

```text
ATLANTIS_REPO_CONFIG=/etc/atlantis/repos.yaml
ATLANTIS_ENABLE_POLICY_CHECKS=true
ORCA_SECURITY_API_TOKEN=<token>
```

Mount points must match the `path` in the `policy_sets` entry:

```text
server-config/repos.yaml                      -> /etc/atlantis/repos.yaml
server-config/policies/orca-iac-placeholder/  -> /etc/atlantis/policies/orca-iac-placeholder/
```

Edit `policies.owners` in `repos.yaml` to your actual security reviewers — those are the people who can override a failed scan with `atlantis approve_policies`.

**3. Copy `atlantis.yaml` to your repo root** and adjust the `dir:` values to your own terragrunt layout. With the server-side config above, the repo file only needs the `projects:` block — the `workflows:` block is ignored once `allow_custom_workflows: false`.

**4. Make it required.** Atlantis reports both plan and policy check status back to the PR. Add the policy check to branch protection alongside your existing required checks — but note that this is defence in depth, not the gate: `atlantis apply` runs before the merge, so `policies_passed` is what actually stops a deploy.

## Demo script

The dev/prod split is built for a side-by-side walkthrough.

```text
atlantis plan -p dev-s3-data
```

Plan renders, policy check passes, apply is available.

```text
atlantis plan -p prod-s3-data
```

Plan renders fine — the Terraform is valid. The **policy check** then fails, and the PR comment shows the Orca findings: public-read ACL, public access block disabled, no encryption at rest.

Now do the part that makes the demo land: **comment `atlantis apply`.** It is refused, because `policies_passed` is unmet. This is the beat worth slowing down on with a customer who has been burned by advisory-only scanners — the finding isn't a comment someone can scroll past, it's an unmet apply requirement.

Then the technical point: **open `live/prod/s3-data/terragrunt.hcl` and `modules/s3-bucket/main.tf` side by side and ask where the public bucket is.** It isn't in either file. A scanner pointed at HCL finds nothing; this one finds three things.

Two ways to clear it, both worth showing:

- **Fix it** — set `acl = "private"`, `block_public_access = true`, `enable_encryption = true`, re-plan. Green in the same PR.
- **Override it** — `atlantis approve_policies` as a configured policy owner. With `approve_count: 2` that needs two owners, and the approval is discarded on the next plan. That's the auditable exception path for a real deadline, as opposed to someone quietly commenting out a CI step.

`atlantis plan -p prod-rds` adds a second angle: IaC findings plus a secrets finding (`master_password` as a literal) on the same file.

## How the gate works

The scan runs in Atlantis's **`policy_check`** phase, not in `plan`. That placement is the whole enforcement story, and it is easy to get wrong.

`orca-cli` exits `3` when the policy decision is *fail*, which fails the phase. When the server runs with `--enable-policy-checks`, Atlantis appends `policies_passed` to every project's apply requirements, so a failed phase blocks `atlantis apply`. `policies_passed` is in Atlantis's `NonOverridableApplyReqs`, and the config loader re-adds it even when a repo supplies its own `apply_requirements` — so a pull request cannot drop it.

### Why not just add a `run` step to `plan`

Because it doesn't gate anything. This is worth understanding before adapting this example:

- `terragrunt plan -out=$PLANFILE` has already written the plan file by the time a later step in the same phase runs.
- Atlantis finds applyable plans with `DefaultPendingPlanFinder`, which walks the workspace for untracked `*.tfplan` files. It does not check whether the plan workflow succeeded.
- Plans are deleted on error only when `automerge` is enabled.

So a scan that fails in the `plan` phase leaves an applyable plan file on disk, and a bare `atlantis apply` comment will apply it. The PR shows a red plan and the change ships anyway.

This bites harder in Atlantis than in a merge-gated pipeline: **`atlantis apply` runs before the PR merges.** Branch protection sits downstream of the thing you're trying to prevent, so it can't be the control. That's the inverse of the GitHub Actions example at the root of this repo, where the merge *is* the deploy gate.

### Overrides and piloting

- **Pilot without blocking:** flip the Orca policy to *Warn only*. No config change.
- **Per-PR exception:** `atlantis approve_policies`, gated by the `owners` in [`server-config/repos.yaml`](server-config/repos.yaml) with `approve_count: 2`. Approvals are discarded on re-plan by default, so an override can't silently survive a force-push. Prefer this path — it leaves a trail.
- **Blanket advisory mode:** `orca-cli --exit-code 0`. Put it in the server-side config so a repo can't set it for itself.

### Fail-closed

`set -euo pipefail` in the scan step means a scanner error — bad token, network failure, malformed plan — also exits non-zero and fails the phase. A gate that waves changes through when the scanner is broken isn't one.

## Security notes

Two things worth being deliberate about.

**A repo-level workflow is not a control.** Anyone who can open a PR can edit `atlantis.yaml` — delete the Orca step, or add one that echoes `$ORCA_SECURITY_API_TOKEN` into a PR comment. Define the workflow in `server-config/repos.yaml` with `allow_custom_workflows: false`. The repo-level file in this directory is a demo convenience and says so at the top.

Note that `policies_passed` and `allow_custom_workflows: false` defend different things. The first stops a repo from *dropping the requirement*; the second stops it from *rewriting the step that satisfies it*. You want both — with a repo-editable workflow, a PR could replace the scan with `exit 0` and legitimately pass the policy check.

**The rendered plan can contain secrets in plaintext.** `terraform show -json` writes sensitive input values into the plan JSON. Atlantis workspaces persist on the server between runs, so the scan step writes `orca-plan.json` inside the project directory and removes it via a `trap ... EXIT` — which fires even when the scan exits 3 and the phase fails. Don't change that to a separate cleanup step; a separate step never runs on the failure path. Don't upload the plan JSON as a build artifact either.

## Demo mode: no cloud credentials

[`terragrunt.hcl`](terragrunt.hcl) generates a provider with static dummy credentials and `skip_credentials_validation` / `skip_metadata_api_check` / `skip_requesting_account_id`, plus a `local` state backend. That renders a complete, scannable plan with no AWS access at all, which makes this demoable without asking anyone for cloud credentials.

Both are marked in the file. Remove the skips and swap the commented S3 backend in when you point this at a real account.

## Scaling past a demo

Three things in here are sized for a three-unit example and will not hold at customer scale.

**Hand-maintained `projects:`.** The community standard for Terragrunt repos is generating `atlantis.yaml` with [`terragrunt-atlantis-config`](https://github.com/transcend-io/terragrunt-atlantis-config), which walks the Terragrunt dependency graph to emit projects and `when_modified` automatically. Adopt it and treat the `projects:` block here as illustrative — keep the `workflows:` block, since that is the part carrying the Orca gate. The generated file still needs the server-side config to be authoritative.

**Dependency-blind `when_modified`.** The globs here cover each unit's own HCL and its module, but they know nothing about Terragrunt `dependency` blocks. Change an upstream unit and its dependents will not replan, so a downstream plan can be scanned while stale. `terragrunt-atlantis-config` solves this properly; a hand-written config cannot.

**`parallel_plan: true` with a shared module.** Concurrent units downloading and initialising the same module can contend on the Terragrunt cache. Consider a shared provider cache (`TF_PLUGIN_CACHE_DIR`), or drop to serial plans if you see flakiness that looks like corrupt cache state rather than real errors.

## If you can't run `plan` in CI

Plan-based scanning needs `terragrunt init`, which needs backend and provider access. If a customer won't grant that yet, scan the modules statically as an interim step — point `orca-cli iac scan --path modules/` at the Terraform directly, or use `orcasecurity/shiftleft-iac-action` in GitHub Actions the way the root of this repo does.

Be honest about what that buys: it catches hardcoded misconfigurations inside modules, and it will miss every finding in this example, because all of them come from inputs. It's a floor, not a substitute.

## Troubleshooting

**`terragrunt: command not found` in the plan output**
The Atlantis image doesn't have it. Use the [`Dockerfile`](Dockerfile) here rather than installing tools in a `run` step.

**The policy check never runs, and the plan comment is the only output**
The server isn't running with `--enable-policy-checks`. This is the failure mode to check first, because everything looks like it works — the plan succeeds, no scan appears, and nothing is gated.

**`policy_sets: cannot be empty; Declare policies that you would like to enforce`**
Atlantis rejects a `policies:` block without at least one policy set. Keep the placeholder entry and mount its directory — see [`server-config/policies/orca-iac-placeholder/README.md`](server-config/policies/orca-iac-placeholder/README.md).

**The Orca step is skipped entirely**
The repo's `atlantis.yaml` is overriding the workflow. Check `allow_custom_workflows` and `allowed_overrides` in the server-side config.

**`Error: no configuration files` from `terragrunt show`**
`$PLANFILE` was never written, which means `terragrunt plan` failed in the plan phase. Read the plan output, not the policy check output.

**Scan runs but reports nothing on a unit you know is misconfigured**
Confirm it's scanning the plan JSON and not the HCL. `--path orca-plan.json`, not `--path .`.

**Findings appear but `atlantis apply` is still allowed**
The Orca policy is in warn mode, `--exit-code 0` is set somewhere, or a policy owner has already run `approve_policies` on this PR. `atlantis approve_policies --clear-policy-approval` resets the last case.

**Everything passes but you can't tell whether the scan actually ran**
The scan is in `policy_check`, so its output is in the policy check comment, not the plan comment. If there's no policy check comment at all, see the first entry.

## References

Docs are region-gated; sign in to your tenant first.

- IaC — Supported Platforms (Terragrunt and plan-JSON sections) — docs.orcasecurity.io/iac-supported-platforms
- IaC Security via the Orca CLI — docs.orcasecurity.io/iac-scanning-via-orca-cli
- Atlantis policy checking (`policy_check`, `policies_passed`, `approve_policies`) — runatlantis.io/docs/policy-checking.html
- Atlantis custom workflows — runatlantis.io/docs/custom-workflows.html
- Atlantis repo-level `atlantis.yaml` — runatlantis.io/docs/repo-level-atlantis-yaml.html
- Atlantis server-side repo config — runatlantis.io/docs/server-side-repo-config.html
- `terragrunt-atlantis-config` — github.com/transcend-io/terragrunt-atlantis-config

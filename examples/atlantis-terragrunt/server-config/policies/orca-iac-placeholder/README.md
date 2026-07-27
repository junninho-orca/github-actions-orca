# Placeholder policy set

This directory exists to satisfy Atlantis config validation, not to enforce anything.

Atlantis requires `policies.policy_sets` to be non-empty whenever a `policies:` block is present — the validator rejects an empty list with *"cannot be empty; Declare policies that you would like to enforce"*. The `policies:` block is present in [`../../repos.yaml`](../../repos.yaml) because its `owners` field is what enables `atlantis approve_policies` as an owner-gated, auditable override.

Because that config also sets `custom_policy_check: true` and replaces the default `policy_check` steps entirely, Conftest is never invoked and [`no_op.rego`](no_op.rego) is never evaluated. The actual policy decision is Orca's, made server-side against your AppSec project policy.

Mount this directory into the Atlantis container at the `path` given in `repos.yaml`:

```text
/etc/atlantis/policies/orca-iac-placeholder
```

If you also want real Conftest policies alongside the Orca scan, add a second `policy_sets` entry pointing at them and add a `conftest` step back into the `policy_check` phase. The two coexist fine — Atlantis runs the phase's steps in order, and any non-zero exit fails the phase.

# Intentionally free of deny rules. See README.md in this directory: this file
# exists so that policies.policy_sets is non-empty, which Atlantis requires
# whenever a policies: block is present. Conftest is never invoked here —
# custom_policy_check is true and the policy_check steps are fully overridden by
# the Orca scan.
package main

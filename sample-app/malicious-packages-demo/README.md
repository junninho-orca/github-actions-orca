# Malicious package demo

`requirements.txt` in this directory exists so the SCA job has a malicious package to flag. It is **scanned but never installed**.

## Why it's a separate manifest

`sample-app/Dockerfile` runs `pip install -r requirements.txt` during the Container Image job. Putting a malicious package in that manifest would execute it on the runner — `abseil-py` in particular exfiltrates host information at install time. Two layers keep that from happening:

1. The Dockerfile copies `requirements.txt` and `src/` only. This directory is never copied.
2. `sample-app/.dockerignore` excludes this directory from the build context, so even a later `COPY . .` cannot pull it in.

Both packages were also removed from PyPI, so `pip` cannot resolve them today. Treat that as a backstop, not the safety mechanism — the safety mechanism is that no installer is ever pointed at this file.

## Why the scan still sees it

The SCA job scans `path: .` recursively, and the file is named `requirements.txt`, so pip's analyzer picks it up with no `file_patterns` configuration needed.

## Verifying the entries are real

Orca's Malicious Packages knowledge base is built primarily from OSV.dev. Both entries are catalogued there, so you can check them without an Orca tenant:

```bash
curl -s https://api.osv.dev/v1/vulns/MAL-2023-1574 | python3 -m json.tool
```

| Package | Advisory | What it is |
|---|---|---|
| `aaiohttp` | [MAL-2023-1574](https://osv.dev/vulnerability/MAL-2023-1574) | Typosquat of `aiohttp`, from the 2023 campaign that pushed 900+ packages to PyPI to hijack clipboard crypto wallet addresses |
| `abseil-py==0.1.0` | [MAL-2026-10760](https://osv.dev/vulnerability/MAL-2026-10760) | Typosquat of `absl-py`; exfiltrates host information on install or import and has no other purpose |

## Expected result

With the project attached to **Orca Built-in - Malicious Packages Policy** in Block mode, the SCA job fails, `Orca Gate` blocks the PR, and the findings appear under **Security → Code scanning** in the `orca-sca` category. Filter the Orca alerts page by the `shiftleft:malicious_packages` label to see them platform-side.

If the SCA job passes, the policy is almost certainly not attached to the project, or is set to Warn. Detection and enforcement are configured separately.

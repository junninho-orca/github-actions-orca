# Malicious package demo

`requirements.txt` in this directory exists so the SCA job has a malicious package to flag. It is **scanned but never installed**.

## Why it's a separate manifest

`sample-app/Dockerfile` runs `pip install -r requirements.txt` during the Container Image job. Putting a malicious package in that manifest would execute it on the runner — `abseil-py` exfiltrates host information at install time. Two layers keep that from happening:

1. The Dockerfile copies `requirements.txt` and `src/` only. This directory is never copied.
2. `sample-app/.dockerignore` excludes this directory from the build context, so even a later `COPY . .` cannot pull it in.

The package was also removed from PyPI, so `pip` cannot resolve it today. Treat that as a backstop, not the safety mechanism — the safety mechanism is that no installer is ever pointed at this file.

## Why the scan still sees it

The SCA job scans `path: .` recursively, and the file is named `requirements.txt`, so pip's analyzer picks it up with no `file_patterns` configuration needed.

## Verifying the entry is real

Orca's Malicious Packages knowledge base is built primarily from OSV.dev. It is catalogued there, so you can check it without an Orca tenant:

```bash
curl -s https://api.osv.dev/v1/vulns/MAL-2026-10760 | python3 -m json.tool
```

| Package | Advisory | What it is |
|---|---|---|
| `abseil-py==0.1.0` | [MAL-2026-10760](https://osv.dev/vulnerability/MAL-2026-10760) | Typosquat of `absl-py`; exfiltrates host information on install or import and has no other purpose |

## Expected result

With the project attached to **Orca Built-in - Malicious Packages Policy** in Block mode, the SCA job fails (verified in run 30312980361), `Orca Gate` blocks the PR, and the findings appear under **Security → Code scanning** in the `orca-sca` category. Filter the Orca alerts page by the `shiftleft:malicious_packages` label to see them platform-side.

If the SCA job passes, either the policy is not attached to the project (the scan errors out rather than skipping — see the root README), or it is set to Warn.

## Pin every entry

The scanner matches on an installed version. An unpinned requirement has no INSTALLED VERSION, so it is never flagged — the scan reports clean and says nothing about it. An earlier revision of this file listed `aaiohttp` (MAL-2023-1574) unpinned, reasoning that every version of it was malicious; the scan silently ignored the line. If you add entries here, pin them to a version the advisory names.

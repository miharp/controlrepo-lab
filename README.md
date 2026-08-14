# matrix-lab

One Ubuntu 24.04 VM (matching the Vox Pupuli fleet per
`site/profiles/metadata.json`) that runs [voxpupuli/controlrepo] PR #153 —
the "Setup Matrix Synapse" deployment for `matrix01.voxpupu.li` — exactly
the way that repo is designed to run: masterless `puppet apply` (its
site.pp carries a pluginsync hack specifically for this).

[voxpupuli/controlrepo]: https://github.com/voxpupuli/controlrepo/pull/153

## Status: mission accomplished (2026-08-13)

The lab found and fixed **19 defects** in the PR — 8 compile blockers,
11 runtime/deployment issues — all as individual commits on the local
`matrix-fixes` branch in `../voxpupuli_controlrepo` (Gene's original
commit preserved as the base). Final validation: a virgin
`vagrant destroy -f && vagrant up` converges from nothing with zero
manual steps — full worker fleet healthy, client API served through
nginx, delegation well-knowns with JSON + CORS.

Write-ups:

- `~/projects/pr153-findings-report.md` — the findings narrative
  (for #sig-matrix-ops / the new PR conversation)
- `~/projects/pr153-new-pr-body.md` — paste-ready PR description
- `~/projects/pr153-review-notes.md` — raw review notes

Nothing has been pushed upstream; the branch ships only after
coordinating with GeneBean in #sig-matrix-ops.

## Prerequisites

- `../voxpupuli_controlrepo` checked out as a sibling, on the
  `matrix-fixes` branch (or `gh pr checkout 153` for the unfixed
  original)
- Vagrant + Parallels

## Use

```console
vagrant up                    # provision + first apply
./scripts/converge            # edit the checkout, re-apply (live share, no commit needed)
./scripts/converge --check    # ...and probe the client API, well-known, containers
```

The lab overlays `hiera-lab-overrides.yaml` onto the node's hiera data in
the VM's copy only — dummy secrets and `manage_borg: false`. Your
controlrepo checkout is mounted read-only and never modified.

`scripts/apply` tolerates puppet exit code 6 (changes + failures)
because certbot always fails in the lab — inspect output for anything
that isn't ACME.

## Expected lab-only failures (not findings)

- certbot/ACME fails against the fake domains → nginx stays HTTP-only
  (the profile's fact-guard handles this by design); probe over http://
- S3 media storage points at a dummy endpoint → uploads/eviction
  untestable; Synapse itself runs
- The lab is arm64 (Parallels); the fleet is x86. Everything here is
  multi-arch, but a one-hour Hetzner x86 spot-check before shipping the
  branch upstream is cheap insurance.

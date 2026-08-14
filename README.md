# matrix-lab

One Ubuntu 24.04 VM (matching the Vox Pupuli fleet per
`site/profiles/metadata.json`) that runs [voxpupuli/controlrepo] PR #153 —
the "Setup Matrix Synapse" deployment for `matrix01.voxpupu.li` — exactly
the way that repo is designed to run: masterless `puppet apply` (its
site.pp carries a pluginsync hack specifically for this).

[voxpupuli/controlrepo]: https://github.com/voxpupuli/controlrepo/pull/153

## Status: mission accomplished (2026-08-13)

The lab found and fixed **19 defects** in the PR — 8 compile blockers,
11 runtime/deployment issues — all as individual commits on the
`matrix-fixes` branch (Gene's original commit preserved as the base). Final validation: a virgin
`vagrant destroy -f && vagrant up` converges from nothing with zero
manual steps — full worker fleet healthy, client API served through
nginx, delegation well-knowns with JSON + CORS.

The fixed branch lives at
[miharp/controlrepo `matrix-fixes`](https://github.com/miharp/controlrepo/tree/matrix-fixes)
([full diff](https://github.com/voxpupuli/controlrepo/compare/production...miharp:controlrepo:matrix-fixes)).
A detailed findings write-up is available on request; commit messages
carry the per-fix reasoning.

## Prerequisites

- [Vagrant](https://developer.hashicorp.com/vagrant/install) with any
  provider the [`bento/ubuntu-24.04`](https://portal.cloud.hashicorp.com/vagrant/discover/bento/ubuntu-24.04)
  box supports — VirtualBox, Parallels, VMware Desktop, libvirt. The box
  ships amd64 and arm64 variants, so Apple Silicon works natively. The
  VM wants 6 GB RAM / 4 CPUs.
- The controlrepo checked out as a sibling directory named
  `voxpupuli_controlrepo`:

  ```console
  # the fixed branch:
  git clone -b matrix-fixes https://github.com/miharp/controlrepo ../voxpupuli_controlrepo

  # or the unfixed original, to reproduce the findings:
  git clone https://github.com/voxpupuli/controlrepo ../voxpupuli_controlrepo
  cd ../voxpupuli_controlrepo && gh pr checkout 153
  ```

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
- On an arm64 host (e.g. Apple Silicon) the lab runs arm64; the fleet
  is x86. Everything here is multi-arch, but a one-hour Hetzner x86
  spot-check before shipping the branch upstream is cheap insurance.

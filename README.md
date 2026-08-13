# matrix-lab

One Debian 12 VM that runs [voxpupuli/controlrepo] PR #153 — the stalled
"Setup Matrix Synapse" deployment for `matrix01.voxpupu.li` — exactly the
way that repo is designed to run: masterless `puppet apply` (its site.pp
carries a pluginsync hack specifically for this). The point is to turn
review opinions into observed facts before offering fixes upstream in
#sig-matrix-ops.

[voxpupuli/controlrepo]: https://github.com/voxpupuli/controlrepo/pull/153

## Findings this lab exists to confirm (see ~/projects/pr153-review-notes.md)

- the `lookup_options` regex typo (`profile::` vs `profiles::`) breaking
  the Sensitive conversion at compile time
- the empty `.well-known/matrix/{client,server}` delegation files
- ananace's nginx comments: deprecated-only media paths, the garbled
  client-paths regex, the 60s sync timeout
- unpinned `matrixdotorg/synapse:latest` (schema-migration hazard)
- whatever else only a real converge reveals (choria? docker on arm64?)

## Prerequisites

- `../voxpupuli_controlrepo` checked out as a sibling, on the `matrix` PR
  branch (`gh pr checkout 153`) or your fix branch
- Vagrant + Parallels

## Use

```console
vagrant up                    # provision + first apply
./scripts/converge            # edit the checkout, re-apply (live share, no commit needed)
./scripts/converge --check    # ...and probe the client API, well-known, containers
```

The lab overlays `hiera-lab-overrides.yaml` onto the node's hiera data in
the VM's copy only — dummy secrets, `manage_borg: false`, and the
corrected Sensitive regex. Your controlrepo checkout is mounted read-only
and never modified.

## Expected lab-only failures (not findings)

- certbot/ACME fails against the fake domains → nginx stays HTTP-only
  (the profile's fact-guard handles this by design); probe over http://
- S3 media storage points at a dummy endpoint → uploads/eviction
  untestable; Synapse itself runs
- Anything reaching Vox production infra (choria brokers, borg) may need
  further lab overrides — add them to `hiera-lab-overrides.yaml` and note
  them as deployment-coupling observations

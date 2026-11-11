# controlrepo-lab

Ubuntu 24.04 VMs (matching the Vox Pupuli fleet per
`site/profiles/metadata.json`) that run [voxpupuli/controlrepo] roles
exactly the way that repo is designed to run: masterless `puppet apply`
(its site.pp carries a pluginsync hack specifically for this).

Machines:

- `matrix01` — `roles::matrix_server`, the PR #153/#202 Matrix Synapse
  deployment (the lab's original mission)
- `vox01` (`vagrant up vox01`, not autostarted) — `roles::voxpupuli`
  under the real node's hostname `voxpupu.li`, added to verify the fix
  for [issue #203] (duplicate Package[certbot], which had kept that
  node's catalog uncompilable since March). Evidence:
  [evidence/vox01-certbot-fix-2026-08-14.log](evidence/vox01-certbot-fix-2026-08-14.log)
  — catalog compiles and applies with the fix; remaining failures are
  fresh-bootstrap gaps unrelated to certbot (rvm group, grafana-cli
  plugin provider, a static sentry vhost that assumes certbot ran).

[voxpupuli/controlrepo]: https://github.com/voxpupuli/controlrepo/pull/153
[issue #203]: https://github.com/voxpupuli/controlrepo/issues/203

## Status: mission accomplished (2026-08-13)

The lab found and fixed **19 defects** in the PR — 8 compile blockers,
11 runtime/deployment issues — all as individual commits on the
`matrix-fixes` branch (Gene's original commit preserved as the base). Final validation: a virgin
`vagrant destroy -f && vagrant up` converges from nothing with zero
manual steps — full worker fleet healthy, client API served through
nginx, delegation well-knowns with JSON + CORS. Full console log of a
virgin run against the final branch:
[evidence/virgin-run-2026-08-14.log](evidence/virgin-run-2026-08-14.log)
(first catalog 236s; the second apply changes nothing but the expected
ACME retries; ends with the container health table).

The fixed branch lives at
[miharp/controlrepo `matrix-synapse`](https://github.com/miharp/controlrepo/tree/matrix-synapse)
([full diff](https://github.com/voxpupuli/controlrepo/compare/production...miharp:controlrepo:matrix-synapse);
`matrix-fixes` is the same history under its older name).
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
  git clone -b matrix-synapse https://github.com/miharp/controlrepo ../voxpupuli_controlrepo

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

## Hetzner: the same role in public

`hetzner/` covers what the Vagrant VMs cannot: an x86 server, certificates
from Let's Encrypt, and federation with other homeservers. It is one
disposable Hetzner Cloud server with the real node's hostname
(`matrix01.voxpupu.li`, so hiera classifies it the same) and ports 80 and
443 open to the world.

First run, 2026-11-11 (`cpx22` in `nbg1`, Synapse v1.165.0, lab names
under `voxlab.mikeharp.com`): the first apply had no failed resources
and got both certificates; all ten containers healthy on x86; the
59-check client flow passed over public HTTPS; the public federation
tester reported `FederationOK: True`. Getting there found two bugs that
only appear once certificates exist, both invisible to the Vagrant lab:

- `ssl_session_cache` is not a parameter of `nginx::resource::server`
  (it is `ssl_cache`), so the catalog stopped compiling on the second run.
- None of the locations set `ssl => true`, so the TLS server blocks had
  no Matrix locations: every https request got a 404, and the well-known
  files came back without the JSON type and CORS header.

It needs the two names in `profiles::matrix` to be parameters
(`server_name` and `matrix_domain`), because a lab cannot get certificates
for Vox Pupuli's names. `scripts/apply` refuses to run without lab names.

### Setup

Needs `terraform`, `hcloud`, `rsync`, `dig` and `python3` on this machine.

1. Copy `hetzner/lab.env.example` to `hetzner/lab.env` and fill in the
   Hetzner API token, two DNS names you control, and a contact address
   for the lab's Let's Encrypt account. Put both names under a subdomain
   used for nothing else, and never reuse a pair that has federated: the
   example file explains the `r1`, `r2` pattern.
2. `./lab.sh address` reserves the lab's IPv4 address and prints the
   record to create: one wildcard A record under that subdomain covers
   every pair. The address survives `./lab.sh down`, so this is done
   once. `./lab.sh dns` shows when it resolves.
3. `./lab.sh up` creates the server.
4. `./lab.sh converge`, twice: the first apply gets the certificates, the
   second turns TLS on in nginx.

### Use

```console
cd hetzner
./lab.sh address     # reserve the address only (no server yet)
./lab.sh up          # create the server
./lab.sh dns         # the record to create, and whether both names resolve
./lab.sh converge    # sync ../../voxpupuli_controlrepo and apply it
./lab.sh smoke       # 59-check client flow over TLS from this machine
./lab.sh federation  # the public federation tester's verdict
./lab.sh ssh         # user lab, sudo without a password
./lab.sh down        # delete the server (keeps the address)
./lab.sh down --all  # release the address, firewall and key too
```

`scripts/smoke.py` also runs inside a Vagrant VM with no arguments:
`vagrant ssh matrix01 -c 'python3 -' < hetzner/scripts/smoke.py` after
creating users `alice` and `bob` with the password in the script.

### What differs from the Vagrant lab

- The overrides are rendered once into `hetzner/overrides/` (gitignored)
  with random secrets, because the server is public. S3 stays a dummy
  until you put a real bucket's values in that file.
- The server's copy of `profiles::lets_encrypt` gets your address in
  place of the hardcoded `pmc@voxpupuli.org`, so the lab does not
  register an ACME account in the PMC's name.
- SSH is open only to the address this machine had at `./lab.sh up`.
  Login is the `lab` user: `profiles::base` purges root's unmanaged keys.
- A failed resource fails `converge`. With real names nothing is expected
  to fail. `choria-server` is started on every run and stops again (no
  broker credentials in a lab), so a clean run exits 2, not 0.
- `converge` runs the apply as a systemd unit and follows its log. The
  first time nftables loads, it rejects the replies of SSH sessions that
  were already open, so a session running the apply itself goes silent.

Cost (November 2026): a `cx33` is about 0.016 EUR an hour while it
exists; the kept IPv4 address is about 0.50 EUR a month until
`./lab.sh down --all`. The `cx` types run out in `nbg1` at times
("error during placement"); `LAB_SERVER_TYPE=cpx22` (2 vCPU, 4 GB, about
0.037 EUR an hour) has been the fallback. The address is tied to its
location, so changing `LAB_LOCATION` means a new address and DNS record.

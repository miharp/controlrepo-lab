# controlrepo-lab

Ubuntu 24.04 machines (matching the Vox Pupuli fleet per
`site/profiles/metadata.json`) that run [voxpupuli/controlrepo] roles
exactly the way that repo is designed to run: masterless `puppet apply`
(its site.pp carries a pluginsync hack specifically for this).

There are two halves. The Vagrant VMs below are the fast local loop, on
a private network with fake names. [`hetzner/`](#hetzner-the-same-role-in-public)
is one public x86 server for what they cannot do: real certificates and
federation.

Vagrant machines:

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

[voxpupuli/controlrepo]: https://github.com/voxpupuli/controlrepo
[issue #203]: https://github.com/voxpupuli/controlrepo/issues/203

## Status

The thing under test is [PR #202], which continues [PR #153]. Its branch
is [miharp/controlrepo `matrix-synapse`](https://github.com/miharp/controlrepo/tree/matrix-synapse)
([full diff](https://github.com/voxpupuli/controlrepo/compare/production...miharp:controlrepo:matrix-synapse));
the commit messages carry the per-fix reasoning.

**August 2026, Vagrant.** The lab found and fixed 19 defects in the PR: 8
compile blockers and 11 runtime or deployment issues, one commit each on
top of Gene's original. A `vagrant destroy -f && vagrant up` then
converged from nothing with zero manual steps: full worker fleet healthy,
client API served through nginx, delegation well-knowns with JSON and
CORS. Console log:
[evidence/virgin-run-2026-08-14.log](evidence/virgin-run-2026-08-14.log)
(first catalog 236s; the second apply changes nothing but the expected
ACME retries; ends with the container health table).

**November 2026, real clients and real TLS.** That run only probed
`/_matrix/client/versions` over plain HTTP. A 59-check client flow
([hetzner/scripts/smoke.py](hetzner/scripts/smoke.py)) and the public
server found six more:

- nginx sent every client endpoint to workers that only serve a
  documented subset: 12 of the 59 checks failed (typing, receipts,
  to-device, logout and others) until the routing followed the Synapse
  worker docs
- no registration shared secret, so no account could be created
- two bugs that only appear once certificates exist (see the Hetzner
  section)
- the URL preview blacklist left out link-local addresses
- Synapse was pinned seven releases back

The Vagrant half of this repo has since been proposed for the controlrepo
itself as [PR #207], generalized to one machine per node.

[PR #153]: https://github.com/voxpupuli/controlrepo/pull/153
[PR #202]: https://github.com/voxpupuli/controlrepo/pull/202
[PR #207]: https://github.com/voxpupuli/controlrepo/pull/207

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

The lab appends `overrides/<fqdn>.yaml` to the node's hiera data in the
VM's copy only — dummy secrets and `manage_borg: false`. Your
controlrepo checkout is mounted read-only and never modified.

`--check` only probes a few endpoints. For the full client flow, create
the two test users once and run the smoke test inside the VM:

```console
vagrant ssh matrix01 -c 'for u in alice bob; do a=--no-admin; [ $u = alice ] && a=--admin
  sudo docker exec synapse-main register_new_matrix_user -c /config/homeserver.yaml \
  -u $u -p lab-password-1234 $a http://localhost:8008; done'
vagrant ssh matrix01 -c 'python3 -' < hetzner/scripts/smoke.py
```

`scripts/apply` tolerates puppet exit code 6 (changes + failures)
because certbot always fails in the lab — inspect output for anything
that isn't ACME.

## Expected lab-only failures (not findings)

- certbot/ACME fails against the fake domains → nginx stays HTTP-only
  (the profile's fact-guard handles this by design); probe over http://
- S3 media storage points at a dummy endpoint → uploads/eviction
  untestable; Synapse itself runs
- On an arm64 host (e.g. Apple Silicon) the lab runs arm64; the fleet
  is x86. `hetzner/` below is the x86 check.

## Hetzner: the same role in public

`hetzner/` covers what the Vagrant VMs cannot: an x86 server, certificates
from Let's Encrypt, and federation with other homeservers. It is one
disposable Hetzner Cloud server with the real node's hostname
(`matrix01.voxpupu.li`, so hiera classifies it the same) and ports 80 and
443 open to the world.

First run, 2026-11-11 (`cpx22` in `nbg1`, Synapse v1.165.0, lab names
under `voxlab.mikeharp.com`): the first apply had no failed resources
and got both certificates; all ten containers up on x86 and passing
their health checks; the 59-check client flow passed over public HTTPS; the public federation
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
./lab.sh smoke --from-server   # the same, requested by the server itself
./lab.sh federation  # the public federation tester's verdict
./lab.sh ssh         # user lab, sudo without a password
./lab.sh status      # what exists right now
./lab.sh down        # delete the server (keeps the address)
./lab.sh down --all  # release the address, firewall and key too
```

`--from-server` is for a resolver on this machine that was asked for the
names before the DNS record existed and still answers "no such name";
that lasts up to the zone's negative TTL.

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

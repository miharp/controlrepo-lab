# matrix-lab: run voxpupuli/controlrepo roles for real.
#
# Ubuntu 24.04 VMs (matching the Vox fleet) that apply the actual
# controlrepo masterless — which is
# how that repo is designed to run (see the pluginsync hack in its site.pp).
# The controlrepo working tree is synced from the sibling checkout
# (../voxpupuli_controlrepo, on the branch under test), so the
# loop is: edit in the checkout, ./scripts/converge, read the diff of
# reality. No commit needed — this lab iterates on open PRs,
# so working-tree speed beats committed-code discipline here.
#
# Machines (bring up only what you need):
#   matrix01  roles::matrix_server  (PR #153/#202 validation)
#   vox01     roles::voxpupuli      (issue #203 certbot-fix validation;
#                                    hostname voxpupu.li, the real node's)
#
# Expectations on a lab box (documented, not bugs):
#   - certbot/ACME fails (fake domains) -> nginx serves HTTP-only, which the
#     profile's letsencrypt_directory fact-guard handles by design
#   - S3 creds are dummies -> media upload/eviction untestable, Synapse runs
#   - hiera secrets come from a lab override appended to the node yaml
#     (see overrides/<fqdn>.yaml)
#
# 192.168.59.x — mattermost-lab holds .58.x, codavox-lab .57.x.

PROVISION = <<-'SHELL'
  set -euo pipefail

  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq
  # git: r10k needs a functional git provider for git-sourced modules
  apt-get install -y -qq curl gnupg rsync git >/dev/null

  if ! dpkg -s openvox8-release >/dev/null 2>&1; then
    curl -sfLo /tmp/openvox8-release.deb https://apt.voxpupuli.org/openvox8-release-ubuntu24.04.deb
    dpkg -i /tmp/openvox8-release.deb
    apt-get update -qq
  fi
  apt-get install -y -qq openvox-agent >/dev/null

  # The controlrepo's hiera.yaml declares the eyaml backend; the gem
  # must exist even though the lab data holds no ENC values. Dummy
  # keys satisfy the configured paths.
  /opt/puppetlabs/puppet/bin/gem list -i r10k >/dev/null 2>&1 || \
    /opt/puppetlabs/puppet/bin/gem install r10k --no-document
  /opt/puppetlabs/puppet/bin/gem list -i hiera-eyaml >/dev/null 2>&1 || \
    /opt/puppetlabs/puppet/bin/gem install hiera-eyaml --no-document
  if [ ! -f /etc/puppetlabs/puppet/keys/private_key.pkcs7.pem ]; then
    install -d -m 0700 /etc/puppetlabs/puppet/keys
    cd /etc/puppetlabs/puppet/keys
    /opt/puppetlabs/puppet/bin/eyaml createkeys \
      --pkcs7-private-key=private_key.pkcs7.pem \
      --pkcs7-public-key=public_key.pkcs7.pem >/dev/null
  fi

  /vagrant-lab/scripts/apply
SHELL

def lab_node(node, mem, cpus)
  # main + 7 synapse workers + postgres + redis need 6G; the web role less
  %w[parallels virtualbox libvirt].each do |provider|
    node.vm.provider provider do |p|
      p.memory = mem
      p.cpus = cpus
    end
  end
  node.vm.provider "vmware_desktop" do |v|
    v.vmx["memsize"] = mem.to_s
    v.vmx["numvcpus"] = cpus.to_s
  end

  node.vm.synced_folder ".", "/vagrant-lab", mount_options: ["ro"]
  node.vm.synced_folder "../voxpupuli_controlrepo", "/vagrant-controlrepo",
    mount_options: ["ro"]
end

Vagrant.configure("2") do |config|
  config.vm.box = "bento/ubuntu-24.04"

  config.vm.define "matrix01", primary: true do |node|
    node.vm.hostname = "matrix01.voxpupu.li"
    node.vm.network "private_network", ip: "192.168.59.10"
    lab_node(node, 6144, 4)

    node.vm.provision "shell", inline: <<-SHELL
      grep -q '# matrix-lab' /etc/hosts || cat >> /etc/hosts <<'EOF'
# matrix-lab
127.0.0.1 matrix01.voxpupu.li matrix01
127.0.0.1 voxpupuli.party
EOF
#{PROVISION}
    SHELL
  end

  config.vm.define "vox01", autostart: false do |node|
    node.vm.hostname = "voxpupu.li"
    node.vm.network "private_network", ip: "192.168.59.11"
    lab_node(node, 4096, 2)

    node.vm.provision "shell", inline: <<-SHELL
      grep -q '# matrix-lab' /etc/hosts || cat >> /etc/hosts <<'EOF'
# matrix-lab
127.0.0.1 voxpupu.li vox01
127.0.0.1 grafana.voxpupu.li
127.0.0.1 puppetmodule.info www.puppetmodule.info
EOF
#{PROVISION}
    SHELL
  end
end

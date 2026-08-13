# matrix-lab: run voxpupuli/controlrepo PR #153 (Matrix Synapse) for real.
#
# One Debian 12 VM that applies the actual controlrepo masterless — which is
# how that repo is designed to run (see the pluginsync hack in its site.pp).
# The controlrepo working tree is synced from the sibling checkout
# (../voxpupuli_controlrepo, on the PR branch or your fix branch), so the
# loop is: edit in the checkout, ./scripts/converge, read the diff of
# reality. No commit needed — this lab iterates on someone else's open PR,
# so working-tree speed beats committed-code discipline here.
#
# Expectations on a lab box (documented, not bugs):
#   - certbot/ACME fails (fake domains) -> nginx serves HTTP-only, which the
#     profile's letsencrypt_directory fact-guard handles by design
#   - S3 creds are dummies -> media upload/eviction untestable, Synapse runs
#   - hiera secrets come from a lab override appended to the node yaml
#
# 192.168.59.x — mattermost-lab holds .58.x, codavox-lab .57.x.

Vagrant.configure("2") do |config|
  config.vm.box = "bento/ubuntu-24.04"

  config.vm.define "matrix01" do |node|
    node.vm.hostname = "matrix01.voxpupu.li"
    node.vm.network "private_network", ip: "192.168.59.10"

    node.vm.provider "parallels" do |prl|
      # main + 7 synapse workers + postgres + redis, all Python-hungry
      prl.memory = 6144
      prl.cpus = 4
    end

    node.vm.synced_folder ".", "/vagrant-lab", mount_options: ["ro"]
    node.vm.synced_folder "../voxpupuli_controlrepo", "/vagrant-controlrepo",
      mount_options: ["ro"]

    node.vm.provision "shell", inline: <<-SHELL
      set -euo pipefail

      grep -q '# matrix-lab' /etc/hosts || cat >> /etc/hosts <<'EOF'
# matrix-lab
127.0.0.1 matrix01.voxpupu.li matrix01
127.0.0.1 voxpupuli.party
EOF

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
  end
end

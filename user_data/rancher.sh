#!/bin/bash
set -euxo pipefail

# ---- swap (helps on smaller instances) ----
if [ ! -f /swapfile ]; then
  fallocate -l 4G /swapfile
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi
echo 'vm.overcommit_memory=1' >> /etc/sysctl.conf
sysctl -p || true

# ---- docker ----
curl -fsSL https://get.docker.com | sh
systemctl enable --now docker

# ---- Rancher (single-node) ----
docker run -d --restart=unless-stopped \
  --privileged \
  -p 80:80 -p 443:443 \
  --name rancher \
  rancher/rancher:${rancher_version}

# bootstrap password ko file me likh do taaki SSH se aasani se nikaalein
( sleep 120; docker logs rancher 2>&1 | grep -m1 "Bootstrap Password:" > /root/rancher-bootstrap-password.txt 2>/dev/null || true ) &

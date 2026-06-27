#!/bin/bash
set -euxo pipefail

# ---- swap ----
if [ ! -f /swapfile ]; then
  fallocate -l 4G /swapfile
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi

# ---- kernel modules + sysctl for k8s networking ----
cat >/etc/modules-load.d/k8s.conf <<EOF
overlay
br_netfilter
EOF
modprobe overlay || true
modprobe br_netfilter || true

cat >/etc/sysctl.d/99-k8s.conf <<EOF
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
vm.overcommit_memory                = 1
EOF
sysctl --system || true

# ---- IMPORTANT: disable nm-cloud-setup ----
# RKE2 on Ubuntu/AWS breaks if NetworkManager cloud-setup rewrites routes.
# (Yahi wo service thi jo logs me 'nm-cloud-setup' ke saath dikh rahi thi.)
systemctl disable --now nm-cloud-setup.service nm-cloud-setup.timer 2>/dev/null || true

# Node ab Rancher registration command ke liye taiyaar hai.
echo "node-prereqs-done" > /root/prereqs-done.txt

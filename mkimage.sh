#!/bin/bash

set -euo pipefail

SCRIPT_NAME="mkimage.sh"
SRC_IMAGE="focal-server-cloudimg-amd64.img"
DST_IMAGE="focal-server-k8s-1.22-cloudimg-amd64.img"
NBD_DEV="/dev/nbd0"
MNT_PATH="/mnt/image"
KUBERNETES_VERSION="1.22.5"
CRIO_VERSION="1.22"
CRIO_OS="xUbuntu_20.04"

tmp_image="${SRC_IMAGE/\.img/-tmp.img}"

_duplicate_image () {
  if [ ! -f "$tmp_image" ]; then
    echo "* copying $SRC_IMAGE to temp image $tmp_image"
    cp "$SRC_IMAGE" "$tmp_image"
  else
    echo "~ temp image already exists"
  fi
}

_mount_image () {
  if ! lsmod | grep nbd >/dev/null; then
    echo "* loading nbd module"
    sudo modprobe nbd
  else
    echo "~ module already loaded"
  fi

  if ! lsblk "$NBD_DEV" >/dev/null; then
    echo "* connecting $tmp_image to $NBD_DEV"
    sudo qemu-nbd --connect "$NBD_DEV" "$tmp_image"
    # wait for kernel to detect partitions
    sleep 1
  else
    echo "~ image already connected"
  fi

  if [ ! -d "$MNT_PATH" ]; then
    echo "* creating mount folder $MNT_PATH"
    sudo mkdir -p "$MNT_PATH"
  else
    echo "~ mount folder already exists"
  fi

  if ! mount | grep "${NBD_DEV}p1" >/dev/null; then
    echo "* mounting ${NBD_DEV}p1 TO $MNT_PATH"
    sudo mount "${NBD_DEV}p1" "$MNT_PATH"
  else
    echo "~ image already mounted"
  fi
}

_image_prepare () {
  echo "* copying $SCRIPT_NAME to mounted image"
  sudo cp -v "$SCRIPT_NAME" "$MNT_PATH"
  echo "* preparing image (this might take a while)..."
  sudo chroot "$MNT_PATH" /bin/bash /$SCRIPT_NAME prepare
  echo "* removing $SCRIPT_NAME from mounted image"
  sudo unlink "$MNT_PATH/$SCRIPT_NAME"
}

_unmount_image () {
  echo "* unmounting image"
  sudo umount "$MNT_PATH"
  echo "* removing mount folder"
  sudo rmdir -v "$MNT_PATH"
  echo "* disconnecting image"
  sudo qemu-nbd --disconnect "$NBD_DEV"
  echo "* removing nbd module"
  # wait for disconnection, as it's not sync
  sleep 1
  sudo rmmod nbd
}

_compress_image () {
  echo "* compressing temp image $tmp_image to image $DST_IMAGE (this WILL take a long time)..."
  qemu-img convert -c -O qcow2 "$tmp_image" "$DST_IMAGE"
  ls -ahl "$DST_IMAGE"
  echo "* removing temp image"
  unlink "$tmp_image"
}

_prepare_common () {
  apt update
  apt purge -y snapd udisks2 multipath-tools policykit-1 open-vm-tools
  apt autoremove -y
  apt upgrade -y
  apt install -y qemu-guest-agent ipset ipvsadm jq
}

_prepare_crio () {
  if ! apt-key list 2>/dev/null | grep devel:kubic >/dev/null; then
    echo "* configuring cri-o repo key"
    curl -fsSL "https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/$CRIO_OS/Release.key" | apt-key add - >/dev/null
  else
    echo "~ cri-o repo key already configured"
  fi

  libcontainers_repo="/etc/apt/sources.list.d/devel:kubic:libcontainers:stable.list"
  if [ ! -f "$libcontainers_repo" ]; then
    echo "* configuring libcontainers repo"
    echo "deb https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/$CRIO_OS/ /" >"$libcontainers_repo"
  else
    echo "~ libcontainers repo already configured"
  fi

  crio_repo="/etc/apt/sources.list.d/devel:kubic:libcontainers:stable:cri-o:$CRIO_VERSION.list"
  if [ ! -f "$crio_repo" ]; then
    echo "* configuring cri-o repo"
    echo "deb http://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable:/cri-o:/$CRIO_VERSION/$CRIO_OS/ /" >"$crio_repo"
  else
    echo "~ cri-o repo already configured"
  fi

  apt update

  # use cri-o's runc instead of system runc
  # cri-o's cri-tools is usually newer than kubernetes'
  apt install -y cri-o cri-o-runc cri-tools
}

_prepare_kubernetes () {
  k8s_repo_key="/usr/share/keyrings/kubernetes-archive-keyring.gpg"
  k8s_repo="/etc/apt/sources.list.d/kubernetes.list"
  if [ ! -f "$k8s_repo_key" ]; then
    echo "* configuring k8s repo key"
    curl -fsSLo "$k8s_repo_key" https://packages.cloud.google.com/apt/doc/apt-key.gpg
  else
    echo "~ k8s repo key already configured"
  fi

  if [ ! -f "$k8s_repo" ]; then
    echo "* configuring k8s repo"
    echo "deb [signed-by=/usr/share/keyrings/kubernetes-archive-keyring.gpg] https://apt.kubernetes.io/ kubernetes-xenial main" >"$k8s_repo"
  else
    echo "~ k8s repo already configured"
  fi

  apt update

  apt install -y "kubeadm=${KUBERNETES_VERSION}-00" "kubelet=${KUBERNETES_VERSION}-00" "kubectl=${KUBERNETES_VERSION}-00"
  apt-mark hold kubeadm kubelet kubectl
  systemctl disable kubelet
}

_prepare () {
  resolv_conf="/etc/resolv.conf"
  if ! grep nameserver "$resolv_conf" >/dev/null 2>&1; then
    echo "* configuring $resolv_conf"
    mv "$resolv_conf" "$resolv_conf.bak"
    echo "nameserver 1.1.1.1" >"$resolv_conf"
  else
    echo "~ $resolv_conf already configured"
  fi

  _prepare_common
  _prepare_crio
  _prepare_kubernetes

  apt clean

  mv -v "$resolv_conf.bak" "$resolv_conf"
}

if [ "${1:-}" = "prepare" ]; then
  _prepare
else
  if [ -f /mkimage.sh ]; then
    echo "ERROR: inside the image chroot, run \"mkimage.sh prepare\""
    exit 1
  else
    _duplicate_image
    _mount_image
    _image_prepare
    _unmount_image
    _compress_image
  fi
fi

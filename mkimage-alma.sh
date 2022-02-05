#!/bin/bash

set -euo pipefail

SCRIPT_NAME="mkimage-alma.sh"
SRC_IMAGE="AlmaLinux-8-GenericCloud-8.5-20211119.x86_64.qcow2"
DST_IMAGE="AlmaLinux-8-GenericCloud-8.5-20211119-vmware-k8s.x86_64.qcow2"
NBD_DEV="/dev/nbd0"
MNT_PATH="/mnt/image"
KUBERNETES_VERSION="1.22.6"
UUID=""

tmp_image="${SRC_IMAGE/\.qcow2/-tmp.qcow2}"

_run () {
  output="$("$@" 2>&1)"
  echo "$output"
}

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

  UUID="$(sudo xfs_admin -u "${NBD_DEV}p2" | cut -d ' ' -f 3)"
  sudo xfs_admin -U generate "${NBD_DEV}p2"
  if ! mount | grep "${NBD_DEV}p2" >/dev/null; then
    echo "* mounting ${NBD_DEV}p2 TO $MNT_PATH"
    sudo mount "${NBD_DEV}p2" "$MNT_PATH"
  else
    echo "~ image already mounted"
  fi
}

_image_prepare () {
  echo "* copying $SCRIPT_NAME to mounted image"
  sudo cp "$SCRIPT_NAME" "$MNT_PATH"
  echo "* preparing image (THIS WILL TAKE A LONG TIME!)..."
  sudo chroot "$MNT_PATH" /bin/bash /$SCRIPT_NAME prepare
  echo "* removing $SCRIPT_NAME from mounted image"
  sudo unlink "$MNT_PATH/$SCRIPT_NAME"
}

_unmount_image () {
  echo "* unmounting image"
  sudo umount "$MNT_PATH"
  sudo xfs_admin -U "$UUID" "${NBD_DEV}p2"
  echo "* removing mount folder"
  sudo rmdir "$MNT_PATH"
  echo "* disconnecting image"
  sudo qemu-nbd --disconnect "$NBD_DEV"
  echo "* removing nbd module"
  # wait for disconnection, as it's not sync
  sleep 1
  sudo rmmod nbd
}

_compress_image () {
  echo "* compressing temp image $tmp_image to image $DST_IMAGE..."
  qemu-img convert -c -O qcow2 "$tmp_image" "$DST_IMAGE"
  ls -ahl "$DST_IMAGE"
  echo "* removing temp image"
  unlink "$tmp_image"
}

_prepare_common () {
  echo "* installing common packages"
  _run yum install -y open-vm-tools yum-plugin-versionlock ipset ipvsadm jq
}

_prepare_containerd () {
  sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
  echo "* installing containerd"
  _run yum install -y containerd.io
}

_prepare_kubernetes () {
  cat <<EOF | sudo tee /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://packages.cloud.google.com/yum/repos/kubernetes-el7-x86_64
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://packages.cloud.google.com/yum/doc/yum-key.gpg https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
EOF
  echo "* installing kubernetes tools (kubeadm, kubelet, kubectl)"
  _run yum install -y "kubeadm-${KUBERNETES_VERSION}" "kubelet-${KUBERNETES_VERSION}" "kubectl-${KUBERNETES_VERSION}"
  yum versionlock kubeadm kubelet kubectl
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
  _prepare_containerd
  _prepare_kubernetes

  yum clean all

  mv "$resolv_conf.bak" "$resolv_conf"

  echo "* stopping gpg-agent"
  GNUPGHOME=/var/cache/dnf/kubernetes-33343725abd9cbdc/pubring gpgconf --kill gpg-agent >/dev/null 2>&1 || :
}

if [ "${1:-}" = "prepare" ]; then
  _prepare
else
  if [ -f /$SCRIPT_NAME ]; then
    echo "ERROR: inside the image chroot, run \"$SCRIPT_NAME prepare\""
    exit 1
  else
    _duplicate_image
    _mount_image
    _image_prepare
    _unmount_image
    _compress_image
  fi
fi

#!/bin/bash

set -euo pipefail

IMAGES_PATH="images"
VM_NAME=""
BASE_IMAGE="focal-server-k8s-1.22-cloudimg-amd64.img"
OS_VARIANT="ubuntu20.04"
VM_IMAGE_SIZE="10G"
MEMORY="1024" # in MiB
CPU="1"
CONSOLE=""
WAIT=""
IP=""
DOMAIN="local.lan"
USERNAME="" # !CHANGEME!
SSH_PUBLIC_KEY="" # !CHANGEME!
# password is "test", you can generate another using "mkpasswd --method=SHA-256"
PASSWD='$5$hIk2gCtfc6MamyXQ$YJo.HLrDlRvRzD3.hfzH67.8nhVo5CbDJy822R6Gm.A'

_usage () {
  echo "Usage: $0 [--ip ip] [--base-image base_image] [--console] [--wait] [--memory memory] [--cpu cpu] name"
  echo " name                     the VM name"
  echo " --ip ip                  set the VM IP address, default: DHCP"
  echo " --base-image base_image  set the VM base image, default: $BASE_IMAGE"
  echo " --console                open console after the VM is created"
  echo " --wait                   wait for VM to start"
  echo " --memory memory          set the VM memory in MiB, default: 1024"
  echo " --cpu cpu                set the VM CPUs, default: 1"
}

_create_vm_image () {
  local image="$1"
  local base_image="$2"
  local image_size="$3"

  if [ -f "$image" ]; then
    echo "ERROR: VM image already exists: $image" >&2
    exit 1
  fi

  echo "* creating VM image $image"
  qemu-img create -b "$base_image" -f qcow2 "$image" "$image_size" >/dev/null
  # qemu-img info "$image"
}

_create_cloudinit_image () {
  local image="$1"
  local vm_name="$2"
  local ip="$3"

  if [ -f "$image" ]; then
    echo "ERROR: cloudinit image already exists: $cloudinit_image" >&2
    exit 1
  fi

  echo "* creating cloudinit image $image"

  local tmp_path="$(mktemp -d)"
  touch "$tmp_path/meta-data"
  cat >"$tmp_path/user-data" <<EOT
#cloud-config

users:
  - name: $USERNAME
    ssh_authorized_keys:
      - $SSH_PUBLIC_KEY
    sudo: ['ALL=(ALL) NOPASSWD:ALL']
    shell: /bin/bash
    lock_passwd: false
    passwd: $PASSWD

fqdn: $vm_name.$DOMAIN
hostname: $vm_name
manage_etc_hosts: true
EOT

  echo "--- user-data ---"
  cat "$tmp_path/user-data"
  echo "-----------------"

  local extra_args=""
  if [ -n "$ip" ]; then
    cat >"$tmp_path/network-config" <<EOT
version: 1
config:
  - type: physical
    name: enp1s0
    subnets:
      - type: static
        address: $ip
        netmask: 255.255.255.0
        gateway: 192.168.122.1
        dns_nameservers:
          - 1.1.1.1
          - 8.8.8.8
        dns_search:
          - $DOMAIN
EOT
    extra_args="$tmp_path/network-config"

    echo "--- network-config ---"
    cat "$tmp_path/network-config"
    echo "----------------------"
  fi

  genisoimage -output "$image" -V cidata -r -J -input-charset utf-8 "$tmp_path/meta-data" "$tmp_path/user-data" $extra_args 2>/dev/null

  rm -fr "$tmp_path"
}

_wait_vm () {
  local name="$1"
  local started=""
  local output ip

  echo "* waiting for VM to start..."
  while [ -z "$started" ]; do
    set +e
    output="$(virsh qemu-agent-command $name '{"execute":"guest-network-get-interfaces"}' 2>&1)"
    if [ "$?" -eq "0" ]; then
      started="1"
    fi
    set -e
    sleep 1
  done

  ip="$(echo "$output" | jq -r '.return[1]."ip-addresses"[0]."ip-address"')"
  echo "* VM started with IP $ip"
}

_mkvm () {
  local name="$1"
  local base_image="$2"
  local image_size="$3"
  local memory="$4"
  local cpu="$5"
  local ip="$6"
  local console="$7"

  local vm_image="$IMAGES_PATH/$name.img"
  local cloudinit_image="$IMAGES_PATH/$name-cloudinit.iso"

  _create_vm_image "$vm_image" "$base_image" "$image_size"
  _create_cloudinit_image "$cloudinit_image" "$name" "$ip"

  echo "* creating VM $name"
  virt-install --name "$name" --memory "$memory" --vcpus "$cpu" --import --disk "path=$vm_image,format=qcow2" --os-variant "$OS_VARIANT" --network network=default,model=virtio --noautoconsole --controller type=usb,model=none --sound none --graphics none --disk "path=$cloudinit_image,device=cdrom" >/dev/null
  if [ -n "$console" ]; then
    virsh console "$name"
  fi

  if [ -n "wait" ]; then
    _wait_vm "$name"
  fi
}

while [ "$#" -gt "0" ]; do
  case $1 in
    --help)
      _usage
      exit
      ;;
    --ip)
      shift
      IP="$1"
      shift
      ;;
    --base-image)
      shift
      BASE_IMAGE="$1"
      shift
      ;;
    --console)
      shift
      CONSOLE="1"
      ;;
    --wait)
      shift
      WAIT="1"
      ;;
    --memory)
      shift
      MEMORY="$1"
      shift
      ;;
    --cpu)
      shift
      CPU="$1"
      shift
      ;;
    *)
      if [ -n "$VM_NAME" ]; then
        echo "ERROR: invalid argument: $1" >&2
        exit 1
      fi
      VM_NAME="$1"
      shift
      ;;
  esac
done

if [ -z "$USERNAME" ] || [ -z "$SSH_PUBLIC_KEY" ]; then
  echo "ERROR: username or SSH public key not set, edit this script and try again"
  exit 1
fi

if [ -z "$VM_NAME" ]; then
  echo "ERROR: VM name missing" >&2
  _usage
  exit 1
fi

_mkvm "$VM_NAME" "$BASE_IMAGE" "$VM_IMAGE_SIZE" "$MEMORY" "$CPU" "$IP" "$CONSOLE"

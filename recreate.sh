#!/bin/sh

set -x

# virsh shutdown test-vm
# virsh undefine test-vm
# sleep 5
# sudo chown lbogdan:lbogdan test-vm-cloudinit.iso
# genisoimage -output test-vm-cloudinit.iso -V cidata -r -J -input-charset utf-8 meta-data user-data
# qemu-img create -b focal-server-cloudimg-amd64.img -f qcow2 test-vm.img 10G
virt-install --name test-vm --ram 1024 --vcpus 1 --import --disk path=test-vm.img,format=qcow2 --os-variant ubuntu20.04 --network network=default,model=virtio --noautoconsole --controller type=usb,model=none --sound none --graphics none --disk path=test-vm-cloudinit.iso,device=cdrom

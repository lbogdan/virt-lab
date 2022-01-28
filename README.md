# virt-lab

## Prerequisites

- clean Ubuntu installation


## Check KVM availability

```sh
sudo apt update
# sudo apt upgrade -y
sudo apt install -y cpu-checker
kvm-ok
# output:
# INFO: /dev/kvm exists
# KVM acceleration can be used
```

## Install libvirt & co.

```sh
sudo apt install -y libvirt-daemon-system virtinst
```

What happened:

- /etc/profile.d/libvirt-uri.sh sets `LIBVIRT_DEFAULT_URI` environment variable

- /var/lib/dpkg/info/libvirt-daemon-system.postinst:69:72
  ```sh
      # Add each sudo user to the libvirt group
      for u in $(getent group sudo | sed -e "s/^.*://" -e "s/,/ /g"); do
          adduser "$u" libvirt >/dev/null || true
      done
  ```

> **IMPORTANT**: Logout, login back and check the `libvirt` settings are in place:

- your user should be part of the `libvirt` group

- `libvirt` default URI is `qemu:///system`:

```sh
id
# output:
# uid=1000(lbogdan) gid=1000(lbogdan) groups=1000(lbogdan),4(adm),24(cdrom),27(sudo),30(dip),46(plugdev),116(lxd),118(libvirt)

virsh uri
# output:
# qemu:///system
```

## Networking

TODO: Explain how networking works in libvirt.

Check networking:

```sh
virsh net-list
# output:
#  Name      State    Autostart   Persistent
# --------------------------------------------
#  default   active   yes         yes

virsh net-info default
# output:
# Name:           default
# UUID:           5782f5be-784e-4a4c-abab-30daf0e083b6
# Active:         yes
# Persistent:     yes
# Autostart:      yes
# Bridge:         virbr0

virsh net-dumpxml default
# output:
# <network>
#   <name>default</name>
#   <uuid>5782f5be-784e-4a4c-abab-30daf0e083b6</uuid>
#   <forward mode='nat'>
#     <nat>
#       <port start='1024' end='65535'/>
#     </nat>
#   </forward>
#   <bridge name='virbr0' stp='on' delay='0'/>
#   <mac address='52:54:00:90:07:57'/>
#   <ip address='192.168.122.1' netmask='255.255.255.0'>
#     <dhcp>
#       <range start='192.168.122.2' end='192.168.122.254'/>
#     </dhcp>
#   </ip>
# </network>

ip address
# output:
# ...
# 3: virbr0: <NO-CARRIER,BROADCAST,MULTICAST,UP> mtu 1500 qdisc noqueue state DOWN group default qlen 1000
#     link/ether 52:54:00:90:07:57 brd ff:ff:ff:ff:ff:ff
#     inet 192.168.122.1/24 brd 192.168.122.255 scope global virbr0
#        valid_lft forever preferred_lft forever
# 4: virbr0-nic: <BROADCAST,MULTICAST> mtu 1500 qdisc fq_codel master virbr0 state DOWN group default qlen 1000
#     link/ether 52:54:00:90:07:57 brd ff:ff:ff:ff:ff:ff
```

## Images

TODO: Explain images, formats (qcow2 etc.), (maybe) pools and volumes.

Download Ubuntu 20.04 (Focal) cloud image:

```sh
wget https://cloud-images.ubuntu.com/focal/current/focal-server-cloudimg-amd64.img
ls -al *.img
# output:
# -rw-rw-r-- 1 lbogdan lbogdan 582090752 Jan 24 22:37 focal-server-cloudimg-amd64.img

qemu-img info focal-server-cloudimg-amd64.img
# output:
# image: focal-server-cloudimg-amd64.img
# file format: qcow2
# virtual size: 2.2 GiB (2361393152 bytes)
# disk size: 555 MiB
# cluster_size: 65536
# Format specific information:
#     compat: 0.10
#     refcount bits: 16
```

Create a new disk image for the test VM, with the image we just downloaded as a base:

```sh
qemu-img create -b focal-server-cloudimg-amd64.img -f qcow2 test-vm.img 10G
# where:
# -b backing image file
# -f created image format
# output:
# Formatting 'test-vm.img', fmt=qcow2 size=10737418240 backing_file=focal-server-cloudimg-amd64.img cluster_size=65536 lazy_refcounts=off refcount_bits=16

qemu-img info test-vm.img
# output:
# image: test-vm.img
# file format: qcow2
# virtual size: 10 GiB (10737418240 bytes)
# disk size: 196 KiB
# cluster_size: 65536
# backing file: focal-server-cloudimg-amd64.img
# Format specific information:
#     compat: 1.1
#     lazy refcounts: false
#     refcount bits: 16
#     corrupt: false
```

We use [`virt-install`](https://www.mankier.com/1/virt-install) to create the test VM:

```sh
virt-install --name test-vm --ram 1024 --vcpus 1 --import --disk path=test-vm.img,format=qcow2 --os-variant ubuntu20.04 --network network=default,model=virtio --noautoconsole --noreboot --controller type=usb,model=none --sound none --graphics none
# output:
# Starting install...
# Domain creation completed.
# You can restart your domain by running:
#   virsh --connect qemu:///system start test-vm

virsh dumpxml test-vm
# output:
# <domain type='kvm'>  <name>test-vm</name>
#   <uuid>d117e403-cb09-48a8-a3ec-660c470e6607</uuid>
#   <metadata>
#     <libosinfo:libosinfo xmlns:libosinfo="http://libosinfo.org/xmlns/libvirt/domain/1.0">
#       <libosinfo:os id="http://ubuntu.com/ubuntu/20.04"/>
#     </libosinfo:libosinfo>
#   </metadata>
#   <memory unit='KiB'>2097152</memory>
#   <currentMemory unit='KiB'>2097152</currentMemory>
#   <vcpu placement='static'>1</vcpu>
#   <os>
#     <type arch='x86_64' machine='pc-q35-4.2'>hvm</type>
#     <boot dev='hd'/>
#   </os>
#   <features>
#     <acpi/>
#     <apic/>
#   </features>
#   <cpu mode='host-model' check='partial'/>
#   <clock offset='utc'>
#     <timer name='rtc' tickpolicy='catchup'/>
#     <timer name='pit' tickpolicy='delay'/>
#     <timer name='hpet' present='no'/>
#   </clock>
#   <on_poweroff>destroy</on_poweroff>
#   <on_reboot>restart</on_reboot>
#   <on_crash>destroy</on_crash>
#   <pm>
#     <suspend-to-mem enabled='no'/>
#     <suspend-to-disk enabled='no'/>
#   </pm>
#   <devices>
#     <emulator>/usr/bin/qemu-system-x86_64</emulator>
#     <disk type='file' device='disk'>
#       <driver name='qemu' type='qcow2'/>
#       <source file='/home/lbogdan/virt-lab/test-vm.img'/>
#       <target dev='vda' bus='virtio'/>
#       <address type='pci' domain='0x0000' bus='0x03' slot='0x00' function='0x0'/>
#     </disk>
#     <controller type='usb' index='0' model='none'/>
#     <controller type='sata' index='0'>
#       <address type='pci' domain='0x0000' bus='0x00' slot='0x1f' function='0x2'/>
#     </controller>
#     <controller type='pci' index='0' model='pcie-root'/>
#     <controller type='virtio-serial' index='0'>
#       <address type='pci' domain='0x0000' bus='0x02' slot='0x00' function='0x0'/>
#     </controller>
#     <controller type='pci' index='1' model='pcie-root-port'>
#       <model name='pcie-root-port'/>
#       <target chassis='1' port='0x8'/>
#       <address type='pci' domain='0x0000' bus='0x00' slot='0x01' function='0x0' multifunction='on'/>
#     </controller>
#     <controller type='pci' index='2' model='pcie-root-port'>
#       <model name='pcie-root-port'/>
#       <target chassis='2' port='0x9'/>
#       <address type='pci' domain='0x0000' bus='0x00' slot='0x01' function='0x1'/>
#     </controller>
#     <controller type='pci' index='3' model='pcie-root-port'>
#       <model name='pcie-root-port'/>
#       <target chassis='3' port='0xa'/>
#       <address type='pci' domain='0x0000' bus='0x00' slot='0x01' function='0x2'/>
#     </controller>
#     <controller type='pci' index='4' model='pcie-root-port'>
#       <model name='pcie-root-port'/>
#       <target chassis='4' port='0xb'/>
#       <address type='pci' domain='0x0000' bus='0x00' slot='0x01' function='0x3'/>
#     </controller>
#     <controller type='pci' index='5' model='pcie-root-port'>
#       <model name='pcie-root-port'/>
#       <target chassis='5' port='0xc'/>
#       <address type='pci' domain='0x0000' bus='0x00' slot='0x01' function='0x4'/>
#     </controller>
#     <controller type='pci' index='6' model='pcie-root-port'>
#       <model name='pcie-root-port'/>
#       <target chassis='6' port='0xd'/>
#       <address type='pci' domain='0x0000' bus='0x00' slot='0x01' function='0x5'/>
#     </controller>
#     <interface type='network'>
#       <mac address='52:54:00:6f:9c:3b'/>
#       <source network='default'/>
#       <model type='virtio'/>
#       <address type='pci' domain='0x0000' bus='0x01' slot='0x00' function='0x0'/>
#     </interface>
#     <serial type='pty'>
#       <target type='isa-serial' port='0'>
#         <model name='isa-serial'/>
#       </target>
#     </serial>
#     <console type='pty'>
#       <target type='serial' port='0'/>
#     </console>
#     <channel type='unix'>
#       <target type='virtio' name='org.qemu.guest_agent.0'/>
#       <address type='virtio-serial' controller='0' bus='0' port='1'/>
#     </channel>
#     <input type='mouse' bus='ps2'/>
#     <input type='keyboard' bus='ps2'/>
#     <memballoon model='virtio'>
#       <address type='pci' domain='0x0000' bus='0x04' slot='0x00' function='0x0'/>
#     </memballoon>
#     <rng model='virtio'>
#       <backend model='random'>/dev/urandom</backend>
#       <address type='pci' domain='0x0000' bus='0x05' slot='0x00' function='0x0'/>
#     </rng>
#   </devices>
# </domain>
```

Start the VM and connect to its console:

```sh
virsh start --console test-vm
# output:
# Domain test-vm started
# Connected to domain test-vm
# Escape character is ^]
# [    0.000000] Linux version 5.4.0-96-generic (buildd@lgw01-amd64-051) (gcc version 9.3.0 (Ubuntu 9.3.0-17ubuntu1~20.04)) #109-Ubuntu SMP Wed Jan 12 16:49:16 UTC 2022 (Ubuntu 5.4.0-96.109-generic 5.4.157)
# [    0.000000] Command line: BOOT_IMAGE=/boot/vmlinuz-5.4.0-96-generic root=LABEL=cloudimg-rootfs ro console=tty1 console=ttyS0
# [    0.000000] KERNEL supported cpus:
# [    0.000000]   Intel GenuineIntel
# [    0.000000]   AMD AuthenticAMD
# [    0.000000]   Hygon HygonGenuine
# [    0.000000]   Centaur CentaurHauls
# [    0.000000]   zhaoxin   Shanghai  
# [    0.000000] x86/fpu: Supporting XSAVE feature 0x001: 'x87 floating point registers'
# [    0.000000] x86/fpu: Supporting XSAVE feature 0x002: 'SSE registers'
# [    0.000000] x86/fpu: Supporting XSAVE feature 0x004: 'AVX registers'
# [    0.000000] x86/fpu: xstate_offset[2]:  576, xstate_sizes[2]:  256
# [    0.000000] x86/fpu: Enabled xstate features 0x7, context size is 832 bytes, using 'compacted' format.
# [    0.000000] BIOS-provided physical RAM map:
# ...
# [FAILED] Failed to start OpenBSD Secure Shell server.
# ...
# [  OK  ] Started snap.lxd.hook.inst…-4ee1-840a-78ec8c63e386.scope.

# Ubuntu 20.04.3 LTS ubuntu ttyS0

# ubuntu login:
```

You'll see that the "OpenBSD Secure Shell server" service fails to start. That's because networking is not configured by default in the Ubuntu cloud image. In order to configure it, along with a few other VM settings, we'll use [`cloud-init`](https://cloudinit.readthedocs.io/en/latest/).

TODO: Dive into the image file owner / group change.

## Configure cloud-init

TODO: Explain `cloud-init`.

If you don't want to set a different password than "test", you can skip this step:

```sh
sudo apt install -y whois # contains mkpasswd
mkpasswd --method=SHA-256
# output:
# Password: (type "test")
# $5$hIk2gCtfc6MamyXQ$YJo.HLrDlRvRzD3.hfzH67.8nhVo5CbDJy822R6Gm.A
```

Create the `cloud-init` files:

```sh
# *IMPORTANT* the meta-data file needs to exist, even if it's empty,
# otherwise the settings in user-data will not be applied properly!
touch meta-data
cat >user-data <<EOT
#cloud-config

# ssh_pwauth: true
# chpasswd:
#   list: |
#      root: pZy5K4LtugSwV9UB
#   expire: true

users:
  - name: lbogdan # *CHANGEME*
    # uncomment the following 2 lines and add your SSH public key if you want
    # ssh_authorized_keys:
    #   - ssh-rsa *CHANGEME*
    sudo: ['ALL=(ALL) NOPASSWD:ALL']
    shell: /bin/bash
    groups: sudo
    lock_passwd: false
    # password is "test", change it if you want
    passwd: $5$hIk2gCtfc6MamyXQ$YJo.HLrDlRvRzD3.hfzH67.8nhVo5CbDJy822R6Gm.A

fqdn: test-vm.localdomain
hostname: test-vm
manage_etc_hosts: true
EOT
```

Create the `cloud-init` disk image:

```sh
genisoimage -output test-vm-cloudinit.iso -V cidata -r -J -input-charset utf-8 meta-data user-data
# output:
# Total translation table size: 0
# Total rockridge attributes bytes: 250
# Total directory bytes: 0
# Path table size(bytes): 10
# Max brk space used 0
# 182 extents written (0 MB)

ls -al *.iso
# output:
# -rw-rw-r-- 1 lbogdan lbogdan 372736 Jan 27 15:20 test-vm-cloudinit.iso
```

Stop and remove the test VM and recreate the root disk image:

```sh
virsh shutdown test-vm
virsh undefine test-vm
sleep
qemu-img create -b focal-server-cloudimg-amd64.img -f qcow2 test-vm.img 10G
```

Recreate and start the test VM, using the `cloud-init` image (removing the `--noreboot` argument will start the VM immediately after it's created):

```
virt-install --name test-vm --ram 1024 --vcpus 1 --import --disk path=test-vm.img,format=qcow2 --os-variant ubuntu20.04 --network network=default,model=virtio --noautoconsole --controller type=usb,model=none --sound none --graphics none --disk path=test-vm-cloudinit.iso,device=cdrom
```

Connect to the console with `virsh console test-vm` and wait for the VM to boot completely. You should see a few more messages than at previous boot, related to `cloud-init`, and all services starting successfully. You can now login from the console with the username and password that you set in `user-data`.

To SSH into the VM, we first need to get its IP address. There's several ways to do this:

- look it up in the console boot messages:
  ```
  [   17.254082] cloud-init[598]: ci-info: +--------+------+----------------------------+---------------+--------+-------------------+
  [   17.268803] cloud-init[598]: ci-info: | Device |  Up  |          Address           |      Mask     | Scope  |     Hw-Address    |
  [   17.286430] cloud-init[598]: ci-info: +--------+------+----------------------------+---------------+--------+-------------------+
  [   17.298908] cloud-init[598]: ci-info: | enp1s0 | True |      192.168.122.245       | 255.255.255.0 | global | 52:54:00:05:ee:48 |
  ```

- showing the network configuration when logged in from the console:
  ```sh
  ip address
  # output:
  # ...
  # 2: enp1s0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc fq_codel state UP group default qlen 1000
  #   link/ether 52:54:00:05:ee:48 brd ff:ff:ff:ff:ff:ff
  #   inet 192.168.122.245/24 brd 192.168.122.255 scope global dynamic enp1s0
  ```

- (preferred) show `libvirt` DHCP leases:
  ```sh
  virsh net-dhcp-leases default
  # output:
  #  Expiry Time           MAC address         Protocol   IP address           Hostname   Client ID or DUID
  # ------------------------------------------------------------------------------------------------------------------------------------------------
  #  2022-01-27 19:07:24   52:54:00:05:ee:48   ipv4       192.168.122.245/24   test-vm    ff:56:50:4d:98:00:02:00:00:ab:11:af:0f:f5:96:c2:e0:bb:8d
  ```

Now let's SSH into the VM and take a look at its internals!

> **NOTE**: need to either have your private key in its default location, e.g. `~/.ssh/id_rsa`, or loaded into `ssh-agent`.

```sh
lbogdan@host:~$ ssh lbogdan@192.168.122.45
The authenticity of host '192.168.122.245 (192.168.122.245)' can’t be established.
ECDSA key fingerprint is SHA256:Dz1MypxVOypb6aAvMZNh21BBv+5yIbJ2BexIy018vbA.
Are you sure you want to continue connecting (yes/no/[fingerprint])? yes
Warning: Permanently added '192.168.122.245' (ECDSA) to the list of known hosts.
Welcome to Ubuntu 20.04.3 LTS (GNU/Linux 5.4.0-96-generic x86_64)

 * Documentation:  https://help.ubuntu.com
 * Management:     https://landscape.canonical.com
 * Support:        https://ubuntu.com/advantage

  System information as of Thu Jan 27 21:50:45 UTC 2022

  System load:  0.0               Processes:               124
  Usage of /:   13.6% of 9.52GB   Users logged in:         0
  Memory usage: 9%                IPv4 address for enp1s0: 192.168.122.245
  Swap usage:   0%

1 update can be applied immediately.
To see these additional updates run: apt list --upgradable



The programs included with the Ubuntu system are free software;
the exact distribution terms for each program are described in the
individual files in /usr/share/doc/*/copyright.

Ubuntu comes with ABSOLUTELY NO WARRANTY, to the extent permitted by
applicable law.

To run a command as administrator (user "root"), use "sudo <command>".
See "man sudo_root" for details.

lbogdan@test-vm:~$ id
uid=1000(lbogdan) gid=1000(lbogdan) groups=1000(lbogdan),27(sudo)
# -----------------------------------------------------------------------------
lbogdan@test-vm:~$ hostname --fqdn
test-vm.localdomain
# -----------------------------------------------------------------------------
lbogdan@test-vm:~$ hostnamectl 
   Static hostname: test-vm
         Icon name: computer-vm
           Chassis: vm
        Machine ID: 5cda04b4d3a846f8a6204e169cad20bc
           Boot ID: c596020739244b6d89e36f6a7fa3eb56
    Virtualization: kvm
  Operating System: Ubuntu 20.04.3 LTS
            Kernel: Linux 5.4.0-96-generic
      Architecture: x86-64
# -----------------------------------------------------------------------------
lbogdan@test-vm:~$ cat /etc/hosts
# Your system has configured 'manage_etc_hosts' as True.
# As a result, if you wish for changes to this file to persist
# then you will need to either
# a.) make changes to the master file in /etc/cloud/templates/hosts.debian.tmpl
# b.) change or remove the value of 'manage_etc_hosts' in
#     /etc/cloud/cloud.cfg or cloud-config from user-data
#
127.0.1.1 test-vm.localdomain test-vm
127.0.0.1 localhost

# The following lines are desirable for IPv6 capable hosts
::1 localhost ip6-localhost ip6-loopback
ff02::1 ip6-allnodes
ff02::2 ip6-allrouters
# -----------------------------------------------------------------------------
lbogdan@test-vm:~$ ping -c 1 test-vm
PING test-vm.localdomain (127.0.1.1) 56(84) bytes of data.
64 bytes from test-vm.localdomain (127.0.1.1): icmp_seq=1 ttl=64 time=0.012 ms

--- test-vm.localdomain ping statistics ---
1 packets transmitted, 1 received, 0% packet loss, time 0ms
rtt min/avg/max/mdev = 0.012/0.012/0.012/0.000 ms
# -----------------------------------------------------------------------------
lbogdan@test-vm:~$ lsblk 
NAME    MAJ:MIN RM  SIZE RO TYPE MOUNTPOINT
loop0     7:0    0 61.9M  1 loop /snap/core20/1270
loop1     7:1    0 67.2M  1 loop /snap/lxd/21835
loop2     7:2    0 43.3M  1 loop /snap/snapd/14295
sr0      11:0    1  364K  0 rom  
vda     252:0    0   10G  0 disk 
├─vda1  252:1    0  9.9G  0 part /
├─vda14 252:14   0    4M  0 part 
└─vda15 252:15   0  106M  0 part /boot/efi
# -----------------------------------------------------------------------------
lbogdan@test-vm:~$ free
              total        used        free      shared  buff/cache   available
Mem:         982328      133468      544564         996      304296      696980
Swap:             0           0           0
# -----------------------------------------------------------------------------
lbogdan@test-vm:~$ nproc
1
# -----------------------------------------------------------------------------
lbogdan@test-vm:~$ timedatectl 
               Local time: Thu 2022-01-27 22:04:16 UTC
           Universal time: Thu 2022-01-27 22:04:16 UTC
                 RTC time: Thu 2022-01-27 22:04:17    
                Time zone: Etc/UTC (UTC, +0000)       
System clock synchronized: yes                        
              NTP service: active                     
          RTC in local TZ: no
# -----------------------------------------------------------------------------
lbogdan@test-vm:~$ resolvectl 
Global
...
Link 2 (enp1s0)
      Current Scopes: DNS          
DefaultRoute setting: yes          
       LLMNR setting: yes          
MulticastDNS setting: no           
  DNSOverTLS setting: no           
      DNSSEC setting: no           
    DNSSEC supported: no           
  Current DNS Server: 192.168.122.1
         DNS Servers: 192.168.122.1
# -----------------------------------------------------------------------------
lbogdan@test-vm:~$ ip route
default via 192.168.122.1 dev enp1s0 proto dhcp src 192.168.122.45 metric 100 
192.168.122.0/24 dev enp1s0 proto kernel scope link src 192.168.122.45 
192.168.122.1 dev enp1s0 proto dhcp scope link src 192.168.122.45 metric 100
```

#!/bin/bash

Usage()
{
    echo "Usage: $0 <vm-name>"
    echo "spawn a new vm with latest centos cloud image"

    echo
    echo "Options"
    echo "  -n vm-name"
}

vm_name='devstack'

while getopts "hn:a:" arg; do
        case $arg in
                h) Usage; exit
                        ;;
                n) vm_name=$OPTARG
                        ;;
                a) IP=$OPTARG
                        ;;
                *) Usage; exit
                        ;;
        esac
done

image_dir='/var/lib/libvirt/images'
vm_image_name="${vm_name}.qcow2"

wget -nc -O ${image_dir}/centos-base.qcow2 https://cloud.centos.org/centos/7/images/CentOS-7-x86_64-GenericCloud.qcow2

yum install libvirt qemu-kvm virt-manager virt-install libguestfs-tools -y
systemctl enable libvirtd && systemctl start libvirtd
yum -y install libguestfs-xfs

qemu-img create -f qcow2 ${image_dir}/${vm_image_name} 50G
virt-resize --expand /dev/sda1 ${image_dir}/centos-base.qcow2 ${image_dir}/${vm_image_name}
virt-customize -a ${image_dir}/${vm_image_name} --run-command 'yum remove cloud-init* -y'
virt-customize -a ${image_dir}/${vm_image_name} --root-password password:redhat
virt-customize -a ${image_dir}/${vm_image_name} --run-command "echo ${vm_name} > /etc/hostname"

cat << EOF > ./ifcfg-eth0
DEVICE="eth0"
ONBOOT="yes"
TYPE="Ethernet"
IPADDR=192.168.122.${IP}
NETMASK=255.255.255.0
GATEWAY=192.168.122.1
NM_CONTROLLED=no
DNS1=192.168.122.1
EOF
virt-customize -a ${image_dir}/${vm_image_name} --upload ./ifcfg-eth0:/etc/sysconfig/network-scripts/ifcfg-eth0
rm -rf ./ifcfg-eth0

virt-install --ram 16384 --vcpus 4 \
--disk path=${image_dir}/${vm_image_name},device=disk,bus=virtio,format=qcow2 \
--import --noautoconsole --vnc \
--network network:default,model=virtio --name ${vm_name}


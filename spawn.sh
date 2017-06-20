#!/bin/bash

image_dir='/var/lib/libvirt/images'
vm_name='devstack'

wget -O ${image_dir}/centos-base.qcow2 https://cloud.centos.org/centos/7/images/CentOS-7-x86_64-GenericCloud.qcow2

yum install libvirt qemu-kvm virt-manager virt-install libguestfs-tools -y
systemctl enable libvirtd && systemctl start libvirtd
yum -y install libguestfs-xfs

qemu-img create -f qcow2 ${image_dir}/centos.qcow2 50G
virt-resize --expand /dev/sda1 ${image_dir}/centos-base.qcow2 ${image_dir}/centos.qcow2
virt-customize -a ${image_dir}/centos.qcow2 --run-command 'yum remove cloud-init* -y'
virt-customize -a ${image_dir}/centos.qcow2 --root-password password:redhat

cp ${image_dir}/centos.qcow2 ${image_dir}/centos-backup.qcow2

virt-install --ram 16384 --vcpus 4 \
--disk path=${image_dir}/centos.qcow2,device=disk,bus=virtio,format=qcow2 \
--import --noautoconsole --vnc \
--network network:default --name ${vm_name}


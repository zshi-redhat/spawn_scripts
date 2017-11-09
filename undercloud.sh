#!/bin/bash

Usage()
{
    echo "Usage: $0"
    echo "spawn a undercloud "

    echo
    echo "Options"
    echo "  -n vm-name"
}

vm_name='undercloud'
distro='centos'

while getopts "hn:a:d:" arg; do
        case $arg in
                h) Usage; exit
                        ;;
                a) IP=$OPTARG
                        ;;
                d) distro=$OPTARG
                        ;;
                *) Usage; exit
                        ;;
        esac
done

image_dir='/var/lib/libvirt/images'
vm_image_name="${vm_name}.qcow2"
base_image_name="${distro}-base.qcow2"

if [ ${distro} = 'centos' ]; then
    wget -nc -O ${image_dir}/${base_image_name} https://cloud.centos.org/centos/7/images/CentOS-7-x86_64-GenericCloud.qcow2
elif [ ${distro} = 'rhel' ]; then
    cp -n /opt/rhel_guest_images/rhel-guest-image-7.4.qcow2 ${image_dir}/${base_image_name}
fi

modprobe kvm && modprobe kvm_intel
yum install libvirt qemu-kvm virt-manager virt-install libguestfs-tools -y
systemctl enable libvirtd && systemctl start libvirtd
yum -y install libguestfs-xfs

cat > /tmp/provisioning.xml <<EOF
<network>
  <name>provisioning</name>
    <ip address="172.16.0.254" netmask="255.255.255.0"/>
</network>
EOF

virsh net-define /tmp/provisioning.xml
virsh net-autostart provisioning
virsh net-start provisioning

qemu-img create -f qcow2 ${image_dir}/${vm_image_name} 50G
virt-resize --expand /dev/sda1 ${image_dir}/${base_image_name} ${image_dir}/${vm_image_name}
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

cat > /tmp/undercloud_customize.sh <<EOF
useradd stack
echo "redhat" | passwd stack --stdin
echo "stack ALL=(root) NOPASSWD:ALL" | tee -a /etc/sudoers.d/stack
chmod 0440 /etc/sudoers.d/stack
sudo hostnamectl set-hostname undercloud.com
sudo hostnamectl set-hostname --transient undercloud.com
EOF
virt-customize -a ${image_dir}/${vm_image_name} --upload /tmp/undercloud_customize.sh:/root/undercloud_customize.sh
virt-customize -a ${image_dir}/${vm_image_name} --run-command "chmod a+x /root/undercloud_customize.sh"
virt-customize -a ${image_dir}/${vm_image_name} --run-command "/root/undercloud_customize.sh"

cat > /tmp/undercloud.conf <<EOF
[DEFAULT]
local_ip = 172.16.0.1/24
undercloud_public_vip = 172.16.0.10
undercloud_admin_vip = 172.16.0.11
local_interface = eth0
masquerade_network = 172.16.0.0/24
dhcp_start = 172.16.0.20
dhcp_end = 172.16.0.120
network_cidr = 172.16.0.0/24
network_gateway = 172.16.0.1
discovery_iprange = 172.16.0.150,172.16.0.180
[auth]
EOF
virt-customize -a ${image_dir}/${vm_image_name} --upload /tmp/undercloud.conf:/home/stack/undercloud.conf

virt-install --ram 16384 --vcpus 4 \
--disk path=${image_dir}/${vm_image_name},device=disk,bus=virtio,format=qcow2 \
--import --noautoconsole --vnc \
--network network:default,model=virtio \
--network network:provisioning,model=virtio \
--name ${vm_name}

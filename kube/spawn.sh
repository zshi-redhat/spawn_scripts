#!/bin/bash

cd $HOME

PACKAGE_TOOLS="vim git wget net-tools pciutils"
yum install -y $PACKAGE_TOOLS

# Install docker
yum install -y docker

# Start & Enable docker
systemctl start docker
systemctl enable docker

# Install kubernetes repo
cat <<EOF > /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://packages.cloud.google.com/yum/repos/kubernetes-el7-x86_64
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://packages.cloud.google.com/yum/doc/yum-key.gpg https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
exclude=kube*
EOF

# Set SELinux in permissive mode (effectively disabling it)
setenforce 0
sed -i 's/^SELINUX=enforcing$/SELINUX=permissive/' /etc/selinux/config


# Disable swapping
swapoff --all

# Install kube-* packages
yum install -y kubelet kubeadm kubectl --disableexcludes=kubernetes

# Enable & Start kubelet
systemctl enable --now kubelet

# Run kubeadm init
kubeadm init --pod-network-cidr=10.244.0.0/16

if [ $? == 0 ]; then
	mkdir -p $HOME/.kube
	sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
	sudo chown $(id -u):$(id -g) $HOME/.kube/config
fi

mkdir -p /var/run/flannel
cat <<EOF > /var/run/flannel/subnet.env
FLANNEL_NETWORK=10.96.0.0/16
FLANNEL_SUBNET=10.96.1.1/24
FLANNEL_MTU=1450
FLANNEL_IPMASQ=true
EOF

# Install epel-release and golang
yum install -y epel-release
yum install -y golang

# Clone multus sriov-cni and sriov-network-device-plugin
git clone https://github.com/intel/multus-cni.git
git clone https://github.com/intel/sriov-cni.git
git clone https://github.com/intel/sriov-network-device-plugin.git

# Build and Copy multus/sriov binaries
cd $HOME/multus-cni
./build
cp bin/multus /opt/cni/bin

cd $HOME/sriov-cni
make build
cp build/sriov /opt/cni/bin

cd $HOME/sriov-network-device-plugin
make build

# Default CNI config
mkdir -p /etc/cni/net.d
cat <<EOF > /etc/cni/net.d/cni-config.json
{
	"name": "multus-cni-network",
	"type": "multus",
	"delegates": [{
		"type": "flannel",
		"delegate": {
			"isDefaultGateway": true
		}
	}],
	"kubeconfig": "/etc/kubernetes/admin.conf"
}
EOF

# Sleep 5 seconds to wait for node ready
sleep 5

# Create sriov device plugin config dir
mkdir -p /etc/pcidp

kubectl taint nodes --all node-role.kubernetes.io/master-

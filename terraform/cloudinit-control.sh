#!/bin/bash

# cloudinit script - installs containerd, kubernetes tools and calico
# based on original work from https://github.com/sandervanvugt/cka
# assumes VM is running Ubuntu 22.04
# Last revision 12-Nov-2024

# updates and install utilities
sudo apt-get update
sudo apt-get upgrade -y
sudo systemctl restart google-osconfig-agent.service
sudo apt-get install -y jq apparmor-utils vim less apt-transport-https bash-completion dialog

# define software versions
# default: use the kubernetes versions defined at CKA exam
# https://training.linuxfoundation.org/certification/certified-kubernetes-administrator-cka/
# the compatibility matrix with containerd can be found at
# https://github.com/containerd/containerd/blob/main/RELEASES.md
# if you want to hard code the releases, uncomment the lines below
# calico compatibility matrix can be found below
# https://docs.tigera.io/calico/latest/getting-started/kubernetes/requirements
#KUBEVERSION="v1.31.2"
#CONTAINERD_VERSION="2.0.0"
#RUNC_VERSION="v1.2.1"
#CALICO_VERSION="v3.29.0"

# beta: building in ARM support
[ $(arch) = aarch64 ] && PLATFORM=arm64
[ $(arch) = x86_64 ] && PLATFORM=amd64

### setting up container runtime prereq
cat <<- EOF | sudo tee /etc/modules-load.d/containerd.conf
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter

# Setup required sysctl params, these persist across reboots.
cat <<- EOF | sudo tee /etc/sysctl.d/99-kubernetes-cri.conf
net.bridge.bridge-nf-call-iptables  = 1
net.ipv4.ip_forward                 = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF

# Apply sysctl params without reboot
sudo sysctl --system

# (Install containerd)
# getting rid of hard coded version numbers
# define version if not hard coded
if [ -z "${CONTAINERD_VERSION}" ]; then
  CONTAINERD_VERSION=$(curl -s https://api.github.com/repos/containerd/containerd/releases/latest | jq -r '.tag_name')
  CONTAINERD_VERSION=${CONTAINERD_VERSION#v}
fi
wget https://github.com/containerd/containerd/releases/download/v${CONTAINERD_VERSION}/containerd-${CONTAINERD_VERSION}-linux-${PLATFORM}.tar.gz
sudo tar xvf containerd-${CONTAINERD_VERSION}-linux-${PLATFORM}.tar.gz -C /usr/local
# Configure containerd
sudo mkdir -p /etc/containerd
cat <<- TOML | sudo tee /etc/containerd/config.toml
version = 2
[plugins]
  [plugins."io.containerd.grpc.v1.cri"]
    [plugins."io.containerd.grpc.v1.cri".containerd]
      discard_unpacked_layers = true
      [plugins."io.containerd.grpc.v1.cri".containerd.runtimes]
        [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc]
          runtime_type = "io.containerd.runc.v2"
          [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc.options]
            SystemdCgroup = true
TOML

# define version if not hard coded
if [ -z "${RUNC_VERSION}" ]; then
  RUNC_VERSION=$(curl -s https://api.github.com/repos/opencontainers/runc/releases/latest | jq -r '.tag_name')
fi

wget https://github.com/opencontainers/runc/releases/download/${RUNC_VERSION}/runc.${PLATFORM}
sudo install -m 755 runc.${PLATFORM} /usr/local/sbin/runc
# Restart containerd
wget https://raw.githubusercontent.com/containerd/containerd/main/containerd.service
sudo mv containerd.service /usr/lib/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now containerd

sudo ln -s /etc/apparmor.d/runc /etc/apparmor.d/disable/
sudo apparmor_parser -R /etc/apparmor.d/runc

touch /tmp/container.txt

# (install kubernetes tools)
# define version if not hard coded
if [ -z "${KUBEVERSION}" ]; then
  # detecting latest Kubernetes version
  KUBEVERSION=$(curl -s https://api.github.com/repos/kubernetes/kubernetes/releases/latest | jq -r '.tag_name')
  KUBEVERSION=${KUBEVERSION%.*}
fi

cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
br_netfilter
EOF

curl -fsSL https://pkgs.k8s.io/core:/stable:/${KUBEVERSION}/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/${KUBEVERSION}/deb/ /" | sudo tee /etc/apt/sources.list.d/kubernetes.list
sleep 2

sudo apt-get update
sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl
sudo swapoff -a

sudo sed -i 's/\/swap/#\/swap/' /etc/fstab

sudo crictl config --set \
    runtime-endpoint=unix:///run/containerd/containerd.sock

# initialize kubelet
sudo kubeadm init

# allow user student to run kubeadm
USER="student"
GROUP="student"
RC_FILE="/home/$USER/.kubectlrc"
cat <<EOF | sudo tee $RC_FILE

# make kubernetes work for non-root user
mkdir -p ~/.kube
sudo cp -i /etc/kubernetes/admin.conf ~/.kube/config
sudo chown $USER:$GROUP ~/.kube/config
EOF
sudo chown $USER:$GROUP $RC_FILE
sudo chmod 750 $RC_FILE
sudo -u $USER bash $RC_FILE

# enable auto complete on student account
sudo -u $USER bash -c "kubectl completion bash > /home/$USER/.kuberc"
sudo -u $USER bash -c "echo source /etc/bash_completion >> /home/$USER/.bashrc"
sudo -u $USER bash -c "echo source .kuberc >> /home/$USER/.bashrc"

# install calico on control node
# use Sander van Vugt reference initialization file
wget -O /tmp/calico.yaml https://raw.githubusercontent.com/sandervanvugt/cka/refs/heads/master/calico.yaml
sudo -u $USER kubectl apply -f /tmp/calico.yaml

echo "Finished setup"
exit
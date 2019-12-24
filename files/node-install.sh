#!/bin/bash

# Get the Docker gpg key:
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -

# Add the Docker repository:
sudo add-apt-repository    "deb [arch=amd64] https://download.docker.com/linux/ubuntu \
   $(lsb_release -cs) \
   stable"

# Get the Kubernetes gpg key:
curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -

# Add the Kubernetes repository:
cat << EOF | sudo tee /etc/apt/sources.list.d/kubernetes.list
deb https://apt.kubernetes.io/ kubernetes-xenial main
EOF

# Update packages and install Docker, kubelet, kubeadm, and kubectl:
sudo apt-get update && \
sudo apt-get install -y docker-ce kubelet kubeadm kubectl && \
sudo apt-mark hold docker-ce kubelet kubeadm kubectl && \
sudo apt-get dist-upgrade -y

# Add the iptables rule to sysctl.conf:
echo "net.bridge.bridge-nf-call-iptables=1" | sudo tee -a /etc/sysctl.conf
    
# Enable iptables immediately:
sudo sysctl -p
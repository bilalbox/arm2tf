#!/bin/bash

#
# Required environment variables:
#  RTF_CONTROLLER_IPS:                  List of ip addresses, separated by whitespace (eg 1.1.1.1 2.2.2.2)
#  RTF_WORKER_IPS:                      List of ip addresses, separated by whitespace (eg 3.3.3.3 4.4.4.4)
#  RTF_ACTIVATION_DATA:                 Data to activate your Runtime Fabric obtained from Anypoint. (example "NzdlMzU1YTktMzAxMC00OGE0LWJlMGQtMDd...")
#
# Optional environment variables:
#  RTF_DOCKER_DEVICE:                   (default /dev/xvdb)
#  RTF_ETCD_DEVICE:                     (default /dev/xvdc)
#  RTF_TOKEN:                           Token used by nodes to auto-join the cluster. (default my-cluster-token)
#  RTF_INSTALL_PACKAGE_URL:             Url to download the installation package from.
#  RTF_NAME:                            Name to give this cluster. (default runtime-fabric)
#  RTF_MULE_LICENSE:                    Mule license digest (contents of a muleLicenseKey.lic)
#  RTF_HTTP_PROXY:                      server:port to use for http/https proxy
#  RTF_NO_PROXY:                        Comma-separated list of hosts to bypass the proxy. (eg 1.1.1.1,no-proxy.com)
#  RTF_MONITORING_PROXY:                SOCKS5 proxy to use for Anypoint Monitoring publisher outbound connections (eg `socks5://192.169.1.1:1080`, `socks5://user:pass@192.168.1.1:1080`)
#  RTF_SERVICE_UID:                     Service user ID for running system services
#  RTF_SERVICE_GID:                     Service group ID for running system services
#  RTF_NEW_CLUSTER                      Default "yes". Set to "no" if updating an existing cluster.
#  POD_NETWORK_CIDR:                    CIDR range Kubernetes will be allocating node subnets and pod IPs from. Must be a minimum of /16
#  SERVICE_CIDR:                        CIDR range Kubernetes will be allocating service IPs from.

set -ue
CODE_COLOR="\e[32m"
CODE_END="\e[0m"
BRK="========================================================="
INSTALL_DIR="/opt/anypoint/runtimefabric"

RTF_DOCKER_DEVICE=${RTF_DOCKER_DEVICE:-/dev/xvdb}
RTF_ETCD_DEVICE=${RTF_ETCD_DEVICE:-/dev/xvdc}
RTF_TOKEN=${RTF_TOKEN:-my-cluster-token}
RTF_INSTALL_PACKAGE_URL=${RTF_INSTALL_PACKAGE_URL:-}
RTF_NAME=${RTF_NAME:-runtime-fabric}
RTF_MULE_LICENSE=${RTF_MULE_LICENSE:-}
RTF_HTTP_PROXY=${RTF_HTTP_PROXY:-}
RTF_MONITORING_PROXY=${RTF_MONITORING_PROXY:-}
RTF_SERVICE_UID=${RTF_SERVICE_UID:-}
RTF_SERVICE_GID=${RTF_SERVICE_GID:-}
RTF_NO_PROXY=${RTF_NO_PROXY:-}
RTF_NEW_CLUSTER=${RTF_NEW_CLUSTER:-yes}
POD_NETWORK_CIDR=${POD_NETWORK_CIDR:-10.244.0.0/16}
SERVICE_CIDR=${SERVICE_CIDR:-10.100.0.0/16}

echo $BRK
echo "Runtime Fabric configuration generator"
echo $BRK

IFS=' ' read -a CONTROLLER_IPS <<< "$RTF_CONTROLLER_IPS"
IFS=' ' read -a WORKER_IPS <<< "$RTF_WORKER_IPS"
AD=$RTF_ACTIVATION_DATA

echo
echo "Cluster topology: ${#CONTROLLER_IPS[@]} controllers, ${#WORKER_IPS[@]} workers"
echo
printf "Instructions:\n"
printf " 1. Create ${CODE_COLOR}/opt/anypoint/runtimefabric${CODE_END} directory and ensure it is writable from your ssh login\n"
printf " 2. Copy each snippet below and execute on the appropriate machine\n"
printf " 3. For each node, copy the init.sh script to the installation directory\n"
printf "    eg ${CODE_COLOR}scp scripts/init.sh <user>@node-ip:${INSTALL_DIR}${CODE_END}\n"
printf " 4. Execute ${CODE_COLOR}sudo init.sh ${CODE_END} on each node. This should be done first on the leader (first controller) node, then concurrently on the other nodes\n"
printf " 5. The nodes will join to the IP address given for the first controller and form your Runtime Fabric cluster. This process can take 10-25 minutes\n"

echo
printf "Note: You can monitor the progress of the installation on any of the nodes with ${CODE_COLOR}tail -f /var/log/rtf-init.log${CODE_END}\n"

LEADER_IP=${CONTROLLER_IPS[0]}
if [ $RTF_NEW_CLUSTER == "yes" ]; then
  # first controller will be the leader
  unset 'CONTROLLER_IPS[0]'
fi
CONTROLLER_COUNT=$((${#CONTROLLER_IPS[@]}))

INSTALLER_NODE_ROLE=controller_node
TOTAL_NODE_COUNT=$((${#CONTROLLER_IPS[@]} + ${#WORKER_IPS[@]}))
if [ $TOTAL_NODE_COUNT == "1" ]; then
    INSTALLER_NODE_ROLE=general_node
fi

if [ $RTF_NEW_CLUSTER == "yes" ]; then
  # This is the leader machine
  echo
  echo ${LEADER_IP}:
  echo $BRK
  printf "${CODE_COLOR}mkdir -p $INSTALL_DIR && cat > $INSTALL_DIR/env <<EOF \n\
 RTF_PRIVATE_IP=${LEADER_IP} \n\
 RTF_NODE_ROLE=$INSTALLER_NODE_ROLE \n\
 RTF_INSTALL_ROLE=leader \n\
 RTF_INSTALL_PACKAGE_URL="$RTF_INSTALL_PACKAGE_URL" \n\
 RTF_ETCD_DEVICE=$RTF_ETCD_DEVICE \n\
 RTF_DOCKER_DEVICE=$RTF_DOCKER_DEVICE \n\
 RTF_TOKEN='$RTF_TOKEN' \n\
 RTF_NAME='$RTF_NAME' \n\
 RTF_ACTIVATION_DATA='$RTF_ACTIVATION_DATA' \n\
 RTF_MULE_LICENSE='$RTF_MULE_LICENSE' \n\
 RTF_HTTP_PROXY='$RTF_HTTP_PROXY' \n\
 RTF_NO_PROXY='$RTF_NO_PROXY' \n\
 RTF_MONITORING_PROXY='$RTF_MONITORING_PROXY' \n\
 RTF_SERVICE_UID='$RTF_SERVICE_UID' \n\
 RTF_SERVICE_GID='$RTF_SERVICE_GID' \n\
 POD_NETWORK_CIDR='$POD_NETWORK_CIDR' \n\
 SERVICE_CIDR='$SERVICE_CIDR' \n\
EOF$CODE_END"
fi

if [ $CONTROLLER_COUNT != "0" ]; then
for c in ${CONTROLLER_IPS[@]}; do
echo
echo
echo $c:
echo $BRK
printf "${CODE_COLOR}mkdir -p $INSTALL_DIR && cat > $INSTALL_DIR/env <<EOF \n\
 RTF_PRIVATE_IP=$c \n\
 RTF_NODE_ROLE=controller_node \n\
 RTF_INSTALL_ROLE=joiner \n\
 RTF_DOCKER_DEVICE=$RTF_DOCKER_DEVICE \n\
 RTF_ETCD_DEVICE=$RTF_ETCD_DEVICE \n\
 RTF_TOKEN='$RTF_TOKEN' \n\
 RTF_INSTALLER_IP=$LEADER_IP \n\
 RTF_HTTP_PROXY='$RTF_HTTP_PROXY' \n\
 RTF_NO_PROXY='$RTF_NO_PROXY' \n\
 RTF_MONITORING_PROXY='$RTF_MONITORING_PROXY' \n\
 RTF_SERVICE_UID='$RTF_SERVICE_UID' \n\
 RTF_SERVICE_GID='$RTF_SERVICE_GID' \n\
EOF$CODE_END"
done
fi

if [ ${#WORKER_IPS[@]} != "0" ]; then
for w in ${WORKER_IPS[@]}; do
echo
echo
echo $w:
echo $BRK
printf "${CODE_COLOR}mkdir -p $INSTALL_DIR && cat > $INSTALL_DIR/env <<EOF \n\
 RTF_PRIVATE_IP=$w \n\
 RTF_NODE_ROLE=worker_node \n\
 RTF_INSTALL_ROLE=joiner \n\
 RTF_DOCKER_DEVICE=$RTF_DOCKER_DEVICE \n\
 RTF_TOKEN='$RTF_TOKEN' \n\
 RTF_INSTALLER_IP=$LEADER_IP \n\
 RTF_HTTP_PROXY='$RTF_HTTP_PROXY' \n\
 RTF_NO_PROXY='$RTF_NO_PROXY' \n\
 RTF_MONITORING_PROXY='$RTF_MONITORING_PROXY' \n\
 RTF_SERVICE_UID='$RTF_SERVICE_UID' \n\
 RTF_SERVICE_GID='$RTF_SERVICE_GID' \n\
EOF$CODE_END"
done
fi

echo

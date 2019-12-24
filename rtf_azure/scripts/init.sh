#!/bin/bash
set -eo pipefail

# Constants
SCRIPT_VERSION='20191218-398eeae'
REDIRECT_LOG=/var/log/rtf-init.log
FSTAB_COMMENT="# Added by RTF"
BASE_DIR=/opt/anypoint/runtimefabric
STATE_DIR=$BASE_DIR/.state
SKIP_TEXT="Skipped. Already executed."
METADATA_IP=169.254.169.254
CURL_OPTS="-L -k -sS --fail --connect-timeout 10 --retry 5 --retry-delay 15"
CURL_METADATA_OPTS="${CURL_OPTS} --noproxy ${METADATA_IP}"
AWS_METADATA_URL=http://$METADATA_IP/latest/meta-data
AZURE_METADATA_HEADER="Metadata:true"
AZURE_METADATA_URL=http://$METADATA_IP/metadata/instance
AZURE_METADATA_VERSION=2017-08-01
DOCKER_MOUNT=/var/lib/gravity
ETCD_MOUNT=/var/lib/gravity/planet/etcd
REGISTRATION_ATTEMPTS=5
JOINING_ATTEMPTS=10
GRAVITY_BASH="gravity planet enter -- --notty /usr/bin/bash -- -c"
SYSTEM_NO_PROXY="kubernetes.default.svc,.local,0.0.0.0/0"
ACTIVATION_PROPERTIES_FILE=activation-properties.json
KUBECTL_CMD_PREFIX=${KUBECTL_CMD_PREFIX:-"gravity planet enter -- --notty /usr/bin/kubectl --"}
HELM="gravity planet enter -- --notty /usr/bin/helm --"
CURRENT_STEP=init
CURRENT_STEP_NBR=0
SEP="Done.\n"
LINE="\n================================================"

# Defaults
RTF_SERVICE_UID=${RTF_SERVICE_UID:-1000}
RTF_SERVICE_GID=${RTF_SERVICE_GID:-1000}
POD_NETWORK_CIDR=${POD_NETWORK_CIDR:-10.244.0.0/16}
SERVICE_CIDR=${SERVICE_CIDR:-10.100.0.0/16}

# ADDITIONAL_ENV_VARS_PLACEHOLDER_DO_NOT_REMOVE

# detect OS
case "$(uname -s)" in
    Darwin*)
      BASE64_DECODE_OPTS="-D"
      ;;
    *)
      BASE64_DECODE_OPTS="-d"
esac

function on_exit {
  local trap_code=$?
  if [ $trap_code -ne 0 ] ; then
    local ANCHOR=$(echo ${CURRENT_STEP} | tr "_" "-")
    echo
    echo "***********************************************************"
    echo "** Oh no! Your installation has stopped due to an error. **"
    echo "***********************************************************"
    echo "  1. Visit the troubleshooting guide for help:"
    echo "     https://docs.mulesoft.com/runtime-fabric/latest/troubleshoot-guide#${ANCHOR}"
    echo
    echo "  2. Resume installation by running ${BASE_DIR}/init.sh"
    echo
    echo "Additional information: Error code: $trap_code; Step: ${CURRENT_STEP}; Line: ${TRAP_LINE:--};"
    echo

  fi

  echo -n $SCRIPT_VERSION > $STATE_DIR/version
}

function on_error {
    TRAP_LINE=$1
}

trap 'on_error $LINENO' ERR
trap on_exit EXIT

function run_step() {
    CURRENT_STEP=$1
    local DESCRIPTION=$2
    (( CURRENT_STEP_NBR++ )) || true
    echo
    echo -e "${CURRENT_STEP_NBR} / ${STEP_COUNT}: ${DESCRIPTION}${LINE}"
    if [ -f ${STATE_DIR}/${CURRENT_STEP} ]; then
        echo ${SKIP_TEXT}
        return 0
    fi
    eval ${CURRENT_STEP}
    touch ${STATE_DIR}/${CURRENT_STEP}
    echo -e ${SEP}
}

function simple_json_get () {
    local prop=$1
    local json=$2
    local regex="\"$prop\":\"([^\"]+)\""

    if [[ $json =~ $regex ]]; then
        echo -n ${BASH_REMATCH[1]}
    else
        echo "Error: Failed to extract json property: \"$prop\" from $json"
        exit 1
    fi
}

function check_root_user() {
    CURRENT_STEP=$FUNCNAME
    if [[ $EUID -ne 0 ]]; then
        echo "Error: You are not running as root. Runtime Fabric requires elevated privileges to install."
        return 1
    fi
}

function load_environment {
    CURRENT_STEP=$FUNCNAME
    if [ -f $BASE_DIR/env ]; then
        . $BASE_DIR/env
    fi

    if [ -z "$RTF_HTTP_PROXY" ]; then
        RTF_HTTP_PROXY=${HTTP_PROXY:-}
    fi

    if [ -z "$RTF_NO_PROXY" ]; then
        RTF_NO_PROXY=${NO_PROXY:-}
    fi
}

function decode_activation_data() {
    CURRENT_STEP=$FUNCNAME
    if [ "$RTF_ACTIVATION_DATA" == "skip" ]; then
        echo "Skipped $CURRENT_STEP. RTF_ACTIVATION_DATA=skip."
        return 0
    fi
    decoded=$(echo -n $RTF_ACTIVATION_DATA | base64 $BASE64_DECODE_OPTS)
    RTF_ENDPOINT=$(echo $decoded | cut -d':' -f 1)
    RTF_ACTIVATION_TOKEN=$(echo $decoded | cut -d':' -f 2)
}

function fetch_activation_properties() {
    CURRENT_STEP=$FUNCNAME
    if [ -z "$RTF_ACTIVATION_TOKEN" ]; then
        echo "Skipped $CURRENT_STEP. RTF_ACTIVATION_TOKEN not set."
        return 0
    fi
    if [ -f $STATE_DIR/install_rtf_components ]; then
        echo "Skipped $CURRENT_STEP. Not installing RTF components."
        return 0
    fi
    echo "Fetching activation properties..."

    if [ ! -z $RTF_ENDPOINT ] && [[ $RTF_ENDPOINT != http* ]]; then
        RTF_ENDPOINT="https://$RTF_ENDPOINT"
    fi

    COUNT=0
    while :
    do
        CODE=$($CURL_WITH_PROXY $CURL_OPTS -w "%{http_code}" $RTF_ENDPOINT/runtimefabric/api/activationData -H "Authorization: $RTF_ACTIVATION_TOKEN" -H "Accept: application/json" -o $ACTIVATION_PROPERTIES_FILE || true)
        if [ "$CODE" == "200" ]; then
            break
        fi
        let COUNT=COUNT+1
        if [ $COUNT -ge 8 ]; then
            echo "Error: Failed to fetch $COUNT times, giving up."
            exit 1
        fi
        echo "Retrying in $((10 * $COUNT)) seconds..."
        sleep $((10 * $COUNT))
    done

    if [ -z "$RTF_INSTALL_PACKAGE_URL" ]; then
        RTF_INSTALL_PACKAGE_URL=$(simple_json_get RTF_INSTALL_PACKAGE_URL `cat $ACTIVATION_PROPERTIES_FILE`)
    fi

    if [ ! -z $RTF_INSTALL_PACKAGE_URL ] && [[ $RTF_INSTALL_PACKAGE_URL != http* ]]; then
        RTF_INSTALL_PACKAGE_URL="https://$RTF_INSTALL_PACKAGE_URL"
    fi

    rm $ACTIVATION_PROPERTIES_FILE
}

function detect_properties() {
    CURRENT_STEP=$FUNCNAME
    if [ -z "$RTF_PRIVATE_IP" ]; then
        echo "RTF_PRIVATE_IP is not set, attempting to detect cloud provider"

        # Detect cloud provider by hitting instance metadata service. For azure, tags are converted to ENV_VARs
        HTTP_CODE=$(curl $CURL_METADATA_OPTS -o /dev/null -w "%{http_code}" $AWS_METADATA_URL/ || true)
        if [ $HTTP_CODE == 200 ]; then
            echo "Detected cloud provider: AWS"
            RTF_PRIVATE_IP=$(curl $CURL_METADATA_OPTS $AWS_METADATA_URL/local-ipv4)
        else
            HTTP_CODE=$(curl $CURL_METADATA_OPTS -o /dev/null -w "%{http_code}" -H$AZURE_METADATA_HEADER "$AZURE_METADATA_URL/?api-version=$AZURE_METADATA_VERSION" || true)
            if [ $HTTP_CODE == 200 ]; then
                echo "Detected cloud provider: Azure"
                RTF_PRIVATE_IP=$(curl $CURL_METADATA_OPTS -H$AZURE_METADATA_HEADER "$AZURE_METADATA_URL/network/interface/0/ipv4/ipAddress/0/privateIpAddress?api-version=$AZURE_METADATA_VERSION&format=text")
                TAGS=$(curl $CURL_METADATA_OPTS -H$AZURE_METADATA_HEADER "$AZURE_METADATA_URL/compute/tags?api-version=$AZURE_METADATA_VERSION&format=text")
                IFS=';' read -ra TAG_ARRAY <<< "$TAGS"
                for i in "${TAG_ARRAY[@]}"; do
                    IFS=':' read -ra THIS_TAG <<< "$i"
                    declare -g "${THIS_TAG[0]}=${THIS_TAG[1]}"
                done
            fi
        fi
    fi

    if [ -z $RTF_HTTP_PROXY ]; then
        CURL_WITH_PROXY="curl"
    else
        CURL_WITH_PROXY="curl --proxy $RTF_HTTP_PROXY"
    fi

    # Update NO_PROXY to make sure we bypass local addresses
    export NO_PROXY="0.0.0.0/0,.local,${NO_PROXY}"

    return 0
}

function validate_properties() {
    CURRENT_STEP=$FUNCNAME
    echo "Validating properties..."
    echo RTF_PRIVATE_IP: $RTF_PRIVATE_IP
    echo RTF_NODE_ROLE: $RTF_NODE_ROLE
    echo RTF_INSTALL_ROLE: $RTF_INSTALL_ROLE
    echo RTF_DOCKER_DEVICE: $RTF_DOCKER_DEVICE
    echo RTF_ETCD_DEVICE: $RTF_ETCD_DEVICE
    echo RTF_DOCKER_DEVICE_SIZE: $RTF_DOCKER_DEVICE_SIZE
    echo RTF_ETCD_DEVICE_SIZE: $RTF_ETCD_DEVICE_SIZE
    echo RTF_HTTP_PROXY: $RTF_HTTP_PROXY
    echo RTF_NO_PROXY: $RTF_NO_PROXY
    echo HTTP_PROXY: $HTTP_PROXY
    echo HTTPS_PROXY: $HTTPS_PROXY
    echo NO_PROXY: $NO_PROXY
    echo RTF_MONITORING_PROXY: $RTF_MONITORING_PROXY
    echo RTF_SERVICE_UID: $RTF_SERVICE_UID
    echo RTF_SERVICE_GID: $RTF_SERVICE_GID

    [ -z "$RTF_INSTALL_ROLE" ] && echo "Error: RTF_INSTALL_ROLE not set" && exit 1
    [ -z "$RTF_NODE_ROLE" ] && echo "Error: RTF_NODE_ROLE not set" && exit 1

    # Install-leader properties
    if [ $RTF_INSTALL_ROLE == "leader" ]; then
        echo RTF_INSTALL_PACKAGE_URL: $RTF_INSTALL_PACKAGE_URL
        echo RTF_TOKEN: $RTF_TOKEN
        echo RTF_NAME: $RTF_NAME
        # Registration properties
        echo RTF_ACTIVATION_TOKEN: $RTF_ACTIVATION_TOKEN
        echo RTF_MULE_LICENSE: ...$(echo $RTF_MULE_LICENSE | tail -c 10)
        [ -z "$RTF_NAME" ] && echo "Error: RTF_NAME not set" && exit 1
    else
        echo RTF_INSTALLER_IP: $RTF_INSTALLER_IP
        [ -z "$RTF_INSTALLER_IP" ] && echo "Error: RTF_INSTALLER_IP" && exit 1
    fi

    [ -z "$RTF_PRIVATE_IP" ] && echo "Error: RTF_PRIVATE_IP not set" && exit 1
    [ -z "$RTF_DOCKER_DEVICE" ] && [ -z "$RTF_DOCKER_DEVICE_SIZE" ] && echo "Error: RTF_DOCKER_DEVICE or RTF_DOCKER_DEVICE_SIZE must be set" && exit 1
    [ -z "$RTF_TOKEN" ] && echo "Error: RTF_TOKEN not set" && exit 1

    if [ $RTF_NODE_ROLE == "controller_node" ] || [ $RTF_NODE_ROLE == "general_node" ]; then
        [ -z "$RTF_ETCD_DEVICE" ] && [ -z "$RTF_ETCD_DEVICE_SIZE" ] && echo "Error: RTF_ETCD_DEVICE or RTF_ETCD_DEVICE_SIZE must be set" && exit 1
    fi
    return 0
}

function install_required_packages() {
    #disable exit-on-error
    set +e
    rpm -q chrony
    if [ $? != 0 ]; then
        echo "Installing chrony..."
        yum install -y chrony || true
    fi

    printf "Checking chrony sync status..."
    COUNT=0
    while :
    do
        chronyc tracking | grep -E 'Leap status\s+:\s+Normal'
        if [ "$?" == "0" ]; then
            echo "[OK]"
            break
        fi
        let COUNT=COUNT+1
        if [ $COUNT -ge "3" ]; then
            echo "Error: chrony sync check failed $COUNT times, giving up."
            exit 1
        fi
        echo "Retrying in 30 seconds..."
        sleep 30
    done
    # enable exit-on-error
    set -e
}


function format_and_mount_disks() {

    # if we specify the size, discover the disk from lsblk
    if [ -n "$RTF_DOCKER_DEVICE_SIZE" ]; then
        set +e
        RTF_DOCKER_DEVICE=/dev/$(lsblk --inverse --nodeps --noheadings --output NAME,TYPE,SIZE | grep $RTF_DOCKER_DEVICE_SIZE | cut -d ' ' -f 1 | head -n1)
        set -e
        if [ "$RTF_DOCKER_DEVICE" == "/dev/" ]; then
            echo "Error: $RTF_DOCKER_DEVICE_SIZE docker disk not found"
            lsblk
            exit 1
        fi
    else
        # devices could be symlinks, resolve now
        if [ -f $RTF_DOCKER_DEVICE ]; then
            RTF_DOCKER_DEVICE=$(readlink -fe "$RTF_DOCKER_DEVICE")
        fi
        # ensure device is a real block device
        echo "Querying block devices for $RTF_DOCKER_DEVICE..."
        lsblk $RTF_DOCKER_DEVICE
    fi

    echo "Initializing docker filesystem ($RTF_DOCKER_DEVICE)..."
    if [ -d "$DOCKER_MOUNT" ]; then
        umount -l $DOCKER_MOUNT || true
        rm -r $DOCKER_MOUNT
    fi
    mkfs.xfs -n ftype=1 -f $RTF_DOCKER_DEVICE
    # get the UUID
    RTF_DOCKER_DEVICE_UUID=$(blkid $RTF_DOCKER_DEVICE -ovalue | head -1)

    sed -i.bak '/RTF/d' /etc/fstab
    echo -e "UUID=$RTF_DOCKER_DEVICE_UUID\t$DOCKER_MOUNT\txfs\tdefaults,nofail\t0\t2\t$FSTAB_COMMENT" >> /etc/fstab

    mkdir -p $DOCKER_MOUNT
    mount $DOCKER_MOUNT
    chown -R $RTF_SERVICE_UID:$RTF_SERVICE_GID $DOCKER_MOUNT

    if [ "$RTF_NODE_ROLE" == "controller_node" ] || [ $RTF_NODE_ROLE == "general_node" ]; then

        # if we specify the size, discover the disk from lsblk
        if [ -n "$RTF_ETCD_DEVICE_SIZE" ]; then
            set +e
            RTF_ETCD_DEVICE=/dev/$(lsblk --inverse --nodeps --noheadings --output NAME,TYPE,SIZE | grep $RTF_ETCD_DEVICE_SIZE | cut -d ' ' -f 1 | head -n1)
            set -e
            if [ "$RTF_ETCD_DEVICE" == "/dev/" ]; then
                echo "Error: $RTF_ECTD_DEVICE_SIZE etcd disk not found"
                lsblk
                exit 1
            fi
        else
            # devices could be symlinks, resolve now
            if [ -f $RTF_ETCD_DEVICE ]; then
                RTF_ETCD_DEVICE=$(readlink -f "$RTF_ETCD_DEVICE")
            fi
            echo "Querying block devices for $RTF_ETCD_DEVICE..."
            lsblk $RTF_ETCD_DEVICE
        fi
        echo "Initializing etcd filesystem ($RTF_ETCD_DEVICE)..."
        if [ -d "$ETCD_MOUNT" ]; then
            umount -l $ETCD_MOUNT || true
            rm -r $ETCD_MOUNT
        fi
        mkfs.xfs -n ftype=1 -f $RTF_ETCD_DEVICE
        # get the UUID
        RTF_ETCD_DEVICE_UUID=$(blkid $RTF_ETCD_DEVICE -ovalue | head -1)
        echo -e "UUID=$RTF_ETCD_DEVICE_UUID\t$ETCD_MOUNT\txfs\tdefaults,nofail\t0\t2\t$FSTAB_COMMENT" >> /etc/fstab
        mkdir -p $ETCD_MOUNT
        mount $ETCD_MOUNT
        chown -R $RTF_SERVICE_UID:$RTF_SERVICE_GID $ETCD_MOUNT
    fi
}

function configure_ip_tables() {
    systemctl disable firewalld || true
    systemctl stop firewalld || true

    # Insert IP tables rules
    echo -e '*filter\n:INPUT ACCEPT [0:0]\n:FORWARD ACCEPT [0:0]\n:OUTPUT ACCEPT [0:0]\n-A OUTPUT -o lo -j ACCEPT\n-A OUTPUT -d 172.31.0.0/16 -p tcp -j ACCEPT\n-A OUTPUT -d 172.31.0.0/16 -p udp -j ACCEPT\n-A OUTPUT -d 10.0.0.0/8 -p tcp -j ACCEPT\n-A OUTPUT -d 10.0.0.0/8 -p udp -j ACCEPT\n-A OUTPUT -p tcp -m tcp ! --tcp-flags FIN,SYN,RST,ACK SYN -j ACCEPT\n-A OUTPUT -p udp --dport 123 -j ACCEPT\n-A INPUT -p udp --sport 123 -j ACCEPT\nCOMMIT' > /etc/rtf-iptables.rules
    echo -e '[Unit]\nDescription=Packet Filtering Framework\n\n[Service]\nType=oneshot\nExecStart=/usr/sbin/iptables-restore /etc/rtf-iptables.rules\nExecReload=/usr/sbin/iptables-restore /etc/rtf-iptables.rules\nRemainAfterExit=yes\n\n[Install]\nWantedBy=multi-user.target' > /etc/systemd/system/iptables.service
}

function configure_kernel_modules() {
    modprobe br_netfilter || true
    modprobe ebtable_filter || true
    modprobe overlay || true
    modprobe ip_tables || true
    modprobe iptable_filter || true
    modprobe iptable_nat || true

    cat > /etc/modules-load.d/telekube.conf <<EOF
ip_tables
iptable_nat
iptable_filter
br_netfilter
overlay
ebtable_filter
EOF

    cat > /etc/sysctl.d/50-telekube.conf <<EOF
net.ipv4.ip_forward=1
net.bridge.bridge-nf-call-iptables=1
EOF

    if sysctl -q fs.may_detach_mounts >/dev/null 2>&1; then
      echo "fs.may_detach_mounts=1" >> /etc/sysctl.d/50-telekube.conf
    fi

    sysctl -p /etc/sysctl.d/50-telekube.conf
}

function start_system_services() {
    systemctl --system daemon-reload
    systemctl enable iptables.service
    systemctl enable chronyd
    systemctl start iptables.service
    systemctl start chronyd
}

function fetch_rtfctl() {
    if [[ -z $RTF_ENDPOINT ]]; then
        RTFCTL_URL=https://anypoint.mulesoft.com/runtimefabric/api/download/rtfctl/latest
    else
        RTFCTL_URL=${RTF_ENDPOINT}/runtimefabric/api/download/rtfctl/latest
    fi

    echo "Fetching rtfctl ${RTFCTL_URL}..."
    $CURL_WITH_PROXY $CURL_OPTS -o rtfctl $RTFCTL_URL
    chmod +x ./rtfctl
}

function add_cgroup_cleanup_job() {
  source /etc/os-release
  if [[ $VERSION_ID != 7* ]]; then
    echo "Skipped. Detected OS version: $VERSION_ID, not compatible."
    return 0
  fi

  mkdir -p /var/lib/gravity/cron

  cat > /var/lib/gravity/cron/systemd_gc.sh <<"EOF"
#!/bin/bash

echo "$(date) - Starting systemd_gc job"

count=0
for i in $(find /sys/fs/cgroup/ -name run-*.scope -type d -printf "%f\n"); do
  pod=$(systemctl list-units --type scope --state running $i | cat | sed -n 's/\(.*\)Kubernetes transient mount for \/var\/lib\/kubelet\/pods\/\(.*\)\/volumes\(.*\)/\2/p')
  if [ ! -f "/var/lib/kubelet/pods/'$pod'" ]; then
    echo -n "Trying to stop '$i' systemd scope... "
    systemctl stop $i
    echo "Stopped."
    count=$((count + 1))
  fi
done

echo "Total ${count} systemd scope stopped."
echo "$(date) - Completed systemd_gc job"
EOF

  chmod +x /var/lib/gravity/cron/systemd_gc.sh

  ADD_CRON_JOB_CMD="cat > /etc/cron.d/systemd_gc <<EOF
SHELL=/bin/bash

# Can be updated to a different time: 0-59 0-23 * * *
$(shuf -i 0-59 -n 1) 0 * * * root  /var/lib/gravity/cron/systemd_gc.sh >> /var/lib/gravity/cron/systemd_gc.log 2>&1
EOF"

  $GRAVITY_BASH "$ADD_CRON_JOB_CMD"

  cat > /etc/logrotate.d/systemd_gc <<EOF
/var/lib/gravity/cron/systemd_gc.log {
  daily
  size 10M
  missingok
  notifempty
  rotate 1
}
EOF

  $GRAVITY_BASH "/var/lib/gravity/cron/systemd_gc.sh"

  echo "Added cgroup cleanup job."
}

function fetch_install_package() {
    if [[ ! -z $RTF_INSTALL_PACKAGE_URL ]]; then
        echo "Fetching installation package \"$RTF_INSTALL_PACKAGE_URL\"..."
        $CURL_WITH_PROXY $CURL_OPTS $RTF_INSTALL_PACKAGE_URL -o installer.tar.gz
    else
        until [ -f $BASE_DIR/installer.tar.gz ]; do
            echo "Waiting for installation package at $BASE_DIR/installer.tar.gz..."
            sleep 15
        done
    fi

    if [ ! -f $BASE_DIR/installer.tar.gz ]; then
        echo "Error: failed to fetch installation package. Exiting."
        exit 1
    fi
}

function install_cluster() {
    echo "Extracting installer package..."
    mkdir -p installer
    tar -zxf installer.tar.gz -C installer
    cd installer

    GRAVITY_VERSION=$(./gravity version | grep "^Version:" | awk '{ print $2 }')
    if [[ ${GRAVITY_VERSION} != "5.2"* ]] && [ -n "${RTF_HTTP_PROXY}" ]; then
        cat > ../runtime_environment.yaml <<EOF
kind: RuntimeEnvironment
version: v1
spec:
  data:
    HTTP_PROXY: "${RTF_HTTP_PROXY}"
    http_proxy: "${RTF_HTTP_PROXY}"
    HTTPS_PROXY: "${RTF_HTTP_PROXY}"
    NO_PROXY: "${SYSTEM_NO_PROXY},${RTF_NO_PROXY}"
EOF
    local EXTRA_CONFIG=--config=../runtime_environment.yaml
    fi

    FLAVOR=dynamic
    if [ $RTF_NODE_ROLE == "general_node" ]; then
        FLAVOR=demo
    fi

    ./gravity install --advertise-addr=$RTF_PRIVATE_IP \
      --token=$RTF_TOKEN \
      --cluster=$RTF_NAME \
      --cloud-provider=generic \
      --flavor=$FLAVOR \
      --role=$RTF_NODE_ROLE \
      --pod-network-cidr=$POD_NETWORK_CIDR \
      --service-cidr=$SERVICE_CIDR \
      --service-uid=$RTF_SERVICE_UID \
      --service-gid=$RTF_SERVICE_GID \
      ${EXTRA_CONFIG}

    if [ ! -f /usr/bin/gravity ]; then
        echo "Error: /usr/bin/gravity does not exist"
        exit 1
    fi

    # ensure we have completed the installation by inspecting our cluster-info cm
    ${KUBECTL_CMD_PREFIX} get configmap cluster-info -nkube-system > /dev/null

    # load KUBECONFIG environment variable for rtfctl
    set -o allexport; source /etc/environment; set +o allexport

    cd $BASE_DIR
}

function inject_proxy_into_dockerd() {
    if [ -z $RTF_HTTP_PROXY ]; then
        echo "Skipped. HTTP proxy not configured"
        return 0
    fi
    # we only need this for 5.2.* versions
    if [[ ${GRAVITY_VERSION} != "5.2"* ]]; then
        return 0
    fi

    echo "Injecting HTTP proxy into Docker daemon..."

    DOCKER_PROXY_VARS_CMD="cat > /etc/systemd/system/docker.service.d/http-proxy-vars.conf <<EOF
HTTP_PROXY=$RTF_HTTP_PROXY
HTTPS_PROXY=$RTF_HTTP_PROXY
NO_PROXY=$SYSTEM_NO_PROXY,$RTF_NO_PROXY
EOF"
    $GRAVITY_BASH "$DOCKER_PROXY_VARS_CMD"

    # we use EnvironmentFile so that systemd can parse special characters in the proxy string
    DOCKER_PROXY_CMD="cat > /etc/systemd/system/docker.service.d/http-proxy.conf <<EOF
[Service]
EnvironmentFile=/etc/systemd/system/docker.service.d/http-proxy-vars.conf
EOF"
    $GRAVITY_BASH "$DOCKER_PROXY_CMD"

    gravity planet enter -- --notty  /usr/bin/systemctl -- daemon-reload
    gravity planet enter -- --notty  /usr/bin/systemctl -- restart docker
}

function join_cluster() {
    echo "Joining cluster, waiting for installer node to complete..."

    # disable exit-on-error
    set +e
    until [ -f gravity ]; do
        sleep 15
        curl $CURL_OPTS https://$RTF_INSTALLER_IP:32009/telekube/gravity -o gravity
    done
    chmod +x gravity

    # if we are setting the proxy, we must wait until the agent has installed, because it
    # restarts dockerd on the leader and causes join to hang for v1.0.x installers
    GRAVITY_VERSION=$(./gravity version | grep "^Version:" | awk '{ print $2 }')
    if [[ ${GRAVITY_VERSION} == "5.2"* ]] && [ -n $RTF_HTTP_PROXY ]; then
        until [ -f .rtf_installed_flag ]; do
            sleep 15
            curl $CURL_OPTS http://$RTF_INSTALLER_IP:30945/api/v1/status/info -o .rtf_installed_flag
        done
    fi

    COUNT=0
    while :
    do
        export GRAVITY_PEER_CONNECT_TIMEOUT=60m
        ./gravity join $RTF_INSTALLER_IP --advertise-addr=$RTF_PRIVATE_IP --token=$RTF_TOKEN --cloud-provider=generic --role=$RTF_NODE_ROLE

        if [ "$?" == "0" ]; then
            if [ ! -f /usr/bin/gravity ]; then
                echo "Error: /usr/bin/gravity does not exist"
                exit 1
            fi
            break
        fi

        let COUNT=COUNT+1
        if [ $COUNT -ge $JOINING_ATTEMPTS ]; then
            echo "Error: Failed to register $COUNT times, giving up."
            exit 1
        fi
        echo "Retrying joining the cluster in 30 seconds..."
        sleep 30
    done

    # enable exit-on-error
    set -e
}

function create_rtf_namespace() {
    ${KUBECTL_CMD_PREFIX} create ns rtf || true
    ${KUBECTL_CMD_PREFIX} label ns rtf rtf.mulesoft.com/role=rtf || true
}

function install_rtf_components() {
    if [ -z "$RTF_ACTIVATION_TOKEN" ]; then
        echo "Skipped. RTF_ACTIVATION_TOKEN not set.  Creating namespace only."
        create_rtf_namespace
        return 0
    fi

    if [ -z "$RTF_AGENT_URL" ]; then
        HTTP_PROXY="$RTF_HTTP_PROXY" MONITORING_PROXY="$RTF_MONITORING_PROXY" ./rtfctl install ${RTF_ACTIVATION_DATA}
    else
        HTTP_PROXY="$RTF_HTTP_PROXY" MONITORING_PROXY="$RTF_MONITORING_PROXY" ./rtfctl install ${RTF_ACTIVATION_DATA} --helm-chart-location ${RTF_AGENT_URL}
    fi
}

function wait_for_connectivity() {
    ./rtfctl wait
}

function install_mule_license() {
    if [ -z "$RTF_MULE_LICENSE" ]; then
        echo "Skipped. RTF_MULE_LICENSE not set"
        return 0
    fi
    echo "Configuring Mule license..."
    ./rtfctl apply mule-license "$RTF_MULE_LICENSE"
}

function generate_ops_center_credentials() {
    ADMIN_PASSWORD="$(env LC_CTYPE=C tr -dc 'a-zA-Z0-9' < /dev/urandom | head -c50)" || true
    if [ -z "$ADMIN_PASSWORD" ]; then
        echo "Error: Failed to generate admin password"
        exit 1;
    fi

    set +e
    OPCENTER_CMD="gravity planet enter -- --notty /usr/bin/gravity -- user create --type=admin --email=admin@runtime-fabric --password=$ADMIN_PASSWORD --ops-url=https://gravity-site.kube-system.svc.cluster.local:3009 --insecure"

    eval $OPCENTER_CMD
    CMD_EXIT_CODE=$?

    COUNT=1
    until [ "$CMD_EXIT_CODE" == "0" ]; do
        echo
        echo "Retrying OpsCenter credentials in 30 seconds..."
        sleep 30
        eval $OPCENTER_CMD
        CMD_EXIT_CODE=$?
        let COUNT=COUNT+1
        if [ $COUNT -ge 5 ]; then
            echo "Error: Failed to generate OpsCenter credentials $COUNT times, giving up."
            exit 1
        fi
    done
    # enable exit-on-error
    set -e

    echo "Ops Center access:"
    echo "URL:      https://$RTF_PRIVATE_IP:32009/web"
    echo "User:     admin@runtime-fabric"
    echo "Password: $ADMIN_PASSWORD"
}

function set_inotify_limit() {
    sysctl -w fs.inotify.max_user_watches=1048576
    echo "fs.inotify.max_user_watches=1048576" > /etc/sysctl.d/inotify.conf
}

function purge() {
    echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
    echo "  WARNING: THIS WILL REMOVE ALL RUNTIME FABRIC COMPONENTS AND APPLICATIONS"
    echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
    read -p "Continue (y/n)? " choice
    case "$choice" in
        y|Y )
            echo "Removing RTF components..."
            ${HELM} delete runtime-fabric --purge || true

            ${KUBECTL_CMD_PREFIX} get secret custom-properties -nrtf --export -oyaml > custom_properties.yaml
            echo "Removing applications..."
            gravity planet enter -- --notty /usr/bin/kubectl -- delete ns -l rtf.mulesoft.com/role || true
            while [ true ]; do
                NS_REMAINING=$(gravity planet enter -- --notty /usr/bin/kubectl -- get ns --no-headers --ignore-not-found -l rtf.mulesoft.com/role | wc -l)
                if [ "$NS_REMAINING" == "0" ]; then
                    break
                fi
                sleep 1
                echo "Waiting for $NS_REMAINING namespaces to be removed..."
            done
            rm .state/install_rtf_components .state/install_mule_license .state/wait_for_connectivity .state/init-complete || true
        ;;

    n|N ) exit
        ;;
    * ) echo "Unexpected response";;
  esac
  echo
  echo "Purge complete."
}

function activate() {
  if [ -z "$1" ]; then
    echo "Activation data is missing, use the following: ./init.sh activate '<activation data snippet>'"
    exit
  fi

  load_environment
  detect_properties
  RTF_ACTIVATION_DATA="$1"
  decode_activation_data
  fetch_activation_properties
  validate_properties
  create_rtf_namespace

  # if we backed up custom-properties during purge, reapply it now
  if [ -f custom_properties.yaml ]; then
    cp custom_properties.yaml /var/lib/gravity/rtf_custom_properties.yaml
    ${KUBECTL_CMD_PREFIX} apply -nrtf -f /var/lib/gravity/rtf_custom_properties.yaml
  fi

  install_rtf_components
  exit
}

function reinstall() {
    RTF_ENV=${RTF_ENV:-prod}

    # reinstall is only valid to run when we have runtime-fabric installed.
    ${HELM} status runtime-fabric

    # Clean up temp directory...
    mkdir -p reinstall-data
    rm -rf reinstall-data/*

    echo "Discovering current configuration..."

    if [ -z $RTF_VERSION ]; then
        RTF_VERSION=$(${KUBECTL_CMD_PREFIX} get deployment deployer -nrtf -o jsonpath="{.spec.template.spec.containers[0].image}" | cut -d: -f 2 | cut -dv -f 2)
    fi
    echo " - version: ${RTF_VERSION}"

    AWS_ACCESS_KEY_ID=$(${KUBECTL_CMD_PREFIX} get secret registry-creds -nrtf -ojsonpath="{.data.AWS_ACCESS_KEY_ID}" | base64 -d)
    AWS_SECRET_ACCESS_KEY=$(${KUBECTL_CMD_PREFIX} get secret registry-creds -nrtf -ojsonpath="{.data.AWS_SECRET_ACCESS_KEY}" | base64 -d)
    AWS_DEFAULT_REGION=$(${KUBECTL_CMD_PREFIX} get secret registry-creds -nrtf -ojsonpath="{.data.AWS_REGION}" | base64 -d)

    ${HELM} get values runtime-fabric > reinstall-data/values.yaml

    echo
    echo "Fetching RTF installation package..."
    awsFile="runtime-fabric-agent-${RTF_VERSION}.tgz"
    bucket="worker-cloud-helm-${RTF_ENV}"
    resource="/${bucket}/${awsFile}"
    contentType="application/x-compressed-tar"
    dateValue=`TZ=GMT date -R`
    stringToSign="GET\n\n${contentType}\n${dateValue}\n${resource}"
    signature=`echo -en ${stringToSign} | openssl sha1 -hmac ${AWS_SECRET_ACCESS_KEY} -binary | base64`
    curl --fail -H "Host: ${bucket}.s3.amazonaws.com" \
         -H "Date: ${dateValue}" \
         -H "Content-Type: ${contentType}" \
         -H "Authorization: AWS ${AWS_ACCESS_KEY_ID}:${signature}" \
         https://${bucket}.s3.amazonaws.com/${awsFile} -o reinstall-data/rtf-agent.tgz

    cp -r reinstall-data /var/lib/gravity

    echo
    echo "Removing current configuration..."
    ${HELM} delete --purge runtime-fabric

    # reinstall
    ${HELM} install /var/lib/gravity/reinstall-data/rtf-agent.tgz --name runtime-fabric --namespace rtf --wait -f /var/lib/gravity/reinstall-data/values.yaml
    rm -rf /var/lib/gravity/reinstall-data
}



##########################################
# Entrypoint
##########################################

# Also log output to file
exec >& >(tee -a "$REDIRECT_LOG")

check_root_user

mkdir -p $BASE_DIR
mkdir -p $STATE_DIR

SCRIPT_DIR=$(realpath $BASH_SOURCE)
if [[ $SCRIPT_DIR != ${BASE_DIR}* ]]; then
   cp $BASH_SOURCE $BASE_DIR/init.sh || true
fi

cd $BASE_DIR

if [ "$1" == "purge" ]; then
    purge
    exit
elif [ "$1" == "activate" ]; then
    activate "$2"
    exit
elif [ "$1" == "reinstall-components" ]; then
    reinstall
    exit
elif [ "$1" == "configure-system" ]; then
    STEP_COUNT=3
    run_step set_inotify_limit "Set inotify watch limits"
    run_step add_cgroup_cleanup_job "Add cgroup cleanup job"
    run_step start_system_services "Start system services"
    exit
elif [ "$1" != "" ]; then
    echo "Invalid command: $1"
    exit 1
fi

echo "Runtime Fabric installation, version: $SCRIPT_VERSION"
echo

echo -e "Detecting properties..."
load_environment
detect_properties
decode_activation_data
fetch_activation_properties
validate_properties

if [ "$RTF_INSTALL_ROLE" == "leader" ]; then
    STEP_COUNT=15
else
    STEP_COUNT=10
fi

# Cluster Setup
run_step install_required_packages "Install required packages"
run_step format_and_mount_disks "Format and mount disks"
run_step configure_ip_tables "Configure IP tables rules"
run_step configure_kernel_modules "Enable kernel modules"
run_step set_inotify_limit "Set inotify watch limits"
run_step start_system_services "Start system services"
run_step fetch_rtfctl "Fetch rtfctl tool"
if [ "$RTF_INSTALL_ROLE" == "leader" ]; then
    run_step fetch_install_package "Fetch installation package"
    run_step install_cluster "Create cluster"
    run_step generate_ops_center_credentials "Generate Ops Center credentials"
else
    run_step join_cluster "Join cluster"
fi
run_step inject_proxy_into_dockerd "Configure dockerd proxy"
run_step add_cgroup_cleanup_job "Add cgroup cleanup job"

# RTF Setup
if [ "$RTF_INSTALL_ROLE" == "leader" ]; then
    run_step install_rtf_components "Install RTF components"
    run_step install_mule_license "Install Mule license"
    run_step wait_for_connectivity "Wait for connectivity"
fi

echo -e "Runtime Fabric installation complete."
touch $STATE_DIR/init-complete

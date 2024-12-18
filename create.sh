#!/bin/bash

# global vars
USERNAME="student"
TF_DIR="./terraform"
SSH_KEY_DIR=".ssh"
SSH_CONFIG_FILE="$HOME/.ssh/config"
SSH_KEY_FILE="$SSH_KEY_DIR/${USERNAME}_key"

# parse command line arguments to set TF vars
# Default values
INSTALL_K8S="yes"
INIT_SCRIPT_SUFFIX=".sh"
PROVISIONING_MODEL=""
K8S_VERSION="latest"

# Function to display help
function display_help() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  --no-install-k8s              Skip Kubernetes installation."
    echo "  --ha-lab                      Set 4 nodes and skip Kubernetes installation."
    echo "  --provisioning-model [value]  Set provisioning model to 'standard' or 'spot'."
    echo "  --k8s-version [value]         Set Kubernetes version to 'latest' (default) or a specific version (e.g., v1.29, v1.30)."
    echo "  --help                        Display this help message."
    exit 0
}

# Function to validate Kubernetes version
function validate_k8s_version() {
    if [[ "$1" != "latest" && ! "$1" =~ ^v[0-9]+\.[0-9]+$ ]]; then
        echo "Error: Invalid Kubernetes version '$1'. Allowed values are 'latest' or versions like 'v1.29', 'v1.30'."
        exit 1
    fi
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --no-install-k8s)
            INSTALL_K8S="no"
            INIT_SCRIPT_SUFFIX="-no-k8s.sh"
            shift
            ;;
        --ha-lab)
            INSTALL_K8S="no"
            INIT_SCRIPT_SUFFIX="-no-k8s.sh"
            export TF_VAR_instance_name='[ "control-node", "worker1-node", "worker2-node", "worker3-node" ]'
            shift
            ;;
        --provisioning-model)
            if [[ "$2" == "standard" ]]; then
                PROVISIONING_MODEL="STANDARD"
            elif [[ "$2" == "spot" ]]; then
                PROVISIONING_MODEL="SPOT"
            else
                echo "Error: Invalid value for --provisioning-model. Allowed values are 'standard' or 'spot'."
                exit 1
            fi
            shift 2
            ;;
        --k8s-version)
            validate_k8s_version "$2"
            K8S_VERSION="$2"
            shift 2
            ;;
        --help)
            display_help
            ;;
        *)
            echo "Error: Unknown argument $1"
            exit 1
            ;;
    esac
done

# Export environment variables only if they are defined
if [[ -n "$INIT_SCRIPT_SUFFIX" ]]; then
    export TF_VAR_init_script_suffix="$INIT_SCRIPT_SUFFIX"
fi

if [[ -n "$PROVISIONING_MODEL" ]]; then
    export TF_VAR_provisioning_model="$PROVISIONING_MODEL"
fi

export TF_VAR_k8s_version="${K8S_VERSION}"

# create ssh key dir if it does not exist
if [ ! -d "${SSH_KEY_DIR}" ]; then
    mkdir $SSH_KEY_DIR
fi
# generate a new ssh_key
echo "Generating new ssh key..."
if [ -f "${SSH_KEY_FILE}" ]; then
    # remove existing keys
    rm $SSH_KEY_FILE
    rm $SSH_KEY_FILE.pub
fi

ssh-keygen -t ed25519 -N "" -b 4096 -C "${USERNAME}" -f $SSH_KEY_FILE
echo "Done"

# get public-key value
KEY=$(cat $SSH_KEY_FILE.pub)
echo $KEY

# create or replace the .ssh_key file used in main.tf file
TF_SSH_KEY_FILE="${TF_DIR}/.ssh_key"
echo -n "${USERNAME}:${KEY}" > $TF_SSH_KEY_FILE
if [[ $? -ne 0 ]]; then
  echo "Error: Failed to write SSH key to $TF_SSH_KEY_FILE."
  exit 1
fi

chmod 600 $TF_SSH_KEY_FILE
if [[ $? -ne 0 ]]; then
  echo "Error: Failed to set permissions on $TF_SSH_KEY_FILE."
  exit 1
fi

# create instances
cd $TF_DIR
terraform apply -auto-approve
cd ..

TF_STATE="${TF_DIR}/terraform.tfstate"
NR_INSTANCES=$(jq -r '.resources[0].instances[].attributes.name' $TF_STATE | wc -l)

function gen_ssh_config_entries() {
    # args: hostname, ip_address, username, ssh_key_file
    config_entry=$(cat <<EOF
Host $1
    Hostname $2
    User $3
    IdentityFile $4
    StrictHostKeyChecking no
    Compression yes
    UserKnownHostsFile ./known_hosts

EOF
)

    echo "$config_entry"
}

function rm_file() {
    # args: filename
    filename=$1
    if [ -f "${1}" ]; then
        echo -n "Removing ${1} file... "
        /bin/rm $1
        echo "Done."
    fi
}

# rm known_hosts file if exist
rm_file "./known_hosts"

# backup ssh_config if it exists
if [ -f $SSH_CONFIG_FILE ]; then
    echo -n "${SSH_CONFIG_FILE} exists. Backing it up... "
    cp $SSH_CONFIG_FILE $SSH_CONFIG_FILE.bak
    echo "Done."
fi

IFS_SAVE=$IFS
IFS=$'\n'
hostnames=( $(jq -r ".resources[0].instances[].attributes.name" $TF_STATE) )
public_ip_addresses=( $(jq -r ".resources[0].instances[].attributes.network_interface[0].access_config[0].nat_ip" $TF_STATE) )
private_ip_addresses=( $(jq -r ".resources[0].instances[].attributes.network_interface[0].network_ip" $TF_STATE) )
IFS=$IFS_SAVE

ssh_lines=""
host_lines=""
for i in ${!hostnames[*]}; do
  hostname=${hostnames[$i]}
  public_ip=${public_ip_addresses[$i]}
  private_ip=${private_ip_addresses[$i]}
  # add ssh_config entries to list
  entries=$(gen_ssh_config_entries "${hostname}" "${public_ip}" "${USERNAME}" "${SSH_KEY_FILE}")
  if [ -z "$ssh_lines" ]; then sep=""; else sep="\n\n"; fi
  ssh_lines="${ssh_lines}${sep}${entries}"
  # add k8s cluster hosts entries to list
  host_lines="${host_lines}\n${private_ip}\t\t${hostname}"
done

echo -n "Writing $SSH_CONFIG_FILE to disk... "
echo -e "$ssh_lines" > $SSH_CONFIG_FILE
echo "Done."

FINISHED_STR="Finished running startup scripts."
echo -n "Waiting 5 seconds... "
sleep 5
echo "Done"

# check if the startup script finished
declare -i RETRIES=18
declare -i INTERVAL=10
countdown=$RETRIES
timeout=$(expr $INTERVAL \* $RETRIES)
ZONE=( $(jq -r '.resources[0].instances[0].attributes.zone' $TF_STATE))
COMPLETION_MARKER="STARTUP-SCRIPT-COMPLETED"
echo "Checking if startup script finished."
while (( countdown > 0 )); do
    OUTPUT=$(
        gcloud compute instances get-serial-port-output "${hostnames[0]}" \
            --zone "$ZONE" --port 3 2>/dev/null | grep "$COMPLETION_MARKER"
    )
    if [ "$OUTPUT" ]; then
        echo "Startup script completed successfully."
        break
    else
        countdown=$((countdown - 1))
        printf "Startup script is still running on control node... Waiting %d secs... " \
            "$INTERVAL"
        printf "(%d attempts remaining)\n" "$countdown"
        sleep "$INTERVAL"
    fi
done

if (( countdown == 0 )); then
    echo "Exiting after timeout. Waited ${timeout} secs. Run ./destroy.sh and try again."
    exit 1
fi

echo "Done"

# Updating /etc/hosts and copying ssh keys to all cluster nodes
for i in ${!hostnames[*]}; do
    hostname=${hostnames[$i]}
    echo "Updating /etc/hosts on ${hostname}"
    ssh ${USERNAME}@${hostname} "echo -e '${host_lines}' | grep -v ${hostname} | sudo tee -a /etc/hosts" 
    echo "Done"
    echo "Copying ssh key files"
    scp ${SSH_KEY_FILE}* "${USERNAME}@${hostname}:~/.ssh"
    # change permissions
    ssh ${USERNAME}@${hostname} "chmod 600 ~/.ssh/${USERNAME}_key && chmod 644 ~/.ssh/${USERNAME}_key.pub"
    echo "Done"
    # define this key as the default identity file
    echo -n "Define ~/.ssh/${USERNAME}_key as default identity file... "
    ssh ${USERNAME}@${hostname} "echo -e 'IdentityFile ~/.ssh/${USERNAME}_key' > ~/.ssh/config" 
    echo "Done"
done

# Complete K8s cluster installation only if the option to not install k8s was not selected
if [[ "$INSTALL_K8S" == "yes" ]]; then
    # check if the control node is ready
    countdown=$RETRIES
    echo "Checking if control node is ready."
    while (( countdown > 0 )); do
        control_node_check=$(ssh control-node "kubectl get nodes" | grep "control-plane" | grep -c "NotReady")
        if [ ${control_node_check} == "0" ]; then
            break
        else
            countdown=$(expr $countdown-1)
            echo "Control node is not ready. Waiting $INTERVAL secs"
            sleep $INTERVAL
        fi
    done

    if (( countdown == 0 )); then
        echo "Exiting after timeout. Waited ${timeout} secs. Run ./destroy.sh and try again."
        exit
    fi

    echo "Done."

    # configuring the cluster
    # assumes node 1 is control, and the others are worker nodes
    echo "Configuring the cluster..."
    for i in ${!hostnames[*]}; do
        hostname=${hostnames[i]}
        if (( $i == 0 )); then
            # generate join command
            echo "Generating join command on control node"
            join_cmd=$(ssh ${hostname} "kubeadm token create --print-join-command")
        else
            # execute join command
            echo "joining on ${hostname}..."
            result=$(ssh ${hostname} "sudo ${join_cmd}")
            echo -e $result
        fi
    done

    echo "Done."

    echo "Check if DNS is working fine on control node using the commands below:"
    echo "1. Check if the coredns pods are running:"
    echo "   => kubectl get pods -n kube-system -l k8s-app=kube-dns -o wide"
    echo "2. If they are running in different nodes, run the command below to test dns:"
    echo "   => kubectl run test-dns --rm -it --image=busybox --restart=Never -- nslookup kubernetes.default.svc.cluster.local"
    echo "If the coredns pods are not running on different worker nodes, try to restart them:"
    echo "   => kubectl -n kube-system rollout restart deployment coredns"
fi
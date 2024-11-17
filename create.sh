#!/bin/bash

# global vars
USERNAME="student"
TF_DIR="./terraform"
SSH_KEY_DIR=".ssh"
SSH_CONFIG_FILE="$HOME/.ssh/config"
SSH_KEY_FILE="$SSH_KEY_DIR/${USERNAME}_key"

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

# replace keys in TF VARS file
sed -i.bak 's#'"$USERNAME"':.*#'"$USERNAME"':'"$KEY"'"#' $TF_DIR/terraform.tfvars

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

# create a new lab_hosts file
echo -e "\n# k8s cluster hosts" > ./lab_hosts

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
echo "Checking if startup script finished."
while (( countdown > 0 )); do
    control_node_check=$(ssh control-node "sudo journalctl -u google-startup-scripts.service -n 5" | grep -c "$FINISHED_STR")
    if [ ${control_node_check} != "0" ]; then
        break
    else
        countdown=$(expr $countdown-1)
        echo "Startup script is still running on control node... Waiting $INTERVAL secs..."
        sleep $INTERVAL
    fi
done

if (( countdown == 0 )); then
    echo "Exiting after timeout. Waited ${timeout} secs."
    exit
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
    echo "Exiting after timeout. Waited ${timeout} secs."
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

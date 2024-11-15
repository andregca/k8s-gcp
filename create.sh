#!/bin/bash

# global vars
USERNAME="student"
TF_DIR="./terraform"
SSH_KEY_DIR=".ssh"
SSH_CONFIG_FILE="$HOME/.ssh/config"
SSH_KEY_FILE="$SSH_KEY_DIR/my_key"

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

ssh-keygen -t ed25519 -N "" -b 4096 -C "$(whoami)@$(hostname)" -f $SSH_KEY_FILE
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

# backup ssh_config if it exists
if [ -f $SSH_CONFIG_FILE ]; then
    echo -n "${SSH_CONFIG_FILE} exists. Backing it up... "
    cp $SSH_CONFIG_FILE $SSH_CONFIG_FILE.bak
    echo "Done."
fi

# rm known_hosts file if exists
if [ -f "./known_hosts" ]; then
    echo -n "Removing ./known_hosts file... "
    /bin/rm ./known_hosts
    echo "Done."
fi

# create a new ssh config file
touch $SSH_CONFIG_FILE

IFS_SAVE=$IFS
IFS=$'\n'
hostnames=( $(jq -r ".resources[0].instances[].attributes.name" $TF_STATE) )
ip_addresses=( $(jq -r ".resources[0].instances[].attributes.network_interface[0].access_config[0].nat_ip" $TF_STATE) )
IFS=$IFS_SAVE

lines=""
for i in ${!hostnames[*]}; do
  hostname=${hostnames[$i]}
  ip_address=${ip_addresses[$i]}
  entries=$(gen_ssh_config_entries "${hostname}" "${ip_address}" "${USERNAME}" "${SSH_KEY_FILE}")
  if [ -z "$lines" ]; then sep=""; else sep="\n\n"; fi
  lines="$lines$sep$entries"
done

echo -n "Writing $SSH_CONFIG_FILE to disk... "
echo -e "$lines" > $SSH_CONFIG_FILE
echo "Done."

FINISHED_STR="Finished running startup scripts"

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
        echo sleeping $INTERVAL
        sleep $INTERVAL
    fi
done

if (( countdown == 0 )); then
    echo "Exiting after timeout. Waited ${timeout} secs."
    exit
fi

echo "Done"

# check if the control node is ready
countdown=$RETRIES
echo "Checking if control node is ready."
while (( countdown > 0 )); do
    control_node_check=$(ssh control-node "kubectl get nodes" | grep "control-plane" | grep -c "NotReady")
    if [ ${control_node_check} == "0" ]; then
        break
    else
        countdown=$(expr $countdown-1)
        echo "Control node not ready. Sleeping $INTERVAL secs"
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

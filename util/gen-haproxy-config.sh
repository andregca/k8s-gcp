#!/bin/bash

# Determine the directory of the script
SCRIPT_DIR=$(dirname "$(realpath "$0")")

# Path to the haproxy.cfg file
HAPROXY_CFG="$SCRIPT_DIR/haproxy.cfg"

# Get the IP addresses from gcloud
declare -A IP_ADDRESSES
while read -r NAME IP; do
    IP_ADDRESSES[$NAME]=$IP
done < <(gcloud compute instances list --format="table[no-heading](NAME,INTERNAL_IP)")

# Check if required nodes are present
REQUIRED_NODES=("control-node" "worker1-node" "worker2-node")
for NODE in "${REQUIRED_NODES[@]}"; do
    if [[ -z "${IP_ADDRESSES[$NODE]}" ]]; then
        echo "Error: Could not find IP for $NODE. Exiting."
        exit 1
    fi
done

# Generate the haproxy.cfg file
cat > "$HAPROXY_CFG" <<EOF
global
        log /dev/log    local0
        log /dev/log    local1 notice
        chroot /var/lib/haproxy
        stats socket /run/haproxy/admin.sock mode 660 level admin expose-fd listeners
        stats timeout 30s
        user haproxy
        group haproxy
        daemon

        # Default SSL material locations
        ca-base /etc/ssl/certs
        crt-base /etc/ssl/private

        # See: https://ssl-config.mozilla.org/#server=haproxy&server-version=2.0.3&config=intermediate
        ssl-default-bind-ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384
        ssl-default-bind-ciphersuites TLS_AES_128_GCM_SHA256:TLS_AES_256_GCM_SHA384:TLS_CHACHA20_POLY1305_SHA256
        ssl-default-bind-options ssl-min-ver TLSv1.2 no-tls-tickets

defaults
        log     global
        mode    http
        option  httplog
        option  dontlognull
        timeout connect 5000
        timeout client  50000
        timeout server  50000
        errorfile 400 /etc/haproxy/errors/400.http
        errorfile 403 /etc/haproxy/errors/403.http
        errorfile 408 /etc/haproxy/errors/408.http
        errorfile 500 /etc/haproxy/errors/500.http
        errorfile 502 /etc/haproxy/errors/502.http
        errorfile 503 /etc/haproxy/errors/503.http
        errorfile 504 /etc/haproxy/errors/504.http

#---------------------------------------------------------------------
# apiserver frontend which proxys to the control plane nodes
#---------------------------------------------------------------------
frontend apiserver
    bind *:6443
    mode tcp
    option tcplog
    default_backend apiserverbackend

#---------------------------------------------------------------------
# round robin balancing for apiserver
#---------------------------------------------------------------------
backend apiserverbackend
    option httpchk

    http-check connect ssl
    http-check send meth GET uri /healthz
    http-check expect status 200

    mode tcp
    balance     roundrobin

    server control-node ${IP_ADDRESSES[control-node]}:6443 check verify none
    server worker1-node ${IP_ADDRESSES[worker1-node]}:6443 check verify none
    server worker2-node ${IP_ADDRESSES[worker2-node]}:6443 check verify none
EOF

# Notify the user
echo "haproxy.cfg has been saved to $HAPROXY_CFG with the latest IP addresses:"
echo "  control-node: ${IP_ADDRESSES[control-node]}"
echo "  worker1-node: ${IP_ADDRESSES[worker1-node]}"
echo "  worker2-node: ${IP_ADDRESSES[worker2-node]}"

#!/bin/bash
set -eu

Hosts=$*
Hosts=$(echo -e "${Hosts// /\\n}" | sort -u | paste -s -d ' ')

echo "hosts: $Hosts"

for host in $Hosts; do
    ssh-keygen -f "/root/.ssh/known_hosts" -R $host || true
    echo "copy to: $host"
    host="root@$host"
    ssh-copy-id $host
    ssh $host 'apt update && apt install -y docker-compose'
    scp /etc/docker/daemon.json $host:/etc/docker/daemon.json
    ssh $host 'systemctl restart docker'
    docker-compose -H "ssh://$host" -f docker/hwmon.yaml up -d
done

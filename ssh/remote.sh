#!/bin/bash
set -eu

NAME="CI/CD server"
HOST=$1
if [ -z "$HOST" ]; then
    echo "$NAME not specified"
    exit 1
fi
echo "$NAME: $HOST"
ssh "root@$HOST" 'bash -s' < init.sh

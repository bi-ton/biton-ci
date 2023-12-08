#!/bin/bash
set -eu

Red='\e[1;31m'
Green='\e[1;32m'
Yellow='\e[1;33m'
Blue='\e[1;34m'
Purple='\e[1;35m'
Cyan='\e[1;36m'
NC='\e[0m'

ssh-keygen -q -t rsa -b 4096 -N '' -f ~/.ssh/id_rsa
echo -e "${Red}"
cat ~/.ssh/id_rsa.pub
echo -e "${NC}"
echo -e "add public key to ${Purple}Biton${NC} github account: https://github.com/settings/ssh/new"

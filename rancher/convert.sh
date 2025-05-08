#!/bin/bash

# Usage: IP=192.168.0.10 ./convert.sh orig.yaml > k3s.yaml

if [[ -z "$IP" || -z "$1" ]]; then
  echo "Usage: IP=your.ip.addr $0 input.yaml" >&2
  exit 1
fi

INPUT="$1"

sed \
  -e "s|127.0.0.1|$IP|g" \
  -e "s| default| k3s|g" \
  -e "s|name: default|name: k3s|g" \
  -e "s|cluster: default|cluster: k3s|g" \
  -e "s|user: default|user: k3s|g" \
  "$INPUT"

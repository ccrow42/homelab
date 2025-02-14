#!/usr/bin/env bash



SERVERS=("rke2-01" "rke2-02" "rke2-03" "rke2-04")
AGENTINSTALL=" curl --insecure -fL https://rancher.ccrow.org/system-agent-install.sh | sudo sh -s - --server https://rancher.ccrow.org --label 'cattle.io/os=linux' --token mxtn5q7hkkvqlm9lqcxrv4fmbqrq5zl92pcfttlvsdt7xpvj5rl4zt --ca-checksum 2593818837e1ea6937beb9fd791330935b113bd15862f4363166b2a140d0f3d2"

set -x

for server in "${SERVERS[@]}"; do
    kubectl delete -f ${server}.yaml
    sleep 5
    kubectl delete pvc ${server}-boot
done

ssh ubuntu@10.0.1.1 "sudo sed -i '/##-##-##01/Q' /etc/hosts"

kubectl delete -f pvc.yaml
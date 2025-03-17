#!/usr/bin/env bash



SERVERS=("util1" "rke2-01" "rke2-02" "rke2-03" "rke2-04" "rke2-05" "rke2-11" "rke2-12" "rke2-13" "rke2-14")
AGENTINSTALL=" curl --insecure -fL https://rancher.ccrow.org/system-agent-install.sh | sudo sh -s - --server https://rancher.ccrow.org --label 'cattle.io/os=linux' --token mxtn5q7hkkvqlm9lqcxrv4fmbqrq5zl92pcfttlvsdt7xpvj5rl4zt --ca-checksum 2593818837e1ea6937beb9fd791330935b113bd15862f4363166b2a140d0f3d2"

set -x

for server in "${SERVERS[@]}"; do
    MAC=$(kubectl get vmi $server -o yaml | yq .spec.domain.devices.interfaces[1].macAddress)
    IP=$(ssh ubuntu@10.0.1.1 "cat /opt/dnsmasq/dnsmasq.leases | grep $MAC" | awk '{print $3}')
    ssh-keygen -f '/home/ccrow/.ssh/known_hosts' -R \'${IP}\'
    kubectl delete -f ${server}.yaml
    sleep 1
    kubectl delete pvc ${server}-boot
done

#ssh ubuntu@10.0.1.1 "sudo sed -i '/##-##-##01/Q' /etc/hosts"
ssh ubuntu@10.0.1.1 "sudo systemctl restart dnsmasq"

kubectl delete -f pvc.yaml
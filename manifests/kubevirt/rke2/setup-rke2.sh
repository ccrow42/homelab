#!/usr/bin/env bash

kubectl port-forward -n cdi svc/cdi-uploadproxy 8080:443 &
PID=$!

#SERVERS=("util1" "rke2-01" "rke2-02" "rke2-03" "rke2-04")
#SERVERS=("rke2-11" "rke2-12" "rke2-13" "rke2-14")
SERVERS=("rke2-14")
AGENTINSTALL="curl --insecure -fL https://rancher.ccrow.org/system-agent-install.sh | sudo sh -s - --server https://rancher.ccrow.org --label 'cattle.io/os=linux' --token sqv6j4cvrblf6n5gbnc6l4wsqd9vcmcdmrmxjnsp4lsbzc8lr57f8f --ca-checksum b217853ea8af1e8dc2b70423db4d7bff65a2ebd15505905783e57fa1945af685"

set -x

kubectl apply -f pvc.yaml
ssh ubuntu@10.0.1.1 "echo \"##-##-##01\" | sudo tee -a /etc/hosts"
for server in "${SERVERS[@]}"; do
    virtctl image-upload pvc ${server}-boot --size 30G --insecure --image-path=/home/ccrow/Downloads/noble-server-cloudimg-amd64.img --uploadproxy-url=https://localhost:8080
    sleep 5
    kubectl apply -f ${server}.yaml
    sleep 5
    virtctl start ${server}
    sleep 60

    MAC=$(kubectl get vmi $server -o yaml | yq .spec.domain.devices.interfaces[1].macAddress)
    IP=$(ssh ubuntu@10.0.1.1 "cat /opt/dnsmasq/dnsmasq.leases | grep $MAC" | awk '{print $3}')
    ssh ubuntu@10.0.1.1 "echo \"${IP} $server\" | sudo tee -a /etc/hosts"
#    ssh -o StrictHostKeyChecking=accept-new ubuntu@${RKE2_IP} "sudo resolvectl dns enp1s0 10.0.5.1"
    sleep 10
    if [[ $server == "rke2-01" ]]; then
        #ssh -o StrictHostKeyChecking=accept-new ubuntu@${RKE2_IP} "${AGENTINSTALL} --etcd --controlplane"
        echo ""
    elif [[ $server == "util1" ]]; then
        echo ""
    else
        echo ""
        #ssh -o StrictHostKeyChecking=accept-new ubuntu@${RKE2_IP} "${AGENTINSTALL} --worker"
    fi
    
#   
done

ssh ubuntu@10.0.1.1 "sudo systemctl restart dnsmasq"

kill $PID
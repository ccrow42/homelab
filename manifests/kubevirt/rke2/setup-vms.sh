#!/usr/bin/env bash

kubectl port-forward -n cdi svc/cdi-uploadproxy 8080:443 &
PID=$!

#SERVERS=("rke2-01" "rke2-02" "rke2-03" "rke2-04" "rke2-11" "rke2-12" "rke2-13" "rke2-14")
#SERVERS=("rke2-11" "rke2-12" "rke2-13" "rke2-14")
SERVERS=("rke2-05")
#SERVERS=("util1")
AGENTINSTALL="curl --insecure -fL https://rancher.ccrow.org/system-agent-install.sh | sudo sh -s - --server https://rancher.ccrow.org --label 'cattle.io/os=linux' --token sqv6j4cvrblf6n5gbnc6l4wsqd9vcmcdmrmxjnsp4lsbzc8lr57f8f --ca-checksum b217853ea8af1e8dc2b70423db4d7bff65a2ebd15505905783e57fa1945af685"

set -x

kubectl apply -f pvc.yaml
ssh ubuntu@10.0.1.1 "echo \"##-##-##01\" | sudo tee -a /etc/hosts"
for server in "${SERVERS[@]}"; do
    virtctl image-upload pvc ${server}-boot --size 40G --insecure --image-path=/home/ccrow/Downloads/noble-server-cloudimg-amd64.img --uploadproxy-url=https://localhost:8080
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
        # ssh -o StrictHostKeyChecking=accept-new ubuntu@${IP} "curl -sfL https://get.k3s.io | sh -"
        # ssh -o StrictHostKeyChecking=accept-new ubuntu@${IP} "curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash"
        # ssh -o StrictHostKeyChecking=accept-new ubuntu@${IP} "helm repo add rancher-prime https://charts.rancher.com/server-charts/prime"
        # ssh -o StrictHostKeyChecking=accept-new ubuntu@${IP} "helm repo update"
        # scp ../../rancher_prime/labrancher-values.yaml ubuntu@${IP}:/tmp/
        # ssh ubuntu@${IP} "sudo chmod 644 /etc/rancher/k3s/k3s.yaml"
        # ssh ubuntu@${IP} "kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml create ns cattle-system"
        # ssh ubuntu@${IP} "kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.17.0/cert-manager.yaml"
        # ssh ubuntu@${IP} "helm --kubeconfig /etc/rancher/k3s/k3s.yaml install rancher rancher-prime/rancher --namespace cattle-system --values /tmp/labrancher-values.yaml"
        # sleep 100
        # RANCHER_POD=$(ssh ubuntu@${IP} "kubectl get pods -l app=rancher -n cattle-system -o jsonpath='{.items[0].metadata.name}'")
        # ssh ubuntu@${IP} "kubectl exec $RANCHER_POD -n cattle-system -- reset-password"
        echo ""
    else
        echo ""
        #ssh -o StrictHostKeyChecking=accept-new ubuntu@${RKE2_IP} "${AGENTINSTALL} --worker"
    fi
    
#   
done

ssh ubuntu@10.0.1.1 "sudo systemctl restart dnsmasq"

kill $PID
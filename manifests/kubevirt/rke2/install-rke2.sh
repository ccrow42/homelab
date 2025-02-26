#!/usr/bin/env bash

kubectl port-forward -n cdi svc/cdi-uploadproxy 8080:443 &
PID=$!

SERVERS=("rke2-01" "rke2-02" "rke2-03" "rke2-04" "rke2-11" "rke2-12" "rke2-13" "rke2-14")
#SERVERS=("rke2-11" "rke2-12" "rke2-13" "rke2-14")
#SERVERS=("rke2-11" "rke2-12" "rke2-13" "rke2-14")
#SERVERS=("util1")
PROD_AGENTINSTALL="curl --insecure -fL https://10.0.5.119:8443/system-agent-install.sh | sudo  sh -s - --server https://10.0.5.119:8443 --label 'cattle.io/os=linux' --token dk2xskmjw8qgxzb2jffv94wnt44bsx67tc2v8xf6qddvczwzb7fpql --ca-checksum 47599c2366aa4ca8657e2ef8ec528cfdb327939d0f738af7c1826517198c818a"
DR_AGENTINSTALL="curl --insecure -fL https://10.0.5.119:8443/system-agent-install.sh | sudo  sh -s - --server https://10.0.5.119:8443 --label 'cattle.io/os=linux' --token dk2xskmjw8qgxzb2jffv94wnt44bsx67tc2v8xf6qddvczwzb7fpql --ca-checksum 47599c2366aa4ca8657e2ef8ec528cfdb327939d0f738af7c1826517198c818a"


set -x


for server in "${SERVERS[@]}"; do

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
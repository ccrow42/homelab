#!/usr/bin/env bash
. demo-magic.sh

TYPE_SPEED=20
# see http://www.tldp.org/HOWTO/Bash-Prompt-HOWTO/bash-prompt-escape-sequences.html for escape sequences
#
DEMO_PROMPT="${GREEN}➜ ${CYAN}Rancher IO Control Demo> ${COLOR_RESET}"

### Environment Requirements:
# We need to run the following:
# ra install_demo
# ra install_grafana
# ra reboot_cluster # this will set the cgroup to v1
# Have grafana up

PROMPT_TIMEOUT=0

source ~/.bashrc

pxctl () {
    kubectl exec $(kubectl get pods -l name=portworx -n portworx -o jsonpath='{.items[0].metadata.name}') -n portworx -- /opt/pwx/bin/pxctl $@
}

clear

wait

pei "# I have a Rancher RKE2 cluster ready to go #"
pe "kubectl get nodes"


pei "### We will start by generating some I/O using kubestr"

pe "kubestr fio -z 30G -s px-csi-db -f rand-write.fio -o json -e rand-RW-WL.json >& /dev/null &"

pe "kubectl get pvc"

pei "export VolName=\$(pxctl volume list | grep \"28 GiB\" | awk '{ print \$2}' )"

pei "pxctl volume inspect \$VolName"

pei "### Lets check on the amount of I/O being generated in Grafana"

#pei "$ENDPOINT=http://\$(kubectl -n portworx get svc grafana-svc -o jsonpath='{.status.loadBalancer.ingress[0].ip}'):3000"
#pei "echo $ENDPOINT"

wait


pei "#We will now set a max IO limit on the volume"

pei "pxctl volume update --max_iops 750\,750 \$VolName"

pei "pxctl volume inspect \$VolName"

pei "# Lets check the I/O in Grafana again"

wait

pe "kubectl delete pods --all&"

pe "kubectl delete pvc --all&"


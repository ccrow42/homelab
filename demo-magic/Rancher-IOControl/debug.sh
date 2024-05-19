#!/usr/bin/env bash
. demo-magic.sh

 TYPE_SPEED=20
 see http://www.tldp.org/HOWTO/Bash-Prompt-HOWTO/bash-prompt-escape-sequences.html for escape sequences
#
DEMO_PROMPT="${GREEN}➜ ${CYAN}\W ${COLOR_RESET}"

### Environment Requirements:
# We need to run the following:
# ra install_demo
# ra install_grafana

PROMPT_TIMEOUT=0

pxctl () {
    kubectl exec $(kubectl get pods -l name=portworx -n portworx -o jsonpath='{.items[0].metadata.name}') -n portworx -- /opt/pwx/bin/pxctl $@
}



clear

pei "export VolName=\$(pxctl volume list | grep \"28 GiB\" | awk '{ print \$2}' )"

pei "pxctl volume inspect \$VolName"

wait

pei "### We will start by generating some I/O using kubestr"

pe "kubestr fio -z 30G -s px-csi-db -f rand-write.fio -o json -e rand-RW-WL.json >& /dev/null &"

pe "kubectl get pvc"

pei "### Lets check on the amount of I/O being generated"

wait

pei "export VolName=\$(pxctl volume list | grep \"28 GiB\" | awk '{print \$2}' )"

pei "pxctl volume inspect \$VolName"
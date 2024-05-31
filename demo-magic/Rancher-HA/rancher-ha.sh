#!/usr/bin/env bash
. demo-magic.sh

TYPE_SPEED=20
# see http://www.tldp.org/HOWTO/Bash-Prompt-HOWTO/bash-prompt-escape-sequences.html for escape sequences
#
DEMO_PROMPT="${GREEN}➜ ${CYAN}Rancher HA Demo> ${COLOR_RESET}"

### Environment Requirements:
# We need to run the following:
# ra install_demo
# Have the connection to pxbbq up

PROMPT_TIMEOUT=0

source ~/.bashrc

ccat() { pygmentize -g $1 | perl -e 'print ++$i. " $_" for <>'; }

pxctl () {
    kubectl exec $(kubectl get pods -l name=portworx -n portworx -o jsonpath='{.items[0].metadata.name}') -n portworx -- /opt/pwx/bin/pxctl $@
}

clear

wait


pei "# We have a demo application running in our cluster #"

pei "# This application has a MongoDB back end that is using Portworx to provide its Persistent Volume"
pei "kubectl -n pxbbq get pvc"
pei "# Let's look at the storage class that we are using"
pei "kubectl get sc px-csi-db -o yaml | kubectl neat"

wait

pei "# Let's order some BBQ!"
pei "# Let's connect to the destination IP address: #"
pei "IP=http://\$(kubectl -n pxbbq get svc pxbbq-svc -o jsonpath='{.status.loadBalancer.ingress[0].ip}')"
pei "echo \$IP"

wait

pe "kubectl -n pxbbq get pods,pvc -o wide"

pe "# Notice the node that mongo-0 is running on"

pe "# We will now halt it #"
#pei "node=\$(kubectl -n pxbbq get pods mongo-0 -o wide --no-headers | awk '{print \$7}')"
#pei "ssh -o StrictHostKeyChecking=no ubuntu@\$node sudo halt"

pe "# It may take some time for the cluster to notice the node is down"
pei "watch kubectl -n pxbbq get pods,pvc -o wide"

#kubectl -n pxbbq scale deployments --all --replicas=0 2>&1 /dev/null
#kubectl -n pxbbq scale deployments --all --replicas=1 2>&1 /dev/null
#sleep 3
pei "# Now that our mongo db instance has restarted, let's check on our order"
wait
wait

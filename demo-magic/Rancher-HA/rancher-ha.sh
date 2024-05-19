#!/usr/bin/env bash
. demo-magic.sh

TYPE_SPEED=20
# see http://www.tldp.org/HOWTO/Bash-Prompt-HOWTO/bash-prompt-escape-sequences.html for escape sequences
#
DEMO_PROMPT="${GREEN}➜ ${CYAN}Rancher Autopilot Demo ${COLOR_RESET}"

### Environment Requirements:
# We need to run the following:
# ra install_demo
# Have the connection to pxbbq up

PROMPT_TIMEOUT=3

source ~/.bashrc

ccat() { pygmentize -g $1 | perl -e 'print ++$i. " $_" for <>'; }

pxctl () {
    kubectl exec $(kubectl get pods -l name=portworx -n portworx -o jsonpath='{.items[0].metadata.name}') -n portworx -- /opt/pwx/bin/pxctl $@
}

clear

wait

pei "# We have a demo application running in our cluster #"
pe "# Let's order some BBQ!"

pe "kubectl -n pxbbq get pods,pvc -o wide"

pe "# Notice the node that mongo-0 is running on"

pe "# We will now halt it #"
pei "node=\$(kubectl -n pxbbq get pods mongo-0 -o wide --no-headers | awk '{print \$7}')"
pei "ssh ubuntu@\$node sudo halt"

pe "# It may take some time for the cluster to notice the node is down"
pei "watch kubectl -n pxbbq get pods,pvc -o wide"

kubectl -n pxbbq scale deployments --all --replicas=0
kubectl -n pxbbq scale deployments --all --replicas=1

pe "# Now that our mongo db instance has restarted, let's check on our order"

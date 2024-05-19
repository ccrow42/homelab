#!/usr/bin/env bash
. demo-magic.sh

TYPE_SPEED=20
# see http://www.tldp.org/HOWTO/Bash-Prompt-HOWTO/bash-prompt-escape-sequences.html for escape sequences
#
DEMO_PROMPT="${WHITE}➜ ${GREEN}Source Cluster> ${COLOR_RESET}"

### Environment Requirements:
# We need to run the following:
# ra install_demo_async
# Have the connection to pxbbq up
SRCPOOL="demo3"
DSTPOOL="demo4"

PROMPT_TIMEOUT=0

source ~/.bashrc

ccat() { pygmentize -g $1 | perl -e 'print ++$i. " $_" for <>'; }

pxctl () {
    kubectl exec $(kubectl get pods -l name=portworx -n portworx -o jsonpath='{.items[0].metadata.name}') -n portworx -- /opt/pwx/bin/pxctl $@
}

kubectl config use-context ${SRCPOOL}
kubectl apply -f pxbbq-schedule.yaml

clear

wait

pei "# In this demo, we will be showing a DR failover of our PXBBQ application #"

pei "# Let's order some BBQ!"
pei "# Let's connect to the IP address of our webapp: #"
pei "IP=http://\$(kubectl -n pxbbq get svc pxbbq-svc -o jsonpath='{.status.loadBalancer.ingress[0].ip}')"
pei "echo \$IP"

wait

pei "# Let's look at the cluster pair that was set up before this demo #"

pei "kubectl describe clusterpair demo -n portworx"

pei "# The cluster pair object also supports rancher project mapping #"

wait

clear

pei "# We also have a schedule that will trigger a sync of our application #"

pe "ccat pxbbq-schedule.yaml"

pe "watch storkctl get migrations -n portworx"

wait
clear

pei "# Let's simulate a DR event #"

pei "nodes=\$(kubectl get nodes -o jsonpath='{.items[*].metadata.name}')"
pei "for node in \${nodes[@]}; do"
pei "ssh -o StrictHostKeyChecking=no  ubuntu@\$node \"sudo halt\""
pei "done"


pei "# Let's change contexts to our destination cluster #"
kubectl config use-context ${DSTPOOL}
DEMO_PROMPT="${WHITE}➜ ${RED}Destination Cluster> ${COLOR_RESET}"

pei "We will now activate the DR namespace"
pe "storkctl activate migration -n pxbbq"

pe "watch kubectl -n pxbbq get pods,pvc,svc"

pei "# Let's connect to the destination IP address: #"
pei "DSTIP=http://\$(kubectl -n pxbbq get svc pxbbq-svc -o jsonpath='{.status.loadBalancer.ingress[0].ip}')"
pei "echo \$DSTIP"

wait

pe "# We can see that our order is still there! #"

# Reset the environment:

pei ""

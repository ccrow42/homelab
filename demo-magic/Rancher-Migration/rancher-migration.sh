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

clear

wait

pei "# In this demo, we will be migrating a namespace from a source cluster to a destination cluster #"

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

pei "# We will now migrate the pxbbq application #"
pei "ccat migrate.yaml"

pei "# Migration objects support transforms and label selectors. This one is simple. #" 

pe "kubectl apply -f migrate.yaml"

pe "watch storkctl get migrations -n portworx"

pei "# Let's change contexts to our destination cluster #"
kubectl config use-context ${DSTPOOL}
DEMO_PROMPT="${WHITE}➜ ${RED}Destination Cluster> ${COLOR_RESET}"

pe "watch kubectl -n pxbbq get pods,pvc,svc"

pei "# Let's connect to the destination IP address: #"
pei "DSTIP=http://\$(kubectl -n pxbbq get svc pxbbq-svc -o jsonpath='{.status.loadBalancer.ingress[0].ip}')"
pei "echo \$DSTIP"

wait

pe "# We can see that our order is still there! #"

# Reset the environment:
kubectl delete ns pxbbq &
kubectl --context ${SRCPOOL} -n portworx delete migration migrate01 &

pei ""

#!/usr/bin/env bash
. demo-magic.sh

TYPE_SPEED=20
# see http://www.tldp.org/HOWTO/Bash-Prompt-HOWTO/bash-prompt-escape-sequences.html for escape sequences
#
DEMO_PROMPT="${WHITE}➜ ${GREEN}Source Cluster ${COLOR_RESET}"

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

pe "# Let's order some BBQ!"

wait

pei "# Let's look at the cluster pair that was set up before this demo #"

pe "kubectl describe clusterpair demo -n portworx"

pe "# The cluster pair object also supports rancher project mapping #"

wait

clear

pe "# We will now migrate the pxbbq application #"
pe "ccat migrate.yaml"

pei "# Migration objects support transforms and label selectors. This one is simple. #" 

pe "kubectl apply -f migrate.yaml"

pe "watch storkctl get migrations -n portworx"

pe "# Let's change contexts to our destination cluster #"
kubectl config use-context ${DSTPOOL}
DEMO_PROMPT="${WHITE}➜ ${RED}Destination Cluster ${COLOR_RESET}"

pe "kubectl -n pxbbq get pods,pvc"
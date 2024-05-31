#!/usr/bin/env bash
. demo-magic.sh

TYPE_SPEED=20
# see http://www.tldp.org/HOWTO/Bash-Prompt-HOWTO/bash-prompt-escape-sequences.html for escape sequences
#
DEMO_PROMPT="${WHITE}➜ ${GREEN}Source Cluster> "
# removed ${COLOR_RESET}

#DEMO_PROMPT="Source Cluster> "
### Environment Requirements:
# We need to run the following:
# ra install_demo_async
# license dr
# Have the connection to pxbbq up
SRCPOOL="demo3"
DSTPOOL="demo4"

PROMPT_TIMEOUT=0

source ~/.bashrc

ccat() { pygmentize -g $1 | perl -e 'print ++$i. " $_" for <>'; }

pxctl () {
    kubectl exec $(kubectl get pods -l name=portworx -n portworx -o jsonpath='{.items[0].metadata.name}') -n portworx -- /opt/pwx/bin/pxctl $@
}

# kubectl config use-context ${SRCPOOL}
# kubectl apply -f pxbbq-schedule.yaml

# clear

# wait

# pei "# In this demo, we will be showing a DR failover of our PXBBQ application"

# pei "# I have two rancher clusters ready to go!"

# pei ""

# pei "# Source Cluster"

# pei "kubectl get nodes"

# pei ""

# pei "# Destination Cluster"

# pei "kubectl get nodes --context demo4"

# pei ""


# wait

# pei "# Let's look at the cluster pair that was set up before this demo"

# pe "kubectl describe clusterpair demo -n portworx"

# pei "# The clusterpair object describes how we communicate with the DR cluster"

# pei "# Clusterpairs also support Rancher project mapping"


# wait
# clear

# pei "# Replication is controlled by a Migrationschedule manifest"

# pei "kubectl -n portworx get migrationschedules -o yaml | kubectl neat"

# pei "# This manifest controls what namespaces and resources we will be protecting"

# wait

# clear

# pei "# Let's order some BBQ!"

# wait 
# clear

# pei "# We will watch for the next migration to trigger"

# pe "watch storkctl get migrations -n portworx"

# wait
# clear

# pei "# Let's simulate a DR event #"

# pei "./halt_nodes.sh"

# wait
# pei "OPERATOR NOTE: PREP DESTINATION PXBBQ WINDOW AND CHANGE TERMINAL PROFILES"
clear
wait
clear

pei "# Let's change contexts to our destination cluster #"
kubectl config use-context ${DSTPOOL}
DEMO_PROMPT="${WHITE}➜ ${RED}Destination Cluster> "
wait
pei "# We will now activate the DR namespace"
pei "storkctl activate migration -n pxbbq"

pe "watch kubectl -n pxbbq get pods,pvc,svc"

pei "# Let's connect to the destination instance of Portworx BBQ"

wait

pe "# We can see that our order is still there! #"

pei ""

wait

wait

storkctl deactivate migration -n pxbbq

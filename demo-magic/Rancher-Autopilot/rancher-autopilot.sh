#!/usr/bin/env bash
. demo-magic.sh

TYPE_SPEED=20
# see http://www.tldp.org/HOWTO/Bash-Prompt-HOWTO/bash-prompt-escape-sequences.html for escape sequences
#
DEMO_PROMPT="${GREEN}➜ ${CYAN}Rancher Autopilot Demo ${COLOR_RESET}"

### Environment Requirements:
# We need to run the following:
# ra install_demo


PROMPT_TIMEOUT=3

source ~/.bashrc

ccat() { pygmentize -g $1 | perl -e 'print ++$i. " $_" for <>'; }

pxctl () {
    kubectl exec $(kubectl get pods -l name=portworx -n portworx -o jsonpath='{.items[0].metadata.name}') -n portworx -- /opt/pwx/bin/pxctl $@
}

clear

wait

pei "# First, let's create a namespace for our demo #"

pe "kubectl apply -f namespaces.yaml"

pe "# Lets look at our autopilot rule #"

pei "ccat autopilotrule.yaml"

pei "# Autopilot rules have a number of configuration options"
pei "# Line 9: Target PVCs with the Kubernetes label app: disk-filler"
pei "# Line 13: Target PVCs in namespaces with the label type: db"
pei "# Lines 18-21: Monitor if capacity usage grows to or above 30%"
pei "# Line 28: Automatically grow the volume and underlying filesystem by 100% of the current volume size if usage above 30% is detected"
pei "# Line 30: Now grow the volume by 100%"

wait
clear

pei "# We will now apply the autopilot rule #"
pe "kubectl create -f autopilotrule.yaml"

pei "# Now let's make sure that our namespace label is applied #"
pe "kubectl get ns -l type=db"

pei "# Now we will deploy a disk-filler pvc #"
pe "kubectl create -f disk-filler-pvc.yaml -n autopilot"

pei "# Now let's check the size of our pvc #"
pe "kubectl get pvc -n autopilot"

pei "# Now let's start filling the disk #"
pe "kubectl create -f disk-filler.yaml -n autopilot"

pei "# We will now monitor for autopilot events #"
pe "watch 'kubectl get events --field-selector involvedObject.kind=AutopilotRule,involvedObject.name=volume-resize  --all-namespaces --sort-by .lastTimestamp; cat autopilotevents.txt'"

pei "# Let's look at the size of our pvc #"
pe "kubectl get pvc -n autopilot"

wait

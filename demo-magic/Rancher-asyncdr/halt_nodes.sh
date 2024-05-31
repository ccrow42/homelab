#!/usr/bin/env bash

set -x

govc vm.power -off -force demo3*

#nodes=$(kubectl get nodes -o jsonpath='{.items[*].metadata.name}')
#for node in ${nodes[@]}; do
#	ssh -o StrictHostKeyChecking=no  ubuntu@$node "sudo halt"
#done


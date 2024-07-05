govc import.ova -options=./k3s-vm6.json ~/Downloads/jammy-server-cloudimg-amd64.ova
govc vm.change -vm k8s-1 -m 16384 -c 8

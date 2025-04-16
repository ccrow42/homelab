#!/usr/bin/env bash


### Global Config
BASE_DIR=/home/ccrow/personal/homelab/rancher
KUBEVIRT_VM_TEMPLATE="${BASE_DIR}/TEMPLATE-kubevirtvm.yaml"
PX_PVC_TEMPLATE="${BASE_DIR}/TEMPLATE-pxpvc.yaml"
IMAGE_PATH="/home/ccrow/Downloads/noble-server-cloudimg-amd64.img"

### Standard Functions

log () {
    if [[ ${DISABLE_LOGS} == 1 ]]; then
        echo "logs disabled"
        return
    fi
    echo $(date -u +"%Y-%m-%dT%H:%M:%SZ") "${@}"
}

debug () {
  if [[ ${DEBUG} == 1 ]]; then
    echo $(date -u +"%Y-%m-%dT%H:%M:%SZ") "${@}"
  fi
}

terminate () {
  local msg="${1}"
  local code="${2:-1}"
  echo "Error: ${msg}" >&2
  exit "${code}"
}



create_bootdisk () {
    kubectl port-forward -n cdi svc/cdi-uploadproxy 8080:443 &
    PID=$!
    sleep 5
    virtctl image-upload pvc ${VMNAME}-boot --size 50G --insecure --image-path=${IMAGE_PATH} --uploadproxy-url=https://localhost:8080
    sleep 5
    kill $PID

}

update_dns () {
    ssh ubuntu@10.0.1.1 "echo \"${IP} $VMNAME\" | sudo tee -a /etc/hosts"
    echo "${IP} $VMNAME" | sudo tee -a /etc/hosts

    ssh ubuntu@10.0.1.1 "sudo systemctl restart dnsmasq"
}

create_pxdisk () {
   PXPVC="$(< ${PX_PVC_TEMPLATE})"
   PXPVC="${PXPVC//_HOSTNAME_/${VMNAME}}"

   kubectl apply -f <(echo "${PXPVC}")

}

create_kubevirtvm () {
    KUBEVIRTVM="$(cat "${KUBEVIRT_VM_TEMPLATE}")"

    KUBEVIRTVM="${KUBEVIRTVM//_IP_ADDRESS_/${IP}}"
    KUBEVIRTVM="${KUBEVIRTVM//_HOSTNAME_/${VMNAME}}"

    if [[ $PXDISK == "true" ]]; then
        PVC_CLAIM="${VMNAME}-px"
        KUBEVIRTVM=$(echo "$KUBEVIRTVM" | yq '
  .spec.template.spec.domain.devices.disks += [{"name": "px", "disk": {"bus": "virtio"}}] |
  .spec.template.spec.volumes += [{"name": "px", "persistentVolumeClaim": {"claimName": "'"$PVC_CLAIM"'"}}]
')
    fi


    kubectl apply -f <(echo "${KUBEVIRTVM}")
    sleep 5
    virtctl start $VMNAME

}


### Parse the CLI arguments
while [[ ${1} != "" ]]; do
    case $1 in
        create)
            COMMAND="create_vm"
        ;;
        delete)
            COMMAND="delete_vm"
        ;;
        --vmname)
            shift
            VMNAME=$1
            log "VMNAME = $VMNAME"
        ;;
        --ip)
            shift
            IP=$1
            log "IP = $IP"
        ;;
        --pxdisk)
            shift
            PXDISK=$1
            log "PXDISK = $PXDISK"
        ;;
        --image)
            shift
            IMAGE_PATH=$1
            log "overwriting image path with ${IMAGE_PATH}"
        ;;
        *)
            terminate "Unknown Arg: $1" 160
        ;;
    esac
    shift
done


### META

create_vm () {

    if [[ $PXDISK == "true" ]]; then
        create_pxdisk
    fi

    create_bootdisk
    create_kubevirtvm


    update_dns

}

delete_vm () {
    kubectl delete vm $VMNAME
    kubectl delete pvc ${VMNAME}-boot
    kubectl delete pvc ${VMNAME}-px
    ssh-keygen -f '/home/ccrow/.ssh/known_hosts' -R \'${IP}\'
    ssh ubuntu@10.0.1.1 "sudo sed -i \"/^${IP//./\\.}/d\" /etc/hosts"
    sudo sed -i "/^${IP//./\\.}/d" /etc/hosts
    ssh-keygen -f '/home/ccrow/.ssh/known_hosts' -R $VMNAME
}

### Begin code block

kubectl config use-context gentoo

$COMMAND


exit 0
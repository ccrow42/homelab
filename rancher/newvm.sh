#!/usr/bin/env bash


# Import rancher config:
SCRIPT_NAME=$(basename $0)
BASE_DIR=~/personal/homelab/rancher
CONFIG_FILE="${BASE_DIR}/rancher_conf.sh"
NAMESPACE=vmlab

### Global Config



### Defaults
CPU="4"
MEMORY="16G"

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

### Import config
log "Starting ${SCRIPT_NAME}"

# Import the config file
readonly ERR_CONF_FILE_NOT_FOUND=160
source $CONFIG_FILE || terminate "Could not source ${CONFIG_FILE}" ${ERR_CONF_FILE_NOT_FOUND}
#Secrets should be exported by the profile so I think we are fine
#source ~/.bashrc || terminate "Could not source .bashrc which contains secrets" ${ERR_CONF_FILE_NOT_FOUND}
log "Configuration files imported"


create_bootdisk () {
    kubectl port-forward -n cdi svc/cdi-uploadproxy 8080:443 &
    PID=$!
    sleep 5
    virtctl -n $NAMESPACE image-upload pvc ${VMNAME}-boot --size 80G --insecure --image-path=${IMAGE_PATH} --uploadproxy-url=https://localhost:8080
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
    KUBEVIRTVM="${KUBEVIRTVM//_CPU_CORES_/${CPU}}"
    KUBEVIRTVM="${KUBEVIRTVM//_MEMORY_/${MEMORY}}"

    if [[ $PXDISK == "true" ]]; then
        PVC_CLAIM="${VMNAME}-px"
        KUBEVIRTVM=$(echo "$KUBEVIRTVM" | yq '
  .spec.template.spec.domain.devices.disks += [{"name": "px", "disk": {"bus": "virtio"}}] |
  .spec.template.spec.volumes += [{"name": "px", "persistentVolumeClaim": {"claimName": "'"$PVC_CLAIM"'"}}]
')
    fi


    kubectl apply -f <(echo "${KUBEVIRTVM}")
    sleep 5
    virtctl -n $NAMESPACE start $VMNAME

    sleep 30
    
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
        --cpu)
            shift
            CPU=$1
            log "overwriting default core count to ${CPU}"
        ;;
        --mem)
            shift
            MEMORY=$1
            log "overwriting default memory value to ${MEMORY}"
        ;;
        --namespace)
            shift
            NAMESPACE=$1
            log "overwriting namespace value to ${NAMESPACE}"
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


    #update_dns

}

delete_vm () {
    if [[ -z ${IP} ]];then
        terminate "IP address MUST be specified"
    fi

    kubectl -n $NAMESPACE delete vm $VMNAME
    kubectl -n $NAMESPACE delete pvc ${VMNAME}-boot
    kubectl -n $NAMESPACE delete pvc ${VMNAME}-px
    ssh-keygen -f '/home/ccrow/.ssh/known_hosts' -R \'${IP}\'
    ssh ubuntu@10.0.1.1 "sudo sed -i \"/^${IP//./\\.}/d\" /etc/hosts"
    sudo sed -i "/^${IP//./\\.}/d" /etc/hosts
    ssh-keygen -f '/home/ccrow/.ssh/known_hosts' -R $VMNAME
}

### Begin code block

kubectl config use-context gentoo

$COMMAND


exit 0
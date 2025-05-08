#!/usr/bin/env bash


### Assumptions
# 1. No secrets will be in this file and must be provided by environment variables
# 2. The rancher server will have SSL configured
# 3. We are going to keep the scope to demo3 and demo4 clusters for now
# 4. Configuration values will be keyed on the pool. For instance, if we set up a new cluster, we will pass a pool name for uniqueness.
#    This means that we will also expect the pool for kustomize overlays (where supported)
# 5. For the adiminstrative connection to the rancher server, $CONTEXT sets the cluster, user and context.

### Requirements
# - helm
# - kubectl
# - yq
# - kustomize

### Roadmap
# - [ ] get the bearer token from the rancher server
# - [ ] options to perform the initial setup of the rancher server
# - [ ] Need to squelch errors in the wait_ready commands
# - [ ] Add automatic dependency resolution
# - [ ] consider moving to --context instead of switching contexts

### Short term fixes
# - [x] fix leading places from cluster UUID in env function
# - [ ] fix DISABLE_SSL logic in configure_pxbackup function. Current logic forces it to be true
# - [x] write wait_ready_minio function
# - [ ] add a sync function for install operations
# - [ ] fix hard coded grafana yaml files

### What I know is missing:
# - TEMPLATE cloneFrom is hardcoded

### Configuration Section
# These vars are not populated by the rancher_conf.sh file
# BEARER_TOKEN is the token that will be used to authenticate to the Rancher API
# SEALED_SECRET_TLS_CERT and SEALED_SECRET_TLS_KEY are used for bitnomi's sealed secrets

SCRIPT_NAME=$(basename $0)
BASE_DIR=~/personal/homelab/rancher
CONFIG_FILE="${BASE_DIR}/rancher_conf.sh"





# Standard Functions

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


log "Starting ${SCRIPT_NAME}"



# Import the config file
readonly ERR_CONF_FILE_NOT_FOUND=160
source $CONFIG_FILE || terminate "Could not source ${CONFIG_FILE}" ${ERR_CONF_FILE_NOT_FOUND}
#Secrets should be exported by the profile so I think we are fine
#source ~/.bashrc || terminate "Could not source .bashrc which contains secrets" ${ERR_CONF_FILE_NOT_FOUND}
log "Configuration files imported"

# Let's set a pxctl alias:
alias pxctl='kubectl exec $(kubectl get pods -l name=portworx -n portworx -o jsonpath='{.items[0].metadata.name}') -n portworx -- /opt/pwx/bin/pxctl'

###### Helper Functions

### Usage Function
usage() {
  cat <<USAGE
Usage: ${SCRIPT_NAME} COMMOND [OPTIONS]

This script is used to build and configure a rancher cluster and server.
This is a work in progress.

Commands:
    create_rancher          Create a new rancher server
    connect                 Connect to the rancher server
    cleanup                 Cleanup the rancher config from kubectl files
    view                    View the current kubectl config
    env                     Output environment variables for the current pool  
    create                  Create a new cluster
    delete                  Delete a cluster
    create_context          Create a context for a cluster. Uses --pool to specify the cluster and --context to specify the context used to pull the server info
    install_sealed_secrets  Install sealed secrets to the cluster
    install_argocd          Install ArgoCD to the cluster
    install_metallb         Install MetalLB to the cluster
    install_portworx        Install Portworx to the cluster
    install_pxbackup        Install PXBackup to the cluster
    install_lpp             Install local path provisioner
    install_etcd            Install etcd to the cluster
    install_pxbbq           Install PXBBQ to the cluster
    install_aidemo          Install the PXBBQ AI DEMO to the cluster
    install_minio           Install Minio to the cluster
    install_grafana         Install Grafana to the cluster
    install_pxbbq_taster    Install PXBBQ taster to the cluster
    configure_minio         Configure Minio with mc
    configure_pxbackup      Configure PXBackup with demo schedules, buckets and clusters
    install_utilities       Install binary utilities to the current host. Requires BINARY_DIR is set
    px_clusterpair          Create a cluster pair between two clusters. Requires --pool and --dr-pool
    install_demo_async      Install two clusters with Portworx, PXBBQ, minio
    install_demo            Install 1 cluster with Portworx, PXBBQ, minio, pxbackup
    install_mvp             Install 1 cluster with Argo, Sealed Secrets, LPP, and portworx
    install_cluster         Build a cluster with ArgoCD, MetalLB, LPP, and sealed secrets
    reboot_cluster          Reboot the cluster. This also updates grub.

Options:
    -h, --help              Display this help message
    -d, --debug             Enable debug output
    -v,                     Print environment variables to the screen (may contain secrets)
    --disable-logs          Disable logging
    --context               The context to use for some kubectl command
    --pool                  specifies the pool name. 
    --dr-pool               specifies a secondary pool for DR workflows

Examples:
    ${SCRIPT_NAME}          connect
    ${SCRIPT_NAME}          cleanup

Helpful notes:
    You can seal an existing secret with: kubeseal --format=yaml < secret.yaml > sealed-secret.yaml
    Do not run more than one "META" task at a time. Meta tasks run more complex workflows such as "install_demo"

USAGE
}


requires_poolname () {
    if [[ -z ${POOL_NAME} ]]; then
        terminate "Pool name is required for this command" ${ERR_NO_ARGS}
    fi
}
requires_drpoolname () {
    if [[ -z ${DR_POOL_NAME} ]]; then
        terminate "DR Pool name is required for this command" ${ERR_NO_ARGS}
    fi
}
requires_argocd () {
    if kubectl get namespace argocd; then
        log "ArgoCD appears to be installed, proceeding"
    else
        terminate "ArgoCD is not installed. Please install ArgoCD first" ${ERR_ARGOCD_NOT_INSTALLED}
    fi
}
requires_portworx () {
    if kubectl get namespace portworx; then
        log "Portworx appears to be installed, proceeding"
    else
        terminate "Portworx is not installed, install Portworx first" ${ERR_PORTWORX_NOT_INSTALLED}
    fi
}
requires_mc () {
    if [[ -z $(which mc) ]]; then
        terminate "mc is not installed. Please install mc first" ${ERR_UTILITY_NOT_INSTALLED}
    fi

}
requires_storkctl () {
    if [[ -z $(which storkctl) ]]; then
        terminate "storkctl is not installed. Please install storkctl first" ${ERR_UTILITY_NOT_INSTALLED}
    fi
}
requires_minio () {
    if kubectl get namespace minio; then
        log "Minio appears to be installed, proceeding"
    else
        terminate "Minio is not installed, install Minio first" ${ERR_MINIO_NOT_INSTALLED}
    fi

}
requires_lpp () {
    if kubectl get namespace local-path-storage; then
        log "Local Path Provisioner appears to be installed, proceeding"
    else
        terminate "Local Path Provisioner is not installed, install Minio first" ${ERR_LPP_NOT_INSTALLED}
    fi

}
requires_pxbackup () {
    if [[ $(kubectl get po --namespace central --no-headers -ljob-name=pxcentral-post-install-hook  -o json | jq -rc '.items[0].status.phase') == "Succeeded" ]]; then
        log "PXBackup appears to be installed, proceeding"
    else
        terminate "PXBackup is not installed, install PXBackup first" ${ERR_PXBACKUP_NOT_INSTALLED}
    fi
}

wait_ready_racher_cluster () {
    kubectl config use-context ${KUBECTL_CONTEXT} || terminate "Could not switch to ${KUBECTL_CONTEXT}" 
    log "Waiting for cluster to be ready, this may take a few minutes."
    until [[ $(kubectl -n fleet-default get clusters ${POOL_NAME} -o jsonpath='{.status.conditions[?(@.type=="ControlPlaneReady")].status}') == "True" ]]; do
        echo -n "."
        sleep 10
    done
}
wait_ready_portworx () {
    kubectl config use-context ${POOL_NAME} || terminate "Could not switch to ${POOL_NAME}" ${ERR_POOL_NOT_FOUND}
    log "Waiting for Portworx to be ready, this may take a few minutes."
    until [[ $(kubectl -n portworx get stc -o jsonpath='{.items[0].status.phase}' 2> /dev/null) == "Running" ]]; do
        echo -n "."
        sleep 10
    done
}

# while ! kubectl get stc -A -n portworx | grep -q 'Running\|Online'; do
#    echo "Waiting for StorageCluster status online"
#    sleep 3
# done
wait_ready_pxbackup () {
    kubectl config use-context ${POOL_NAME} || terminate "Could not switch to ${POOL_NAME}" ${ERR_POOL_NOT_FOUND}
    log "Waiting for PXBackup to be ready, this may take a few minutes."
    until [[ $(kubectl get po --namespace central --no-headers -ljob-name=pxcentral-post-install-hook  -o json | jq -rc '.items[0].status.phase') == "Succeeded" ]]; do
        echo -n "."
        sleep 10
    done
}
wait_ready_minio () {
    kubectl config use-context ${POOL_NAME} || terminate "Could not switch to ${POOL_NAME}" ${ERR_POOL_NOT_FOUND}
    log "Waiting for Minio to be ready, this may take a few minutes."
    until [[ $(kubectl -n minio get deployments.apps minio -o jsonpath={'.status.readyReplicas'}) -ge 1 ]]; do
        echo -n "."
        sleep 10
    done
}
wait_ready_argocd () {
    kubectl config use-context ${POOL_NAME} || terminate "Could not switch to ${POOL_NAME}" ${ERR_POOL_NOT_FOUND}
    log "Waiting for ArgoCD to be ready, this may take a few minutes."
    until [[ $(kubectl -n argocd get deployments.apps argocd-server -o jsonpath={'.status.readyReplicas'}) -ge 1 ]]; do
        echo -n "."
        sleep 10
    done

}
wait_ready_vm () {
    VMNAME=$1
    until ssh -o StrictHostKeyChecking=accept-new ${VM_USER_ACCOUNT}@${VMNAME} date; do
        log "waiting for ${VMNAME} to boot"
        sleep 10
    done

}
wait_ready_rancher () {
    log "Waiting for rancher to be availible"
    until [[ $(curl -k "${RANCHER_SERVER_URL}/ping") == "pong" ]]; do
        echo -n "."
        sleep 15
    done
}
wait_ready_k3s () {
    log "Waiting for k3s service to be availible"
    until [[ $(curl -k "https://${K3S_IP}:6443/ping") == "pong" ]]; do
        echo -n "."
        sleep 15
    done
}




###### Main Functions

### This function will set up the rancher server context if it doesn't exist and switch to it. It should ALWAYS exist.
kubectl_rancher_server () {

    if kubectl config use-context ${KUBECTL_CONTEXT}; then
        log "${KUBECTL_CONTEXT} context already exists. Switching to it."
    else
        log "Creating ${KUBECTL_CONTEXT} context"
        kubectl config set-cluster ${KUBECTL_CONTEXT} --server=${RANCHER_SERVER_URL}
        kubectl config set-credentials ${KUBECTL_CONTEXT} --token=${BEARER_TOKEN}
        kubectl config set-context ${KUBECTL_CONTEXT} --cluster=rancher --user=rancher --insecure-skip-tls-verify
        kubectl config use-context ${KUBECTL_CONTEXT}
    fi

}

kubectl_k3s_server () {

    if kubectl config use-context ${K3S_CONTEXT}; then
        log "${K3S_CONTEXT} context already exists. Switching to it."
    else
        log "Creating ${K3S_CONTEXT} context"
        kubectl config set-cluster ${k3s_CONTEXT} --server=${RANCHER_SERVER_URL}
        kubectl config set-credentials ${K3S_CONTEXT} --token=${BEARER_TOKEN}
        kubectl config set-context ${K3S_CONTEXT} --cluster=rancher --user=rancher --insecure-skip-tls-verify
        kubectl config use-context ${K3S_CONTEXT}
    fi

}

### View kubeconfig
kubectl_view_configs () {
    log "Showing ${KUBECTL_CONTEXT} context"
    kubectl config use-context ${KUBECTL_CONTEXT}
    kubectl config view --minify --flatten
}

### Cleanup function
kubectl_rancher_server_cleanup () {
    log "Cleaning up rancher config"
    kubectl config delete-context rancher
    kubectl config delete-cluster rancher
    kubectl config delete-user rancher
}


### Create a cluster
create_rancher_cluster () {
    log "Creating a new cluster called ${POOL_NAME} using ${KUBECTL_CONTEXT}"
    # Create the cluster
    kubectl config use-context ${KUBECTL_CONTEXT}
    
    ## Create VMs for Pool
    # This is horrible and static
    if [[ ${POOL_NAME} == "rke2-lab-01" ]]; then
        ${BASE_DIR}/newvm.sh create --ip 10.0.5.11 --vmname rke2-lab-01-01 --pxdisk true
        ${BASE_DIR}/newvm.sh create --ip 10.0.5.12 --vmname rke2-lab-01-02 --pxdisk true
        ${BASE_DIR}/newvm.sh create --ip 10.0.5.13 --vmname rke2-lab-01-03 --pxdisk true
    fi
    if [[ ${POOL_NAME} == "rke2-lab-02" ]]; then
        ${BASE_DIR}/newvm.sh create --ip 10.0.5.21 --vmname rke2-lab-02-01 --pxdisk true
        ${BASE_DIR}/newvm.sh create --ip 10.0.5.22 --vmname rke2-lab-02-02 --pxdisk true
        ${BASE_DIR}/newvm.sh create --ip 10.0.5.23 --vmname rke2-lab-02-03 --pxdisk true
    fi
    kubectl config use-context ${KUBECTL_CONTEXT}
    # Create the cluster
      cat << EOF | kubectl apply -f -
apiVersion: provisioning.cattle.io/v1
kind: Cluster
metadata:
  name: ${POOL_NAME}
  namespace: fleet-default
spec:
  kubernetesVersion: ${RANCHER_K8S_VERSION}
  localClusterAuthEndpoint: {}
  rkeConfig:
    chartValues:
      rke2-calico: {}
    dataDirectories: {}
    etcd:
      snapshotRetention: 5
      snapshotScheduleCron: 0 */5 * * *
    machineGlobalConfig:
      cni: calico
      disable-kube-proxy: false
      etcd-expose-metrics: false
    machinePoolDefaults: {}
    machineSelectorConfig:
    - config:
        protect-kernel-defaults: false
    registries: {}
    upgradeStrategy:
      controlPlaneConcurrency: "1"
      controlPlaneDrainOptions:
        deleteEmptyDirData: true
        disableEviction: false
        enabled: false
        force: false
        gracePeriod: -1
        ignoreDaemonSets: true
        ignoreErrors: false
        postDrainHooks: null
        preDrainHooks: null
        skipWaitForDeleteTimeoutSeconds: 0
        timeout: 120
      workerConcurrency: "1"
      workerDrainOptions:
        deleteEmptyDirData: true
        disableEviction: false
        enabled: false
        force: false
        gracePeriod: -1
        ignoreDaemonSets: true
        ignoreErrors: false
        postDrainHooks: null
        preDrainHooks: null
        skipWaitForDeleteTimeoutSeconds: 0
        timeout: 120
EOF

    login_rancher_server

    CLUSTERID=$(kubectl --context ${KUBECTL_CONTEXT} -n fleet-default get clusters.provisioning.cattle.io ${POOL_NAME} -o yaml | yq -r .status.clusterName)

    log "CLUSTERID: $CLUSTERID"


    RESPONSE=$(curl ${RANCHER_SERVER_URL}'/v3/clusterregistrationtoken' -H 'content-type: application/json' -H "Authorization: Bearer $RANCHER_TOKEN" --data-binary '{"type":"clusterRegistrationToken","clusterId":"'$CLUSTERID'"}') #--insecure

 until [[ $AGENTCMD != "" ]]; do
    AGENTCMD=`curl -s ${RANCHER_SERVER_URL}'/v3/clusterregistrationtoken?id="'$CLUSTERID'"' -H 'content-type: application/json' -H "Authorization: Bearer $RANCHER_TOKEN" | jq -r '.data[].nodeCommand' | head -1`
    log "AGENTCMD: $AGENTCMD"
    debug "agentcmd full output: "
    sleep 10
  done


  sleep 40

    # Again, aweful and static
    if [[ ${POOL_NAME} == "rke2-lab-01" ]]; then

          ssh ubuntu@rke2-lab-01-01 -o StrictHostKeyChecking=no << EOF
            sleep 5

            $AGENTCMD --controlplane --etcd --worker
EOF
          ssh ubuntu@rke2-lab-01-02 -o StrictHostKeyChecking=no << EOF
            sleep 5

            $AGENTCMD --controlplane --etcd --worker
EOF
          ssh ubuntu@rke2-lab-01-03 -o StrictHostKeyChecking=no << EOF
            sleep 5

            $AGENTCMD --controlplane --etcd --worker
EOF

    fi

    # Again, aweful and static
    if [[ ${POOL_NAME} == "rke2-lab-02" ]]; then

          ssh ubuntu@rke2-lab-02-01 -o StrictHostKeyChecking=no << EOF
            sleep 5

            $AGENTCMD --controlplane --etcd --worker
EOF
          ssh ubuntu@rke2-lab-02-02 -o StrictHostKeyChecking=no << EOF
            sleep 5

            $AGENTCMD --controlplane --etcd --worker
EOF
          ssh ubuntu@rke2-lab-02-03 -o StrictHostKeyChecking=no << EOF
            sleep 5

            $AGENTCMD --controlplane --etcd --worker
EOF

    fi

}

### List the available pools on the server
list_rancher_clusters () {
    log "Listing the available pools"
    kubectl config use-context ${KUBECTL_CONTEXT}
    kubectl get -n fleet-default clusters.provisioning.cattle.io
}

### Delete a cluster
delete_rancher_cluster () {
    requires_poolname
    log "Deleting the cluster ${POOL_NAME}"
    kubectl config use-context ${KUBECTL_CONTEXT}
    kubectl delete -n fleet-default clusters ${POOL_NAME}

    if [[ ${POOL_NAME} == "rke2-lab-01" ]]; then
        ${BASE_DIR}/newvm.sh delete --ip 10.0.5.11 --vmname rke2-lab-01-01 --pxdisk true
        ${BASE_DIR}/newvm.sh delete --ip 10.0.5.12 --vmname rke2-lab-01-02 --pxdisk true
        ${BASE_DIR}/newvm.sh delete --ip 10.0.5.13 --vmname rke2-lab-01-03 --pxdisk true
    fi
    kubectl config use-context ${KUBECTL_CONTEXT}
    kubectl config delete-context ${POOL_NAME}
    kubectl config delete-cluster ${POOL_NAME}

    # Need to clean up cloud drives
}

### Create a context for a cluster
create_context () {
    requires_poolname
    log "Creating a context for ${POOL_NAME}"
    CONTEXT_URL="${RANCHER_SERVER_URL}/k8s/clusters/$(kubectl --context ${KUBECTL_CONTEXT} -n fleet-default get clusters.provisioning.cattle.io ${POOL_NAME} -o yaml | yq -r .status.clusterName)"
    kubectl config set-cluster ${POOL_NAME} --server=${CONTEXT_URL}
    kubectl config set-context ${POOL_NAME} --cluster=${POOL_NAME} --user=rancher --insecure-skip-tls-verify
    kubectl config use-context ${POOL_NAME} || terminate "Could not switch to ${POOL_NAME}" ${ERR_POOL_NOT_FOUND}
}

### Install Sealed Secrets
install_sealed_secrets () {
    kubectl config use-context ${POOL_NAME} || terminate "Could not switch to ${POOL_NAME}" ${ERR_POOL_NOT_FOUND}
    requires_poolname
    log "Installing sealed secrets to ${POOL_NAME}"


    SEALED_SECRET=$(< ${SEALED_SECRET_TEMPLATE})
    SEALED_SECRET="${SEALED_SECRET//${TLS_CERT_PLACEHOLDER}/${SEALED_SECRET_TLS_CERT}}"
    SEALED_SECRET="${SEALED_SECRET//${TLS_KEY_PLACEHOLDER}/${SEALED_SECRET_TLS_KEY}}"
    kubectl apply -f <(echo "${SEALED_SECRET}")



    helm repo add sealed-secrets https://bitnami-labs.github.io/sealed-secrets
    helm repo update
    helm install sealed-secrets sealed-secrets/sealed-secrets -n kube-system --set=keyrenewperiod=0
    sleep 10
    kubectl delete pod -n kube-system -l app.kubernetes.io/name=sealed-secrets
    # Sealed secret substitution


}

### Install ArgoCD
install_argocd () {
    requires_poolname
    log "Installing ArgoCD to ${POOL_NAME}"
    kubectl config use-context ${POOL_NAME} || terminate "Could not switch to ${POOL_NAME}" ${ERR_POOL_NOT_FOUND}
    kubectl create namespace argocd
    kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml


}

### Install Metallb
install_metallb () {



    log "Installing MetalLB to ${POOL_NAME}"
    kubectl config use-context ${POOL_NAME} || terminate "Could not switch to ${POOL_NAME}" ${ERR_POOL_NOT_FOUND}

    requires_poolname
    requires_argocd
    
    # ArgoCD Variables
    ARGOCD_APPNAME="metallb"
    ARGOCD_NAMESPACE="metallb-system"
    ARGOCD_PATH="${ARGOCD_PATH_ROOT}/metallb/overlays/${POOL_NAME}"
    ARGOCD_REPO_URL="${ARGOCD_REPO_URL}"

    # Apply Application
    ARGOAPP=$(< ${ARGOCD_APP_TEMPLATE})
    ARGOAPP="${ARGOAPP//${ARGOCD_NAMESPACE_PLACEHOLDER}/${ARGOCD_NAMESPACE}}"
    ARGOAPP="${ARGOAPP//${ARGOCD_APP_NAME_PLACEHOLDER}/${ARGOCD_APPNAME}}"
    ARGOAPP="${ARGOAPP//${ARGOCD_REPO_URL_PLACEHOLDER}/${ARGOCD_REPO_URL}}"
    ARGOAPP="${ARGOAPP//${ARGOCD_REPO_PATH_PLACEHOLDER}/${ARGOCD_PATH}}"
    kubectl apply -f <(echo "${ARGOAPP}")

    # Fallback option
    # kubectl apply -k ${MANIFEST_LOCAL_DIR}/metallb/overlays/${POOL_NAME}
    # until [[ $(kubectl -n metallb-system get pods --no-headers | grep 1/1 | wc -l ) == 4 ]]; do
    #     kubectl apply -k ${MANIFEST_LOCAL_DIR}/metallb/overlays/${POOL_NAME}
    #     sleep 10
    #     echo -n "."
    # done

}

### Install PX Operator
install_px_operator () {

    log "Installing PX Operator to ${POOL_NAME}"
    kubectl config use-context ${POOL_NAME} || terminate "Could not switch to ${POOL_NAME}" ${ERR_POOL_NOT_FOUND}

    requires_poolname
    #requires_argocd

    # ArgoCD Variables
    ARGOCD_APPNAME="px-operator"
    ARGOCD_NAMESPACE="portworx"
    ARGOCD_PATH="${ARGOCD_PATH_ROOT}/px-operator/overlays/${POOL_NAME}"
    ARGOCD_REPO_URL="${ARGOCD_REPO_URL}"

    # Apply Application
    ARGOAPP=$(< ${ARGOCD_APP_TEMPLATE})
    ARGOAPP="${ARGOAPP//${ARGOCD_NAMESPACE_PLACEHOLDER}/${ARGOCD_NAMESPACE}}"
    ARGOAPP="${ARGOAPP//${ARGOCD_APP_NAME_PLACEHOLDER}/${ARGOCD_APPNAME}}"
    ARGOAPP="${ARGOAPP//${ARGOCD_REPO_URL_PLACEHOLDER}/${ARGOCD_REPO_URL}}"
    ARGOAPP="${ARGOAPP//${ARGOCD_REPO_PATH_PLACEHOLDER}/${ARGOCD_PATH}}"
    kubectl apply -f <(echo "${ARGOAPP}")

    log "Installing vsphere secret manually because we removed the sealed secret."
    #kubectl apply -f ~/temp/px-vsphere-secret.yaml

    #kubectl apply -k ${MANIFEST_LOCAL_DIR}/px-operator/overlays/${POOL_NAME}
}

### Install PX Enterprise
install_px_ent () {

    log "Installing PX Enteprise to ${POOL_NAME}"
    kubectl config use-context ${POOL_NAME} || terminate "Could not switch to ${POOL_NAME}" ${ERR_POOL_NOT_FOUND}

    requires_poolname
    requires_argocd
    
    # ArgoCD Variables
    ARGOCD_APPNAME="portworx"
    ARGOCD_NAMESPACE="portworx"
    ARGOCD_PATH="${ARGOCD_PATH_ROOT}/portworx/overlays/${POOL_NAME}"
    ARGOCD_REPO_URL="${ARGOCD_REPO_URL}"

    # Apply Application
    ARGOAPP=$(< ${ARGOCD_APP_TEMPLATE})
    ARGOAPP="${ARGOAPP//${ARGOCD_NAMESPACE_PLACEHOLDER}/${ARGOCD_NAMESPACE}}"
    ARGOAPP="${ARGOAPP//${ARGOCD_APP_NAME_PLACEHOLDER}/${ARGOCD_APPNAME}}"
    ARGOAPP="${ARGOAPP//${ARGOCD_REPO_URL_PLACEHOLDER}/${ARGOCD_REPO_URL}}"
    ARGOAPP="${ARGOAPP//${ARGOCD_REPO_PATH_PLACEHOLDER}/${ARGOCD_PATH}}"
    kubectl apply -f <(echo "${ARGOAPP}")

    # Add the correct secret util I figure out secret keys
    #kubectl -n portworx apply -f ~/temp/px-vsphere-secret.yaml

    #kubectl apply -k ${MANIFEST_LOCAL_DIR}/portworx/overlays/${POOL_NAME}
}

### Install Local Path Provisioner
install_lpp () {

    log "Installing Localpath Provisioner to ${POOL_NAME}"
    kubectl config use-context ${POOL_NAME} || terminate "Could not switch to ${POOL_NAME}" ${ERR_POOL_NOT_FOUND}

    requires_poolname
    requires_argocd
    
    # ArgoCD Variables
    ARGOCD_APPNAME="localpath"
    ARGOCD_NAMESPACE="local-path-storage"
    ARGOCD_PATH="${ARGOCD_PATH_ROOT}/local-path-provisioner/overlays/${POOL_NAME}"
    ARGOCD_REPO_URL="${ARGOCD_REPO_URL}"

    # Apply Application
    ARGOAPP=$(< ${ARGOCD_APP_TEMPLATE})
    ARGOAPP="${ARGOAPP//${ARGOCD_NAMESPACE_PLACEHOLDER}/${ARGOCD_NAMESPACE}}"
    ARGOAPP="${ARGOAPP//${ARGOCD_APP_NAME_PLACEHOLDER}/${ARGOCD_APPNAME}}"
    ARGOAPP="${ARGOAPP//${ARGOCD_REPO_URL_PLACEHOLDER}/${ARGOCD_REPO_URL}}"
    ARGOAPP="${ARGOAPP//${ARGOCD_REPO_PATH_PLACEHOLDER}/${ARGOCD_PATH}}"
    kubectl apply -f <(echo "${ARGOAPP}")

    #kubectl apply -k ${MANIFEST_LOCAL_DIR}/local-path-provisioner/overlays/${POOL_NAME}
}

### Install PXBBQ
install_pxbbq () {

    log "Installing PXBBQ to ${POOL_NAME}"
    kubectl config use-context ${POOL_NAME} || terminate "Could not switch to ${POOL_NAME}" ${ERR_POOL_NOT_FOUND}

    requires_poolname
    requires_argocd
   
    # ArgoCD Variables
    ARGOCD_APPNAME="pxbbq"
    ARGOCD_NAMESPACE="pxbbq"
    ARGOCD_PATH="${ARGOCD_PATH_ROOT}/pxbbq/overlays/${POOL_NAME}"
    ARGOCD_REPO_URL="${ARGOCD_REPO_URL}"

    # Apply Application
    ARGOAPP=$(< ${ARGOCD_APP_TEMPLATE})
    ARGOAPP="${ARGOAPP//${ARGOCD_NAMESPACE_PLACEHOLDER}/${ARGOCD_NAMESPACE}}"
    ARGOAPP="${ARGOAPP//${ARGOCD_APP_NAME_PLACEHOLDER}/${ARGOCD_APPNAME}}"
    ARGOAPP="${ARGOAPP//${ARGOCD_REPO_URL_PLACEHOLDER}/${ARGOCD_REPO_URL}}"
    ARGOAPP="${ARGOAPP//${ARGOCD_REPO_PATH_PLACEHOLDER}/${ARGOCD_PATH}}"
    kubectl apply -f <(echo "${ARGOAPP}")

    #kubectl apply -k ${MANIFEST_LOCAL_DIR}/pxbbq/overlays/${POOL_NAME}
}

### Install aidemo
install_aidemo () {

    log "Installing PXBBQ to ${POOL_NAME}"
    kubectl config use-context ${POOL_NAME} || terminate "Could not switch to ${POOL_NAME}" ${ERR_POOL_NOT_FOUND}

    requires_poolname
    requires_argocd
   
    # ArgoCD Variables
    ARGOCD_APPNAME="aidemo"
    ARGOCD_NAMESPACE="genai"
    ARGOCD_PATH="${ARGOCD_PATH_ROOT}/aidemo/overlays/${POOL_NAME}"
    ARGOCD_REPO_URL="${ARGOCD_REPO_URL}"

    # Apply Application
    ARGOAPP=$(< ${ARGOCD_APP_TEMPLATE})
    ARGOAPP="${ARGOAPP//${ARGOCD_NAMESPACE_PLACEHOLDER}/${ARGOCD_NAMESPACE}}"
    ARGOAPP="${ARGOAPP//${ARGOCD_APP_NAME_PLACEHOLDER}/${ARGOCD_APPNAME}}"
    ARGOAPP="${ARGOAPP//${ARGOCD_REPO_URL_PLACEHOLDER}/${ARGOCD_REPO_URL}}"
    ARGOAPP="${ARGOAPP//${ARGOCD_REPO_PATH_PLACEHOLDER}/${ARGOCD_PATH}}"
    kubectl apply -f <(echo "${ARGOAPP}")

    #kubectl apply -k ${MANIFEST_LOCAL_DIR}/pxbbq/overlays/${POOL_NAME}
}

install_pxbbq_taster () {

    log "Installing PXBBQ taster to ${POOL_NAME}"
    kubectl config use-context ${POOL_NAME} || terminate "Could not switch to ${POOL_NAME}" ${ERR_POOL_NOT_FOUND}

    requires_poolname
    requires_argocd
    requires_minio
    requires_mc
   
       env

    cat <<EOF | kubectl apply -f -
apiVersion: v1
data:
  mongonode: $(echo "mongo" | base64)
  mongopass: $(echo "porxie" | base64)
  mongouser: $(echo "porxie" | base64)
  s3accesskey: $(echo ${MINIO_ACCESS_KEY} | base64)
  s3bucket: $(echo "${POOL_NAME}-bbq-taster" | base64)
  s3resultsbucket: $(echo "${POOL_NAME}-bbq-taster" | base64)
  s3secretkey: $(echo ${MINIO_SECRET_KEY} | base64)
  s3url: $(echo ${MINIO_ENDPOINT} | base64)
kind: Secret
metadata:
  name: bbq-taster
  namespace: pxbbq
type: Opaque
EOF

    mc mb ${POOL_NAME}/${POOL_NAME}-bbq-taster
    mc mb ${POOL_NAME}/${POOL_NAME}-bbq-taster-results
    # ArgoCD Variables
    ARGOCD_APPNAME="pxbbq-taster"
    ARGOCD_NAMESPACE="pxbbq"
    ARGOCD_PATH="${ARGOCD_PATH_ROOT}/pxbbq/bbq-taster"
    ARGOCD_REPO_URL="${ARGOCD_REPO_URL}"

    # Apply Application
    ARGOAPP=$(< ${ARGOCD_APP_TEMPLATE})
    ARGOAPP="${ARGOAPP//${ARGOCD_NAMESPACE_PLACEHOLDER}/${ARGOCD_NAMESPACE}}"
    ARGOAPP="${ARGOAPP//${ARGOCD_APP_NAME_PLACEHOLDER}/${ARGOCD_APPNAME}}"
    ARGOAPP="${ARGOAPP//${ARGOCD_REPO_URL_PLACEHOLDER}/${ARGOCD_REPO_URL}}"
    ARGOAPP="${ARGOAPP//${ARGOCD_REPO_PATH_PLACEHOLDER}/${ARGOCD_PATH}}"
    kubectl apply -f <(echo "${ARGOAPP}")

}
install_minio () {

    log "Installing minio to ${POOL_NAME}"
    kubectl config use-context ${POOL_NAME} || terminate "Could not switch to ${POOL_NAME}" ${ERR_POOL_NOT_FOUND}

    requires_poolname
    requires_argocd

    # # ArgoCD Variables
    # ARGOCD_APPNAME="minio"
    # ARGOCD_NAMESPACE="minio"

    # # Must point to a values file
    # ARGOCD_VALUE_FILES="\$values/${ARGOCD_HELM_VALUES_ROOT}/minio/${POOL_NAME}/values.yaml"
    # ARGOCD_REPO_URL="${ARGOCD_REPO_URL}"

    # # Helm specific options
    # ARGOCD_HELM_REPO="https://charts.min.io/"
    # ARGOCD_HELM_CHART_VERSION="5.2.0"
    # ARGOCD_HELM_CHART="minio"

    # # Apply Application
    # ARGOAPP=$(< ${ARGOCD_HELM_APP_TEMPLATE})
    # ARGOAPP="${ARGOAPP//${ARGOCD_NAMESPACE_PLACEHOLDER}/${ARGOCD_NAMESPACE}}"
    # ARGOAPP="${ARGOAPP//${ARGOCD_APP_NAME_PLACEHOLDER}/${ARGOCD_APPNAME}}"
    # ARGOAPP="${ARGOAPP//${ARGOCD_REPO_URL_PLACEHOLDER}/${ARGOCD_REPO_URL}}"
    # ARGOAPP="${ARGOAPP//${ARGOCD_HELM_VALUE_FILES_PLACEHOLDER}/${ARGOCD_VALUE_FILES}}"
    # ARGOAPP="${ARGOAPP//${ARGOCD_HELM_REPO_URL_PLACEHOLDER}/${ARGOCD_HELM_REPO}}"
    # ARGOAPP="${ARGOAPP//${ARGOCD_HELM_CHART_PLACEHOLDER}/${ARGOCD_HELM_CHART}}"
    # ARGOAPP="${ARGOAPP//${ARGOCD_HELM_TARGET_PLACEHOLDER}/${ARGOCD_HELM_CHART_VERSION}}"

    # # Create the minio namespace
    # kubectl create namespace minio
    # kubectl apply -f <(echo "${ARGOAPP}")

    #fallback to manual install
    log "Installing minio to ${POOL_NAME} using fallback method"
    helm install minio \
    --set mode=standalone \
    --set persistence.storageClass=px-repl2 \
    --set persistence.accessMode=ReadWriteMany \
    --set persistence.size=10Gi \
    --set resources.requests.memory=1Gi \
    --set service.type=LoadBalancer \
    --namespace minio \
    --create-namespace \
    minio/minio


}

install_etcd () {

    log "Installing etcd to ${POOL_NAME}"
    kubectl config use-context ${POOL_NAME} || terminate "Could not switch to ${POOL_NAME}" ${ERR_POOL_NOT_FOUND}
=$(pxctl status | sed -n -E 's/Cluster UUID: (\w+)/\1/p')

    # ArgoCD Variables
    ARGOCD_APPNAME="etcd"
    ARGOCD_NAMESPACE="etcd"

    # Must point to a values file
    ARGOCD_VALUE_FILES="\$values/${ARGOCD_HELM_VALUES_ROOT}/etcd/${POOL_NAME}/values.yaml"
    ARGOCD_REPO_URL="${ARGOCD_REPO_URL}"

    # Helm specific options
    ARGOCD_HELM_REPO="registry-1.docker.io/bitnamicharts"
    ARGOCD_HELM_CHART_VERSION="10.0.9"
    ARGOCD_HELM_CHART="etcd"

    # Apply Application
    ARGOAPP=$(< ${ARGOCD_HELM_APP_TEMPLATE})
    ARGOAPP="${ARGOAPP//${ARGOCD_NAMESPACE_PLACEHOLDER}/${ARGOCD_NAMESPACE}}"
    ARGOAPP="${ARGOAPP//${ARGOCD_APP_NAME_PLACEHOLDER}/${ARGOCD_APPNAME}}"
    ARGOAPP="${ARGOAPP//${ARGOCD_REPO_URL_PLACEHOLDER}/${ARGOCD_REPO_URL}}"
    ARGOAPP="${ARGOAPP//${ARGOCD_HELM_VALUE_FILES_PLACEHOLDER}/${ARGOCD_VALUE_FILES}}"
    ARGOAPP="${ARGOAPP//${ARGOCD_HELM_REPO_URL_PLACEHOLDER}/${ARGOCD_HELM_REPO}}"
    ARGOAPP="${ARGOAPP//${ARGOCD_HELM_CHART_PLACEHOLDER}/${ARGOCD_HELM_CHART}}"
    ARGOAPP="${ARGOAPP//${ARGOCD_HELM_TARGET_PLACEHOLDER}/${ARGOCD_HELM_CHART_VERSION}}"

    # Create the minio namespace
    kubectl create namespace etcd
    kubectl apply -f <(echo "${ARGOAPP}")
}
install_grafana () {
    #Check to make sure Grafana is running
    if [[ `kubectl -n portworx get pods -l app=grafana | grep Running | grep 1/1 | wc -l` -eq 1 ]]; then
            sleep 1
    else


    kubectl -n portworx create configmap grafana-dashboard-config --from-file=${BASE_DIR}/grafana-dashboard-config.yaml
    sleep 10

    kubectl -n portworx create configmap grafana-source-config --from-file=${BASE_DIR}/grafana-datasource.yaml
    sleep 10

    curl "https://docs.portworx.com/samples/k8s/pxc/portworx-cluster-dashboard.json" -o ${BASE_DIR}/portworx-cluster-dashboard.json && \
    curl "https://docs.portworx.com/samples/k8s/pxc/portworx-node-dashboard.json" -o ${BASE_DIR}/portworx-node-dashboard.json && \
    curl "https://docs.portworx.com/samples/k8s/pxc/portworx-volume-dashboard.json" -o ${BASE_DIR}/portworx-volume-dashboard.json && \
    curl "https://docs.portworx.com/samples/k8s/pxc/portworx-performance-dashboard.json" -o ${BASE_DIR}/portworx-performance-dashboard.json && \
    curl "https://docs.portworx.com/samples/k8s/pxc/portworx-etcd-dashboard.json" -o ${BASE_DIR}/portworx-etcd-dashboard.json && \

    kubectl -n portworx create configmap grafana-dashboards --from-file=${BASE_DIR}/portworx-cluster-dashboard.json --from-file=${BASE_DIR}/portworx-performance-dashboard.json --from-file=${BASE_DIR}/portworx-node-dashboard.json --from-file=${BASE_DIR}/portworx-volume-dashboard.json --from-file=${BASE_DIR}/portworx-etcd-dashboard.json

    sleep 10

    kubectl apply -f ${BASE_DIR}/grafana.yaml
    sleep 5

    #Check to make sure Grafana is running
    until [[ `kubectl -n portworx get pods -l app=grafana | grep Running | grep 1/1 | wc -l` -eq 1 ]]; do
            echo "Waiting for Grafana to be ready...."
            sleep 10
    done

    #rm grafana-dashboard-config.yaml
    #rm grafana-datasource.yaml
    rm ${BASE_DIR}/portworx-cluster-dashboard.json
    rm ${BASE_DIR}/portworx-node-dashboard.json
    rm ${BASE_DIR}/portworx-volume-dashboard.json
    rm ${BASE_DIR}/portworx-performance-dashboard.json
    rm ${BASE_DIR}/portworx-etcd-dashboard.json
    #rm grafana.yaml

fi

}
install_pxbackup () {

    log "Installing pxbackup to ${POOL_NAME}"
    kubectl config use-context ${POOL_NAME} || terminate "Could not switch to ${POOL_NAME}" ${ERR_POOL_NOT_FOUND}

    requires_poolname
    # NOTICE: We are going to try a manual helm command instead of using ArgoCD
    # requires_argocd

    # # ArgoCD Variables
    # ARGOCD_APPNAME="pxbackup"
    # ARGOCD_NAMESPACE="central"

    # # Must point to a values file
    # ARGOCD_VALUE_FILES="\$values/${ARGOCD_HELM_VALUES_ROOT}/pxbackup/${POOL_NAME}/values.yaml"
    # ARGOCD_REPO_URL="${ARGOCD_REPO_URL}"

    # # Helm specific options
    # ARGOCD_HELM_REPO="http://charts.portworx.io/"
    # ARGOCD_HELM_CHART_VERSION="2.6.0"
    # ARGOCD_HELM_CHART="px-central"

    # # Apply Application
    # ARGOAPP=$(< ${ARGOCD_HELM_APP_TEMPLATE})
    # ARGOAPP="${ARGOAPP//${ARGOCD_NAMESPACE_PLACEHOLDER}/${ARGOCD_NAMESPACE}}"
    # ARGOAPP="${ARGOAPP//${ARGOCD_APP_NAME_PLACEHOLDER}/${ARGOCD_APPNAME}}"
    # ARGOAPP="${ARGOAPP//${ARGOCD_REPO_URL_PLACEHOLDER}/${ARGOCD_REPO_URL}}"
    # ARGOAPP="${ARGOAPP//${ARGOCD_HELM_VALUE_FILES_PLACEHOLDER}/${ARGOCD_VALUE_FILES}}"
    # ARGOAPP="${ARGOAPP//${ARGOCD_HELM_REPO_URL_PLACEHOLDER}/${ARGOCD_HELM_REPO}}"
    # ARGOAPP="${ARGOAPP//${ARGOCD_HELM_CHART_PLACEHOLDER}/${ARGOCD_HELM_CHART}}"
    # ARGOAPP="${ARGOAPP//${ARGOCD_HELM_TARGET_PLACEHOLDER}/${ARGOCD_HELM_CHART_VERSION}}"

    # Create the central namespace
    # kubectl create namespace central
    # kubectl apply -f <(echo "${ARGOAPP}")

    # This is the failback install command:
    helm install px-central portworx/px-central --namespace central --create-namespace --version ${PXBACKUP_VERSION} --set persistentStorage.enabled=true,persistentStorage.storageClassName="px-repl2",pxbackup.enabled=true,oidc.centralOIDC.updateAdminProfile=false

}
configure_pxbackup() {
    log "Configuring PXBackup"
    kubectl config use-context ${POOL_NAME} || terminate "Could not switch to ${POOL_NAME}" ${ERR_POOL_NOT_FOUND}

    requires_pxbackup
    requires_minio
    env

    kubectl port-forward -n central svc/px-backup 10002:10002 &
    PORT_FORWARD_PID=$!
    # This is a hack
    LB_SERVER_IP="localhost"

    log "#### Configuring PX Backup API for Checks"
    # First, let's get what we need configured to run pxbackupctl commands:
    kubectl patch svc px-backup -n central --type='json' -p '[{"op":"replace","path":"/spec/type","value":"LoadBalancer"}]'
    log "Waiting for LoadBalancer IP to be assigned"
    ip_regex='^([0-9]{1,3}\.){3}[0-9]{1,3}$'
    until [[ $(kubectl -n central get svc px-backup -o json | jq -cr '.status.loadBalancer.ingress[0].ip') =~ $ip_regex ]]; do 
    # do nothing!
    sleep 5
    done

    log "Logging in to pxbackup"
    until [[ $return_value == 0 ]]; do
        pxbackupctl login -s http://$LB_UI_IP -u admin -p admin
        return_value=$?
        echo "Waiting for successful login"
        sleep 5
    done
    log "Creating cloud credentials"
    pxbackupctl create cloudcredential --name s3-account -p aws -e $LB_SERVER_IP:10002 --aws-access-key $MINIO_ACCESS_KEY --aws-secret-key $MINIO_SECRET_KEY
    cloud_credential_uid=$(pxbackupctl get cloudcredential -e $LB_SERVER_IP:10002 --orgID default -o json | jq -cr '.[0].metadata.uid') 

    log "Create backup locations"
    pxbackupctl create backuplocation -e $LB_SERVER_IP:10002 --cloud-credential-Uid $cloud_credential_uid --name backup-location-1 -p s3 --cloud-credential-name s3-account --path $MINIO_BUCKET --s3-endpoint ${MINIO_ENDPOINT} --s3-region ${S3_REGION} --s3-disable-pathstyle=true --s3-disable-ssl=true
    pxbackupctl create backuplocation -e $LB_SERVER_IP:10002 --cloud-credential-Uid $cloud_credential_uid --name obj-lock-backup-location-1 -p s3 --cloud-credential-name s3-account --path ${MINIO_BUCKET_OBJECTLOCK} --s3-endpoint ${MINIO_ENDPOINT} --s3-region ${S3_REGION} --s3-disable-pathstyle=true --s3-disable-ssl=true

    log "Create backup schedules"
    pxbackupctl create schedulepolicy --interval-minutes 15 -e $LB_SERVER_IP:10002 --name 15-min
    pxbackupctl create schedulepolicy --interval-minutes 15 -e $LB_SERVER_IP:10002 --name 15-min-object --forObjectLock    


cat << EOF > ${TEMP_DIR}/mongo-pre-rule.yaml
    rules:
    - actions:
      - value: 'mongosh -u porxie -p porxie --eval "db.adminCommand( { fsync: 1 }
          )"'
      podSelector:
          app.kubernetes.io/name: mongo
EOF
cat << EOF > ${TEMP_DIR}/mongo-post-rule.yaml
    rules:
    - actions:
        - value: mongodump -u porxie -p porxie
      podSelector:
          app.kubernetes.io/name: mongo
EOF
    pxbackupctl create rule -e $LB_SERVER_IP:10002 -f ${TEMP_DIR}/mongo-pre-rule.yaml --name mongo-pre
    pxbackupctl create rule -e $LB_SERVER_IP:10002 -f ${TEMP_DIR}/mongo-post-rule.yaml --name mongo-post
    unlink ${TEMP_DIR}/mongo-pre-rule.yaml
    unlink ${TEMP_DIR}/mongo-post-rule.yaml

    log "create test users"
    export KCIP=$(kubectl get svc -n central pxcentral-keycloak-http -o jsonpath='{.spec.clusterIP}')
cat << EOF | kubectl -n central exec pxcentral-keycloak-0 -i -- bash
sleep 1
/opt/keycloak/bin/kcadm.sh config credentials --user admin --server http://${KCIP}:80/auth --realm master --password admin
/opt/keycloak/bin/kcadm.sh create users -r master -s username=dev -s firstName=Developer -s lastName=Portworx -s email=developer@portworx.com  -s enabled=true
/opt/keycloak/bin/kcadm.sh create users -r master -s username=platformadmin -s firstName=Platformadmin -s lastName=Portworx -s email=platformadmin@portworx.com  -s enabled=true
/opt/keycloak/bin/kcadm.sh set-password -r master --username dev --new-password Password1
/opt/keycloak/bin/kcadm.sh set-password -r master --username platformadmin --new-password Password1
EOF

    log "Add the cluster"
    kubectl config view --flatten --minify > ./kubeconfig.yaml
    pxbackupctl create cluster --name rke2 -k ./kubeconfig.yaml -e $LB_SERVER_IP:10002 --orgID default
    unlink ./kubeconfig.yaml

    log "Stopping port forward"
    kill $PORT_FORWARD_PID

}
reboot_cluster () {
    log "Rebooting the cluster"
    kubectl config use-context ${POOL_NAME} || terminate "Could not switch to ${POOL_NAME}" ${ERR_POOL_NOT_FOUND}
    requires_poolname
    nodes=$(kubectl get nodes -o jsonpath='{.items[*].metadata.name}')
    for node in ${nodes[@]}; do
        ssh -o StrictHostKeyChecking=no  ubuntu@$node "sudo update-grub"
        ssh -o StrictHostKeyChecking=no  ubuntu@$node "sudo reboot"
    done

}
configure_minio () {
    log "Configuring Minio"
    kubectl config use-context ${POOL_NAME} || terminate "Could not switch to ${POOL_NAME}" ${ERR_POOL_NOT_FOUND}

    requires_mc
    requires_minio

    MINIO_ENDPOINT=http://$(kubectl get svc -n minio minio -o jsonpath='{.status.loadBalancer.ingress[].ip}'):9000
    MINIO_ACCESS_KEY=$(kubectl get secret -n minio minio -o jsonpath="{.data.rootUser}" | base64 --decode)
    MINIO_SECRET_KEY=$(kubectl get secret -n minio minio -o jsonpath="{.data.rootPassword}" | base64 --decode)

    mc alias set ${POOL_NAME} $MINIO_ENDPOINT $MINIO_ACCESS_KEY $MINIO_SECRET_KEY
    mc mb ${POOL_NAME}/${BUCKET_NAME}
    mc mb ${POOL_NAME}/${BUCKET_NAME}-objectlock --with-lock
    mc retention set --default COMPLIANCE 7d ${POOL_NAME}/${BUCKET_NAME}-objectlock

}

# Install binary utilities locally
install_utilities () {
    kubectl config use-context ${POOL_NAME} || terminate "Could not switch to ${POOL_NAME}" ${ERR_POOL_NOT_FOUND}

    requires_portworx

    log "Installing utilities to ${BINARY_DIR}"
    log "Installing storkctl to ${BINARY_DIR}"

    STORK_POD=$(kubectl get pods -n portworx -l name=stork -o jsonpath='{.items[0].metadata.name}')
    kubectl cp -n portworx $STORK_POD:storkctl/linux/storkctl ${BINARY_DIR}/storkctl  --retries=10
    chmod +x ${BINARY_DIR}/storkctl

    log "Installing mc to ${BINARY_DIR}"
    wget -q -O ${BINARY_DIR}/mc https://dl.minio.io/client/mc/release/linux-amd64/mc
    chmod +x ${BINARY_DIR}/mc

    log "Installing pxctl to ${BINARY_DIR}"
    BACKUP_POD_NAME=$(kubectl get pods -n central -l app=px-backup -o jsonpath='{.items[0].metadata.name}')
    kubectl cp -n central $BACKUP_POD_NAME:pxbackupctl/linux/pxbackupctl ${BINARY_DIR}/pxbackupctl --retries=10
    chmod +x ${BINARY_DIR}/pxbackupctl

    log "Installing kubestr to ${BINARY_DIR}"
    wget https://github.com/kastenhq/kubestr/releases/download/v0.4.36/kubestr_0.4.36_Linux_amd64.tar.gz
    sleep 5
    tar -xvf kubestr_0.4.36_Linux_amd64.tar.gz
    unlink kubestr_0.4.36_Linux_amd64.tar.gz
    mv kubestr ${BINARY_DIR}/kubestr
}


### Output Variables for environment
env () {
    kubectl config use-context ${POOL_NAME} || terminate "Could not switch to ${POOL_NAME}" ${ERR_POOL_NOT_FOUND}
    log "Exporting environment variables"

    requires_poolname

        MINIO_ACCESS_KEY=$(kubectl get secret -n minio minio -o jsonpath="{.data.rootUser}" | base64 --decode)
        MINIO_SECRET_KEY=$(kubectl get secret -n minio minio -o jsonpath="{.data.rootPassword}" | base64 --decode)
        MINIO_ENDPOINT=http://$(kubectl get svc -n minio minio -o jsonpath='{.status.loadBalancer.ingress[].ip}'):9000
        MINIO_BUCKET=${BUCKET_NAME}
        MINIO_BUCKET_OBJECTLOCK=${BUCKET_NAME}-objectlock
        CLUSTER_UUID=$(kubectl exec $(kubectl get pods -l name=portworx -n portworx -o jsonpath='{.items[0].metadata.name}') -n portworx -- /opt/pwx/bin/pxctl status| sed -n -E 's/\s+Cluster UUID: ([a-zA-Z0-9]+)/\1/p')

        LB_UI_IP=$(kubectl get svc -n central px-backup-ui -o jsonpath='{.status.loadBalancer.ingress[].ip}')
        # This doesnat actually work because argo keep squashing the loadbalancer change
        #LB_SERVER_IP=$(kubectl get svc -n central px-backup -o jsonpath='{.status.loadBalancer.ingress[].ip}')
        client_secret=$(kubectl get secret --namespace central pxc-backup-secret -o jsonpath={.data.OIDC_CLIENT_SECRET} | base64 --decode)
        
        if [[ ${VIEWENV} == 1 ]]; then
            echo ""
            echo "###############################################"
            echo "###### Paste the following in to .bashrc ######"
            echo "###############################################"
            echo "export MINIO_ENDPOINT=${MINIO_ENDPOINT}"
            echo "export MINIO_ACCESS_KEY=${MINIO_ACCESS_KEY}"
            echo "export MINIO_SECRET_KEY=${MINIO_SECRET_KEY}"
            echo "export MINIO_BUCKET=${MINIO_BUCKET}"
            echo "export MINIO_BUCKET_OBJECTLOCK=${MINIO_BUCKET_OBJECTLOCK}"
            echo "export LB_UI_IP=${LB_UI_IP}"
            echo "export LB_SERVER_IP=${LB_SERVER_IP}"
        else
            log "missing -v flag, not printing variables"
        fi

    if [[ -z ${DR_POOL_NAME} ]]; then
        PORTWORX_API=$(kubectl -n portworx get svc portworx-api -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
        if [[ ${VIEWENV} == 1 ]]; then
            echo "export PORTWORX_API=${PORTWORX_API}"
            echo "export CLUSTER_UUID=${CLUSTER_UUID}"
        fi
    else
        POOL1=${POOL_NAME}
        POOL2=${DR_POOL_NAME}
        
        POOL1_PORTWORX_API="$(kubectl --context ${POOL1} -n portworx get svc portworx-api -o jsonpath='{.status.loadBalancer.ingress[0].ip}'):9001"
        POOL2_PORTWORX_API="$(kubectl --context ${POOL2} -n portworx get svc portworx-api -o jsonpath='{.status.loadBalancer.ingress[0].ip}'):9001"
        kubectl config use-context ${POOL2}
        POOL2_CLUSTER_UUID=$(kubectl exec $(kubectl get pods -l name=portworx -n portworx -o jsonpath='{.items[0].metadata.name}') -n portworx -- /opt/pwx/bin/pxctl status| sed -n -E 's/\s+Cluster UUID: (\w+)/\1/p')
        kubectl config use-context ${POOL1}
        POOL1_CLUSTER_UUID=$(kubectl exec $(kubectl get pods -l name=portworx -n portworx -o jsonpath='{.items[0].metadata.name}') -n portworx -- /opt/pwx/bin/pxctl status| sed -n -E 's/\s+Cluster UUID: (\w+)/\1/p')
        
        if [[ ${VIEWENV} == 1 ]]; then
            echo "export POOL1_PORTWORX_API=${POOL1_PORTWORX_API}"
            echo "export POOL2_PORTWORX_API=${POOL2_PORTWORX_API}"
            echo "export POOL1_CLUSTER_UUID=${POOL1_CLUSTER_UUID}"
            echo "export POOL2_CLUSTER_UUID=${POOL2_CLUSTER_UUID}"
        fi
    fi


}


# ###############################################
# ###### META Functions for the script ##########

install_portworx () {
    install_px_operator
    sleep 30
    install_px_ent
}

install_demo () {
    kubectl config use-context ${KUBECTL_CONTEXT} || terminate "Could not switch to ${KUBECTL_CONTEXT}" 
    requires_poolname

    log "Creating cluster"
    create_rancher_cluster
    wait_ready_racher_cluster
    create_context
    install_sealed_secrets
    install_argocd
    wait_ready_argocd
    install_metallb
    install_portworx
    wait_ready_portworx
    install_minio
    wait_ready_minio
    configure_minio
    install_pxbackup
    wait_ready_pxbackup
    configure_pxbackup
    install_pxbbq
}

install_mvp () {
    kubectl config use-context ${KUBECTL_CONTEXT} || terminate "Could not switch to ${KUBECTL_CONTEXT}" 
    requires_poolname

    log "Creating cluster"
    create_rancher_cluster
    wait_ready_racher_cluster
    create_context
    install_sealed_secrets
    install_argocd
    #wait_ready_argocd
    install_metallb
    install_portworx
    wait_ready_portworx
    #install_minio
    #wait_ready_minio
    #configure_minio
    #install_pxbackup
    #wait_ready_pxbackup
    #configure_pxbackup
    #install_pxbbq
}


install_demo_async () {
    # we are going to use the pool1 and pool2 params for the demo
    kubectl config use-context ${KUBECTL_CONTEXT} || terminate "Could not switch to ${KUBECTL_CONTEXT}" 
    requires_poolname
    requires_drpoolname
    POOL1=${POOL_NAME}
    POOL2=${DR_POOL_NAME}


    # Create first cluster
    log "Creating first cluster"
    create_rancher_cluster
    wait_ready_racher_cluster
    create_context
    install_sealed_secrets
    install_argocd
    wait_ready_argocd
    install_metallb
    install_portworx
    wait_ready_portworx
    install_minio
    wait_ready_minio
    install_pxbbq

    POOL_NAME=${DR_POOL_NAME}
    kubectl config use-context ${KUBECTL_CONTEXT} || terminate "Could not switch to ${KUBECTL_CONTEXT}" 

    # Create second cluster
    log "Creating second cluster"
    create_rancher_cluster
    wait_ready_racher_cluster
    create_context

    log "Switching to ${POOL_NAME}"
    kubectl config use-context ${POOL_NAME} || terminate "Could not switch to ${POOL_NAME}" ${ERR_POOL_NOT_FOUND}
    install_sealed_secrets
    install_argocd
    wait_ready_argocd
    install_metallb
    install_portworx
    wait_ready_portworx


    # fixing pools
    POOL_NAME=${POOL1}
    DR_POOL_NAME=${POOL2}
    log "Pools reset to ${POOL_NAME} and ${DR_POOL_NAME}"
    sleep 15
    px_clusterpair

}

px_deleteclusterpair () {
    requires_poolname
    requires_drpoolname
    requires_storkctl
    log "Removing a cluster pair between ${POOL_NAME} and ${DR_POOL_NAME}"

    # Make sure we capture the pool names because we are going to be moving them around
    POOL1=${POOL_NAME}
    POOL2=${DR_POOL_NAME}

    log "Getting environment variables"
    env
    log "deleting cluster pair"    

    kubectl --context ${POOL1} -n portworx delete clusterpair demo
    kubectl --context ${POOL1} -n portworx delete secret demo
    kubectl --context ${POOL1} -n portworx delete backuplocations.stork.libopenstorage.org demo

    kubectl --context ${POOL2} -n portworx delete clusterpair demo
    kubectl --context ${POOL2} -n portworx delete secret demo
    kubectl --context ${POOL2} -n portworx delete backuplocations.stork.libopenstorage.org demo

}

px_clusterpair () {
    requires_poolname
    requires_drpoolname
    requires_storkctl
    log "Creating a cluster pair between ${POOL_NAME} and ${DR_POOL_NAME}"

    # Make sure we capture the pool names because we are going to be moving them around
    POOL1=${POOL_NAME}
    POOL2=${DR_POOL_NAME}

    log "Getting config files"
    kubectl --context ${POOL1} config view --flatten --minify > $BASE_DIR/${POOL1}_config.yaml
    kubectl --context ${POOL2} config view --flatten --minify > $BASE_DIR/${POOL2}_config.yaml

    log "Getting environment variables"
    env
    log "Creating cluster pair"
    storkctl create clusterpair demo \
    --dest-kube-file $BASE_DIR/${POOL2}_config.yaml \
    --src-kube-file $BASE_DIR/${POOL1}_config.yaml \
    --dest-ep $POOL2_PORTWORX_API \
    --src-ep $POOL1_PORTWORX_API \
    --namespace portworx \
    --provider s3 \
    --s3-endpoint $MINIO_ENDPOINT \
    --s3-access-key $MINIO_ACCESS_KEY \
    --s3-secret-key $MINIO_SECRET_KEY \
    --s3-region $S3_REGION \
    --mode migration \
    $DISABLE_SSL \

    log "Cluster pair created"
    log "Cleaning up config files"
    unlink $BASE_DIR/${POOL1}_config.yaml
    unlink $BASE_DIR/${POOL2}_config.yaml
}

install_cluster () {
    kubectl config use-context ${KUBECTL_CONTEXT} || terminate "Could not switch to ${KUBECTL_CONTEXT}" 
    requires_poolname
    log "Creating first cluster"
    create_rancher_cluster
    wait_ready_racher_cluster
    create_context

    log "Switching to ${POOL_NAME}"
    kubectl config use-context ${POOL_NAME} || terminate "Could not switch to ${POOL_NAME}" ${ERR_POOL_NOT_FOUND}

    install_sealed_secrets
    install_argocd
    sleep 10
    install_metallb
    install_lpp

}

create_rancher () {
    log "Creating new rancher instance"
    echo "${RANCHER_SERVER_URL}"

    # Ensure util1 doesn't already exist
    if [[ $(kubectl get vm ${K3S_SERVER_NAME} -o name --no-headers --context ${KUBEVIRT_CONTEXT}) == "virtualmachine.kubevirt.io/${K3S_SERVER_NAME}" ]]; then
        log "${K3S_SERVER_NAME} already present"
    else
        log "${K3S_SERVER_NAME} not found, provisioning"
        ${BASE_DIR}/newvm.sh create --ip ${K3S_IP} --vmname ${K3S_SERVER_NAME} --cpu 2 --mem 8G
    fi

    wait_ready_vm ${K3S_SERVER_NAME}


    if [[ $(curl -k https://${K3S_IP}:6443/ping) == "pong" ]]; then
        log "K3S is already running"
    else
    # We can now assume that the rancher server is up
    # Let's install K3S
        ssh -o StrictHostKeyChecking=accept-new ${VM_USER_ACCOUNT}@${K3S_SERVER_NAME} << EOF
curl -sfL https://get.k3s.io | INSTALL_K3S_CHANNEL=$K3S_VERSION sh -
EOF
    fi

    wait_ready_k3s

if kubectl --context $KUBECTL_CONTEXT get nodes; then
    log "Our $KUBECTL_CONTEXT seems to be working"
else

    ssh ${VM_USER_ACCOUNT}@${K3S_SERVER_NAME} "sudo cat /etc/rancher/k3s/k3s.yaml" > tmp-k3s.yaml
    sed \
  -e "s|127.0.0.1|${K3S_IP}|g" \
  -e "s| default| k3s|g" \
  -e "s|name: default|name: k3s|g" \
  -e "s|cluster: default|cluster: k3s|g" \
  -e "s|user: default|user: k3s|g" \
  "tmp-k3s.yaml" > tmp-k3s-2.yaml

    # Merge your current config with k3s.yaml and save the result
    KUBECONFIG=~/.kube/config:tmp-k3s-2.yaml kubectl config view --flatten > merged.yaml

    # Backup your original config first
    cp ~/.kube/config ~/.kube/config.bak

    # Replace your kubeconfig with the merged one
    mv merged.yaml ~/.kube/config
    #unlink tmp-k3s.yaml
    #unlink tmp-k3s-2.yaml
fi
    kubectl config use-context $KUBECTL_CONTEXT

    # add the rancher prime chart
    helm repo add rancher-prime https://charts.rancher.com/server-charts/prime
    helm repo add jetstack https://charts.jetstack.io
    helm repo update

    # install cert-manager
    helm install cert-manager jetstack/cert-manager \
        --namespace cert-manager \
        --create-namespace \
        --set crds.enabled=true

    sleep 15
    
    kubectl apply -f ${BASE_DIR}/k3s_issuer.yaml

    kubectl create ns cattle-system

    cat << EOF | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: rancher-ingress
  namespace: cattle-system 
spec:
  secretName: tls-rancher-ingress
  issuerRef:
    name: letsencrypt-k3s
    kind: ClusterIssuer
  commonName: "${RANCHER_SERVER_HOSTNAME}"
  dnsNames:
  - "${RANCHER_SERVER_HOSTNAME}"
EOF

    # install rancher prime

    # helm install rancher rancher-prime/rancher \
    #     --namespace cattle-system \
    #     --version ${RANCHER_CHART_VERSION} \
    #     --set hostname=${RANCHER_SERVER_HOSTNAME} \
    #     --set bootstrapPassword=admin \
    #     --set ingress.tls.source=letsEncrypt \
    #     --set replicas=1 \
    #     --set letsEncrypt.email=chris@pxbbq.com \
    #     --set letsEncrypt.ingress.class=traefik

    helm install rancher rancher-prime/rancher \
        --namespace cattle-system \
        --version ${RANCHER_CHART_VERSION} \
        --set hostname=${RANCHER_SERVER_HOSTNAME} \
        --set bootstrapPassword=admin \
        --set ingress.tls.source=secret \
        --set ingress.tls.secret=tls-rancher-ingress \
        --set replicas=1 

    # wait for the rancher server to start
    wait_ready_rancher
    sleep 10

    RANCHER_BOOTSTRAP_PASSWORD="admin"
    debug "RANCHER_BOOTSTRAP_PASSWORD: $RANCHER_BOOTSTRAP_PASSWORD"

    # Log in to rancher using the bootstrap password
    RANCHER_RESPONSE=`curl -s "${RANCHER_SERVER_URL}/v3-public/localProviders/local?action=login" -H 'content-type: application/json' --data-binary "{\"username\":\"admin\",\"password\":\"$RANCHER_BOOTSTRAP_PASSWORD\"}" --insecure`
    debug "RANCHER_RESPONSE: $RANCHER_RESPONSE"
    RANCHER_TOKEN=`echo $RANCHER_RESPONSE | jq -r .token`
    curl -s "${RANCHER_SERVER_URL}/v3/users?action=changepassword" -H 'content-type: application/json' -H "Authorization: Bearer $RANCHER_TOKEN" --data-binary "{\"currentPassword\":\"$RANCHER_BOOTSTRAP_PASSWORD\",\"newPassword\":\"$RANCHER_PASSWORD\"}" --insecure
 
}

delete_rancher () {
    kubectl config delete-context $KUBECTL_CONTEXT
    kubectl config delete-cluster $KUBECTL_CONTEXT
    kubectl config delete-user $KUBECTL_CONTEXT

    ${BASE_DIR}/newvm.sh delete --ip ${K3S_IP} --vmname ${K3S_SERVER_NAME}

}

login_rancher_server () {

    #requires_poolname
    RANCHER_RESPONSE=`curl -s "${RANCHER_SERVER_URL}/v3-public/localProviders/local?action=login" -H 'content-type: application/json' --data-binary "{\"username\":\"admin\",\"password\":\"$RANCHER_PASSWORD\"}" --insecure`
    export RANCHER_TOKEN=`echo $RANCHER_RESPONSE | jq -r .token`

    kubectl config set-credentials rancher --token ${RANCHER_TOKEN}

}

###### Script Run Section
#set -x
### Ensure we have an argument
if [[ $# -eq 0 ]]; then
  usage
  terminate "No arguments provided" ${ERR_NO_ARGS}
fi

### Parse the CLI arguments
while [[ ${1} != "" ]]; do
    case $1 in
        -h|--help)
            usage
            exit 0
        ;;
        -d|--debug)
            DEBUG=1
        ;;
        connect)
            COMMAND="kubectl_rancher_server"
        ;;
        login)
            COMMAND="login_rancher_server"
        ;;
        create_rancher)
            COMMAND="create_rancher"
        ;;
        delete_rancher)
            COMMAND="delete_rancher"
        ;;
        cleanup)
            COMMAND="kubectl_rancher_server_cleanup"
        ;;
        view)
            COMMAND="kubectl_view_configs"
        ;;
        env)
            COMMAND="env"
        ;;
        create)
            COMMAND="create_rancher_cluster"
        ;;
        list)
            COMMAND="list_rancher_clusters"
        ;;
        delete)
            COMMAND="delete_rancher_cluster"
        ;;
        create_context)
            COMMAND="create_context"
        ;;
        install_sealed_secrets)
            COMMAND="install_sealed_secrets"
        ;;
        install_argocd)
            COMMAND="install_argocd"
        ;;
        install_metallb)
            COMMAND="install_metallb"
        ;;
        install_minio)
            COMMAND="install_minio"
        ;;
        install_grafana)
            COMMAND="install_grafana"
        ;;
        configure_minio)
            COMMAND="configure_minio"
        ;;
        configure_pxbackup)
            COMMAND="configure_pxbackup"
        ;;
        install_portworx)
            COMMAND="install_portworx"
        ;;
        install_pxbackup)
            COMMAND="install_pxbackup"
        ;;
        install_lpp)
            COMMAND="install_lpp"
        ;;
        install_etcd)
            COMMAND="install_etcd"
        ;;
        install_pxbbq)
            COMMAND="install_pxbbq"
        ;;
        install_aidemo)
            COMMAND="install_aidemo"
        ;;
        install_pxbbq_taster)
            COMMAND="install_pxbbq_taster"
        ;;
        install_utilities)
            COMMAND="install_utilities"
        ;;
        px_clusterpair)
            COMMAND="px_clusterpair"
        ;;
        px_deleteclusterpair)
            COMMAND="px_deleteclusterpair"
        ;;
        install_demo)
            COMMAND="install_demo"
        ;;
        install_mvp)
            COMMAND="install_mvp"
        ;;
        install_demo_async)
            COMMAND="install_demo_async"
        ;;
        install_cluster)
            COMMAND="install_cluster"
        ;;
        reboot_cluster)
            COMMAND="reboot_cluster"
        ;;
        --disable-logs)
            DISABLE_LOGS=1
        ;;
        -v)
            VIEWENV=1
        ;;
        --context)
            shift
            CONTEXT=$1
            log "Setting context to ${CONTEXT}"
        ;;
        --pool | --cluster)
            shift
            POOL_NAME=$1
            log "Setting pool to ${POOL_NAME}"
        ;;
        --dr-pool)
            shift
            DR_POOL_NAME=$1
            log "Setting DR pool to ${DR_POOL_NAME}"
        ;;
        # Default case
        *)
        terminate "Unknown argument: $1" ${ERR_UNKNOWN_COMMAND}
        ;;
    esac
    shift
done

if [[ -z ${COMMAND} ]]; then
    terminate "No command provided" ${ERR_NO_ARGS}
fi

$COMMAND

exit 0
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




###### Main Functions

### This function will set up the rancher server context if it doesn't exist and switch to it. It should ALWAYS exist.
kubectl_rancher_server () {

    if kubectl config use-context ${KUBECTL_CONTEXT}; then
        log "${KUBECTL_CONTEXT} context already exists. Switching to it."
    else
        log "Creating ${KUBECTL_CONTEXT} context"
        kubectl config set-cluster ${KUBECTL_CONTEXT} --server=${RANCHER_SERVER_URL}
        kubectl config set-credentials ${KUBECTL_CONTEXT} --token=${BEARER_TOKEN}
        kubectl config set-context ${KUBECTL_CONTEXT} --cluster=rancher --user=rancher
        kubectl config use-context ${KUBECTL_CONTEXT}
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
    
    # Variable Substitution
    CONTROL_POOL=$(< ${CONTROL_POOL_TEMPLATE})
    debug "control pool: ${CONTROL_POOL}"
    debug "control pool template: ${CONTROL_POOL_TEMPLATE}"
    CONTROL_POOL="${CONTROL_POOL//${POOL_NAME_PLACEHOLDER}/${POOL_NAME}}"
    debug "new control pool: ${CONTROL_POOL}"

    WORKER_POOL=$(< ${WORKER_POOL_TEMPLATE})
    debug "worker pool: ${WORKER_POOL}"
    debug "worker pool template: ${WORKER_POOL_TEMPLATE}"
    WORKER_POOL="${WORKER_POOL//${POOL_NAME_PLACEHOLDER}/${POOL_NAME}}"
    debug "new worker pool: ${WORKER_POOL}"

    CLUSTER=$(< ${CLUSTER_TEMPLATE})
    CLUSTER="${CLUSTER//${POOL_NAME_PLACEHOLDER}/${POOL_NAME}}"

    kubectl apply -f <(echo "${CONTROL_POOL}")
    kubectl apply -f <(echo "${WORKER_POOL}")
    kubectl apply -f <(echo "${CLUSTER}")
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
    kubectl -n fleet-default delete VmwarevsphereConfig nc-${POOL_NAME}-control
    kubectl -n fleet-default delete VmwarevsphereConfig nc-${POOL_NAME}-worker

    kubectl config delete-context ${POOL_NAME}
    kubectl config delete-cluster ${POOL_NAME}

    # Need to clean up cloud drives
}

### Create a context for a cluster
create_context () {
    requires_poolname
    log "Creating a context for ${POOL_NAME}"
    CONTEXT_URL="$(kubectl --context ${KUBECTL_CONTEXT} config view --flatten --minify | yq -r .clusters[0].cluster.server)/k8s/clusters/$(kubectl --context ${KUBECTL_CONTEXT} -n fleet-default get clusters.provisioning.cattle.io ${POOL_NAME} -o yaml | yq -r .status.clusterName)"
    kubectl config set-cluster ${POOL_NAME} --server=${CONTEXT_URL}
    kubectl config set-context ${POOL_NAME} --cluster=${POOL_NAME} --user=${KUBECTL_CONTEXT}
    kubectl config use-context ${POOL_NAME} || terminate "Could not switch to ${POOL_NAME}" ${ERR_POOL_NOT_FOUND}
}

### Install Sealed Secrets
install_sealed_secrets () {
    kubectl config use-context ${POOL_NAME} || terminate "Could not switch to ${POOL_NAME}" ${ERR_POOL_NOT_FOUND}
    requires_poolname
    log "Installing sealed secrets to ${POOL_NAME}"
    helm repo add sealed-secrets https://bitnami-labs.github.io/sealed-secrets
    helm repo update
    helm install sealed-secrets sealed-secrets/sealed-secrets -n kube-system
    sleep 10
    # Sealed secret substitution
    SEALED_SECRET=$(< ${SEALED_SECRET_TEMPLATE})
    SEALED_SECRET="${SEALED_SECRET//${TLS_CERT_PLACEHOLDER}/${SEALED_SECRET_TLS_CERT}}"
    SEALED_SECRET="${SEALED_SECRET//${TLS_KEY_PLACEHOLDER}/${SEALED_SECRET_TLS_KEY}}"
    kubectl apply -f <(echo "${SEALED_SECRET}")
    kubectl delete pod -n kube-system -l app.kubernetes.io/name=sealed-secrets

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
    --set persistence.storageClass=px-csi-db \
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
    helm install px-central portworx/px-central --namespace central --create-namespace --version ${PXBACKUP_VERSION} --set persistentStorage.enabled=true,persistentStorage.storageClassName="px-csi-db",pxbackup.enabled=true,oidc.centralOIDC.updateAdminProfile=false

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
    px_clusterpair

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

log "Ending ${SCRIPT_NAME}"
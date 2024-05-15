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
# - [ ] 


### What I know is missing:
# - TEMPLATE cloneFrom is hardcoded

### Configuration Section

# BEARER_TOKEN is the token that will be used to authenticate to the Rancher API
# SEALED_SECRET_TLS_CERT and SEALED_SECRET_TLS_KEY are used for bitnomi's sealed secrets

SCRIPT_NAME=$(basename $0)
BASE_DIR=/home/ccrow/personal/homelab/rancher
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
    create                  Create a new cluster
    delete                  Delete a cluster
    create_context          Create a context for a cluster. Uses --pool to specify the cluster and --context to specify the context used to pull the server info
    install_sealed_secrets  Install sealed secrets to the cluster
    install_argocd          Install ArgoCD to the cluster
    install_metallb         Install MetalLB to the cluster
    install_portworx        Install Portworx to the cluster
    install_minio           Install Minio to the cluster
    install_utilities       Install binary utilities to the current host. Requires BINARY_DIR is set

Options:
    -h, --help              Display this help message
    -d, --debug             Enable debug output
    --disable-logs          Disable logging
    --context               The context to use for some kubectl command
    --pool                  specific the pool name. 

Examples:
    ${SCRIPT_NAME}          connect
    ${SCRIPT_NAME}          cleanup

Helpful notes:
    You can seal an existing secret with: kubeseal --format=yaml < secret.yaml > sealed-secret.yaml

USAGE
}

### requires_poolname
requires_poolname () {
    if [[ -z ${POOL_NAME} ]]; then
        terminate "Pool name is required for this command" ${ERR_NO_ARGS}
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
    CONTROL_POOL="${CONTROL_POOL//${POOL_NAME_PLACEHOLDER}/${POOL_NAME}}"

    WORKER_POOL_TEMPLATE=$(< ${WORKER_POOL_TEMPLATE})
    WORKER_POOL_TEMPLATE="${WORKER_POOL_TEMPLATE//${POOL_NAME_PLACEHOLDER}/${POOL_NAME}}"

    CLUSTER=$(< ${CLUSTER_TEMPLATE})
    CLUSTER="${CLUSTER//${POOL_NAME_PLACEHOLDER}/${POOL_NAME}}"

    kubectl apply -f <(echo "${CONTROL_POOL}")
    kubectl apply -f <(echo "${WORKER_POOL_TEMPLATE}")
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
}

### Create a context for a cluster
create_context () {
    requires_poolname
    log "Creating a context for ${POOL_NAME}"
    CONTEXT_URL="$(kubectl --context ${KUBECTL_CONTEXT} config view --flatten --minify | yq .clusters[0].cluster.server)/k8s/clusters/$(kubectl --context ${KUBECTL_CONTEXT} -n fleet-default get clusters.provisioning.cattle.io ${POOL_NAME} -o yaml | yq .status.clusterName)"
    kubectl config set-cluster ${POOL_NAME} --server=${CONTEXT_URL}
    kubectl config set-context ${POOL_NAME} --cluster=${POOL_NAME} --user=${KUBECTL_CONTEXT}
}

### Install Sealed Secrets
install_sealed_secrets () {
    requires_poolname
    log "Installing sealed secrets to ${POOL_NAME}"
    
    kubectl config use-context ${POOL_NAME} || terminate "Could not switch to ${POOL_NAME}" ${ERR_POOL_NOT_FOUND}
    helm repo add sealed-secrets https://bitnami-labs.github.io/sealed-secrets
    helm repo update
    helm install sealed-secrets sealed-secrets/sealed-secrets -n kube-system

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

    requires_poolname
    requires_argocd

    log "Installing MetalLB to ${POOL_NAME}"
    kubectl config use-context ${POOL_NAME} || terminate "Could not switch to ${POOL_NAME}"
    
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


}

### Install PX Operator
install_px_operator () {

    requires_poolname
    requires_argocd

    log "Installing MetalLB to ${POOL_NAME}"
    kubectl config use-context ${POOL_NAME} || terminate "Could not switch to ${POOL_NAME}"
    
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
}

### Install PX Operator
install_px_ent () {

    requires_poolname
    requires_argocd

    log "Installing MetalLB to ${POOL_NAME}"
    kubectl config use-context ${POOL_NAME} || terminate "Could not switch to ${POOL_NAME}"
    
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
}

install_minio () {
    requires_poolname
    requires_argocd

    log "Installing minio to ${POOL_NAME}"
    kubectl config use-context ${POOL_NAME} || terminate "Could not switch to ${POOL_NAME}"

    # ArgoCD Variables
    ARGOCD_APPNAME="minio"
    ARGOCD_NAMESPACE="minio"

    # Must point to a values file
    ARGOCD_VALUE_FILES="\$values/${ARGOCD_HELM_VALUES_ROOT}/minio/${POOL_NAME}/values.yaml"
    ARGOCD_REPO_URL="${ARGOCD_REPO_URL}"

    # Helm specific options
    ARGOCD_HELM_REPO="https://charts.min.io/"
    ARGOCD_HELM_CHART_VERSION="5.2.0"
    ARGOCD_HELM_CHART="minio"

    # Apply Application
    ARGOAPP=$(< ${ARGOCD_HELM_APP_TEMPLATE})
    ARGOAPP="${ARGOAPP//${ARGOCD_NAMESPACE_PLACEHOLDER}/${ARGOCD_NAMESPACE}}"
    ARGOAPP="${ARGOAPP//${ARGOCD_APP_NAME_PLACEHOLDER}/${ARGOCD_APPNAME}}"
    ARGOAPP="${ARGOAPP//${ARGOCD_REPO_URL_PLACEHOLDER}/${ARGOCD_REPO_URL}}"
    ARGOAPP="${ARGOAPP//${ARGOCD_HELM_VALUE_FILES_PLACEHOLDER}/${ARGOCD_VALUE_FILES}}"
    ARGOAPP="${ARGOAPP//${ARGOCD_HELM_REPO_URL_PLACEHOLDER}/${ARGOCD_HELM_REPO}}"
    ARGOAPP="${ARGOAPP//${ARGOCD_HELM_CHART_PLACEHOLDER}/${ARGOCD_HELM_CHART}}"
    ARGOAPP="${ARGOAPP//${ARGOCD_HELM_TARGET_PLACEHOLDER}/${ARGOCD_HELM_CHART_VERSION}}"
    #kubectl apply -f <(echo "${ARGOAPP}")
    echo "${ARGOAPP}"
    log "${ARGOCD_VALUE_FILES}"
}


#     log "Installing Minio to ${POOL_NAME}"
#     kubectl config use-context ${POOL_NAME} || terminate "Could not switch to ${POOL_NAME}"

#     helm repo add minio https://charts.min.io/ && helm repo update

#     helm install minio \
#         --set mode=standalone \
#         --set persistence.storageClass=px-csi-db \
#         --set persistence.size=10Gi \
#         --set resources.requests.memory=1Gi \
#         --set service.type=LoadBalancer \
#         --namespace minio \
#         --create-namespace \
#         minio/minio

#     ip_regex='^([0-9]{1,3}\.){3}[0-9]{1,3}$'
#     until [[ $(kubectl -n minio get svc minio -o json | jq -cr '.status.loadBalancer.ingress[0].ip') =~ $ip_regex ]]; do 
#         echo "Waiting for IP to be provisioned..."
#         sleep 5
#     done

#     until [[ $(kubectl -n minio get deployments.apps minio -o json | jq -r '.status.readyReplicas') -le 2 ]]; do
#         log "Waiting for Minio to be ready..."
#         sleep 5
#     done
# }

configure_minio () {
    requires_mc
    log "Configuring Minio"
    kubectl config use-context ${POOL_NAME} || terminate "Could not switch to ${POOL_NAME}"

    MINIO_ENDPOINT=http://$(kubectl get svc -n minio minio -o jsonpath='{.status.loadBalancer.ingress[].ip}'):9000
    MINIO_ACCESS_KEY=$(kubectl get secret -n minio minio -o jsonpath="{.data.rootUser}" | base64 --decode)
    MINIO_SECRET_KEY=$(kubectl get secret -n minio minio -o jsonpath="{.data.rootPassword}" | base64 --decode)

    mc alias set ${POOL_NAME} $MINIO_ENDPOINT $MINIO_ACCESS_KEY $MINIO_SECRET_KEY
    mc mb ${POOL_NAME}/${BUCKET_NAME}
    mc mb ${POOL_NAME}/${BUCKET_NAME}-objectlock --with-lock
    mc retention set --default COMPLIANCE 7d ${POOL_NAME}/${POOL_NAME}${BUCKETNAME_PATTERN}-objectlock

}

# Install binary utilities locally
install_utilities () {
    requires_portworx
    kubectl config use-context ${POOL_NAME} || terminate "Could not switch to ${POOL_NAME}"

    log "Installing utilities to ${BINARY_DIR}"

    log "Installing storkctl to ${BINARY_DIR}"

    STORK_POD=$(kubectl get pods -n portworx -l name=stork -o jsonpath='{.items[0].metadata.name}')
    kubectl cp -n portworx $STORK_POD:storkctl/linux/storkctl ${BINARY_DIR}/storkctl  --retries=10
    chmod +x ${BINARY_DIR}/storkctl

    log "Installing mc to ${BINARY_DIR}"
    wget -q -O ${BINARY_DIR}/mc https://dl.minio.io/client/mc/release/linux-amd64/mc
    chmod +x ${BINARY_DIR}/mc

}


### Output Variables for environment
env () {
    requires_poolname
    kubectl config use-context ${POOL_NAME} || terminate "Could not switch to ${POOL_NAME}"
    log "Exporting environment variables"
    export MINIO_ACCESS_KEY=$(kubectl get secret -n minio minio -o jsonpath="{.data.rootUser}" | base64 --decode)
    export MINIO_SECRET_KEY=$(kubectl get secret -n minio minio -o jsonpath="{.data.rootPassword}" | base64 --decode)
    export MINIO_ENDPOINT=http://$(kubectl get svc -n minio minio -o jsonpath='{.status.loadBalancer.ingress[].ip}'):9000
    export MINIO_BUCKET=${BUCKET_NAME}
    export MINIO_BUCKET_OBJECTLOCK=${BUCKET_NAME}-objectlock
    
    log "Paste the following in to .bashrc"
    echo "export MINIO_ENDPOINT=${MINIO_ENDPOINT}"
    echo "export MINIO_ACCESS_KEY=${MINIO_ACCESS_KEY}"
    echo "export MINIO_SECRET_KEY=${MINIO_SECRET_KEY}"
    echo "export MINIO_BUCKET=${MINIO_BUCKET}"
    echo "export MINIO_BUCKET_OBJECTLOCK=${MINIO_BUCKET_OBJECTLOCK}"

}

### Meta Commands
# These commands will call other commands for workflows

install_portworx () {
    install_px_operator
    install_px_ent
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
        install_portworx)
            COMMAND="install_portworx"
        ;;
        install_utilities)
            COMMAND="install_utilities"
        ;;
        --disable-logs)
            DISABLE_LOGS=1
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
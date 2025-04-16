#!/usr/bin/env bash

# !!!! IMPORTANT !!!!
# You need to set some env vars manually for some script functions to work!
# BEARER_TOKEN is used 
# SEALED_SECRET_TLS_CERT and SEALED_SECRET_TLS_KEY are used for bitnomi's sealed secrets installation. 
# Should be populated with the hashed value 


# Environment variables to set other fuctions
# DEBUG - set to 1 to enable debug output

### Standard Error Codes
readonly ERR_CONF_FILE_NOT_FOUND=160
readonly ERR_DEFAULT_ERROR=1
readonly ERR_NO_ARGS=161
readonly ERR_UNKNOWN_COMMAND=162
readonly ERR_POOL_NOT_FOUND=163
readonly ERR_ARGOCD_NOT_INSTALLED=164
readonly ERR_PORTWORX_NOT_INSTALLED=165
readonly ERR_UTILITY_NOT_INSTALLED=166
readonly ERR_MINIO_NOT_INSTALLED=167
readonly ERR_LPP_NOT_INSTALLED=168
readonly ERR_PXBACKUP_NOT_INSTALLED=169

### Placeholders
# These placeholders appear in the TEMPLATE* files and should probably not be changed
readonly POOL_NAME_PLACEHOLDER="POOL_NAME_PLACEHOLDER"
readonly TLS_CERT_PLACEHOLDER="TLS_CERT_PLACEHOLDER"
readonly TLS_KEY_PLACEHOLDER="TLS_KEY_PLACEHOLDER"

readonly ARGOCD_NAMESPACE_PLACEHOLDER="ARGOCD_NAMESPACE_PLACEHOLDER"
readonly ARGOCD_APP_NAME_PLACEHOLDER="ARGOCD_APP_NAME_PLACEHOLDER"
readonly ARGOCD_REPO_URL_PLACEHOLDER="ARGOCD_REPO_URL_PLACEHOLDER"
readonly ARGOCD_REPO_PATH_PLACEHOLDER="ARGOCD_REPO_PATH_PLACEHOLDER"
readonly ARGOCD_HELM_REPO_URL_PLACEHOLDER="ARGOCD_HELM_REPO_URL_PLACEHOLDER"
readonly ARGOCD_HELM_CHART_PLACEHOLDER="ARGOCD_HELM_CHART_PLACEHOLDER"
readonly ARGOCD_HELM_TARGET_PLACEHOLDER="ARGOCD_HELM_TARGET_PLACEHOLDER"
readonly ARGOCD_HELM_VALUE_FILES_PLACEHOLDER="ARGOCD_HELM_VALUE_FILES_PLACEHOLDER"



### Environment Variables
BASE_DIR=/home/ccrow/personal/homelab/rancher
MANIFEST_LOCAL_DIR=/home/ccrow/personal/homelab/manifests
CONFIG_FILE="${BASE_DIR}/rancher_conf.sh"

# Used to store binary utilies
BINARY_DIR="/home/ccrow/bin"

TEMP_DIR=${BASE_DIR}

### Templates we use
HOST_KUBEVIRT_CONTEXT="gentoo"
RANCHER_SERVER_URL="https://rancher.pxbbq.com"
RANCHER_SERVER_IP="10.0.5.10"
K3S_IP="10.0.5.10"
CONTROL_POOL_TEMPLATE="${BASE_DIR}/TEMPLATE-controlpool.yaml"
WORKER_POOL_TEMPLATE="${BASE_DIR}/TEMPLATE-workerpool.yaml"
CLUSTER_TEMPLATE="${BASE_DIR}/TEMPLATE-cluster.yaml"
SEALED_SECRET_TEMPLATE="${BASE_DIR}/TEMPLATE-sealedsecret.yaml"
ARGOCD_APP_TEMPLATE="${BASE_DIR}/TEMPLATE-argocdapp.yaml"
ARGOCD_HELM_APP_TEMPLATE="${BASE_DIR}/TEMPLATE-argocdapp-helm.yaml"

### ArgoCD URLs
# Example paths: ${ARGOCD_REPO_URL}/${ARGOCD_PATH_ROOT}/ovarlays/${POOL_NAME}
# ${ARGOCD_REPO_URL}/${ARGOCD_HELM_VALUES_ROOT}/${POOL_NAME}/values.yaml
ARGOCD_REPO_URL="https://github.com/ccrow42/homelab"
ARGOCD_PATH_ROOT="manifests"
ARGOCD_HELM_VALUES_ROOT="manifests"

### Defaults
# These vars can be overridden by the script
KUBECTL_CONTEXT="k3s"
K3S_CONTEXT="k3s"
POOL_NAME=""
BUCKET_NAME="bucket"
S3_REGION="us-west-2"
# should be set to --disable-ssl if you are using http, otherwise NULL
DISABLE_SSL="--disable-ssl"

### Versions
PXBACKUP_VERSION=${PXBACKUP_VERSION:-2.7.0}
# We are using customize here
#PORTWORX_VERSION=${PORTWORK_VERSION:-3.1}
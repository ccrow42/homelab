#!/usr/bin/env bash

# BEARER_TOKEN is the token that will be used to authenticate to the Rancher API
# SEALED_SECRET_TLS_CERT and SEALED_SECRET_TLS_KEY are used for bitnomi's sealed secrets


# Environment variables to set other fuctions
# DEBUG - set to 1 to enable debug output

### Standard Error Codes
readonly ERR_CONF_FILE_NOT_FOUND=160
readonly ERR_DEFAULT_ERROR=1
readonly ERR_NO_ARGS=161
readonly ERR_UNKNOWN_COMMAND=162
readonly ERR_POOL_NOT_FOUND=163
readonly ERR_ARGOCD_NOT_INSTALLED=164

### Placeholders
# These placeholders appear in the TEMPLATE* files and should probably not be changed
readonly POOL_NAME_PLACEHOLDER="POOL_NAME_PLACEHOLDER"
readonly TLS_CERT_PLACEHOLDER="TLS_CERT_PLACEHOLDER"
readonly TLS_KEY_PLACEHOLDER="TLS_KEY_PLACEHOLDER"
readonly ARGOCD_NAMESPACE_PLACEHOLDER="ARGOCD_NAMESPACE_PLACEHOLDER"
readonly ARGOCD_APP_NAME_PLACEHOLDER="ARGOCD_APP_NAME_PLACEHOLDER"
readonly ARGOCD_REPO_URL_PLACEHOLDER="ARGOCD_REPO_URL_PLACEHOLDER"
readonly ARGOCD_REPO_PATH_PLACEHOLDER="ARGOCD_REPO_PATH_PLACEHOLDER"


### Environment Variables
BASE_DIR=/home/ccrow/personal/homelab/rancher
CONFIG_FILE="${BASE_DIR}/rancher_conf.sh"

### Templates we use
RANCHER_SERVER_URL="https://rancher.lan.ccrow.org"
CONTROL_POOL_TEMPLATE="${BASE_DIR}/TEMPLATE-controlpool.yaml"
WORKER_POOL_TEMPLATE="${BASE_DIR}/TEMPLATE-workerpool.yaml"
CLUSTER_TEMPLATE="${BASE_DIR}/TEMPLATE-cluster.yaml"
SEALED_SECRET_TEMPLATE="${BASE_DIR}/TEMPLATE-sealedsecret.yaml"
ARGOCD_APP_TEMPLATE="${BASE_DIR}/TEMPLATE-argocdapp.yaml"

### ArgoCD URLs
ARGOCD_REPO_URL="https://github.com/ccrow42/homelab"
ARGOCD_PATH_ROOT="manifests"

### Defaults
# These vars can be overridden by the script
KUBECTL_CONTEXT="rancher"
POOL_NAME=""
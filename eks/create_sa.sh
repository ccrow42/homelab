
    local context=$1  # The kubeconfig context (e.g., cluster1, cluster2)
    local cluster_name=$2  # The GKE cluster name passed as parameter
    local zone=$3  # The GKE zone passed as parameter
    local sa_name="dr-sa"
    local namespace="portworx"
    local clusterrolebinding_name="${sa_name}-cluster-admin-binding"
    local kubeconfig_file="${sa_name}-kubeconfig-${context}"
    local token_expiration_seconds=$((2 * 24 * 3600))  # 2 days expiration (48 hours)

    echo "Switching to context: $context"
    kubectl config use-context $context

    # Step 1: Create Service Account (ignore error if it already exists)
    echo "Creating service account $sa_name in namespace $namespace"
    kubectl create serviceaccount $sa_name -n $namespace || echo "Service account $sa_name already exists"

    # Step 2: Grant cluster-admin permissions to the service account (ignore error if it already exists)
    echo "Assigning cluster-admin permissions to $sa_name"
    kubectl create clusterrolebinding $clusterrolebinding_name \
      --clusterrole=cluster-admin \
      --serviceaccount=$namespace:$sa_name || echo "ClusterRoleBinding $clusterrolebinding_name already exists"

    # Step 3: Generate a Token Request for the service account
    echo "Generating token with expiration"
    TOKEN=$(kubectl create token $sa_name -n $namespace --duration=${token_expiration_seconds}s)

    # Step 4: Get the API server URL using gcloud
    echo "Fetching API server URL using gcloud for cluster: $cluster_name in zone: $zone"
    SERVER_URL=$(gcloud container clusters describe $cluster_name \
        --zone=$zone \
        --format="value(endpoint)")

    # Add the protocol to the SERVER_URL
    SERVER_URL="https://$SERVER_URL"

    # Escape the slashes in SERVER_URL for sed
    ESCAPED_SERVER_URL=$(echo "$SERVER_URL" | sed 's/\//\\\//g')

    # Step 5: Use gcloud to retrieve the CA certificate for the GKE cluster
    echo "Fetching CA certificate using gcloud for cluster: $cluster_name in zone: $zone"
    GKE_CA_CERT=$(gcloud container clusters describe $cluster_name \
        --zone=$zone \
        --format="value(masterAuth.clusterCaCertificate)")

    # Step 6: Create the kubeconfig file
    echo "Creating kubeconfig file for $sa_name"

    # Configure the cluster without the CA certificate, we'll add it manually later
    kubectl config set-cluster kubernetes \
      --server=$SERVER_URL \
      --kubeconfig=$kubeconfig_file

    # Set the credentials using the token
    kubectl config set-credentials $sa_name \
      --token=$TOKEN \
      --kubeconfig=$kubeconfig_file

    # Set the context for the service account
    kubectl config set-context ${sa_name}-context \
      --cluster=kubernetes \
      --user=$sa_name \
      --namespace=$namespace \
      --kubeconfig=$kubeconfig_file

    # Use the context
    kubectl config use-context ${sa_name}-context --kubeconfig=$kubeconfig_file

    # Step 7: Embed the GKE CA certificate into the kubeconfig
    echo "Embedding CA certificate into kubeconfig"

    # Use sed with escaped server URL to append certificate-authority-data
    sed -i "/server: $ESCAPED_SERVER_URL/a\ \ \ \ certificate-authority-data: $GKE_CA_CERT" $kubeconfig_file

    echo "Kubeconfig for $sa_name created: $kubeconfig_file"

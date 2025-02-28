kubectl apply -f 'https://install.portworx.com/3.2?comp=pxoperator&kbver=1.30.8&ns=portworx'

cat << EOF | kubectl apply -f -
# SOURCE: https://install.portworx.com/?operator=true&mc=false&kbver=1.30.8&ns=portworx&b=true&iop=6&mz=3&s=%22type%3Dgp3%2Csize%3D50%22%2C%22type%3Dgp3%2Csize%3D50%22%2C%22type%3Dgp3%2Csize%3D50%22%2C%22type%3Dgp3%2Csize%3D50%22&ce=aws&c=px-cluster-ab477e00-31b8-498b-a149-16374f9b216d&eks=true&stork=true&csi=true&mon=true&tel=true&st=k8s&promop=true
kind: StorageCluster
apiVersion: core.libopenstorage.org/v1
metadata:
  name: px-cluster-ab477e00-31b8-498b-a149-16374f9b216d
  namespace: portworx
  annotations:
    portworx.io/service-type: "portworx-api:LoadBalancer"
    portworx.io/install-source: "https://install.portworx.com/?operator=true&mc=false&kbver=1.30.8&ns=portworx&b=true&iop=6&mz=3&s=%22type%3Dgp3%2Csize%3D50%22%2C%22type%3Dgp3%2Csize%3D50%22%2C%22type%3Dgp3%2Csize%3D50%22%2C%22type%3Dgp3%2Csize%3D50%22&ce=aws&c=px-cluster-ab477e00-31b8-498b-a149-16374f9b216d&eks=true&stork=true&csi=true&mon=true&tel=true&st=k8s&promop=true"
    portworx.io/is-eks: "true"
spec:
  image: portworx/oci-monitor:3.2.1.2
  imagePullPolicy: Always
  kvdb:
    internal: true
  cloudStorage:
    deviceSpecs:
    - type=gp3,size=50
    maxStorageNodesPerZone: 3
  secretsProvider: k8s
  stork:
    enabled: true
    args:
      admin-namespace: "portworx"
      webhook-controller: "true"
  autopilot:
    enabled: true
  runtimeOptions:
    default-io-profile: "6"
  csi:
    enabled: true
  monitoring:
    telemetry:
      enabled: false
    prometheus:
      enabled: true
      exportMetrics: true
  env:
EOF

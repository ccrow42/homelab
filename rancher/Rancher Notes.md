
Discord: https://discord.gg/pU826VPu 

Join Zoom Meeting [https://purestorage.zoom.us/j/96330502638?pwd=WjVwbHhsT1dZSlFjclYvOHQ5aVN0QT09](https://purestorage.zoom.us/j/96330502638?pwd=WjVwbHhsT1dZSlFjclYvOHQ5aVN0QT09)

- Rancher Server vs RKE2
- a word on authentication
	- example ArgoCD


State of the lab
- Rancher1 -
- Rancher2 -
- Rancher3 - Manual  Complete
- Rancher4 - Custom Complete



### The Manual Way


Build a new ubuntu server and run the following on it:

***For a cluster with multiple hosts***:
/etc/rancher/rke2/config.yaml
```yaml
token: RancherReddit
tls-san:
 - rancher.ccrow.org
 - rancher.lab.local

```


```bash
# Update and reboot our server
sudo apt update
sudo apt upgrade -y
reboot

# install git
sudo apt install git

# install kubectl 
sudo snap install kubectl --classic
```

**For a control-plane nodes**
```bash
sudo curl -sfL https://get.rke2.io |sudo  INSTALL_RKE2_CHANNEL=v1.27 sh -
###
###
sudo systemctl enable rke2-server.service
sudo systemctl start rke2-server.service
```


**For worker nodes
```bash
sudo curl -sfL https://get.rke2.io |sudo  INSTALL_RKE2_CHANNEL=v1.27 INSTALL_RKE2_TYPE="agent" sh -
###
###
sudo systemctl enable rke2-agent.service
sudo systemctl start rke2-agent.service
```

```bash
# Snag the configuration file
mkdir .kube
sudo cp /etc/rancher/rke2/rke2.yaml ~/.kube/config
sudo chown ubuntu:ubuntu .kube -R
```

### The Rancher Server Way


```bash
docker run -d --restart=unless-stopped \
--name rancher \
-p 8081:80 -p 8443:443 \
--privileged \
-v /home/ubuntu/rancher:/var/lib/rancher \
rancher/rancher:v2.9-head
```


#### Provisioning a cluster with a cloud init image

Prereqs: Ensure that you have DHCP and that DNS gets updated (PIHole will do this)

https://help.ubuntu.com/community/CloudInit

Import the image in to vSphere

- Create cloud credentials
- Create a cluster



#### Provision a cluster manually

Build out any number of VMs.

Create a cluster in rancher server of other and bootstrap the cluster.


#### kubectl API basics

```bash
export SERVER_URL="https://10.0.1.148:8443"
```
```bash
export API_KEY="token-msbwt:manymanycharactersinthistoken"
```

```bash
cat <<EOF > kubeconfig.yaml
apiVersion: v1
kind: Config
clusters:
- name: "rancher"
  cluster:
    server: "$SERVER_URL"
    insecure-skip-tls-verify: true

users:
- name: "rancher"
  user:
    token: "$API_KEY"

contexts:
- name: "rancher"
  context:
    user: "rancher"
    cluster: "rancher"

current-context: "rancher"
EOF
```

Create a context for a newly created cluster
```bash
export PRODURL="$(k --context rancher-insecure config view --flatten --minify | yq .clusters[0].cluster.server)/k8s/clusters/$(k --context rancher-insecure -n fleet-default get cluster prod -o yaml | yq .status.clusterName)"

k config set-context prod-insecure
k config use-context prod-insecure
k config set-cluster prod-insecure --server $PRODURL --insecure-skip-tls-verify
k config set-context prod-insecure --cluster prod-insecure --user rancher
```


# AKS Nginx demo

An image based on `nginx:latest` serves **Hello from Azure AKS!** on port 80.
The page is copied into the image during build, not mounted at runtime.
The Deployment requests one replica on the existing AKS Spot worker pool;
no Service or Ingress is created.

```text
index.html -> Docker build -> ACR -> AKS Spot pod
                                      ^
Browser -> localhost:8080 -> kubectl port-forward
```

- `Dockerfile` packages `index.html` in the standard Nginx web root.
- `deployment.yaml` selects Linux Spot nodes and tolerates their `NoSchedule` taint.

## Prerequisites

Run the Bash commands below from the repository root. Install Docker,
Azure CLI, OpenTofu, kubectl, and kubelogin, and sign in with `az login`.
The infrastructure must already be applied with ACR, AKS, and the Spot worker
pool enabled. Your Azure identity needs ACR push permissions and AKS access
with permission to manage Deployments and port-forward pods.
AKS also needs `AcrPull` for its kubelet identity; the existing container-registry
module configures this when its AKS pull-role assignment is enabled.

Spot nodes can be evicted or unavailable. With only one desired replica, the
demo can be interrupted or remain Pending until Spot capacity is available.

## Build and push

Use the existing OpenTofu outputs to identify the registry and cluster:

```bash
set -euo pipefail

ACR_NAME="$(tofu -chdir=tf output -raw container_registry_name)"
ACR_LOGIN_SERVER="$(tofu -chdir=tf output -raw container_registry_login_server)"
RESOURCE_GROUP="$(tofu -chdir=tf output -raw resource_group_name)"
AKS_NAME="$(tofu -chdir=tf output -raw kubernetes_cluster_name)"
IMAGE="${ACR_LOGIN_SERVER}/aks-demo:v1"

az acr login --name "$ACR_NAME"
docker build --pull --platform linux/amd64 --tag "$IMAGE" ./apps/demo-app
docker push "$IMAGE"
```

`--pull` refreshes the mutable `nginx:latest` base image at build time.
The resulting application image uses a separate versioned tag, `v1`.
Use a new application tag for subsequent releases and update the Deployment
image accordingly. The build targets the existing x86-64 AKS node sizes.

## Deploy and access

Continue in the same shell. Render the registry placeholder without modifying
the source manifest:

```bash
az aks get-credentials --resource-group "$RESOURCE_GROUP" --name "$AKS_NAME"
kubelogin convert-kubeconfig -l azurecli

sed "s|<acr-login-server>|${ACR_LOGIN_SERVER}|g" apps/demo-app/deployment.yaml \
  | kubectl apply --namespace default -f -
kubectl rollout status --namespace default deployment/aks-demo --timeout=180s
kubectl port-forward --namespace default deployment/aks-demo 8080:80
```

Open <http://localhost:8080> or run `curl http://localhost:8080` in another
terminal. Nginx serves the page embedded in the image. Port-forward binds to
localhost by default and requires no Kubernetes Service or public endpoint.
Stop it with Ctrl+C; restart it if the selected pod is replaced.

## Cleanup

```bash
kubectl delete deployment aks-demo --namespace default
```

This removes the demo workload, not the ACR image or Azure infrastructure.

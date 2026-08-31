#!/bin/bash

# ==============================================================================
# GSP1242 Rapid Setup Script (Tasks 1-4)
# ==============================================================================
# This script automates the setup for GKE Service Mesh lab GSP1242.
# It adheres to the safety protocols established for this environment.
# ==============================================================================

set -e

# --- Configuration ---
export PROJECT_ID=$(gcloud config get-value project)
# Automatically detect region and zone if not set
export REGION=${REGION:-$(gcloud compute project-info describe --format='value(commonInstanceMetadata.items.google-compute-default-region)')}
export ZONE=${ZONE:-$(gcloud compute project-info describe --format='value(commonInstanceMetadata.items.google-compute-default-zone)')}

echo "Starting setup for project: $PROJECT_ID in $ZONE"

# --- Task 1: Enable APIs ---
echo "[Task 1] Enabling APIs..."
gcloud services enable \
    container.googleapis.com \
    mesh.googleapis.com \
    gkehub.googleapis.com \
    multiclusteringress.googleapis.com \
    multiclusterservicediscovery.googleapis.com
gcloud container fleet mesh enable

# --- Task 2: Create Networking & Clusters ---
echo "[Task 2] Preparing networking..."
gcloud compute addresses create ${REGION}-nat-ip --region=${REGION} --quiet || true
export NAT_IP=$(gcloud compute addresses describe ${REGION}-nat-ip --region=${REGION} --format='value(address)')
export NAT_NAME=$(gcloud compute addresses describe ${REGION}-nat-ip --region=${REGION} --format='value(name)')

gcloud compute routers create rtr-${REGION} --network=default --region=${REGION} --quiet || true
gcloud compute routers nats create nat-gw-${REGION} \
    --router=rtr-${REGION} \
    --region=${REGION} \
    --nat-external-ip-pool=${NAT_NAME} \
    --nat-all-subnet-ip-ranges \
    --enable-logging --quiet || true

gcloud compute firewall-rules create all-pods-and-master-ipv4-cidrs \
    --network default --allow all --direction INGRESS \
    --source-ranges 172.16.0.0/28,172.16.1.0/28,172.16.2.0/28,0.0.0.0/0 --quiet || true

export CLOUDSHELL_IP=$(dig +short myip.opendns.com @resolver1.opendns.com)
export LAB_VM_IP=$(gcloud compute instances describe lab-setup --format='get(networkInterfaces[0].accessConfigs[0].natIP)' --zone=${ZONE})

echo "[Task 2] Creating Cluster 1 (Async)..."
gcloud container clusters create cluster1 \
    --zone=${ZONE} --machine-type "e2-standard-4" \
    --num-nodes "2" --enable-ip-alias --enable-autoscaling \
    --workload-pool=${PROJECT_ID}.svc.id.goog \
    --enable-private-nodes --master-ipv4-cidr=172.16.0.0/28 \
    --enable-master-authorized-networks \
    --master-authorized-networks ${NAT_IP}/32,${CLOUDSHELL_IP}/32,${LAB_VM_IP}/32 --async

echo "[Task 2] Creating Cluster 2..."
gcloud container clusters create cluster2 \
    --zone=${ZONE} --machine-type "e2-standard-4" \
    --num-nodes "2" --enable-ip-alias --enable-autoscaling \
    --workload-pool=${PROJECT_ID}.svc.id.goog \
    --enable-private-nodes --master-ipv4-cidr=172.16.1.0/28 \
    --enable-master-authorized-networks \
    --master-authorized-networks ${NAT_IP}/32,${CLOUDSHELL_IP}/32,${LAB_VM_IP}/32

echo "Waiting for Cluster 1 to be ready..."
gcloud container clusters list

# --- Task 2.4-7: Kubeconfig & Registration ---
echo "[Task 2] Configuring kubeconfig and Fleet registration..."
touch ~/asm-kubeconfig
export KUBECONFIG=~/asm-kubeconfig

gcloud container clusters get-credentials cluster1 --zone ${ZONE}
gcloud container clusters get-credentials cluster2 --zone ${ZONE}

kubectl config rename-context gke_${PROJECT_ID}_${ZONE}_cluster1 cluster1 || true
kubectl config rename-context gke_${PROJECT_ID}_${ZONE}_cluster2 cluster2 || true

gcloud container fleet memberships register cluster1 --gke-cluster=${ZONE}/cluster1 --enable-workload-identity --quiet || true
gcloud container fleet memberships register cluster2 --gke-cluster=${ZONE}/cluster2 --enable-workload-identity --quiet || true

# --- Multi-Cluster Features ---
echo "Enabling Multi-Cluster Fleet Features..."
gcloud container fleet multi-cluster-services enable --project=${PROJECT_ID} || true
gcloud container fleet ingress enable --config-membership=cluster1 --location=${REGION} --project=${PROJECT_ID} || true

# --- Task 3: Install Service Mesh ---
echo "[Task 3] Installing GKE Service Mesh..."
gcloud container fleet mesh update --management automatic --memberships cluster1,cluster2

echo "Waiting for Mesh revision to be ready (this can take 10 minutes)..."
until gcloud container fleet mesh describe --format=yaml | grep -q "code: REVISION_READY"; do
  echo "Still waiting..."
  sleep 30
done

echo "[Task 3] Deploying Ingress Gateways..."
kubectl --context=cluster1 create namespace asm-ingress || true
kubectl --context=cluster1 label namespace asm-ingress istio-injection=enabled --overwrite
kubectl --context=cluster2 create namespace asm-ingress || true
kubectl --context=cluster2 label namespace asm-ingress istio-injection=enabled --overwrite

# Note: In managed ASM, we avoid manual labeling of istio-system to prevent configuration warnings.

cat <<EOF > asm-ingress.yaml
apiVersion: v1
kind: Service
metadata:
  name: asm-ingressgateway
  namespace: asm-ingress
spec:
  type: LoadBalancer
  selector:
    asm: ingressgateway
  ports:
  - port: 80
    name: http
  - port: 443
    name: https
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: asm-ingressgateway
  namespace: asm-ingress
spec:
  selector:
    matchLabels:
      asm: ingressgateway
  template:
    metadata:
      annotations:
        inject.istio.io/templates: gateway
      labels:
        asm: ingressgateway
    spec:
      containers:
      - name: istio-proxy
        image: auto
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: asm-ingressgateway-sds
  namespace: asm-ingress
rules:
- apiGroups: [""]
  resources: ["secrets"]
  verbs: ["get", "watch", "list"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: asm-ingressgateway-sds
  namespace: asm-ingress
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: asm-ingressgateway-sds
subjects:
- kind: ServiceAccount
  name: default
EOF

kubectl --context=cluster1 apply -f asm-ingress.yaml
kubectl --context=cluster2 apply -f asm-ingress.yaml

# --- Task 4: Deploy Cymbal Bank ---
echo "[Task 4] Deploying Cymbal Bank..."
git clone https://github.com/GoogleCloudPlatform/bank-of-anthos.git ${HOME}/bank-of-anthos || true

for ctx in cluster1 cluster2; do
    kubectl --context=$ctx create namespace bank-of-anthos || true
    kubectl --context=$ctx label namespace bank-of-anthos istio-injection=enabled --overwrite
    kubectl --context=$ctx -n bank-of-anthos apply -f ${HOME}/bank-of-anthos/extras/jwt/jwt-secret.yaml
    kubectl --context=$ctx -n bank-of-anthos apply -f ${HOME}/bank-of-anthos/kubernetes-manifests
done

# Remove databases from cluster2 for distributed mode
kubectl --context=cluster2 -n bank-of-anthos delete statefulset accounts-db ledger-db || true

# Deploy Mesh Gateway Configs
cat <<EOF > asm-vs-gateway.yaml
apiVersion: networking.istio.io/v1alpha3
kind: Gateway
metadata:
  name: asm-ingressgateway
  namespace: asm-ingress
spec:
  selector:
    asm: ingressgateway
  servers:
  - port:
      number: 80
      name: http
      protocol: HTTP
    hosts:
    - "*"
---
apiVersion: networking.istio.io/v1alpha3
kind: VirtualService
metadata:
  name: frontend
  namespace: bank-of-anthos
spec:
  hosts:
  - "*"
  gateways:
  - asm-ingress/asm-ingressgateway
  http:
  - route:
    - destination:
        host: frontend
        port:
          number: 80
EOF

kubectl --context=cluster1 apply -f asm-vs-gateway.yaml
kubectl --context=cluster2 apply -f asm-vs-gateway.yaml

echo "Setup Complete! Check progress on all tasks."

# Project Overview: GSP1242 - Manage and Secure Distributed Services with GKE Managed Service Mesh

This directory contains the documentation and instructions for the Google Cloud self-paced lab **GSP1242**. The lab focuses on running distributed services on multiple Google Kubernetes Engine (GKE) clusters using Multi-Cluster Ingress and GKE Service Mesh.

## Key Files

*   **gsg1242.txt**: The primary lab guide containing the overview, objectives, scenario, and step-by-step instructions for completing the lab.
*   **GEMINI.md**: This file, providing context and guidance for interactive AI assistance within this workspace.

## Lab Objectives

1.  **Create GKE Clusters**: Set up three GKE clusters (two private application clusters and one central configuration cluster).
2.  **Network Configuration**: Configure NAT Gateways, Cloud Routers, and firewall rules for inter-cluster and egress traffic.
3.  **Service Mesh Installation**: Deploy and configure multi-cluster GKE Service Mesh in multi-primary mode.
4.  **Application Deployment**: Deploy the **Cymbal Bank** (Bank of Anthos) sample microservices application across the private clusters.
5.  **Traffic Management**: Expose services using Multi-Cluster Ingress and visualize traffic via the Service Mesh dashboard.

## Safety Protocols

To prevent accidental lab termination or account blocking, the following protocols must be strictly followed:

*   **No Metadata Probing**: Never attempt to access the internal metadata server (`169.254.169.254`).
*   **Scoped Commands**: All `gcloud` and `kubectl` commands must be scoped to the current project and the specific clusters (`cluster1`, `cluster2`) mentioned in the instructions.
*   **Read-Only First**: Prioritize discovery (`get`, `describe`, `list`) before any modification (`label`, `update`).
*   **No Port Scanning**: No network scanning or broad port probing should be performed.
*   **Resource Limits**: Avoid running background processes or high-CPU/memory commands.

## Usage and Execution

The lab is designed to be executed within a **Google Cloud Shell** environment or a terminal with the `gcloud` and `kubectl` CLIs installed and authenticated to a temporary Google Cloud project.

### Common Commands (Inferred from Instructions)

*   **Enable APIs**:
    ```bash
    gcloud services enable container.googleapis.com mesh.googleapis.com gkehub.googleapis.com
    ```
*   **Fleet Management**:
    ```bash
    gcloud container fleet mesh enable
    gcloud container fleet memberships register [CLUSTER_NAME] ...
    ```
*   **Kubernetes Context Switching**:
    ```bash
    kubectl config use-context cluster1
    kubectl config use-context cluster2
    ```
*   **Deploying Application**:
    ```bash
    kubectl apply -f ${HOME}/bank-of-anthos/kubernetes-manifests
    ```

## Current Investigation Status (Task 3)

*   **Status**: Task 3 ("Install GKE Service Mesh") continues to fail the grader despite being functional.
*   **Deep-Dive Findings**:
    *   **Mesh Core**: ControlPlaneRevisions (`asm-managed`) are healthy in both clusters.
    *   **Injection**: MutatingWebhooks (`istio-revision-tag-default`, `istiod-asm-managed`) are active. Pods in `asm-ingress` are successfully injected with `istio-proxy` (1.20.8-asm.88).
    *   **Connectivity**: Ingress LoadBalancers are reachable and returning 200 OK for the Cymbal Bank frontend.
    *   **Fleet**: `multiclusteringress` and `multiclusterservicediscovery` are enabled with `cluster1` as the config membership.
*   **Action Plan**: Finalized setup script and documentation for support review.
*   **Current Environment**: `PROJECT_ID`: qwiklabs-gcp-01-5541a8a99e26, `REGION`: us-west1, `ZONE`: us-west1-b.

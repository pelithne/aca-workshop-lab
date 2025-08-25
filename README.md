# Azure Container Apps Workshop

End‑to‑end hands‑on labs for modernizing and scaling workloads on **Azure Container Apps (ACA)** with secure software supply chain, AI inference options, and multi‑region architecture patterns.

## Labs Overview

| Lab | Focus | Key Outcomes |
|-----|-------|--------------|
| [Lab 1 – App Service ➜ ACA](labs/LAB1-AppService-to-ACA.md) | Containerize & deploy | ACR push, ACA env, ingress, probes, autoscale, revisions |
| [Lab 2 – AI Training & Inference](labs/LAB2-Inference-on-ACA.md) | Train (Azure ML) + serve on ACA | Model training job, model registry, build inference image, deploy & autoscale |
| [Lab 3 – Security Hardening & Secrets](labs/LAB3-Security-Hardening.md) | Defense-in-depth | Managed identity to ACR/Key Vault, Front Door + WAF, image signing, private egress |

Additional (facilitator / design) segments cover: When to choose ACA vs AKS, Global active‑active pattern, Operations & cost optimization, and Executive readout.

## Repository Structure

```
├─ bicep/                    # Infrastructure as Code (ACA env, Log Analytics, Front Door add‑ons)
├─ manifests/                # Container Apps manifest(s)
├─ src/app/                  # Sample Node.js API + AI integration endpoints
├─ scripts/                  # Deployment helper scripts
├─ labs/                     # Step‑by‑step lab guides
└─ SECURITY.md               # Supply chain & promotion notes
```

## Prerequisites

See each lab for specifics; common requirements:
* Azure subscription (Owner or Contributor + User Access Administrator for RBAC assignments)
* Azure CLI >= 2.60 with `containerapp` extension (`az extension add -n containerapp`)
* Docker or Azure Cloud Shell w/ Buildpacks (for build) / or ACR Task
* Git & GitHub repo access (for optional CI/CD steps)

## Fast Start (Minimal Happy Path)

1. Login & set subscription:
```
az login
az account set -s <SUBSCRIPTION_ID>
```
2. Deploy core infra (Bicep):
```
az deployment sub create -l westeurope -f bicep/main.bicep -p namePrefix=acalab
```
3. Build & push image (ACR quick path or local): see Lab 1.
4. Deploy Container App using manifest & substitute variables: see Lab 1.

## Best Practices Embedded
* Principle of least privilege (Managed Identity, Key Vault access policies / RBAC)
* Observability: Log Analytics linked in `main.bicep`; extend with DCR & OpenTelemetry exporter (see Labs)
* Secure networking: Front Door WAF, readiness/liveness probes, optional VNet integration & private egress pattern (Lab 3)
* Cost governance: autoscale concurrency, min replicas = 0 where feasible, workload profile choice
* Supply chain: image signing (cosign), provenance, policy evaluation (Gatekeeper / Defender for Cloud)
* AI Safety: Use Azure OpenAI with content filters OR isolated local inference via sidecar

Proceed to the labs to begin.


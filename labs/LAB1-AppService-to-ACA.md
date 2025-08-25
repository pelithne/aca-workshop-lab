# Lab 1 – App Service to Azure Container Apps

Goal: Containerize an existing Web API, push image to Azure Container Registry (ACR), provision Azure Container Apps (ACA) environment, deploy, configure ingress, probes, scaling, and test blue/green revisions.

Estimated time: 65 minutes

## Architecture (Target)

Developer -> (Docker build / Oryx build) -> ACR -> ACA Environment (Revision v1) -> Ingress (HTTP) -> App Container

Observability via Log Analytics; future revisions (v2) for blue/green.

## Prerequisites
* Azure subscription + rights: Contributor + User Access Administrator (for role assignments)
* Azure CLI >= 2.60.0 with `containerapp` extension
```
az extension add -n containerapp || az extension update -n containerapp
```
* Docker locally OR use `az acr build` for cloud build
* (Optional) Existing App Service sample (we use provided Node.js API in `src/app`).

## 1. Clone & Inspect
```
git clone <your-fork-or-original> && cd aca-workshop-lab
ls src/app
```
Review `server.js` for health endpoints `/healthz` and `/ready` and AI routes.

## 2. Create Resource Group & Deploy Base Infra
Parameters: location (e.g. westeurope), namePrefix.
```
LOCATION=westeurope
PREFIX=acalab$RANDOM
az group create -n ${PREFIX}-rg -l $LOCATION
az deployment group create -g ${PREFIX}-rg -f bicep/main.bicep -p location=$LOCATION namePrefix=$PREFIX
```
Outputs (capture):
```
az deployment group show -g ${PREFIX}-rg -n main --query properties.outputs
```
Note: `managedEnvName`, `logAnalyticsId`, `identityId`.

## 3. Create ACR & Grant Pull Permissions
```
ACR_NAME=${PREFIX//-/}acr  # must be globally unique
az acr create -n $ACR_NAME -g ${PREFIX}-rg --sku Basic --admin-enabled false
# Grant the User Assigned Managed Identity AcrPull
MI_ID=$(az identity show -g ${PREFIX}-rg -n mi-shopapi --query id -o tsv)
az role assignment create --assignee-object-id $(az identity show -g ${PREFIX}-rg -n mi-shopapi --query principalId -o tsv) \
  --assignee-principal-type ServicePrincipal \
  --scope $(az acr show -n $ACR_NAME --query id -o tsv) \
  --role AcrPull
```
Security: avoid ACR admin user; use managed identity.

## 4. Build & Push Image
Option A – Local Docker (needs login):
```
az acr login -n $ACR_NAME
IMAGE=${ACR_NAME}.azurecr.io/shopapi:v1
cd src/app
docker build -t $IMAGE ../../
docker push $IMAGE
```
Option B – ACR Task (source build):
```
IMAGE=${ACR_NAME}.azurecr.io/shopapi:v1
az acr build -r $ACR_NAME -t shopapi:v1 -f Dockerfile .
```
Verify:
```
az acr repository show-tags -n $ACR_NAME --repository shopapi
```

## 5. Deploy Container App (Initial Revision)
```
ENV_NAME=acaenv-weu   # from output (or adjust if param changes)
APP_NAME=${PREFIX}-shopapi
az containerapp create \
  -g ${PREFIX}-rg \
  -n $APP_NAME \
  --environment $ENV_NAME \
  --image $IMAGE \
  --target-port 8080 \
  --ingress external \
  --min-replicas 1 --max-replicas 3 \
  --scale-rule-name httpc --scale-rule-type http --scale-rule-http-concurrency 60 \
  --revision-suffix v1 \
  --registry-server ${ACR_NAME}.azurecr.io \
  --user-assigned $MI_ID \
  --query properties.configuration.ingress.fqdn -o tsv
```
Capture FQDN for testing.

## 6. Configure Probes (If not set via manifest)
(Already exposed endpoints exist; you can patch):
```
az containerapp update -g ${PREFIX}-rg -n $APP_NAME \
  --set template.containers[0].probes='[{"type":"liveness","httpGet":{"path":"/healthz","port":8080}},{"type":"readiness","httpGet":{"path":"/ready","port":8080}}]'
```

## 7. Test Deployment
```
FQDN=$(az containerapp show -g ${PREFIX}-rg -n $APP_NAME --query properties.configuration.ingress.fqdn -o tsv)
curl https://$FQDN/
```
Check logs:
```
az containerapp logs show -g ${PREFIX}-rg -n $APP_NAME --tail 50
```

## 8. Blue/Green (New Revision v2)
Change an env var or label:
```
az containerapp update -g ${PREFIX}-rg -n $APP_NAME --revision-suffix v2 \
  --set template.containers[0].env='[{"name":"APP_VERSION","value":"v2"}]'
```
List revisions:
```
az containerapp revision list -g ${PREFIX}-rg -n $APP_NAME -o table
```
Split traffic 50/50:
```
REV1=$(az containerapp revision list -g ${PREFIX}-rg -n $APP_NAME --query "[?contains(name,'v1')].name" -o tsv)
REV2=$(az containerapp revision list -g ${PREFIX}-rg -n $APP_NAME --query "[?contains(name,'v2')].name" -o tsv)
az containerapp ingress traffic set -g ${PREFIX}-rg -n $APP_NAME \
  --revision-weight ${REV1}=50 ${REV2}=50
```
Observe requests (run curl multiple times). Then shift 100% to v2 when satisfied.

## 9. Scale to Zero (Optional)
```
az containerapp update -g ${PREFIX}-rg -n $APP_NAME --min-replicas 0
```

## 10. Cleanup (Optional)
```
az group delete -n ${PREFIX}-rg -y --no-wait
```

## Success Criteria
* Image in ACR
* Container App reachable with probes healthy
* Two revisions with controlled traffic split
* Managed identity used for registry pull (no admin secret)

## Troubleshooting
* 404 or DNS: wait ~1–2 min after create
* Image pull error: confirm role assignment AcrPull + propagation (can take a minute)
* Logs empty: ensure workspace object exists (`az monitor log-analytics workspace show`)

## Best Practices Highlighted
* No ACR admin credentials
* Probes for resiliency & zero-downtime traffic shifting
* Revision-based deployments for rollback
* Autoscale on HTTP concurrency for cost control

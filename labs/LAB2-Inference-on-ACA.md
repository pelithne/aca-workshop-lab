# Lab 2 – AI Inference on Azure Container Apps

Goal: Add AI inference to your ACA workload via (A) Azure OpenAI using Managed Identity OR (B) Local model inference with an Ollama sidecar. Implement autoscale and validate latency.

Estimated time: 70 minutes

## Decision Path
| Scenario | Choose Option |
|----------|---------------|
| Need enterprise compliance, data filtering, high SLA | Azure OpenAI (Managed) |
| Need private / offline model, custom finetunes, data locality | Ollama Sidecar |
| Hybrid (fallback local if AOAI quota) | Combine both endpoints |

## Prerequisites
Complete Lab 1 (base app & environment). Have `APP_NAME`, `PREFIX`, resource group, and managed identity ID.

## Option A – Azure OpenAI (Managed Service)

### 1. Provision Azure OpenAI (Portal or CLI)
Portal typically required for access approval. After deployment, note:
* Endpoint (e.g., https://my-aoai.openai.azure.com/)
* Model deployment name (e.g., gpt-4o-mini)

### 2. Grant Managed Identity access
Assign Cognitive Services User role to the managed identity at the Azure OpenAI resource scope.
```
AOAI_NAME=<your-aoai-name>
AOAI_ID=$(az cognitiveservices account show -n $AOAI_NAME -g ${PREFIX}-rg --query id -o tsv)
MI_PRINCIPAL=$(az identity show -g ${PREFIX}-rg -n mi-shopapi --query principalId -o tsv)
az role assignment create --role "Cognitive Services User" --assignee-object-id $MI_PRINCIPAL --assignee-principal-type ServicePrincipal --scope $AOAI_ID
```

### 3. Configure Environment Variables
```
AOAI_ENDPOINT=$(az cognitiveservices account show -n $AOAI_NAME -g ${PREFIX}-rg --query properties.endpoint -o tsv)
DEPLOYMENT=<modelDeployment>
az containerapp update -g ${PREFIX}-rg -n $APP_NAME \
  --set template.containers[0].env='[{"name":"AZURE_OPENAI_ENDPOINT","value":"'$AOAI_ENDPOINT'"},{"name":"AZURE_OPENAI_DEPLOYMENT","value":"'$DEPLOYMENT'"}]'
```

### 4. Call the Endpoint
```
FQDN=$(az containerapp show -g ${PREFIX}-rg -n $APP_NAME --query properties.configuration.ingress.fqdn -o tsv)
curl -X POST https://$FQDN/ai/openai -H "Content-Type: application/json" -d '{"messages":[{"role":"user","content":"Say hello from Azure OpenAI"}]}'
```

If you receive auth errors: ensure Managed Identity role assignment propagation (can take several minutes). The sample uses a direct HTTP call; for production add API version pinning & retry/backoff.

## Option B – Local Model with Ollama Sidecar

### 1. Deploy Multi-Container Revision via Manifest
Edit / use `manifests/containerapp-ollama.yaml` substituting variables:
```
export APP_IMAGE=${ACR_NAME}.azurecr.io/shopapi:v1
export AZURE_OPENAI_ENDPOINT="" # optional blank
export AZURE_OPENAI_DEPLOYMENT=""
cat manifests/containerapp-ollama.yaml | envsubst > /tmp/ollama.yaml
az containerapp update -g ${PREFIX}-rg -n $APP_NAME --yaml /tmp/ollama.yaml --revision-suffix aiollama
```
This introduces a second container `ollama` downloading the model (phi3.5:latest) on cold start.

### 2. Test Local Inference
```
FQDN=$(az containerapp show -g ${PREFIX}-rg -n $APP_NAME --query properties.configuration.ingress.fqdn -o tsv)
curl -X POST https://$FQDN/ai/ollama -H "Content-Type: application/json" -d '{"prompt":"List three Azure services for containers"}'
```

### 3. Autoscale Tuning
Scaling rule already set (HTTP concurrency 60). Evaluate CPU/memory pressure using metrics:
```
az containerapp show -g ${PREFIX}-rg -n $APP_NAME --query properties.template.scale
```
Adjust if model loads cause high latency:
```
az containerapp update -g ${PREFIX}-rg -n $APP_NAME --max-replicas 6 --scale-rule-http-concurrency 30
```

### 4. Model Warmup Optimization (Optional)
Pre-pull during sidecar startup already included. For large models consider:
* Use larger workload profile (D or E series) if enabled
* Keep min replicas = 1 for reduced cold start

## Observability Additions (Both Options)
Query logs (chat latency):
```
az monitor log-analytics query -w $(az monitor log-analytics workspace list -g ${PREFIX}-rg --query "[0].customerId" -o tsv) \
  --analytics-query "ContainerAppConsoleLogs | where ContainerAppName == '$APP_NAME' | limit 20"
```
(Enhancement: instrument code with OpenTelemetry SDK for traces.)

## Security & Compliance Notes
* Managed Identity avoids embedding API keys
* If using API keys (not recommended), store in Key Vault and mount via secret refs / Dapr component
* Network isolation: consider VNet integration + private endpoints for AOAI (if supported regionally)

## Cleanup of Revision
If you want to remove Ollama revision:
```
az containerapp revision deactivate -g ${PREFIX}-rg -n $APP_NAME --revision <revName>
```
List revisions to identify name first.

## Success Criteria
* Working inference response (either AOAI or local sidecar)
* Environment variables configured without secrets in code
* Autoscale parameters reviewed/adjusted

## Troubleshooting
* 500 from /ai/openai: role assignment propagation or missing model deployment
* Long cold start for Ollama: reduce model size or keep min replicas > 0
* Memory OOM: move to larger workload profile or reduce concurrent load

## Best Practices Highlighted
* Auth via Managed Identity (no static keys)
* Sidecar pattern for specialized inference runtime
* Autoscale tuned to model latency characteristics
* Separation of concerns: API container vs model runtime

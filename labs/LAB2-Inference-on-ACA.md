az containerapp show -g ${PREFIX}-rg -n $APP_NAME --query properties.template.scale
az containerapp update -g ${PREFIX}-rg -n $APP_NAME --max-replicas 6 --scale-rule-http-concurrency 30
az monitor log-analytics query -w $(az monitor log-analytics workspace list -g ${PREFIX}-rg --query "[0].customerId" -o tsv) \
az containerapp revision deactivate -g ${PREFIX}-rg -n $APP_NAME --revision <revName>
# Lab 2 – AI Training & Inference (Azure ML + Azure Container Apps)

Goal: Run a lightweight model training (or fine‑tuning) job using **Azure Machine Learning (Azure ML)**, register the model, build an inference image, and deploy it to **Azure Container Apps (ACA)** with autoscale and managed identity. (We removed the Ollama sidecar to focus on the agenda item "AI training & inference".)

Estimated time: 70–80 minutes

## Scope Clarification
This lab covers: small sample training / fine‑tuning, model registration, packaging, and ACA deployment for online inference. Large distributed GPU training (multi‑node, MPI) is out of scope—use Azure ML with GPU clusters or AKS inference endpoints for high‑scale / specialized hardware.

## Architecture Flow
Code + Data -> Azure ML Workspace (Compute) -> Train Job -> Registered Model -> Build Inference Image (ACR) -> ACA Revision (HTTP Inference API) -> Autoscale

## Prerequisites
* Lab 1 complete (ACA environment, ACR, managed identity)
* Azure CLI + `ml` extension: `az extension add -n ml` (or update)
* A resource group (`${PREFIX}-rg`), ACR (`$ACR_NAME`)
* Python 3.10+ locally (optional if using remote compute only)

## 1. Create Azure ML Workspace & Compute
```
AML_WS=${PREFIX}mlws
az ml workspace create -g ${PREFIX}-rg -n $AML_WS -l $LOCATION
az ml compute create -g ${PREFIX}-rg -w $AML_WS -f - <<EOF
name: cpu-cluster
type: amlcompute
size: STANDARD_DS3_v2
min_instances: 0
max_instances: 2
idle_time_before_scale_down: 120
EOF
```

## 2. Prepare Training Assets
Create a minimal training script (example: logistic regression on sample data) and YAML job definition. (You can store under `ml/` directory—omitted here for brevity; facilitator may pre‑commit.)

Example `train.py` (conceptual): reads small CSV, trains, saves `model.pkl`.

`job-train.yaml` sample:
```
command: >-
  python train.py
code: .
environment:
  image: mcr.microsoft.com/azureml/openmpi4.1.0-ubuntu22.04:latest
compute: cpu-cluster
experiment_name: demo-train
outputs:
  model_output: {type: uri_folder}
```

Submit job:
```
az ml job create -g ${PREFIX}-rg -w $AML_WS -f job-train.yaml --query name -o tsv
```
Wait for status Succeeded:
```
az ml job show -g ${PREFIX}-rg -w $AML_WS -n <JOB_NAME> --query status -o tsv
```

## 3. Register the Model
Assuming training output `model.pkl` in `model_output`:
```
az ml model create -g ${PREFIX}-rg -w $AML_WS -n demo-model --type uri_folder \
  --path "azureml://jobs/<JOB_NAME>/outputs/model_output/"
```
List models:
```
az ml model list -g ${PREFIX}-rg -w $AML_WS -o table
```

## 4. Build Inference Image (Azure ML Managed Environment -> ACR)
Create a scoring script `score.py` exposing `init()` and `run(data)` returning inference.

`env-inference.yaml` example:
```
name: demo-infer-env
dependencies:
  - python=3.10
  - pip:
      - scikit-learn==1.4.2
      - joblib==1.3.2
      - flask==3.0.3
```

Create online deployment image locally via Azure ML build:
```
az ml environment create -g ${PREFIX}-rg -w $AML_WS -f env-inference.yaml
```

Containerize manually (simpler path for ACA) – build runtime that loads model from model asset downloaded during image build:
Create a folder `inference/` with `Dockerfile`:
```
FROM mcr.microsoft.com/azureml/openmpi4.1.0-ubuntu22.04:latest
RUN pip install scikit-learn==1.4.2 joblib==1.3.2 flask==3.0.3
WORKDIR /app
COPY score.py .
COPY download_model.py .
RUN python download_model.py  # pulls model from model registry using Azure ML REST + MSI (optional) OR pre-export artifact
ENV PORT=8080
CMD ["python","score.py"]
```
`download_model.py` would call Azure ML model download endpoint (for brevity facilitator may pre-package the model artifact instead).

Build & push:
```
IMAGE=${ACR_NAME}.azurecr.io/demo-model-infer:v1
docker build -t $IMAGE inference/
docker push $IMAGE
```
(Alternative: `az acr build`.)

## 5. Deploy Inference API to ACA
```
APP_NAME=${PREFIX}-modelapi
az containerapp create -g ${PREFIX}-rg -n $APP_NAME \
  --environment acaenv-weu \
  --image $IMAGE \
  --target-port 8080 --ingress external \
  --min-replicas 1 --max-replicas 5 \
  --scale-rule-name httpc --scale-rule-type http --scale-rule-http-concurrency 50 \
  --registry-server ${ACR_NAME}.azurecr.io \
  --user-assigned $(az identity show -g ${PREFIX}-rg -n mi-shopapi --query id -o tsv) \
  --revision-suffix v1
```
Add probes (if not included in image):
```
az containerapp update -g ${PREFIX}-rg -n $APP_NAME \
  --set template.containers[0].probes='[{"type":"liveness","httpGet":{"path":"/healthz","port":8080}},{"type":"readiness","httpGet":{"path":"/ready","port":8080}}]'
```

## 6. Test Inference
```
FQDN=$(az containerapp show -g ${PREFIX}-rg -n $APP_NAME --query properties.configuration.ingress.fqdn -o tsv)
curl -X POST https://$FQDN/score -H "Content-Type: application/json" -d '{"features":[[1,2,3,4]]}'
```

## 7. Create New Model Version & Roll Forward
Repeat training with a parameter change, register `demo-model:2`, rebuild image v2:
```
IMAGE2=${ACR_NAME}.azurecr.io/demo-model-infer:v2
docker build -t $IMAGE2 inference/
docker push $IMAGE2
az containerapp update -g ${PREFIX}-rg -n $APP_NAME --image $IMAGE2 --revision-suffix v2
```
Traffic split canary 20/80:
```
REV1=$(az containerapp revision list -g ${PREFIX}-rg -n $APP_NAME --query "[?contains(name,'v1')].name" -o tsv)
REV2=$(az containerapp revision list -g ${PREFIX}-rg -n $APP_NAME --query "[?contains(name,'v2')].name" -o tsv)
az containerapp ingress traffic set -g ${PREFIX}-rg -n $APP_NAME --revision-weight ${REV1}=80 ${REV2}=20
```
Promote to 100% when metrics healthy.

## 8. Autoscale Optimization
Monitor concurrency & latency, adjust rule:
```
az containerapp update -g ${PREFIX}-rg -n $APP_NAME --scale-rule-http-concurrency 30 --max-replicas 8
```
Add CPU based rule (example):
```
az containerapp update -g ${PREFIX}-rg -n $APP_NAME --scale-rule-name cpu --scale-rule-type cpu --scale-rule-metadata "threshold=70"
```

## 9. Observability
Logs:
```
az containerapp logs show -g ${PREFIX}-rg -n $APP_NAME --tail 50
```
Sample Kusto (latency placeholder—if instrumented):
```
ContainerAppConsoleLogs 
| where ContainerAppName == '${APP_NAME}'
| take 20
```

## 10. Security Notes
* Managed Identity for ACR pull & future model registry access
* Avoid embedding keys; training artifacts pulled via Azure ML auth
* Consider private endpoints for AML + ACR + ACA environment (advanced)

## 11. Cleanup (Optional)
```
az containerapp delete -g ${PREFIX}-rg -n $APP_NAME -y
```

## Success Criteria
* Model trained & registered in Azure ML
* Inference image built and stored in ACR
* ACA deployment serving /score endpoint with probes healthy
* Revision canary (v1 → v2) executed with traffic split

## Troubleshooting
* Job stuck Queued: ensure compute cluster quota / region availability
* Image build fails: verify Docker context includes `score.py`
* 502 on ACA: readiness probe failing—check logs for stack trace
* Latency high: lower concurrency target or increase replicas

## Best Practices Highlighted
* Separation of training (Azure ML) and serving (ACA)
* Immutable model versioning & revision-based rollout
* Autoscale based on HTTP concurrency (add CPU rule for backpressure)
* Health probes + canary reduce risk during model updates
* Managed Identity central to pulling image & (optionally) model artifacts


#!/usr/bin/env bash
set -euo pipefail
RG=${RG:-rg-aca-lab}
LOC=${LOC:-westeurope}
ACR=${ACR:-acrlab$RANDOM}
ENV=${ENV:-acaenv-weu}
APP=${APP:-shopapi}
az group create -n $RG -l $LOC
az deployment group create -g $RG -f bicep/main.bicep -p location=$LOC namePrefix=acalab
az acr create -g $RG -n $ACR --sku Standard
az acr login -n $ACR
IMG=$(az acr show -n $ACR -g $RG --query loginServer -o tsv)/$APP:local
docker build -t $IMG .
docker push $IMG
MI_ID=$(az identity show -g $RG -n mi-$APP --query id -o tsv)
ACR_LOGIN=$(az acr show -n $ACR -g $RG --query loginServer -o tsv)
MI_CLIENT=$(az identity show -g $RG -n mi-$APP --query clientId -o tsv)
ACR_ID=$(az acr show -n $ACR -g $RG --query id -o tsv)
az role assignment create --assignee $MI_CLIENT --role AcrPull --scope $ACR_ID || true
if az containerapp show -g $RG -n $APP >/dev/null 2>&1; then
  az containerapp update -g $RG -n $APP --image $IMG --registry-server $ACR_LOGIN --registry-identity $MI_ID
else
  az containerapp create -g $RG -n $APP --environment $ENV --image $IMG --ingress external --target-port 8080 --transport auto --min-replicas 1 --max-replicas 10 --scale-rule-name http --scale-rule-type http --scale-rule-http-concurrency 60 --cpu 0.5 --memory 1.0Gi --registry-server $ACR_LOGIN --registry-identity $MI_ID --user-assigned $MI_ID
fi
az containerapp update -g $RG -n $APP --set-template-probes liveness=httpGet,path=/healthz,port=8080 readiness=httpGet,path=/ready,port=8080
FQDN=$(az containerapp show -g $RG -n $APP --query properties.configuration.ingress.fqdn -o tsv)
echo "App URL: https://$FQDN"

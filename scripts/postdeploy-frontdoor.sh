#!/usr/bin/env bash
set -euo pipefail
RG=${RG:-rg-aca-lab}
PREFIX=${PREFIX:-acalab}
APP=${APP:-shopapi}
PROFILE=${PROFILE:-${PREFIX}-afd}
WAF=${WAF:-${PREFIX}-waf}
FQDN=$(az containerapp show -g $RG -n $APP --query properties.configuration.ingress.fqdn -o tsv)
OG=${OG:-og}
ORIGIN=${ORIGIN:-origin1}
ENDPOINT=${ENDPOINT:-site}
az afd origin-group create --resource-group $RG --profile-name $PROFILE --origin-group-name $OG --probe-request-type GET --probe-protocol Https --probe-interval-in-seconds 30 --probe-path /healthz --sample-size 4 --successful-samples-required 3 --additional-latency-in-milliseconds 50
az afd origin create --resource-group $RG --profile-name $PROFILE --origin-group-name $OG --origin-name $ORIGIN --host-name $FQDN --https-port 443 --enabled-state Enabled
az afd endpoint create --resource-group $RG --profile-name $PROFILE --endpoint-name $ENDPOINT
az afd route create --resource-group $RG --profile-name $PROFILE --endpoint-name $ENDPOINT --route-name default --https-redirect Enabled --origin-group $OG --supported-protocols Http Https --link-to-default-domain Enabled
az afd endpoint update --resource-group $RG --profile-name $PROFILE --endpoint-name $ENDPOINT --web-application-firewall-policy $WAF
echo "Front Door endpoint: $(az afd endpoint show -g $RG --profile-name $PROFILE -n $ENDPOINT --query hostName -o tsv)"

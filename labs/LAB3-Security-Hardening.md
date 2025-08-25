# Lab 3 – Security Hardening & Secrets for Azure Container Apps

Goal: Apply defense-in-depth: Managed Identity-based pulls & secrets, Key Vault integration, Front Door + WAF, image signing policy, private egress pattern, and Defender for Cloud recommendations.

Estimated time: 60 minutes

## Prerequisites
* Labs 1 & (optionally) 2 completed
* Resource group, ACA app name, managed identity

## 1. Managed Identity for ACR & Key Vault
Already assigned AcrPull in Lab 1. Next: Key Vault secret retrieval.

### Add a secret to Key Vault
```
KV_NAME=$(az keyvault list -g ${PREFIX}-rg --query "[0].name" -o tsv)
az keyvault secret set -n sample-api-key --vault-name $KV_NAME --value "super-secret-value"
```

### Grant access (RBAC preferred)
```
MI_PRINCIPAL=$(az identity show -g ${PREFIX}-rg -n mi-shopapi --query principalId -o tsv)
# Assign Key Vault Secrets User role
az role assignment create --role "Key Vault Secrets User" --assignee-object-id $MI_PRINCIPAL --assignee-principal-type ServicePrincipal --scope $(az keyvault show -n $KV_NAME --query id -o tsv)
```
(If using access policies instead of RBAC: add policy granting get/list secrets.)

### Mount secret into Container App (env ref)
Fetch secret value at deployment time via CLI (for demo). For runtime retrieval consider code that calls KV REST using MSI.
```
SECRET_VALUE=$(az keyvault secret show -n sample-api-key --vault-name $KV_NAME --query value -o tsv)
az containerapp update -g ${PREFIX}-rg -n $APP_NAME --set template.containers[0].env='[{"name":"SAMPLE_API_KEY","value":"'$SECRET_VALUE'"}]'
```
(Note: This bakes value into revision; for dynamic rotation prefer managed identity calls instead of env injection.)

## 2. Front Door + WAF Integration
If not yet deployed, use `bicep/addons-network-frontdoor.bicep`.
```
az deployment group create -g ${PREFIX}-rg -f bicep/addons-network-frontdoor.bicep -p location=$LOCATION namePrefix=$PREFIX
```
Add origin: use ACA ingress FQDN.
```
FQDN=$(az containerapp show -g ${PREFIX}-rg -n $APP_NAME --query properties.configuration.ingress.fqdn -o tsv)
# (Portal or additional bicep) configure origin + route to WAF policy.
```
Best practice: enable HTTPS only, enforce WAF in Prevention mode (already set in Bicep), add custom rules for rate limiting.

## 3. Image Signing (Cosign)
Sign local image then add verification in pipeline / admission control.
```
# Generate key pair (store public key in repo / secure location)
cosign generate-key-pair
cosign sign ${ACR_NAME}.azurecr.io/shopapi:v1
cosign verify --key cosign.pub ${ACR_NAME}.azurecr.io/shopapi:v1
```
Add policy (concept): use Azure Policy / Defender to require signatures.

## 4. Private Egress Pattern (Conceptual / Optional Hands-on)
Steps:
1. Create VNet with dedicated subnet for ACA environment & NAT Gateway
2. Integrate ACA environment (internal) with VNet
3. Use Private Endpoints for ACR, Key Vault, OpenAI
4. Restrict firewall so outbound only via approved endpoints
(Implement via extended Bicep in future iteration.)

## 5. Defender for Cloud
Enable plan for Containers & App Service (covers ACA). Review recommendations:
```
az security pricing create -n AppServices --tier Standard
az security assessment list --query "[?contains(displayName,'Container Apps')]" -o table
```
Address critical findings (vuln scanning, unpinned tags, privileged escalation checks).

## 6. Least Privilege RBAC Review
List role assignments scoped to resource group:
```
az role assignment list -g ${PREFIX}-rg --query '[].{PrincipalName:principalName,Role:roleDefinitionName,Scope:scope}' -o table
```
Remove unused Contributor rights for service principals.

## 7. Logging & Threat Detection
* Ensure Log Analytics retention set (30 days in template) – adjust for compliance.
* Ingest container stdout & system logs (already configured). Add diagnostic settings for Front Door & WAF to same workspace.

## 8. Validate App Still Functions via Front Door
Get Front Door endpoint and curl path. Confirm WAF logs (blocked vs allowed) in Log Analytics.

## 9. Compliance Checklist
| Control | Implemented | Notes |
|---------|-------------|-------|
| Identity-based registry access | Yes | AcrPull via UAMI |
| Secrets externalized | Partial | Move from env injection to runtime MSI calls |
| Network protection | Partial | Front Door + WAF; add VNet + private endpoints for full |
| Supply chain signing | Pilot | Cosign introduced, enforce policy pending |
| Observability | Yes | Logs; add traces & metrics later |

## Success Criteria
* Key Vault secret accessed without static credentials persisted in code repo
* WAF policy active
* Image signature created & verification command passes

## Troubleshooting
* KV access denied: wait RBAC propagation or verify role scope
* Front Door 502: origin health probe path mismatch – ensure `/` or `/healthz` configured
* Cosign not found: install (https://docs.sigstore.dev/cosign/installation/)

## Best Practices Highlighted
* Managed Identity + RBAC > access policies (future-proof)
* Centralized secrets (no .env files committed)
* WAF for Layer 7 protection + rate limiting
* Signed images & policy enforcement reduce tampering risk
* Plan toward private network egress & least privilege

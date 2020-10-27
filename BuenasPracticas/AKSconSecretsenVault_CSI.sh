#!/bin/bash

#https://docs.microsoft.com/es-es/azure/key-vault/general/key-vault-integrate-kubernetes

#vars
nombreserv="elcoso"
nombreClusterAks="kluster5"
location="eastus"
resgroup="probando0"
kvName="kvaultbbx1yz"
subscr=$(az account show --query id --output tsv)
nombrsecrAks="secret1"

#creagrupo de recursos
az group create \
 --location $location \
 -n $resgroup 

#create keyvault (softdelete & purge protection seted to true?)
az keyvault create --name $kvName \
  --location $location \
  --resource-group $resgroup \
  --enable-soft-delete true \
  --enable-purge-protection true
  
tenantVault=$(az keyvault show --name $kvName --query properties.tenantId --output tsv)

#crear una entidad de servicio Y obtiene PASS
passwsv=$(az ad sp create-for-rbac --name ${nombreserv}ServicePrincipal --skip-assignment --query password --output tsv)  

# obtener appid
appidsv=$(az ad sp show --id http://${nombreserv}ServicePrincipal --query appId --output tsv)

#almacenar secreto de la entidad servicio
 az keyvault secret set \
   --vault-name $kvName \
   --name $nombrsecrAks \
   --value $passwsv

#crea cluster kubernetes 
az aks create -n $nombreClusterAks \
 -g $resgroup \
 --location $location \
 --node-count 1 
# --enable-managed-identity

sleep 30

# obtener principalId, Clientid, subscriptionId, nodeResourceGroup desde AKS
principalId=$(az aks show \
               --name $nombreClusterAks \
               --resource-group $resgroup \
               --query identity.principalId \
               --output tsv)
Clientid=$(az aks show \
            --name $nombreClusterAks \
            --resource-group $resgroup \
            --query identityProfile.kubeletidentity.clientId \
            --output tsv)
subscriptionId=$(az aks show \
                  --name $nombreClusterAks \
                  --resource-group $resgroup \
                  --query networkProfile.loadBalancerProfile.effectiveOutboundIps \
                  --output tsv)
nodeResourceGroup=$(az aks show \
                     --name $nombreClusterAks \
                     --resource-group $resgroup \
                     --query nodeResourceGroup \
                     --output tsv)

sleep 30

# conecta a cluster
az account set --subscription $subscr
az aks get-credentials --resource-group $resgroup --name $nombreClusterAks --overwrite-existing

#instalar controlador Secret Store CSI
helm repo add csi-secrets-store-provider-azure https://raw.githubusercontent.com/Azure/secrets-store-csi-driver-provider-azure/master/charts

helm install csi-secrets-store-provider-azure/csi-secrets-store-provider-azure --generate-name

#Creación de su propio objeto SecretProviderClass
cat  > secretproviderclass_service_principal.yaml << EOF
apiVersion: secrets-store.csi.x-k8s.io/v1alpha1
kind: SecretProviderClass
metadata:
  name: azure-kvname
spec:
  provider: azure
  parameters:
    usePodIdentity: "false"                   # [REQUIRED] Set to "true" if using managed identities
    useVMManagedIdentity: "false"             # [OPTIONAL] if not provided, will default to "false"
    userAssignedIdentityID: $appidsv          # [REQUIRED] If you're using a service principal, use the client id to specify which user-assigned managed identity to use. If you're using a user-assigned identity as the VM's managed identity, specify the identity's client id. If the value is empty, it defaults to use the system-assigned identity on the VM
                                              #     az ad sp show --id http://contosoServicePrincipal --query appId -o tsv
                                              #     the preceding command will return the client ID of your service principal
    keyvaultName: $kvName                     # [REQUIRED] the name of the key vault
                                              #     az keyvault show --name contosoKeyVault5
                                              #     the preceding command will display the key vault metadata, which includes the subscription ID, resource group name, key vault 
    cloudName: ""                             # [OPTIONAL for Azure] if not provided, Azure environment will default to AzurePublicCloud
    objects:  |
      array:
        - |
          objectName: $nombrsecrAks           # [REQUIRED] object name
                                              #     az keyvault secret list --vault-name "contosoKeyVault5"
                                              #     the above command will display a list of secret names from your key vault
          objectType: secret                  # [REQUIRED] object types: secret, key, or cert
          objectVersion: ""                   # [OPTIONAL] object versions, default to latest if empty
        
    resourceGroup: $resgroup                # [REQUIRED] the resource group name of the key vault
    subscriptionId: $subscr                 # [REQUIRED] the subscription ID of the key vault
    tenantId: $tenantVault                  # [REQUIRED] the tenant ID of the key vault
EOF

#Asignación de una entidad de servicio
az role assignment create \
 --role Reader \
 --assignee $appidsv \
 --scope /subscriptions/$subscr/resourcegroups/$resgroup/providers/Microsoft.KeyVault/vaults/$kvName

sleep 30

#Conceda a la entidad de servicio permisos para obtener secretos
az keyvault set-policy -n $kvName --secret-permissions get --spn $appidsv
az keyvault set-policy -n $kvName --key-permissions get --spn $appidsv

#a ha configurado la entidad de servicio con permisos para leer secretos desde el almacén de claves. $appidsv es la contraseña de la entidad de servicio.
# Agregue las credenciales de la entidad de servicio como un secreto de Kubernetes al que pueda acceder el controlador Secrets Store CSI:
kubectl create secret generic secrets-store-creds \
  --from-literal clientid=$appidsv \
  --from-literal clientsecret=$passwsv
  
#si hay errores 
#kubectl delete secrets secrets-store-creds

#siquiere reestablecerlo
#az ad sp credential reset --name ${nombreserv}ServicePrincipal --credential-description "APClientSecret" --query password -o tsv

sleep 30

#aplicar con
kubectl apply -f secretproviderclass_service_principal.yaml

#probar con 
wget https://raw.githubusercontent.com/Azure/secrets-store-csi-driver-provider-azure/master/examples/nginx-pod-inline-volume-service-principal.yaml
kubectl apply -f nginx-pod-inline-volume-service-principal.yaml

sleep 30

#ver si los pod pudieron crearse
kubectl get pods

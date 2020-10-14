#!/bin/bash
# https://docs.microsoft.com/en-us/azure/container-registry/container-registry-customer-managed-keys

#location
location="southcentralus"
#Resource Group name
rgName="rg-tst-dev"
#ACR name
crName="acrtstdev"
#key vault name
kvName="mikvault999"
#identity name
idttName="idntacr-dev"
#key name
keyAcrName="acrkey1"


az identity create \
  --resource-group $rgName \
  --name $idttName 

#get the id's
identityID=$(az identity show \
  --resource-group $rgName \
  --name $idttName \
  --query 'id' --output tsv)

identityPrincipalID=$(az identity show \
  --resource-group $rgName \
  --name $idttName \
  --query 'principalId' --output tsv)

#create keyvault (softdelete & purge protection seted to true)
az keyvault create --name $kvName \
  --location $location \
  --resource-group $rgName \
  --enable-soft-delete true \
  --enable-purge-protection true

#get keyvault id
keyvaultID=$(az keyvault show \
  --resource-group $rgName \
  --name $kvName \
  --query 'id' --output tsv)

#enable key access
az keyvault set-policy \
  --resource-group $rgName \
  --name $kvName \
  --object-id $identityPrincipalID \
  --key-permissions get unwrapKey wrapKey

#Now create a key
az keyvault key create \
  --name $keyAcrName \
  --vault-name $kvName

#get the key id
keyID=$(az keyvault key show \
  --name $keyAcrName \
  --vault-name $kvName \
  --query 'key.kid' --output tsv)


#Now Create the ACR

az acr create \
  --resource-group $rgName \
  --name $crName\
  --identity $identityID \
  --key-encryption-key $keyID \
  --sku Premium


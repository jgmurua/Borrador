#!/bin/bash
# https://docs.microsoft.com/en-us/azure/container-registry/container-registry-customer-managed-keys

#location
location="southcentralus"
#Resource Group name
rgName="rg-tst-dev"
#ACR name
crName="acrtstdev"
#key vault name
kvName="mikvault9lo"
#identity name
idttName="idntacr-dev01"
#key name
keyAcrName="acrkey10"

#container
NameContainer="miapp"
ImgContainer="docker.io/jgmurua/repojuan:latest"
imgCntx="repojuan:latest" 							#correjir#
imgrepo="repojuan"
MemRamGb=1
CpuUn=1
PortOpn="80"

#aks
AksCluster="akluster"
AkNodes=1


#with encription at rest

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

#Put a docker image in ACR
az acr import \
  --name $crName \
  --source $ImgContainer \
  -t ${imgrepo}:latest


#compose the url of the latest image in acr
ImgLoginSrv=$(az acr show -n $crName --query loginServer --output tsv)
IMGinACRcnt=$(az acr show -n $crName --query loginServer --output tsv )/$imgCntx




#2 secrets ------------------------------------------- begin

#https://docs.microsoft.com/en-us/azure/container-instances/container-instances-using-azure-container-registry


# Create service principal, store its password in vault (the registry *password*)

AcrId=$(az acr show --name $crName --query id --output tsv)
SRCtx=$(az ad sp create-for-rbac \
  --name http://$crName-pull \
  --scopes $AcrId \
  --role acrpull \
  --query password \
  --output tsv)

az keyvault secret set \
  --vault-name $kvName \
  --name $crName-pull-pwd \
  --value $SRCtx
  
 
# Store service principal ID in vault (the registry *username*)
az keyvault secret set \
  --vault-name $kvName \
  --name $crName-pull-usr \
  --value $(az ad sp show --id http://$crName-pull --query appId --output tsv)
  
#2 secretos#
#$crName-pull-usr
#$crName-pull-pwd
#se obtienen asi
#$(az keyvault secret show --vault-name $kvName -n $crName-pull-usr --query value -o tsv)
#$(az keyvault secret show --vault-name $kvName -n $crName-pull-pwd --query value -o tsv)

#2 secrets -------------------------------------------- end



#Container 
#https://docs.microsoft.com/en-us/cli/azure/container?view=azure-cli-latest
az container create \
  --resource-group $rgName \
  --name $NameContainer \
  --registry-login-server $ImgLoginSrv \
  --registry-username $(az keyvault secret show --vault-name $kvName -n $crName-pull-usr --query value -o tsv) \
  --registry-password $(az keyvault secret show --vault-name $kvName -n $crName-pull-pwd --query value -o tsv) \
  --image $IMGinACRcnt \
  --cpu $CpuUn \
  --memory $MemRamGb \
  --ports $PortOpn \
  --dns-name-label $NameContainer$RANDOM
  

#Create an AKS
az aks create \
  --resource-group $rgName \
  --name $AksCluster \
  --node-count $AkNodes \
  --enable-addons monitoring \
  --generate-ssh-keys
  







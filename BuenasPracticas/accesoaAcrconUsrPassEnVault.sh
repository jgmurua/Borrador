#!/bin/bash
# https://docs.microsoft.com/en-us/azure/container-registry/container-registry-customer-managed-keys

#location
location="southcentralus"
#Resource Group name
rgName="rg-tst-dev"
#ACR name
crName="acrtstdex"
#key vault name
kvName="mikvaulxlo"
#identity name
idttName="idntacr-dex03"
#key name
keyAcrName="acrkeyx0"

#container
NameContainer="miapx"
ImgContainer="docker.io/jgmurua/repojuan:latest"
imgCntx="repojuan:latest" 							#correjir#
imgrepo="repojuan"
MemRamGb=1
CpuUn=1
PortOpn="80"


#without encription at rest

#create identity 
az identity create \
  --resource-group $rgName \
  --name $idttName 
  
#get the identity
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

#enable key access
az keyvault set-policy \
  --resource-group $rgName \
  --name $kvName \
  --object-id $identityPrincipalID \
  --key-permissions get unwrapKey wrapKey


#Now Create the ACR
az acr create \
  --resource-group $rgName \
  --name $crName\
  --sku Basic

#Put a docker image in ACR
az acr import \
  --name $crName \
  --source $ImgContainer \
  -t ${imgrepo}:latest


#compose the url of the latest image in acr
ImgLoginSrv=$(az acr show -n $crName --query loginServer --output tsv)
IMGinACRcnt=$(az acr show -n $crName --query loginServer --output tsv )/$imgCntx


###################
### Secretos    ###
###################


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


###################
### Container   ###
###################


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
  

###################
### cluster AKS ###
###################

AksCluster="kluster"  
subscriptionx= $(az account show --query id --output tsv) 
AkNodes=1
img="repojuan:latest"



#Create an AKS y atach acr
az aks create \
  --resource-group $rgName \
  --name $AksCluster \
  --node-count $AkNodes \
  --enable-addons monitoring \
  --generate-ssh-keys \
  --attach-acr $crName
  
#conecta con AKS
az account set --subscription $subscriptionx
az aks get-credentials --resource-group $rgName --name $AksCluster

#ejemplo de como importar imagen a acr
#az acr import  -n $crName --source docker.io/library/nginx:latest --image nginx:v1   #importar a mi acr

#consigue la credencial del aks
az aks get-credentials -g $rgName -n $AksCluster 

#crea el yml de los pods

cat > contfromacr.yaml << EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: micc-deployment
  labels:
    app: micc-deployment
spec:
  replicas: 2
  selector:
    matchLabels:
      app: micc
  template:
    metadata:
      labels:
        app: micc
    spec:
      containers:
      - name: micc
        image: $crName.azurecr.io/$img
        ports:
        - containerPort: 80
EOF

#crea el yml del servicio

cat > contsrc.yaml << EOF
apiVersion: v1
kind: Service
metadata:
  name: micc
  labels:
    app: micc

spec:
  selector:
    app: micc

  ports:
    - name: http
      port: 80

  type: LoadBalancer
EOF


#despliega pod y srvc
kubectl apply -f .
#ver ip loadbalancer
kubectl get services -o jsonpath='{.items[1].status.loadBalancer.ingress[0].ip}'

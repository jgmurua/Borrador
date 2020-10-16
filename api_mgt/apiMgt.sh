#!/bin/bash

#obtiene Mailsubsc
while getopts "m:*" opt
do
   case "$opt" in
      m ) Mailsubsc="$OPTARG" ;;
      ? ) echo "ingrese ./apiMgt.sh -m SuMail@hotmail.com"
   esac
done


#Api Manager 
MyApim="puchuloinc"
rgName="rg-tst-dev"
Loc="southcentralus"
email= $Mailsubsc
PubshName="Microsoft"
apimSku="Basic"
#-----#
sUrl="https://demoapirirpipi.azurewebsites.net"
Apiname="apipp2"
#-----#


#docs
#https://docs.microsoft.com/en-us/cli/azure/apim/api?view=azure-cli-latest#az_apim_api_create


#nombres y path de las operaciones Api
op1Name="get-all-courses"
op1Template="/api/Courses"
op2Name="get-a-course"
op2Template="/api/Courses/"
op3Name="add-a-course"
op3Template="/api/Courses"


#Api Manager 

#ApiMgr create
az apim create \
  --name $MyApim \
  --resource-group $rgName \
  --location $Loc \
  --publisher-email $email \
  --publisher-name $PubshName \
  --sku-name $apimSku

#espera media hora masomenos
az apim wait \
  --created \
  --name $MyApim \
  --resource-group $rgName

#crea api
az apim api create \
  --service-name $MyApim \
  --resource-group $rgName \
  --api-id $Apiname \
  --service-url $sUrl \
  --path "" \
  --display-name $Apiname 
  
  
#crea las operaciones
az apim api operation create \
  --resource-group $rgName \
  --service-name $MyApim \
  --api-id $Apiname \
  --url-template $op1Template \
  --method "GET" \
  --display-name $op1Name \
  --description "" 
  
#crea las operaciones
az apim api operation create \
  --resource-group $rgName \
  --service-name $MyApim \
  --api-id $Apiname \
  --url-template $op2Template"{id}" \
  --method "GET" \
  --display-name $op2Name \
  --description "" \
  --template-parameters name=id description="" type=paramType required="true" 
  
#crea las operaciones
az apim api operation create \
  --resource-group $rgName \
  --service-name $MyApim \
  --api-id $Apiname \
  --url-template $op3Template \
  --method "POST" \
  --display-name $op3Name \
  --description "" 
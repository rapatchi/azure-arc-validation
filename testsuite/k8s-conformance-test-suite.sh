# Set the following environment variables to run the test suite

# Common Variables
# Some of the variables need to be populated from the service principal and storage account details provided to you by Microsoft
connectedClustedId=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 7 ; echo '')
AZ_TENANT_ID= # tenant field of the service principal
AZ_SUBSCRIPTION_ID= # subscription id of the azure subscription (will be provided)
AZ_CLIENT_ID= # appid field of the service principal
AZ_OBJECT_ID= # objectid of the service principal, please add it within the quotes
AZ_CLIENT_SECRET= # password field of the service principal
AZ_STORAGE_ACCOUNT= # name of your storage account (will be provided)
AZ_STORAGE_ACCOUNT_SAS="" # sas token for your storage account, please add it within the quotes (will be provided)
RESOURCE_GROUP=rapatchi # resource group name (will be provided)
OFFERING_NAME=test # name of the partner offering; use this variable to distinguish between the results tar for different offerings
CLUSTERNAME=arc-partner-test-$connectedClustedId # name of the arc connected cluster
LOCATION=eastus # location of the arc connected cluster

# Platform Cleanup Plugin
CLEANUP_TIMEOUT=1500 # time in seconds after which the platform cleanup plugin times out

# In case your cluster is behind an outbound proxy, please add the following environment variables in the below command
# --plugin-env azure-arc-platform.HTTPS_PROXY="http://<proxy ip>:<proxy port>"
# --plugin-env azure-arc-platform.HTTP_PROXY="http://<proxy ip>:<proxy port>"
# --plugin-env azure-arc-platform.NO_PROXY="kubernetes.default.svc,<ip CIDR etc>"

# In case your outbound proxy is setup with certificate authentication, follow the below steps:
# Create a Kubernetes generic secret with the name sonobuoy-proxy-cert with key proxycert in any namespace:
# kubectl create secret generic sonobuoy-proxy-cert --from-file=proxycert=<path-to-cert-file>
# By default we check for the secret in the default namespace. In case you have created the secret in some other namespace, please add the following variables in the sonobuoy run command: 
# --plugin-env azure-arc-platform.PROXY_CERT_NAMESPACE="<namespace of sonobuoy secret>"
# --plugin-env azure-arc-agent-cleanup.PROXY_CERT_NAMESPACE="namespace of sonobuoy secret"

az login --service-principal --username $AZ_CLIENT_ID --password $AZ_CLIENT_SECRET --tenant $AZ_TENANT_ID
az account set -s $AZ_SUBSCRIPTION_ID

while IFS= read -r arc_platform_version || [ -n "$arc_platform_version" ]; do

    echo "Running the test suite for Arc for Kubernetes version: ${arc_platform_version}"    

    sonobuoy run --wait \
    --plugin arc-k8s-platform/platform.yaml \
    --plugin-env azure-arc-platform.TENANT_ID=$AZ_TENANT_ID \
    --plugin-env azure-arc-platform.SUBSCRIPTION_ID=$AZ_SUBSCRIPTION_ID \
    --plugin-env azure-arc-platform.RESOURCE_GROUP=$RESOURCE_GROUP \
    --plugin-env azure-arc-platform.CLUSTER_NAME=$CLUSTERNAME \
    --plugin-env azure-arc-platform.LOCATION=$LOCATION \
    --plugin-env azure-arc-platform.CLIENT_ID=$AZ_CLIENT_ID \
    --plugin-env azure-arc-platform.CLIENT_SECRET=$AZ_CLIENT_SECRET \
    --plugin-env azure-arc-platform.HELMREGISTRY=mcr.microsoft.com/azurearck8s/batch1/stable/azure-arc-k8sagents:$arc_platform_version \
    --plugin arc-k8s-platform/cleanup.yaml \
    --plugin-env azure-arc-agent-cleanup.TENANT_ID=$AZ_TENANT_ID \
    --plugin-env azure-arc-agent-cleanup.SUBSCRIPTION_ID=$AZ_SUBSCRIPTION_ID \
    --plugin-env azure-arc-agent-cleanup.RESOURCE_GROUP=$RESOURCE_GROUP \
    --plugin-env azure-arc-agent-cleanup.CLUSTER_NAME=$CLUSTERNAME \
    --plugin-env azure-arc-agent-cleanup.CLEANUP_TIMEOUT=$CLEANUP_TIMEOUT \
    --plugin-env azure-arc-agent-cleanup.CLIENT_ID=$AZ_CLIENT_ID \
    --plugin-env azure-arc-agent-cleanup.CLIENT_SECRET=$AZ_CLIENT_SECRET \
    --plugin-env azure-arc-platform.OBJECT_ID=$AZ_OBJECT_ID \
    --config config.json \

    echo "Test execution completed..Retrieving results"

    sonobuoyResults=$(sonobuoy retrieve)
    sonobuoy results $sonobuoyResults
    mkdir results
    mv $sonobuoyResults results/$sonobuoyResults
    cp partner-metadata.md results/partner-metadata.md
    tar -czvf conformance-results-$arc_platform_version.tar.gz results
    rm -rf results

    echo "Publishing results.."

    IFS='.'
    read -ra version <<< $arc_platform_version
    containerString="conformance-results-major-${version[0]}-minor-${version[1]}-patch-${version[2]}"
    IFS=$' \t\n'

    az storage container create -n $containerString --account-name $AZ_STORAGE_ACCOUNT --sas-token $AZ_STORAGE_ACCOUNT_SAS
    az storage blob upload --file conformance-results-$arc_platform_version.tar.gz --name conformance-results-$OFFERING_NAME.tar.gz --container-name $containerString --account-name $AZ_STORAGE_ACCOUNT --sas-token $AZ_STORAGE_ACCOUNT_SAS

    echo "Cleaning the cluster.."
    sonobuoy delete --wait

    echo "Buffer wait 5 minutes..."
    sleep 5m

done < aak8sSupportPolicy.txt
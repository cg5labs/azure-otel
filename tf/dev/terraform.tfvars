# Set a subscription ID here when you need to target a subscription other than
# the one selected by Azure CLI or the AzureRM authentication environment.
subscription_id = "ebcd3e3d-6e5b-48ef-b0c9-cecb454edeec"


# Enable or disable various Azure Kubernetes Service (AKS) and monitoring features
enable_aks                          = true
enable_aks_worker_pool              = true
enable_azure_monitor_metrics        = true
enable_azure_monitor_logs           = true
enable_defender                     = false
enable_event_hub                    = true
otel_service_principal_display_name = "otel-azure-metrics-reader"

eventhub_namespace_name_prefix  = "otel-azure-dev-eh"
eventhub_name                   = "otel-azure-dev-aks-logs"
eventhub_capacity               = 1
eventhub_partition_count        = 2
eventhub_message_retention_days = 1

# Module configuration variables
resource_group_name             = "otel-azure-dev-rg"
location                        = "westus2"
workspace_name                  = "otel-azure-dev-law"
retention_in_days               = 30
daily_quota_gb                  = 1
allow_resource_only_permissions = true
internet_ingestion_enabled      = true
internet_query_enabled          = true
local_authentication_enabled    = true

environment = "dev"
tags        = {}

virtual_network_name            = "otel-azure-dev-vnet"
virtual_network_address_space   = ["10.20.0.0/16"]
aks_subnet_name                 = "aks"
aks_subnet_address_prefixes     = ["10.20.0.0/24"]
kubernetes_cluster_name         = "otel-azure-dev-aks"
dns_prefix                      = "otel-azure-dev"
kubernetes_version              = null
aks_admin_group_object_ids      = []
api_server_authorized_ip_ranges = ["116.89.33.134/32"]
service_cidr                    = "10.0.0.0/16"
dns_service_ip                  = "10.0.0.10"
pod_cidr                        = "10.244.0.0/16"

node_vm_size         = "Standard_D2s_v7"
node_count           = 1
spot_node_pool_name  = "spot"
spot_node_count      = 1
spot_max_price       = -1
node_os_disk_size_gb = 64
aks_sku_tier         = "Standard"

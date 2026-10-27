locals {
  common_tags = merge(var.tags, {
    environment = var.environment
    managed_by  = "OpenTofu"
  })

  aks_kubernetes_version  = var.kubernetes_version != null ? var.kubernetes_version : try(data.azurerm_kubernetes_service_versions.current[0].latest_version, null)
  subscription_suffix     = substr(lower(replace(data.azurerm_client_config.current.subscription_id, "-", "")), 0, 8)
  eventhub_namespace_name = "${var.eventhub_namespace_name_prefix}-${substr(lower(replace(data.azurerm_client_config.current.subscription_id, "-", "")), 0, 12)}"
  container_registry_name = "${var.container_registry_name_prefix}${local.subscription_suffix}"
}

data "azurerm_client_config" "current" {}

module "otel_service_principal" {
  count  = var.enable_aks && var.enable_azure_monitor_metrics ? 1 : 0
  source = "./modules/otel-service-principal"

  display_name = var.otel_service_principal_display_name
}

data "azurerm_kubernetes_service_versions" "current" {
  count           = var.enable_aks && var.kubernetes_version == null ? 1 : 0
  location        = var.location
  include_preview = false
}

resource "azurerm_resource_group" "this" {
  name     = var.resource_group_name
  location = var.location
  tags     = local.common_tags
}

resource "azurerm_virtual_network" "aks" {
  count               = var.enable_aks ? 1 : 0
  name                = var.virtual_network_name
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  address_space       = var.virtual_network_address_space
  tags                = local.common_tags
}

resource "azurerm_subnet" "aks" {
  count                = var.enable_aks ? 1 : 0
  name                 = var.aks_subnet_name
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = try(azurerm_virtual_network.aks[0].name, null)
  address_prefixes     = var.aks_subnet_address_prefixes
}

module "log_analytics" {
  source = "./modules/log-analytics"

  workspace_name                  = var.workspace_name
  location                        = azurerm_resource_group.this.location
  resource_group_name             = azurerm_resource_group.this.name
  retention_in_days               = var.retention_in_days
  daily_quota_gb                  = var.daily_quota_gb
  allow_resource_only_permissions = var.allow_resource_only_permissions
  internet_ingestion_enabled      = var.internet_ingestion_enabled
  internet_query_enabled          = var.internet_query_enabled
  local_authentication_enabled    = var.local_authentication_enabled
}

module "event_hub" {
  count  = var.enable_event_hub ? 1 : 0
  source = "./modules/event-hub"

  namespace_name         = local.eventhub_namespace_name
  eventhub_name          = var.eventhub_name
  location               = azurerm_resource_group.this.location
  resource_group_name    = azurerm_resource_group.this.name
  workspace_resource_id  = module.log_analytics.workspace_id
  table_names            = var.eventhub_export_tables
  terraform_principal_id = data.azurerm_client_config.current.object_id
  capacity               = var.eventhub_capacity
  partition_count        = var.eventhub_partition_count
  message_retention_days = var.eventhub_message_retention_days
  tags                   = local.common_tags
}

module "aks_control_plane" {
  count  = var.enable_aks ? 1 : 0
  source = "./modules/aks-control-plane"

  cluster_name                     = var.kubernetes_cluster_name
  dns_prefix                       = var.dns_prefix
  location                         = azurerm_resource_group.this.location
  resource_group_name              = azurerm_resource_group.this.name
  resource_group_id                = azurerm_resource_group.this.id
  subscription_id                  = data.azurerm_client_config.current.subscription_id
  tenant_id                        = data.azurerm_client_config.current.tenant_id
  kubectl_principal_id             = data.azurerm_client_config.current.object_id
  otel_service_principal_object_id = try(module.otel_service_principal[0].object_id, null)
  kubernetes_version               = local.aks_kubernetes_version
  subnet_id                        = try(azurerm_subnet.aks[0].id, null)
  log_analytics_workspace_id       = module.log_analytics.workspace_id
  aks_admin_group_object_ids       = var.aks_admin_group_object_ids
  api_server_authorized_ip_ranges  = var.api_server_authorized_ip_ranges
  node_vm_size                     = var.node_vm_size
  node_count                       = var.node_count
  node_os_disk_size_gb             = var.node_os_disk_size_gb
  aks_sku_tier                     = var.aks_sku_tier
  service_cidr                     = var.service_cidr
  dns_service_ip                   = var.dns_service_ip
  pod_cidr                         = var.pod_cidr
  enable_azure_monitor_metrics     = var.enable_azure_monitor_metrics
  enable_otel_metrics_reader       = var.enable_azure_monitor_metrics
  enable_azure_monitor_logs        = var.enable_azure_monitor_logs
  enable_defender                  = var.enable_defender
  tags                             = local.common_tags
}

module "container_registry" {
  count  = var.enable_container_registry ? 1 : 0
  source = "./modules/container-registry"

  name                       = local.container_registry_name
  resource_group_name        = azurerm_resource_group.this.name
  location                   = azurerm_resource_group.this.location
  tags                       = local.common_tags
  assign_aks_pull_role       = var.enable_aks
  kubelet_identity_object_id = try(module.aks_control_plane[0].kubelet_identity_object_id, null)
}

module "aks_worker" {
  count  = var.enable_aks && var.enable_aks_worker_pool ? 1 : 0
  source = "./modules/aks-worker"

  cluster_id           = try(module.aks_control_plane[0].cluster_id, null)
  kubernetes_version   = try(module.aks_control_plane[0].kubernetes_version, null)
  subnet_id            = try(azurerm_subnet.aks[0].id, null)
  node_pool_name       = var.spot_node_pool_name
  node_vm_size         = var.node_vm_size
  node_count           = var.spot_node_count
  node_os_disk_size_gb = var.node_os_disk_size_gb
  spot_max_price       = var.spot_max_price
  tags                 = local.common_tags
}

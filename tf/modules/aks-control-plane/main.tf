resource "azurerm_kubernetes_cluster" "this" {
  name                = var.cluster_name
  location            = var.location
  resource_group_name = var.resource_group_name
  dns_prefix          = var.dns_prefix
  kubernetes_version  = var.kubernetes_version
  sku_tier            = var.aks_sku_tier

  automatic_upgrade_channel         = "patch"
  azure_policy_enabled              = true
  local_account_disabled            = true
  oidc_issuer_enabled               = true
  workload_identity_enabled         = true
  private_cluster_enabled           = false
  role_based_access_control_enabled = true

  default_node_pool {
    name                         = var.system_node_pool_name
    vm_size                      = var.node_vm_size
    node_count                   = var.node_count
    type                         = "VirtualMachineScaleSets"
    vnet_subnet_id               = var.subnet_id
    os_sku                       = "AzureLinux"
    os_disk_size_gb              = var.node_os_disk_size_gb
    only_critical_addons_enabled = false
  }

  identity {
    type = "SystemAssigned"
  }

  azure_active_directory_role_based_access_control {
    tenant_id              = var.tenant_id
    azure_rbac_enabled     = true
    admin_group_object_ids = var.aks_admin_group_object_ids
  }

  api_server_access_profile {
    authorized_ip_ranges = var.api_server_authorized_ip_ranges
  }

  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    network_data_plane  = "cilium"
    network_policy      = "cilium"
    pod_cidr            = var.pod_cidr
    service_cidr        = var.service_cidr
    dns_service_ip      = var.dns_service_ip
    outbound_type       = "loadBalancer"
  }

  dynamic "monitor_metrics" {
    for_each = var.enable_azure_monitor_metrics ? [true] : []

    content {}
  }

  dynamic "oms_agent" {
    for_each = var.enable_azure_monitor_logs ? [true] : []

    content {
      log_analytics_workspace_id      = var.log_analytics_workspace_id
      msi_auth_for_monitoring_enabled = true
    }
  }

  dynamic "microsoft_defender" {
    for_each = var.enable_defender ? [true] : []

    content {
      log_analytics_workspace_id = var.log_analytics_workspace_id
    }
  }

  tags = var.tags
}

locals {
  otel_metrics_reader_enabled = var.enable_otel_metrics_reader
}

resource "azurerm_role_definition" "otel_resource_discovery" {
  count = local.otel_metrics_reader_enabled ? 1 : 0

  name        = "Azure Monitor Metrics Resource Discovery Reader"
  scope       = "/subscriptions/${var.subscription_id}"
  description = "Allows the OpenTelemetry Azure Monitor receiver to discover subscription resources."

  permissions {
    actions     = ["Microsoft.Resources/subscriptions/resources/read"]
    not_actions = []
  }

  assignable_scopes = ["/subscriptions/${var.subscription_id}"]
}

resource "azurerm_role_assignment" "otel_resource_discovery" {
  count = local.otel_metrics_reader_enabled ? 1 : 0

  scope              = "/subscriptions/${var.subscription_id}"
  role_definition_id = azurerm_role_definition.otel_resource_discovery[0].role_definition_resource_id
  principal_id       = var.otel_service_principal_object_id
  principal_type     = "ServicePrincipal"
}

resource "azurerm_role_assignment" "otel_monitoring_reader" {
  count = local.otel_metrics_reader_enabled ? 1 : 0

  scope                = var.resource_group_id
  role_definition_name = "Monitoring Reader"
  principal_id         = var.otel_service_principal_object_id
  principal_type       = "ServicePrincipal"
}

locals {
  container_insights_streams = [
    "Microsoft-ContainerLogV2",
    "Microsoft-KubeEvents",
    "Microsoft-KubePodInventory",
  ]
}

resource "azurerm_monitor_data_collection_rule" "container_insights" {
  count = var.enable_azure_monitor_logs ? 1 : 0

  name                = "MSCI-${var.location}-${var.cluster_name}"
  resource_group_name = var.resource_group_name
  location            = var.location
  kind                = "Linux"
  description         = "Container Insights data collection rule for ${var.cluster_name}."

  destinations {
    log_analytics {
      name                  = "ciworkspace"
      workspace_resource_id = var.log_analytics_workspace_id
    }
  }

  data_flow {
    streams      = local.container_insights_streams
    destinations = ["ciworkspace"]
  }

  data_sources {
    extension {
      name           = "ContainerInsightsExtension"
      extension_name = "ContainerInsights"
      streams        = local.container_insights_streams
      extension_json = jsonencode({
        dataCollectionSettings = {
          interval               = "1m"
          namespaceFilteringMode = "Off"
          enableContainerLogV2   = true
        }
      })
    }
  }

  tags = var.tags
}

resource "azurerm_monitor_data_collection_rule_association" "container_insights" {
  count = var.enable_azure_monitor_logs ? 1 : 0

  name                    = "ContainerInsightsExtension"
  target_resource_id      = azurerm_kubernetes_cluster.this.id
  data_collection_rule_id = azurerm_monitor_data_collection_rule.container_insights[0].id
  description             = "Associates Container Insights collection with ${var.cluster_name}."
}

resource "azurerm_role_assignment" "kubectl_access" {
  for_each = toset([
    "Azure Kubernetes Service Cluster User Role",
    "Azure Kubernetes Service RBAC Cluster Admin",
  ])

  scope                = azurerm_kubernetes_cluster.this.id
  role_definition_name = each.value
  principal_id         = var.kubectl_principal_id
}

resource "azurerm_monitor_diagnostic_setting" "this" {
  count = var.enable_azure_monitor_logs ? 1 : 0

  name                       = "${var.cluster_name}-diagnostics"
  target_resource_id         = azurerm_kubernetes_cluster.this.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  dynamic "enabled_log" {
    for_each = var.control_plane_log_categories

    content {
      category = enabled_log.value
    }
  }
}

data "azurerm_client_config" "current" {}

resource "azurerm_log_analytics_workspace" "this" {
  name                            = var.workspace_name
  location                        = var.location
  resource_group_name             = var.resource_group_name
  sku                             = "PerGB2018"
  retention_in_days               = var.retention_in_days
  daily_quota_gb                  = var.daily_quota_gb
  allow_resource_only_permissions = var.allow_resource_only_permissions
  internet_ingestion_enabled      = var.internet_ingestion_enabled
  internet_query_enabled          = var.internet_query_enabled
  local_authentication_enabled    = var.local_authentication_enabled
}

resource "azurerm_role_assignment" "current_user_log_analytics_data_reader" {
  scope                = azurerm_log_analytics_workspace.this.id
  role_definition_name = "Log Analytics Data Reader"
  principal_id         = data.azurerm_client_config.current.object_id
}

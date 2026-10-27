resource "azurerm_eventhub_namespace" "this" {
  name                = var.namespace_name
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "Standard"
  capacity            = var.capacity
  tags                = var.tags
}

resource "azurerm_eventhub" "this" {
  name              = var.eventhub_name
  namespace_id      = azurerm_eventhub_namespace.this.id
  partition_count   = var.partition_count
  message_retention = var.message_retention_days
}

resource "azurerm_eventhub_authorization_rule" "otel_collector" {
  name                = "otel-collector-listen"
  resource_group_name = var.resource_group_name
  namespace_name      = azurerm_eventhub_namespace.this.name
  eventhub_name       = azurerm_eventhub.this.name
  listen              = true
  send                = false
  manage              = false
}

resource "azurerm_role_assignment" "data_export" {
  scope                = azurerm_eventhub_namespace.this.id
  role_definition_name = "Azure Event Hubs Data Owner"
  principal_id         = var.terraform_principal_id
}

resource "azurerm_log_analytics_data_export_rule" "aks" {
  name                    = var.data_export_rule_name
  resource_group_name     = var.resource_group_name
  workspace_resource_id   = var.workspace_resource_id
  destination_resource_id = azurerm_eventhub.this.id
  table_names             = var.table_names
  enabled                 = true

  depends_on = [azurerm_role_assignment.data_export]
}

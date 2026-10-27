output "workspace_id" {
  description = "Azure resource ID of the Log Analytics workspace."
  value       = azurerm_log_analytics_workspace.this.id
}

output "workspace_customer_id" {
  description = "Customer ID used by the Log Analytics query API."
  value       = azurerm_log_analytics_workspace.this.workspace_id
}

output "workspace_name" {
  description = "Name of the Log Analytics workspace."
  value       = azurerm_log_analytics_workspace.this.name
}

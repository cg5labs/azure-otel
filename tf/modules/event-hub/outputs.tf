output "namespace_id" {
  description = "Azure resource ID of the Event Hubs namespace."
  value       = azurerm_eventhub_namespace.this.id
}

output "namespace_name" {
  description = "Name of the Event Hubs namespace."
  value       = azurerm_eventhub_namespace.this.name
}

output "eventhub_id" {
  description = "Azure resource ID of the Event Hub."
  value       = azurerm_eventhub.this.id
}

output "eventhub_name" {
  description = "Name of the Event Hub."
  value       = azurerm_eventhub.this.name
}

output "listen_connection_string" {
  description = "Listen-only SAS connection string for the OTEL Collector."
  value       = azurerm_eventhub_authorization_rule.otel_collector.primary_connection_string
  sensitive   = true
}

output "consumer_group" {
  description = "Default Event Hub consumer group."
  value       = "$Default"
}

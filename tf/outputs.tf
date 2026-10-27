output "resource_group_name" {
  description = "Name of the resource group containing the Log Analytics workspace."
  value       = azurerm_resource_group.this.name
}

output "subscription_id" {
  description = "Azure subscription ID selected for this deployment."
  value       = data.azurerm_client_config.current.subscription_id
}

output "workspace_id" {
  description = "Azure resource ID of the Log Analytics workspace."
  value       = module.log_analytics.workspace_id
}

output "workspace_customer_id" {
  description = "Customer ID used by the Log Analytics query API."
  value       = module.log_analytics.workspace_customer_id
}

output "workspace_name" {
  description = "Name of the Log Analytics workspace."
  value       = module.log_analytics.workspace_name
}

output "container_registry_id" {
  description = "Azure resource ID of the container registry, or null when disabled."
  value       = try(module.container_registry[0].registry_id, null)
}

output "container_registry_name" {
  description = "Name of the container registry, or null when disabled."
  value       = try(module.container_registry[0].registry_name, null)
}

output "container_registry_login_server" {
  description = "Login server for tagging and pulling images, or null when disabled."
  value       = try(module.container_registry[0].login_server, null)
}

output "eventhub_namespace_name" {
  description = "Name of the Event Hubs namespace receiving Log Analytics exports."
  value       = try(module.event_hub[0].namespace_name, null)
}

output "eventhub_name" {
  description = "Name of the Event Hub receiving Log Analytics exports."
  value       = try(module.event_hub[0].eventhub_name, null)
}

output "eventhub_resource_id" {
  description = "Azure resource ID of the Event Hub receiving Log Analytics exports."
  value       = try(module.event_hub[0].eventhub_id, null)
}

output "eventhub_sas_connection_string" {
  description = "Listen-only SAS connection string for the OTEL Collector."
  value       = try(module.event_hub[0].listen_connection_string, null)
  sensitive   = true
}

output "eventhub_consumer_group" {
  description = "Consumer group for the OTEL Collector."
  value       = try(module.event_hub[0].consumer_group, null)
}

output "kubernetes_cluster_name" {
  description = "Name of the AKS cluster."
  value       = try(module.aks_control_plane[0].cluster_name, null)
}

output "kubernetes_cluster_id" {
  description = "Azure resource ID of the AKS cluster."
  value       = try(module.aks_control_plane[0].cluster_id, null)
}

output "kubernetes_version" {
  description = "AKS Kubernetes version used by the control plane."
  value       = try(module.aks_control_plane[0].kubernetes_version, null)
}

output "otel_service_principal_object_id" {
  description = "Microsoft Entra object ID of the OTEL service principal."
  value       = try(module.otel_service_principal[0].object_id, null)
}

output "otel_service_principal_client_id" {
  description = "Client ID of the OTEL service principal."
  value       = try(module.otel_service_principal[0].client_id, null)
}

output "otel_service_principal_tenant_id" {
  description = "Microsoft Entra tenant ID for the OTEL service principal."
  value       = try(module.otel_service_principal[0].tenant_id, null)
}

output "otel_service_principal_client_secret" {
  description = "Sensitive client secret for OTEL collector authentication; expires 12 months after creation."
  value       = try(module.otel_service_principal[0].client_secret, null)
  sensitive   = true
}

output "worker_node_pool_name" {
  description = "Name of the Spot AKS worker node pool."
  value       = try(module.aks_worker[0].node_pool_name, null)
}

output "worker_node_pool_id" {
  description = "Azure resource ID of the Spot AKS worker node pool."
  value       = try(module.aks_worker[0].node_pool_id, null)
}

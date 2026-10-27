output "node_pool_id" {
  description = "Azure resource ID of the AKS worker node pool."
  value       = azurerm_kubernetes_cluster_node_pool.this.id
}

output "node_pool_name" {
  description = "Name of the AKS worker node pool."
  value       = azurerm_kubernetes_cluster_node_pool.this.name
}

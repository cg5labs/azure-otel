output "cluster_id" {
  description = "Azure resource ID of the AKS cluster."
  value       = azurerm_kubernetes_cluster.this.id
}

output "cluster_name" {
  description = "Name of the AKS cluster."
  value       = azurerm_kubernetes_cluster.this.name
}

output "kubelet_identity_object_id" {
  description = "Object ID of the managed identity used by AKS nodes."
  value       = azurerm_kubernetes_cluster.this.kubelet_identity[0].object_id
}

output "kubernetes_version" {
  description = "AKS Kubernetes version used by the control plane."
  value       = azurerm_kubernetes_cluster.this.kubernetes_version
}

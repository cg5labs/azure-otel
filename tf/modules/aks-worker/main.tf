resource "azurerm_kubernetes_cluster_node_pool" "this" {
  name                  = var.node_pool_name
  kubernetes_cluster_id = var.cluster_id
  orchestrator_version  = var.kubernetes_version
  vm_size               = var.node_vm_size
  node_count            = var.node_count
  os_type               = "Linux"
  os_sku                = "AzureLinux"
  os_disk_size_gb       = var.node_os_disk_size_gb
  vnet_subnet_id        = var.subnet_id
  mode                  = "User"
  auto_scaling_enabled  = false
  priority              = "Spot"
  eviction_policy       = "Delete"
  spot_max_price        = var.spot_max_price

  node_labels = {
    "kubernetes.azure.com/scalesetpriority" = "spot"
  }

  node_taints = [
    "kubernetes.azure.com/scalesetpriority=spot:NoSchedule",
  ]

  tags = var.tags
}

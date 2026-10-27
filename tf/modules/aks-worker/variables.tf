variable "cluster_id" {
  description = "Azure resource ID of the AKS cluster."
  type        = string
}

variable "kubernetes_version" {
  description = "AKS Kubernetes version to use for the worker pool."
  type        = string
}

variable "subnet_id" {
  description = "Subnet resource ID for the worker nodes."
  type        = string
}

variable "node_pool_name" {
  description = "Name of the Spot-priority user node pool."
  type        = string
  default     = "spot"
}

variable "node_vm_size" {
  description = "Azure VM size for the Spot worker nodes."
  type        = string
}

variable "node_count" {
  description = "Fixed Spot worker node pool size."
  type        = number
}

variable "node_os_disk_size_gb" {
  description = "Managed OS disk size in GiB for the Spot worker nodes."
  type        = number
}

variable "spot_max_price" {
  description = "Maximum Spot VM price in USD; -1 allows up to the on-demand price."
  type        = number

  validation {
    condition     = var.spot_max_price == -1 || var.spot_max_price > 0
    error_message = "spot_max_price must be -1 or a positive price in USD."
  }
}

variable "tags" {
  description = "Tags applied to the worker node pool."
  type        = map(string)
  default     = {}
}

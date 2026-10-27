variable "cluster_name" {
  description = "Name of the AKS cluster."
  type        = string
}

variable "dns_prefix" {
  description = "DNS prefix for the AKS-managed API server endpoint."
  type        = string
}

variable "location" {
  description = "Azure region for the AKS cluster."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group containing the AKS cluster."
  type        = string
}

variable "resource_group_id" {
  description = "Resource ID of the resource group containing the AKS cluster."
  type        = string
}

variable "subscription_id" {
  description = "Azure subscription ID containing the AKS cluster."
  type        = string
}

variable "tenant_id" {
  description = "Microsoft Entra tenant ID for AKS Azure RBAC."
  type        = string
}

variable "kubectl_principal_id" {
  description = "Object ID of the Terraform caller granted AKS cluster-user and cluster-admin roles."
  type        = string
}

variable "kubernetes_version" {
  description = "AKS Kubernetes version."
  type        = string
}

variable "subnet_id" {
  description = "Subnet resource ID for AKS nodes."
  type        = string
}

variable "log_analytics_workspace_id" {
  description = "Log Analytics workspace resource ID for AKS monitoring."
  type        = string
}

variable "aks_admin_group_object_ids" {
  description = "Microsoft Entra group object IDs granted AKS cluster-admin access through Azure RBAC."
  type        = list(string)
  default     = []
}

variable "api_server_authorized_ip_ranges" {
  description = "Public IPv4 CIDRs allowed to reach the AKS API server."
  type        = list(string)

  validation {
    condition = length(var.api_server_authorized_ip_ranges) > 0 && alltrue([
      for cidr in var.api_server_authorized_ip_ranges :
      can(cidrhost(cidr, 0)) && !strcontains(cidr, ":") && cidr != "0.0.0.0/0"
    ])
    error_message = "Provide at least one valid API server CIDR and do not allow all IPv4 or IPv6 addresses."
  }
}

variable "system_node_pool_name" {
  description = "Name of the AKS-required system node pool."
  type        = string
  default     = "system"
}

variable "node_vm_size" {
  description = "Azure VM size used by the AKS system node pool."
  type        = string
}

variable "node_count" {
  description = "Fixed system node pool size."
  type        = number
}

variable "node_os_disk_size_gb" {
  description = "Managed OS disk size in GiB for AKS nodes."
  type        = number
}

variable "aks_sku_tier" {
  description = "AKS control-plane tier."
  type        = string
}

variable "service_cidr" {
  description = "IPv4 CIDR used for Kubernetes ClusterIP services."
  type        = string
}

variable "dns_service_ip" {
  description = "IP address for the Kubernetes DNS service."
  type        = string
}

variable "pod_cidr" {
  description = "IPv4 CIDR used for Azure CNI Overlay pods."
  type        = string
}

variable "enable_azure_monitor_metrics" {
  description = "Enable Azure Monitor managed metrics for AKS."
  type        = bool
  default     = true
}

variable "enable_otel_metrics_reader" {
  description = "Enable OTEL service-principal metrics reader role assignments."
  type        = bool
  default     = false
}

variable "otel_service_principal_object_id" {
  description = "Optional object ID of the OpenTelemetry service principal granted Azure Monitor metrics read access."
  type        = string
  default     = null
  nullable    = true

  validation {
    condition = var.otel_service_principal_object_id == null ? true : can(regex(
      "^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$",
      var.otel_service_principal_object_id
    ))
    error_message = "otel_service_principal_object_id must be null or a UUID."
  }
}

variable "enable_azure_monitor_logs" {
  description = "Enable Container Insights and AKS control-plane diagnostic logs to Log Analytics."
  type        = bool
  default     = true
}

variable "control_plane_log_categories" {
  description = "AKS control-plane diagnostic log categories sent to Log Analytics when logging is enabled."
  type        = set(string)
  default = [
    "kube-audit",
    "kube-audit-admin",
    "kube-apiserver",
    "kube-controller-manager",
    "kube-scheduler",
    "cluster-autoscaler",
  ]
}

variable "enable_defender" {
  description = "Enable the Microsoft Defender for Containers integration."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags applied to the AKS cluster."
  type        = map(string)
  default     = {}
}

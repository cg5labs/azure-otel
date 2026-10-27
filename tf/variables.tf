variable "subscription_id" {
  description = "Azure subscription ID. Null uses the subscription selected by Azure CLI or AzureRM environment authentication."
  type        = string
  default     = null
  nullable    = true
}

variable "resource_group_name" {
  description = "Name of the resource group containing the observability and AKS resources."
  type        = string
  default     = "otel-azure-dev-rg"
}

variable "location" {
  description = "Azure region for the resource group, Log Analytics workspace, and AKS cluster."
  type        = string
  default     = "westus2"
}

variable "workspace_name" {
  description = "Name of the Log Analytics workspace."
  type        = string
  default     = "otel-azure-dev-law"
}

variable "retention_in_days" {
  description = "Log Analytics workspace retention in days."
  type        = number
  default     = 30

  validation {
    condition     = var.retention_in_days >= 30 && var.retention_in_days <= 730 && floor(var.retention_in_days) == var.retention_in_days
    error_message = "retention_in_days must be a whole number between 30 and 730."
  }
}

variable "daily_quota_gb" {
  description = "Daily Log Analytics ingestion quota in GiB; use -1 for unlimited."
  type        = number
  default     = 1

  validation {
    condition     = var.daily_quota_gb == -1 || var.daily_quota_gb >= 0.5
    error_message = "daily_quota_gb must be -1 (unlimited) or at least 0.5 GiB."
  }
}

variable "allow_resource_only_permissions" {
  description = "Allow workspace access to be authorized by resource-level permissions."
  type        = bool
  default     = true
}

variable "internet_ingestion_enabled" {
  description = "Allow public network access for Log Analytics ingestion."
  type        = bool
  default     = true
}

variable "internet_query_enabled" {
  description = "Allow public network access for Log Analytics queries."
  type        = bool
  default     = true
}

variable "local_authentication_enabled" {
  description = "Allow local authentication for the Log Analytics workspace."
  type        = bool
  default     = true
}

variable "environment" {
  description = "Environment label applied to Azure resource tags."
  type        = string
  default     = "dev"
}

variable "tags" {
  description = "Additional tags applied to Azure resources."
  type        = map(string)
  default     = {}
}

variable "virtual_network_name" {
  description = "Name of the virtual network used by AKS."
  type        = string
  default     = "otel-azure-dev-vnet"
}

variable "virtual_network_address_space" {
  description = "IPv4 address space for the AKS virtual network."
  type        = list(string)
  default     = ["10.20.0.0/16"]

  validation {
    condition = length(var.virtual_network_address_space) > 0 && alltrue([
      for cidr in var.virtual_network_address_space :
      can(cidrhost(cidr, 0)) && !strcontains(cidr, ":")
    ])
    error_message = "virtual_network_address_space must contain valid IPv4 CIDRs."
  }
}

variable "aks_subnet_name" {
  description = "Name of the subnet used by AKS nodes."
  type        = string
  default     = "aks"
}

variable "aks_subnet_address_prefixes" {
  description = "IPv4 address prefixes assigned to the AKS subnet."
  type        = list(string)
  default     = ["10.20.0.0/24"]

  validation {
    condition = length(var.aks_subnet_address_prefixes) > 0 && alltrue([
      for cidr in var.aks_subnet_address_prefixes :
      can(cidrhost(cidr, 0)) && !strcontains(cidr, ":")
    ])
    error_message = "aks_subnet_address_prefixes must contain valid IPv4 CIDRs."
  }
}

variable "kubernetes_cluster_name" {
  description = "Name of the AKS cluster."
  type        = string
  default     = "otel-azure-dev-aks"

  validation {
    condition     = can(regex("^[a-z]([a-z0-9-]{0,61}[a-z0-9])?$", var.kubernetes_cluster_name))
    error_message = "kubernetes_cluster_name must be 1-63 lowercase letters, digits, or hyphens, start with a letter, and end with a letter or digit."
  }
}

variable "dns_prefix" {
  description = "DNS prefix for the AKS-managed API server endpoint."
  type        = string
  default     = "otel-azure-dev"

  validation {
    condition     = can(regex("^[a-z]([a-z0-9-]{0,52}[a-z0-9])?$", var.dns_prefix))
    error_message = "dns_prefix must be 1-54 lowercase letters, digits, or hyphens, start with a letter, and end with a letter or digit."
  }
}

variable "kubernetes_version" {
  description = "Optional AKS version pin. Null selects the latest supported non-preview version in the configured region."
  type        = string
  default     = null
  nullable    = true
}

variable "aks_admin_group_object_ids" {
  description = "Microsoft Entra group object IDs granted AKS cluster-admin access through Azure RBAC."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for object_id in var.aks_admin_group_object_ids : can(regex("^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$", object_id))])
    error_message = "Each AKS admin group object ID must be a UUID."
  }
}

variable "api_server_authorized_ip_ranges" {
  description = "Public IPv4 CIDRs allowed to reach the AKS API server. Replace the development default with your operator egress range; 0.0.0.0/0 is not allowed."
  type        = list(string)
  default     = ["182.19.216.0/24"]

  validation {
    condition = length(var.api_server_authorized_ip_ranges) > 0 && alltrue([
      for cidr in var.api_server_authorized_ip_ranges :
      can(cidrhost(cidr, 0)) && !strcontains(cidr, ":") && cidr != "0.0.0.0/0"
    ])
    error_message = "Provide at least one valid API server CIDR and do not allow all IPv4 or IPv6 addresses."
  }
}

variable "service_cidr" {
  description = "IPv4 CIDR used for Kubernetes ClusterIP services."
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrhost(var.service_cidr, 0)) && !strcontains(var.service_cidr, ":")
    error_message = "service_cidr must be a valid IPv4 CIDR."
  }
}

variable "dns_service_ip" {
  description = "IP address for the Kubernetes DNS service, inside service_cidr."
  type        = string
  default     = "10.0.0.10"

  validation {
    condition     = can(cidrhost("${var.dns_service_ip}/32", 0)) && !strcontains(var.dns_service_ip, ":")
    error_message = "dns_service_ip must be a valid IPv4 address."
  }
}

variable "pod_cidr" {
  description = "IPv4 CIDR used for Azure CNI Overlay pods."
  type        = string
  default     = "10.244.0.0/16"

  validation {
    condition     = can(cidrhost(var.pod_cidr, 0)) && !strcontains(var.pod_cidr, ":")
    error_message = "pod_cidr must be a valid IPv4 CIDR."
  }
}

variable "node_vm_size" {
  description = "Azure VM size used by the AKS system pool and Spot worker pool."
  type        = string
  default     = "Standard_D2s_v7"
}

variable "node_count" {
  description = "Fixed system node pool size."
  type        = number
  default     = 1

  validation {
    condition     = var.node_count >= 1 && var.node_count <= 100 && floor(var.node_count) == var.node_count
    error_message = "node_count must be a whole number between 1 and 100."
  }
}

variable "spot_node_pool_name" {
  description = "Name of the Spot-priority AKS user node pool."
  type        = string
  default     = "spot"
}

variable "spot_node_count" {
  description = "Fixed Spot worker node pool size."
  type        = number
  default     = 1

  validation {
    condition     = var.spot_node_count >= 1 && var.spot_node_count <= 100 && floor(var.spot_node_count) == var.spot_node_count
    error_message = "spot_node_count must be a whole number between 1 and 100."
  }
}

variable "spot_max_price" {
  description = "Maximum Spot VM price in USD; -1 allows up to the on-demand price."
  type        = number
  default     = -1

  validation {
    condition     = var.spot_max_price == -1 || var.spot_max_price > 0
    error_message = "spot_max_price must be -1 or a positive price in USD."
  }
}

variable "node_os_disk_size_gb" {
  description = "Managed OS disk size in GiB for AKS nodes."
  type        = number
  default     = 64

  validation {
    condition     = var.node_os_disk_size_gb >= 30 && floor(var.node_os_disk_size_gb) == var.node_os_disk_size_gb
    error_message = "node_os_disk_size_gb must be a whole number of at least 30 GiB."
  }
}

variable "aks_sku_tier" {
  description = "AKS control-plane tier. Standard is billable; Free is available for development."
  type        = string
  default     = "Standard"

  validation {
    condition     = contains(["Free", "Standard", "Premium"], var.aks_sku_tier)
    error_message = "aks_sku_tier must be Free, Standard, or Premium."
  }
}

variable "enable_azure_monitor_metrics" {
  description = "Enable Azure Monitor managed metrics for AKS."
  type        = bool
  default     = true
}

variable "otel_service_principal_display_name" {
  description = "Display name of the Entra application and service principal used by the OTEL collector."
  type        = string
  default     = "otel-azure-metrics-reader"
}

variable "enable_aks" {
  description = "Provision the AKS network, control plane, and any enabled worker pool."
  type        = bool
  default     = true
}

variable "enable_aks_worker_pool" {
  description = "Provision the Spot worker pool when AKS is enabled."
  type        = bool
  default     = true
}

variable "enable_container_registry" {
  description = "Provision an Azure Container Registry for AKS workloads."
  type        = bool
  default     = true
}

variable "container_registry_name_prefix" {
  description = "Lowercase alphanumeric prefix for the globally unique container registry name."
  type        = string
  default     = "otelazuredevacr"

  validation {
    condition     = length(var.container_registry_name_prefix) >= 5 && length(var.container_registry_name_prefix) <= 42 && can(regex("^[a-z0-9]+$", var.container_registry_name_prefix))
    error_message = "container_registry_name_prefix must be 5-42 lowercase letters or numbers."
  }
}

variable "enable_azure_monitor_logs" {
  description = "Enable Container Insights and AKS control-plane diagnostic logs to Log Analytics."
  type        = bool
  default     = true
}

variable "enable_defender" {
  description = "Enable the billable Microsoft Defender for Containers integration."
  type        = bool
  default     = false
}

variable "enable_event_hub" {
  description = "Provision Event Hubs and export supported AKS tables from Log Analytics."
  type        = bool
  default     = true
}

variable "eventhub_namespace_name_prefix" {
  description = "Prefix for the globally unique Event Hubs namespace name; a subscription-derived suffix is added."
  type        = string
  default     = "otel-azure-dev-eh"

  validation {
    condition     = length(var.eventhub_namespace_name_prefix) >= 6 && length(var.eventhub_namespace_name_prefix) <= 37 && can(regex("^[A-Za-z0-9][A-Za-z0-9-]*[A-Za-z0-9]$", var.eventhub_namespace_name_prefix))
    error_message = "eventhub_namespace_name_prefix must be 6-37 characters, contain only letters, digits, or hyphens, and begin and end with a letter or digit."
  }
}

variable "eventhub_name" {
  description = "Name of the Event Hub receiving Log Analytics exports."
  type        = string
  default     = "otel-azure-dev-aks-logs"
}

variable "eventhub_capacity" {
  description = "Standard Event Hubs namespace throughput units."
  type        = number
  default     = 1
}

variable "eventhub_partition_count" {
  description = "Number of partitions in the Event Hub."
  type        = number
  default     = 2
}

variable "eventhub_message_retention_days" {
  description = "Number of days Event Hub messages are retained."
  type        = number
  default     = 1
}

variable "eventhub_export_tables" {
  description = "Supported AKS diagnostic and Container Insights tables exported continuously to Event Hubs."
  type        = set(string)
  default = [
    "AKSAudit",
    "AKSAuditAdmin",
    "AKSControlPlane",
    "AzureDiagnostics",
    "ContainerInventory",
    "ContainerLog",
    "ContainerLogV2",
    "ContainerNodeInventory",
    "ContainerNodeStatus",
    "ContainerPodInventory",
    "ContainerServiceLog",
    "InsightsMetrics",
    "KubeEvents",
    "KubeHealth",
    "KubeMonAgentEvents",
    "KubeNodeInventory",
    "KubePodInventory",
    "KubePVInventory",
    "KubeServices",
    "Perf",
  ]
}

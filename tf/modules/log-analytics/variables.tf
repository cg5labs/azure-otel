variable "workspace_name" {
  description = "Name of the Log Analytics workspace."
  type        = string
  default     = "otel-azure-dev-law"

  validation {
    condition     = length(var.workspace_name) >= 4 && length(var.workspace_name) <= 63 && can(regex("^[A-Za-z0-9][A-Za-z0-9-]*[A-Za-z0-9]$", var.workspace_name))
    error_message = "workspace_name must be 4-63 characters, contain only letters, digits, and hyphens, and begin and end with a letter or digit."
  }
}

variable "location" {
  description = "Azure region for the Log Analytics workspace."
  type        = string
  default     = "westus2"
}

variable "resource_group_name" {
  description = "Name of the resource group containing the workspace."
  type        = string
  default     = "otel-azure-dev-rg"
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

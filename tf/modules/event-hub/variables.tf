variable "namespace_name" {
  description = "Globally unique name of the Event Hubs namespace."
  type        = string
}

variable "eventhub_name" {
  description = "Name of the Event Hub receiving Log Analytics exports."
  type        = string
}

variable "location" {
  description = "Azure region for the Event Hubs namespace."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group for the Event Hubs namespace and export rule."
  type        = string
}

variable "workspace_resource_id" {
  description = "Resource ID of the Log Analytics workspace to export."
  type        = string
}

variable "data_export_rule_name" {
  description = "Name of the Log Analytics data export rule."
  type        = string
  default     = "aks-eventhub-export"
}

variable "table_names" {
  description = "Supported Log Analytics tables continuously exported to the Event Hub."
  type        = set(string)
}

variable "terraform_principal_id" {
  description = "Object ID of the identity creating the Log Analytics export rule."
  type        = string
}

variable "capacity" {
  description = "Standard Event Hubs namespace throughput units."
  type        = number
  default     = 1

  validation {
    condition     = var.capacity >= 1 && var.capacity <= 20 && floor(var.capacity) == var.capacity
    error_message = "capacity must be a whole number between 1 and 20."
  }
}

variable "partition_count" {
  description = "Number of partitions in the Event Hub."
  type        = number
  default     = 2

  validation {
    condition     = var.partition_count >= 1 && var.partition_count <= 32 && floor(var.partition_count) == var.partition_count
    error_message = "partition_count must be a whole number between 1 and 32."
  }
}

variable "message_retention_days" {
  description = "Number of days Event Hub messages are retained."
  type        = number
  default     = 1

  validation {
    condition     = var.message_retention_days >= 1 && var.message_retention_days <= 7 && floor(var.message_retention_days) == var.message_retention_days
    error_message = "message_retention_days must be a whole number between 1 and 7 for a Standard namespace."
  }
}

variable "tags" {
  description = "Tags applied to the Event Hubs namespace."
  type        = map(string)
  default     = {}
}

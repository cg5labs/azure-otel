variable "name" {
  description = "Globally unique, lowercase alphanumeric Azure Container Registry name."
  type        = string

  validation {
    condition     = length(var.name) >= 5 && length(var.name) <= 50 && can(regex("^[a-z0-9]+$", var.name))
    error_message = "name must be 5-50 lowercase letters or numbers."
  }
}

variable "resource_group_name" {
  description = "Resource group containing the container registry."
  type        = string
}

variable "location" {
  description = "Azure region for the container registry."
  type        = string
}

variable "tags" {
  description = "Tags applied to the container registry."
  type        = map(string)
  default     = {}
}

variable "assign_aks_pull_role" {
  description = "Whether to grant the AKS kubelet identity pull access to this registry."
  type        = bool
  default     = false
}

variable "kubelet_identity_object_id" {
  description = "Object ID of the AKS kubelet managed identity."
  type        = string
  default     = null
  nullable    = true

  validation {
    condition = var.assign_aks_pull_role ? (
      var.kubelet_identity_object_id != null &&
      can(regex("^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$", var.kubelet_identity_object_id))
    ) : true
    error_message = "kubelet_identity_object_id must be a UUID when AKS pull access is enabled."
  }
}

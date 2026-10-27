variable "display_name" {
  description = "Display name of the Entra application and service principal."
  type        = string

  validation {
    condition     = length(trimspace(var.display_name)) > 0
    error_message = "display_name must not be empty."
  }
}

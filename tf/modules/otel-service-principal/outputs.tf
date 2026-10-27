output "object_id" {
  description = "Microsoft Entra object ID of the service principal."
  value       = azuread_service_principal.this.object_id
}

output "client_id" {
  description = "Client ID of the Entra application."
  value       = azuread_application.this.client_id
}

output "tenant_id" {
  description = "Microsoft Entra tenant ID."
  value       = data.azuread_client_config.current.tenant_id
}

output "client_secret" {
  description = "Sensitive application password for OTEL collector authentication."
  value       = azuread_application_password.this.value
  sensitive   = true
}

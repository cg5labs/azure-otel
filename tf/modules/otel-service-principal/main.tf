data "azuread_client_config" "current" {}

resource "azuread_application" "this" {
  display_name     = var.display_name
  sign_in_audience = "AzureADMyOrg"
  owners           = [data.azuread_client_config.current.object_id]
}

resource "azuread_service_principal" "this" {
  client_id = azuread_application.this.client_id
  owners    = [data.azuread_client_config.current.object_id]
}

resource "azuread_application_password" "this" {
  application_id = azuread_application.this.id
  display_name   = "OTEL collector client secret"
  end_date       = timeadd(timestamp(), "8760h")

  lifecycle {
    # Avoid extending the expiry date on every plan; rotate the secret explicitly.
    ignore_changes = [end_date]
  }
}

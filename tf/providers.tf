provider "azurerm" {
  subscription_id                 = var.subscription_id
  resource_provider_registrations = "extended"

  features {}
}

provider "azuread" {}

terraform {
  required_version = ">= 1.7"

  backend "azurerm" {
    resource_group_name  = "rg-tfstate-shared"
    storage_account_name = "sttfsharedjw"
    container_name       = "github-repos"
    key                  = "terraform.tfstate"
    use_azuread_auth     = true
  }
  required_providers {
    github = {
      source  = "integrations/github"
      version = "~> 6.0"
    }
    # Used only by data.tf/identities.tf/state.tf, for the "shared" Terraform
    # state storage account this repo creates access to (not the account
    # itself — see scripts/bootstrap-state.ps1). Every other resource here is
    # GitHub, not Azure.
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

# Token comes from the GITHUB_TOKEN env var (the provider's default) - never
# hardcode it here. Locally that's a personal PAT with admin rights on every
# repo below; in CI it's the TF_GITHUB_TOKEN repository secret. See
# terraform/README.md for how to create and scope it.
provider "github" {
  owner = var.github_owner
}

# Subscription comes from ARM_SUBSCRIPTION_ID in the environment — azurerm
# 4.x requires it explicitly, it does not infer it from the az CLI context.
provider "azurerm" {
  features {}
}

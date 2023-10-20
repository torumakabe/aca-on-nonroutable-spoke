terraform {
  required_version = "~> 1.6.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.77.0"
    }

    azapi = {
      source  = "Azure/azapi"
      version = "~> 1.9"
    }

    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }
}

provider "azurerm" {
  skip_provider_registration = true
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
}

provider "azapi" {}
provider "tls" {}

resource "random_string" "vpngateway_shared_key" {
  length  = 16
  special = false
}

resource "azurerm_resource_group" "ca_nonroutable_sample" {
  name     = "rg-ca-nonroutable-sample${var.rg_suffix}"
  location = "eastus"
}

resource "azurerm_private_dns_zone" "corp_vnetexample" {
  name                = "vnetexample.corp"
  resource_group_name = azurerm_resource_group.ca_nonroutable_sample.name
}

resource "azurerm_firewall_policy" "lz_snat" {
  name                = "afwp-lz-snat"
  resource_group_name = azurerm_resource_group.ca_nonroutable_sample.name
  location            = azurerm_resource_group.ca_nonroutable_sample.location
  sku                 = "Basic"
  private_ip_ranges   = ["255.255.255.255/32"]
}

resource "azurerm_firewall_policy_rule_collection_group" "lz_snat" {
  name               = "lz-snat"
  firewall_policy_id = azurerm_firewall_policy.lz_snat.id
  priority           = 1000

  network_rule_collection {
    name     = "allow_all"
    priority = 1000
    action   = "Allow"
    rule {
      name                  = "allow_all"
      protocols             = ["Any"]
      source_addresses      = ["*"]
      destination_addresses = ["*"]
      destination_ports     = ["*"]
    }
  }
}

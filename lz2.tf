module "subnet_addrs_lz2_routable" {
  source = "hashicorp/subnets/cidr"

  base_cidr_block = local.vnet_address_space.lz2_routable
  networks = [
    {
      name     = "default"
      new_bits = 8
    },
    {
      name     = "firewall"
      new_bits = 10
    },
    {
      name     = "firewall_management"
      new_bits = 10
    },
    {
      name     = "appgateway"
      new_bits = 8
    },
  ]
}

module "subnet_addrs_lz2_nonroutable" {
  source = "hashicorp/subnets/cidr"

  base_cidr_block = local.vnet_address_space.lz2_nonroutable
  networks = [
    {
      name     = "default"
      new_bits = 8
    },
    {
      name     = "containerapps_environment"
      new_bits = 4
    },
  ]
}

resource "azurerm_virtual_network" "lz2_routable" {
  name                = "vnet-lz2-routable"
  resource_group_name = azurerm_resource_group.ca_nonroutable_sample.name
  location            = azurerm_resource_group.ca_nonroutable_sample.location
  address_space       = [local.vnet_address_space.lz2_routable]
}

resource "azurerm_virtual_network_peering" "lz2_routable_to_hub" {
  depends_on = [
    azurerm_virtual_network_gateway.hub,
  ]
  name                      = "lz2-routable-to-hub"
  resource_group_name       = azurerm_resource_group.ca_nonroutable_sample.name
  virtual_network_name      = azurerm_virtual_network.lz2_routable.name
  remote_virtual_network_id = azurerm_virtual_network.hub.id

  allow_forwarded_traffic = true
  // Just for propagation of route to on-premises
  use_remote_gateways = true
}

resource "azurerm_virtual_network_peering" "lz2_routable_to_nonroutable" {
  name                      = "lz2-routable-to-nonroutable"
  resource_group_name       = azurerm_resource_group.ca_nonroutable_sample.name
  virtual_network_name      = azurerm_virtual_network.lz2_routable.name
  remote_virtual_network_id = azurerm_virtual_network.lz2_nonroutable.id

  allow_forwarded_traffic = true
}

resource "azurerm_subnet" "lz2_routable_default" {
  name                 = "default"
  resource_group_name  = azurerm_resource_group.ca_nonroutable_sample.name
  virtual_network_name = azurerm_virtual_network.lz2_routable.name
  address_prefixes     = [module.subnet_addrs_lz2_routable.network_cidr_blocks["default"]]
}

resource "azurerm_subnet" "lz2_routable_firewall" {
  name                 = "AzureFirewallSubnet"
  resource_group_name  = azurerm_resource_group.ca_nonroutable_sample.name
  virtual_network_name = azurerm_virtual_network.lz2_routable.name
  address_prefixes     = [module.subnet_addrs_lz2_routable.network_cidr_blocks["firewall"]]
}

resource "azurerm_subnet" "lz2_routable_firewall_management" {
  name                 = "AzureFirewallManagementSubnet"
  resource_group_name  = azurerm_resource_group.ca_nonroutable_sample.name
  virtual_network_name = azurerm_virtual_network.lz2_routable.name
  address_prefixes     = [module.subnet_addrs_lz2_routable.network_cidr_blocks["firewall_management"]]
}

resource "azurerm_subnet" "lz2_routable_appgateway" {
  name                 = "appgateway"
  resource_group_name  = azurerm_resource_group.ca_nonroutable_sample.name
  virtual_network_name = azurerm_virtual_network.lz2_routable.name
  address_prefixes     = [module.subnet_addrs_lz2_routable.network_cidr_blocks["appgateway"]]
}

locals {
  lz2_routable_appgateway_fe_ip = cidrhost(azurerm_subnet.lz2_routable_appgateway.address_prefixes[0], 10)
}

resource "azurerm_route_table" "lz2_routable" {
  name                          = "udr-lz2-routable"
  resource_group_name           = azurerm_resource_group.ca_nonroutable_sample.name
  location                      = azurerm_resource_group.ca_nonroutable_sample.location
  disable_bgp_route_propagation = true

  route {
    name                   = "default"
    address_prefix         = "0.0.0.0/0"
    next_hop_type          = "VirtualAppliance"
    next_hop_in_ip_address = azurerm_firewall.hub.ip_configuration[0].private_ip_address
  }
}

resource "azurerm_subnet_route_table_association" "lz2_routable_default" {
  subnet_id      = azurerm_subnet.lz2_routable_default.id
  route_table_id = azurerm_route_table.lz2_routable.id
}

resource "azurerm_subnet_route_table_association" "lz2_routable_firewall" {
  subnet_id      = azurerm_subnet.lz2_routable_firewall.id
  route_table_id = azurerm_route_table.lz2_routable.id
}

resource "azurerm_public_ip" "lz2_routable_firewall" {
  name                = "pip-lz2-routable-fw"
  resource_group_name = azurerm_resource_group.ca_nonroutable_sample.name
  location            = azurerm_resource_group.ca_nonroutable_sample.location
  allocation_method   = "Static"
  sku                 = "Standard"
}


resource "azurerm_public_ip" "lz2_routable_firewall_management" {
  name                = "pip-lz2-routable-fw-mgmt"
  resource_group_name = azurerm_resource_group.ca_nonroutable_sample.name
  location            = azurerm_resource_group.ca_nonroutable_sample.location
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_firewall" "lz2_routable" {
  name                = "afw-lz2-routable"
  resource_group_name = azurerm_resource_group.ca_nonroutable_sample.name
  location            = azurerm_resource_group.ca_nonroutable_sample.location
  sku_name            = "AZFW_VNet"
  sku_tier            = "Basic"
  firewall_policy_id  = azurerm_firewall_policy.lz_snat.id

  ip_configuration {
    name                 = "firewall"
    subnet_id            = azurerm_subnet.lz2_routable_firewall.id
    public_ip_address_id = azurerm_public_ip.lz2_routable_firewall.id
  }

  management_ip_configuration {
    name                 = "management"
    subnet_id            = azurerm_subnet.lz2_routable_firewall_management.id
    public_ip_address_id = azurerm_public_ip.lz2_routable_firewall_management.id
  }
}

resource "azurerm_virtual_network" "lz2_nonroutable" {
  name                = "vnet-lz2-nonroutable"
  resource_group_name = azurerm_resource_group.ca_nonroutable_sample.name
  location            = azurerm_resource_group.ca_nonroutable_sample.location
  address_space       = [local.vnet_address_space.lz2_nonroutable]
}

resource "azurerm_virtual_network_peering" "lz2_nonroutable_to_routable" {
  name                      = "lz2-nonroutable-to-routable"
  resource_group_name       = azurerm_resource_group.ca_nonroutable_sample.name
  virtual_network_name      = azurerm_virtual_network.lz2_nonroutable.name
  remote_virtual_network_id = azurerm_virtual_network.lz2_routable.id

  allow_forwarded_traffic = true
}

resource "azurerm_subnet" "lz2_nonroutable_default" {
  name                 = "default"
  resource_group_name  = azurerm_resource_group.ca_nonroutable_sample.name
  virtual_network_name = azurerm_virtual_network.lz2_nonroutable.name
  address_prefixes     = [module.subnet_addrs_lz2_nonroutable.network_cidr_blocks["default"]]
}

resource "azurerm_subnet" "lz2_nonroutable_ca_env" {
  name                 = "cae"
  resource_group_name  = azurerm_resource_group.ca_nonroutable_sample.name
  virtual_network_name = azurerm_virtual_network.lz2_nonroutable.name
  address_prefixes     = [module.subnet_addrs_lz2_nonroutable.network_cidr_blocks["containerapps_environment"]]

  delegation {
    name = "Microsoft.App.environments"

    service_delegation {
      name    = "Microsoft.App/environments"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }

  // Waiting for delegation
  provisioner "local-exec" {
    command = "sleep 30"
  }
}

resource "azurerm_route_table" "lz2_nonroutable" {
  name                          = "udr-lz2-nonroutable"
  resource_group_name           = azurerm_resource_group.ca_nonroutable_sample.name
  location                      = azurerm_resource_group.ca_nonroutable_sample.location
  disable_bgp_route_propagation = true

  route {
    name                   = "default"
    address_prefix         = "0.0.0.0/0"
    next_hop_type          = "VirtualAppliance"
    next_hop_in_ip_address = azurerm_firewall.lz2_routable.ip_configuration[0].private_ip_address
  }
}

resource "azurerm_subnet_route_table_association" "lz2_nonroutable_default" {
  subnet_id      = azurerm_subnet.lz2_nonroutable_default.id
  route_table_id = azurerm_route_table.lz2_nonroutable.id
}

resource "azurerm_subnet_route_table_association" "lz2_nonroutable_ca_env" {
  subnet_id      = azurerm_subnet.lz2_nonroutable_ca_env.id
  route_table_id = azurerm_route_table.lz2_nonroutable.id
}

resource "azapi_resource" "ca_env_lz2" {
  type                      = "Microsoft.App/managedEnvironments@2023-05-01"
  schema_validation_enabled = false
  name                      = "cae-lz2"
  parent_id                 = azurerm_resource_group.ca_nonroutable_sample.id
  location                  = azurerm_resource_group.ca_nonroutable_sample.location

  body = jsonencode({
    properties = {
      vnetConfiguration = {
        "internal"               = true
        "infrastructureSubnetId" = azurerm_subnet.lz2_nonroutable_ca_env.id
      }
      workloadProfiles = [
        {
          name                = "Consumption"
          workloadProfileType = "Consumption"
        },
        {
          name                = "D4-1"
          workloadProfileType = "D4"
          minimumCount        = 1
          maximumCount        = 3
        }
      ]
    }
  })

  response_export_values = ["properties.defaultDomain", "properties.staticIp"]
}

resource "azapi_resource" "ca_lz2_hello" {
  depends_on = [
    azurerm_virtual_network_peering.hub_to_lz2_routable,
    azurerm_virtual_network_peering.lz2_routable_to_hub,
    azurerm_virtual_network_peering.lz2_routable_to_nonroutable,
    azurerm_virtual_network_peering.lz2_nonroutable_to_routable,
    azurerm_route_table.lz2_routable,
    azurerm_route_table.lz2_nonroutable,
  ]
  type                      = "Microsoft.App/containerApps@2023-05-01"
  schema_validation_enabled = false
  name                      = "ca-lz2-hello"
  location                  = azurerm_resource_group.ca_nonroutable_sample.location
  parent_id                 = azurerm_resource_group.ca_nonroutable_sample.id

  body = jsonencode({
    properties = {
      environmentId = azapi_resource.ca_env_lz2.id
      configuration = {
        ingress = {
          allowInsecure = true
          external      = true
          targetPort    = 80
          transport     = "Auto"
        }
      }
      workloadProfileName = "D4-1"
      template = {
        scale = {
          minReplicas = 1
          maxReplicas = 3
        }
        containers = [{
          name  = "hello"
          image = "mcr.microsoft.com/k8se/quickstart:latest"
        }]
      }
    }
  })

  response_export_values = ["properties.configuration.ingress.fqdn"]
}

// TODO: Remove this after resolution of constraints AppGW without public IP
// https://learn.microsoft.com/en-us/azure/application-gateway/application-gateway-private-deployment
resource "azurerm_public_ip" "lz2_agw" {
  name                = "pip-lz2-agw"
  resource_group_name = azurerm_resource_group.ca_nonroutable_sample.name
  location            = azurerm_resource_group.ca_nonroutable_sample.location
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_application_gateway" "lz2" {
  name                = "agw-lz2"
  resource_group_name = azurerm_resource_group.ca_nonroutable_sample.name
  location            = azurerm_resource_group.ca_nonroutable_sample.location

  sku {
    name     = "Standard_v2"
    tier     = "Standard_v2"
    capacity = 2
  }

  gateway_ip_configuration {
    name      = local.agw_settings_name_template.gateway_ip_configuration_name
    subnet_id = azurerm_subnet.lz2_routable_appgateway.id
  }

  frontend_port {
    name = local.agw_settings_name_template.frontend_port_name
    port = 80
  }

  // No bindings to listener
  frontend_ip_configuration {
    name                 = local.agw_settings_name_template.frontend_pip_configuration_name
    public_ip_address_id = azurerm_public_ip.lz2_agw.id
  }

  frontend_ip_configuration {
    name                          = local.agw_settings_name_template.frontend_ip_configuration_name
    subnet_id                     = azurerm_subnet.lz2_routable_appgateway.id
    private_ip_address_allocation = "Static"
    private_ip_address            = local.lz2_routable_appgateway_fe_ip
  }

  backend_address_pool {
    name  = local.ca_lz2_hello.agw_settings.backend_address_pool_name
    fqdns = [jsondecode(azapi_resource.ca_lz2_hello.output).properties.configuration.ingress.fqdn]
  }

  backend_http_settings {
    name                                = local.ca_lz2_hello.agw_settings.backend_http_settings_name
    cookie_based_affinity               = "Disabled"
    path                                = "/"
    port                                = 80
    protocol                            = "Http"
    request_timeout                     = 15
    pick_host_name_from_backend_address = true
    connection_draining {
      enabled           = true
      drain_timeout_sec = 10
    }
  }

  http_listener {
    name                           = local.ca_lz2_hello.agw_settings.http_listener_name
    frontend_ip_configuration_name = local.agw_settings_name_template.frontend_ip_configuration_name
    frontend_port_name             = local.agw_settings_name_template.frontend_port_name
    host_name                      = "hello.vnetexample.corp"
    protocol                       = "Http"
  }

  request_routing_rule {
    name                       = local.ca_lz2_hello.agw_settings.request_routing_rule_name
    rule_type                  = "Basic"
    http_listener_name         = local.ca_lz2_hello.agw_settings.http_listener_name
    backend_address_pool_name  = local.ca_lz2_hello.agw_settings.backend_address_pool_name
    backend_http_settings_name = local.ca_lz2_hello.agw_settings.backend_http_settings_name
    priority                   = 100
  }
}

resource "azurerm_private_dns_zone" "ca_lz2" {
  name                = jsondecode(azapi_resource.ca_env_lz2.output).properties.defaultDomain
  resource_group_name = azurerm_resource_group.ca_nonroutable_sample.name
}

resource "azurerm_private_dns_a_record" "ca_lz2_wildcard" {
  name                = "*"
  zone_name           = azurerm_private_dns_zone.ca_lz2.name
  resource_group_name = azurerm_resource_group.ca_nonroutable_sample.name
  ttl                 = 300
  records             = [jsondecode(azapi_resource.ca_env_lz2.output).properties.staticIp]
}

resource "azurerm_private_dns_a_record" "ca_lz2_apex" {
  name                = "@"
  zone_name           = azurerm_private_dns_zone.ca_lz2.name
  resource_group_name = azurerm_resource_group.ca_nonroutable_sample.name
  ttl                 = 300
  records             = [jsondecode(azapi_resource.ca_env_lz2.output).properties.staticIp]
}

resource "azurerm_private_dns_zone_virtual_network_link" "ca_lz2_to_lz2_routable" {
  name                  = "pdnsz-link-ca-lz2-to-lz2-routable"
  resource_group_name   = azurerm_resource_group.ca_nonroutable_sample.name
  private_dns_zone_name = azurerm_private_dns_zone.ca_lz2.name
  virtual_network_id    = azurerm_virtual_network.lz2_routable.id
}

resource "azurerm_private_dns_zone_virtual_network_link" "ca_lz2_to_lz2_nonroutable" {
  name                  = "pdnsz-link-ca-lz2-to-lz2-nonroutable"
  resource_group_name   = azurerm_resource_group.ca_nonroutable_sample.name
  private_dns_zone_name = azurerm_private_dns_zone.ca_lz2.name
  virtual_network_id    = azurerm_virtual_network.lz2_nonroutable.id
}

resource "azurerm_private_dns_a_record" "corp_lz2_hello" {
  name                = "hello"
  zone_name           = azurerm_private_dns_zone.corp_vnetexample.name
  resource_group_name = azurerm_resource_group.ca_nonroutable_sample.name
  ttl                 = 300
  records             = [local.lz2_routable_appgateway_fe_ip]
}

resource "azurerm_private_dns_resolver_virtual_network_link" "corp_to_lz2_routable" {
  name                      = "pdnsr-link-corp-to-lz2-routable"
  dns_forwarding_ruleset_id = azurerm_private_dns_resolver_dns_forwarding_ruleset.hub.id
  virtual_network_id        = azurerm_virtual_network.lz2_routable.id
}

resource "azurerm_private_dns_resolver_virtual_network_link" "corp_to_lz2_nonroutable" {
  name                      = "pdnsr-link-corp-to-lz2-nonroutable"
  dns_forwarding_ruleset_id = azurerm_private_dns_resolver_dns_forwarding_ruleset.hub.id
  virtual_network_id        = azurerm_virtual_network.lz2_nonroutable.id
}

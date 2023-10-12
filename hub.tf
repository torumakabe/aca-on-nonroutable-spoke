module "subnet_addrs_hub" {
  source = "hashicorp/subnets/cidr"

  base_cidr_block = local.vnet_address_space.hub
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
      name     = "vpngateway"
      new_bits = 11
    },
    {
      name     = "private_dns_resolver_inbound"
      new_bits = 12
    },
    {
      name     = "private_dns_resolver_outbound"
      new_bits = 12
    },
  ]
}

resource "azurerm_virtual_network" "hub" {
  name                = "vnet-hub"
  resource_group_name = azurerm_resource_group.ca_nonroutable_sample.name
  location            = azurerm_resource_group.ca_nonroutable_sample.location
  address_space       = [local.vnet_address_space.hub]
}

resource "azurerm_virtual_network_peering" "hub_to_lz1_routable" {
  name                      = "hub-to-lz1-routable"
  resource_group_name       = azurerm_resource_group.ca_nonroutable_sample.name
  virtual_network_name      = azurerm_virtual_network.hub.name
  remote_virtual_network_id = azurerm_virtual_network.lz1_routable.id

  allow_forwarded_traffic = true
  allow_gateway_transit   = true
}

resource "azurerm_virtual_network_peering" "hub_to_lz2_routable" {
  name                      = "hub-to-lz2-routable"
  resource_group_name       = azurerm_resource_group.ca_nonroutable_sample.name
  virtual_network_name      = azurerm_virtual_network.hub.name
  remote_virtual_network_id = azurerm_virtual_network.lz2_routable.id

  allow_forwarded_traffic = true
  allow_gateway_transit   = true
}

resource "azurerm_subnet" "hub_default" {
  name                 = "default"
  resource_group_name  = azurerm_resource_group.ca_nonroutable_sample.name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = [module.subnet_addrs_hub.network_cidr_blocks["default"]]
}

resource "azurerm_subnet" "hub_firewall" {
  name                 = "AzureFirewallSubnet"
  resource_group_name  = azurerm_resource_group.ca_nonroutable_sample.name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = [module.subnet_addrs_hub.network_cidr_blocks["firewall"]]
}

resource "azurerm_subnet" "hub_vpngateway" {
  name                 = "GatewaySubnet"
  resource_group_name  = azurerm_resource_group.ca_nonroutable_sample.name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = [module.subnet_addrs_hub.network_cidr_blocks["vpngateway"]]
}

resource "azurerm_route_table" "hub_vpngateway_to_spoke" {
  name                = "udr-hub-vpngw-to-spoke"
  resource_group_name = azurerm_resource_group.ca_nonroutable_sample.name
  location            = azurerm_resource_group.ca_nonroutable_sample.location

  route {
    name                   = "to-lz1"
    address_prefix         = local.vnet_address_space.lz1_routable
    next_hop_type          = "VirtualAppliance"
    next_hop_in_ip_address = azurerm_firewall.hub.ip_configuration[0].private_ip_address
  }

  route {
    name                   = "to-lz2"
    address_prefix         = local.vnet_address_space.lz2_routable
    next_hop_type          = "VirtualAppliance"
    next_hop_in_ip_address = azurerm_firewall.hub.ip_configuration[0].private_ip_address
  }
}

resource "azurerm_subnet_route_table_association" "hub_vpngateway_to_spoke" {
  depends_on = [
    azurerm_virtual_network_gateway.hub,
  ]
  subnet_id      = azurerm_subnet.hub_vpngateway.id
  route_table_id = azurerm_route_table.hub_vpngateway_to_spoke.id
}

resource "azurerm_subnet" "hub_private_dns_resolver_inbound" {
  name                 = "pdnsr-inbound"
  resource_group_name  = azurerm_resource_group.ca_nonroutable_sample.name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = [module.subnet_addrs_hub.network_cidr_blocks["private_dns_resolver_inbound"]]

  delegation {
    name = "Microsoft.Network.dnsResolvers"
    service_delegation {
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
      name    = "Microsoft.Network/dnsResolvers"
    }
  }
}

resource "azurerm_subnet" "hub_private_dns_resolver_outbound" {
  name                 = "pdnsr-outbound"
  resource_group_name  = azurerm_resource_group.ca_nonroutable_sample.name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = [module.subnet_addrs_hub.network_cidr_blocks["private_dns_resolver_outbound"]]

  delegation {
    name = "Microsoft.Network.dnsResolvers"
    service_delegation {
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
      name    = "Microsoft.Network/dnsResolvers"
    }
  }
}

resource "azurerm_firewall_policy" "hub_snat" {
  name                = "afwp-hub"
  resource_group_name = azurerm_resource_group.ca_nonroutable_sample.name
  location            = azurerm_resource_group.ca_nonroutable_sample.location
  sku                 = "Basic"
  private_ip_ranges   = ["255.255.255.255/32"]
}

resource "azurerm_firewall_policy_rule_collection_group" "hub_snat" {
  name               = "hub-snat"
  firewall_policy_id = azurerm_firewall_policy.hub_snat.id
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

resource "azurerm_public_ip" "hub_firewall" {
  name                = "pip-hub-fw"
  resource_group_name = azurerm_resource_group.ca_nonroutable_sample.name
  location            = azurerm_resource_group.ca_nonroutable_sample.location
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_firewall" "hub" {
  name                = "afw-hub"
  resource_group_name = azurerm_resource_group.ca_nonroutable_sample.name
  location            = azurerm_resource_group.ca_nonroutable_sample.location
  sku_name            = "AZFW_VNet"
  sku_tier            = "Standard"
  firewall_policy_id  = azurerm_firewall_policy.hub_snat.id

  ip_configuration {
    name                 = "firewall"
    subnet_id            = azurerm_subnet.hub_firewall.id
    public_ip_address_id = azurerm_public_ip.hub_firewall.id
  }
}

resource "azurerm_private_dns_zone_virtual_network_link" "corp_to_hub" {
  name                  = "pdnsz-link-corp-to-hub"
  resource_group_name   = azurerm_resource_group.ca_nonroutable_sample.name
  private_dns_zone_name = azurerm_private_dns_zone.corp_vnetexample.name
  virtual_network_id    = azurerm_virtual_network.hub.id
}

resource "azurerm_public_ip" "hub_vpngateway" {
  name                = "pip-hub-vpng"
  resource_group_name = azurerm_resource_group.ca_nonroutable_sample.name
  location            = azurerm_resource_group.ca_nonroutable_sample.location
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_virtual_network_gateway" "hub" {
  name                = "vpng-hub"
  resource_group_name = azurerm_resource_group.ca_nonroutable_sample.name
  location            = azurerm_resource_group.ca_nonroutable_sample.location

  type = "Vpn"

  active_active = false
  enable_bgp    = false
  sku           = "VpnGw1"

  ip_configuration {
    name                          = "hub"
    public_ip_address_id          = azurerm_public_ip.hub_vpngateway.id
    private_ip_address_allocation = "Dynamic"
    subnet_id                     = azurerm_subnet.hub_vpngateway.id
  }
}

resource "azurerm_virtual_network_gateway_connection" "hub_to_onprem" {
  name                = "vpnc-hub-to-onprem"
  location            = azurerm_resource_group.ca_nonroutable_sample.location
  resource_group_name = azurerm_resource_group.ca_nonroutable_sample.name

  type = "Vnet2Vnet"

  virtual_network_gateway_id      = azurerm_virtual_network_gateway.hub.id
  peer_virtual_network_gateway_id = azurerm_virtual_network_gateway.onprem.id

  shared_key = random_string.vpngateway_shared_key.result
}

resource "azurerm_private_dns_resolver" "hub" {
  name                = "pdnsr-hub"
  resource_group_name = azurerm_resource_group.ca_nonroutable_sample.name
  location            = azurerm_resource_group.ca_nonroutable_sample.location
  virtual_network_id  = azurerm_virtual_network.hub.id
}

resource "azurerm_private_dns_resolver_inbound_endpoint" "hub" {
  name                    = "pdnsr-inbound-ep-hub"
  private_dns_resolver_id = azurerm_private_dns_resolver.hub.id
  location                = azurerm_resource_group.ca_nonroutable_sample.location
  ip_configurations {
    private_ip_allocation_method = "Dynamic"
    subnet_id                    = azurerm_subnet.hub_private_dns_resolver_inbound.id
  }
}

resource "azurerm_private_dns_resolver_outbound_endpoint" "hub" {
  name                    = "pdnsr-outbound-ep-hub"
  private_dns_resolver_id = azurerm_private_dns_resolver.hub.id
  location                = azurerm_resource_group.ca_nonroutable_sample.location
  subnet_id               = azurerm_subnet.hub_private_dns_resolver_outbound.id
}

resource "azurerm_private_dns_resolver_dns_forwarding_ruleset" "hub" {
  name                                       = "pdnsr-fwd-ruleset-hub"
  resource_group_name                        = azurerm_resource_group.ca_nonroutable_sample.name
  location                                   = azurerm_resource_group.ca_nonroutable_sample.location
  private_dns_resolver_outbound_endpoint_ids = [azurerm_private_dns_resolver_outbound_endpoint.hub.id]
}

resource "azurerm_private_dns_resolver_forwarding_rule" "hub_vnet_example" {
  name                      = "vnet"
  dns_forwarding_ruleset_id = azurerm_private_dns_resolver_dns_forwarding_ruleset.hub.id
  domain_name               = "vnetexample.corp."
  enabled                   = true
  target_dns_servers {
    ip_address = azurerm_private_dns_resolver_inbound_endpoint.hub.ip_configurations[0].private_ip_address
    port       = 53
  }
}

resource "azurerm_private_dns_resolver_forwarding_rule" "hub_onprem_example" {
  name                      = "onprem"
  dns_forwarding_ruleset_id = azurerm_private_dns_resolver_dns_forwarding_ruleset.hub.id
  domain_name               = "onpremexample.corp."
  enabled                   = true
  target_dns_servers {
    ip_address = azurerm_container_group.onprem_resolver.ip_address
    port       = 53
  }
}

module "subnet_addrs_onprem" {
  source = "hashicorp/subnets/cidr"

  base_cidr_block = local.vnet_address_space.onprem
  networks = [
    {
      name     = "default"
      new_bits = 8
    },
    {
      name     = "aci"
      new_bits = 10
    },
    {
      name     = "vpngateway"
      new_bits = 11
    },
  ]
}

resource "azurerm_virtual_network" "onprem" {
  name                = "vnet-onprem"
  resource_group_name = azurerm_resource_group.ca_nonroutable_sample.name
  location            = azurerm_resource_group.ca_nonroutable_sample.location
  address_space       = [local.vnet_address_space.onprem]
}

resource "azurerm_subnet" "onprem_default" {
  name                 = "default"
  resource_group_name  = azurerm_resource_group.ca_nonroutable_sample.name
  virtual_network_name = azurerm_virtual_network.onprem.name
  address_prefixes     = [module.subnet_addrs_onprem.network_cidr_blocks["default"]]
}

locals {
  onprem_vm_private_ip = cidrhost(azurerm_subnet.onprem_default.address_prefixes[0], 10)
}

resource "azurerm_subnet" "onprem_aci" {
  name                 = "aci"
  resource_group_name  = azurerm_resource_group.ca_nonroutable_sample.name
  virtual_network_name = azurerm_virtual_network.onprem.name
  address_prefixes     = [module.subnet_addrs_onprem.network_cidr_blocks["aci"]]

  delegation {
    name = "Microsoft.ContainerInstance.containerGroups"

    service_delegation {
      name    = "Microsoft.ContainerInstance/containerGroups"
      actions = ["Microsoft.Network/virtualNetworks/subnets/action"]
    }
  }
}

resource "azurerm_subnet" "onprem_vpngateway" {
  name                 = "GatewaySubnet"
  resource_group_name  = azurerm_resource_group.ca_nonroutable_sample.name
  virtual_network_name = azurerm_virtual_network.onprem.name
  address_prefixes     = [module.subnet_addrs_onprem.network_cidr_blocks["vpngateway"]]
}

resource "azurerm_public_ip" "onprem_vpngateway" {
  name                = "pip-onprem-vpng"
  resource_group_name = azurerm_resource_group.ca_nonroutable_sample.name
  location            = azurerm_resource_group.ca_nonroutable_sample.location
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_virtual_network_gateway" "onprem" {
  name                = "vpng-onprem"
  resource_group_name = azurerm_resource_group.ca_nonroutable_sample.name
  location            = azurerm_resource_group.ca_nonroutable_sample.location

  type = "Vpn"

  active_active = false
  enable_bgp    = false
  sku           = "VpnGw1"

  ip_configuration {
    name                          = "onprem"
    public_ip_address_id          = azurerm_public_ip.onprem_vpngateway.id
    private_ip_address_allocation = "Dynamic"
    subnet_id                     = azurerm_subnet.onprem_vpngateway.id
  }
}

resource "azurerm_virtual_network_gateway_connection" "onprem_to_hub" {
  name                = "vpnc-onprem-to-hub"
  location            = azurerm_resource_group.ca_nonroutable_sample.location
  resource_group_name = azurerm_resource_group.ca_nonroutable_sample.name

  type = "Vnet2Vnet"

  virtual_network_gateway_id      = azurerm_virtual_network_gateway.onprem.id
  peer_virtual_network_gateway_id = azurerm_virtual_network_gateway.hub.id

  shared_key = random_string.vpngateway_shared_key.result
}

resource "azurerm_container_group" "onprem_resolver" {
  name                = "ci-onprem-resolver"
  resource_group_name = azurerm_resource_group.ca_nonroutable_sample.name
  location            = azurerm_resource_group.ca_nonroutable_sample.location
  ip_address_type     = "Private"
  subnet_ids          = [azurerm_subnet.onprem_aci.id]
  os_type             = "Linux"

  container {
    name   = "coredns"
    image  = "coredns/coredns:1.11.1"
    cpu    = "1.0"
    memory = "1.0"

    ports {
      port     = 53
      protocol = "UDP"
    }

    volume {
      name       = "config"
      mount_path = "/config"
      read_only  = true
      secret = {
        "Corefile" = base64encode(templatefile("${path.module}/config/coredns-onprem/Corefile.tftpl",
          {
            RESOLVER_IP = azurerm_private_dns_resolver_inbound_endpoint.hub.ip_configurations[0].private_ip_address
          }
        ))
        "db.onpremexample.corp" = base64encode(templatefile("${path.module}/config/coredns-onprem/db.onpremexample.corp.tftpl",
          {
            APACHE_IP = local.onprem_vm_private_ip
          }
        ))
      }
    }

    commands = ["/coredns", "-conf", "/config/Corefile"]
  }
}

resource "azurerm_network_security_group" "default" {
  name                = "nsg-default"
  resource_group_name = azurerm_resource_group.ca_nonroutable_sample.name
  location            = azurerm_resource_group.ca_nonroutable_sample.location

  // Do not assign rules for SSH statically, use JIT
}

resource "azurerm_public_ip" "onprem_vm" {
  name                = "pip-onprem-vm"
  resource_group_name = azurerm_resource_group.ca_nonroutable_sample.name
  location            = azurerm_resource_group.ca_nonroutable_sample.location
  allocation_method   = "Dynamic"
}

resource "azurerm_network_interface" "onprem_vm" {
  name                          = "nic-onprem-vm"
  resource_group_name           = azurerm_resource_group.ca_nonroutable_sample.name
  location                      = azurerm_resource_group.ca_nonroutable_sample.location
  enable_accelerated_networking = true
  dns_servers                   = [azurerm_container_group.onprem_resolver.ip_address]

  ip_configuration {
    name                          = "default"
    subnet_id                     = azurerm_subnet.onprem_default.id
    private_ip_address_allocation = "Static"
    private_ip_address            = local.onprem_vm_private_ip
    public_ip_address_id          = azurerm_public_ip.onprem_vm.id
  }
}

resource "azurerm_network_interface_security_group_association" "onprem_vm_default" {
  network_interface_id      = azurerm_network_interface.onprem_vm.id
  network_security_group_id = azurerm_network_security_group.default.id
}

resource "tls_private_key" "ssh" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "azurerm_linux_virtual_machine" "onprem" {
  name                            = "vm-onprem"
  resource_group_name             = azurerm_resource_group.ca_nonroutable_sample.name
  location                        = azurerm_resource_group.ca_nonroutable_sample.location
  size                            = "Standard_D2lds_v5"
  admin_username                  = "azureuser"
  disable_password_authentication = true
  identity {
    type = "SystemAssigned"
  }
  network_interface_ids = [
    azurerm_network_interface.onprem_vm.id,
  ]

  admin_ssh_key {
    username   = "azureuser"
    public_key = tls_private_key.ssh.public_key_openssh
  }

  os_disk {
    caching              = "ReadOnly"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  user_data = filebase64("${path.module}/cloud-init/onprem-vm/cloud-config.yaml")
}

resource "azurerm_virtual_machine_extension" "aad_ssh_login_onprem" {
  name                       = "AADSSHLoginForLinux"
  virtual_machine_id         = azurerm_linux_virtual_machine.onprem.id
  publisher                  = "Microsoft.Azure.ActiveDirectory"
  type                       = "AADSSHLoginForLinux"
  type_handler_version       = "1.0"
  auto_upgrade_minor_version = true
}

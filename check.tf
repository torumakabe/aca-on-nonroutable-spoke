# Continuous Validation

resource "null_resource" "always_run" {
  triggers = {
    timestamp = "${timestamp()}"
  }
}

resource "azurerm_container_group" "check_onprem_to_lz1" {
  depends_on = [
    azurerm_virtual_network_gateway_connection.onprem_to_hub,
    azurerm_virtual_network_gateway_connection.hub_to_onprem,
    azurerm_application_gateway.lz1,
    azurerm_private_dns_resolver.hub,
    azurerm_private_dns_zone_virtual_network_link.corp_to_hub,
  ]
  name                = "ci-check-onprem-to-lz1"
  resource_group_name = azurerm_resource_group.ca_nonroutable_sample.name
  location            = azurerm_resource_group.ca_nonroutable_sample.location
  ip_address_type     = "None"
  dns_config {
    nameservers = [azurerm_container_group.onprem_resolver.ip_address]
  }
  subnet_ids     = [azurerm_subnet.onprem_aci.id]
  os_type        = "Linux"
  restart_policy = "Never"

  container {
    name   = "util"
    image  = "mcr.microsoft.com/k8se/quickstart:latest"
    cpu    = "1.0"
    memory = "1.0"

    commands = [
      "curl",
      "--fail",
      "http://${azurerm_private_dns_a_record.corp_lz1_nginx.fqdn}",
      "-o",
      "/dev/null",
      "--retry",
      "5",
    ]
  }

  lifecycle {
    ignore_changes = [
      ip_address_type,
    ]
  }

  // Waiting for execution
  provisioner "local-exec" {
    command = "sleep 120"
  }
}

resource "azapi_resource_action" "ci_check_onprem_to_lz1_start" {
  type        = "Microsoft.ContainerInstance/containerGroups@2023-05-01"
  resource_id = azurerm_container_group.check_onprem_to_lz1.id
  action      = "start"

  lifecycle {
    replace_triggered_by = [
      null_resource.always_run
    ]
  }

  // Waiting for execution
  provisioner "local-exec" {
    command = "sleep 60"
  }
}

check "onprem_to_lz1" {
  data "azapi_resource" "ci_check_onprem_to_lz1" {
    name      = "ci-check-onprem-to-lz1"
    parent_id = azurerm_resource_group.ca_nonroutable_sample.id
    type      = "Microsoft.ContainerInstance/containerGroups@2023-05-01"

    response_export_values = ["properties.instanceView.state"]
  }

  assert {
    condition     = jsondecode(data.azapi_resource.ci_check_onprem_to_lz1.output).properties.instanceView.state == "Succeeded"
    error_message = "curl check failed: onprem to lz1"
  }
}

resource "azurerm_container_group" "check_onprem_to_lz2" {
  depends_on = [
    azurerm_virtual_network_gateway_connection.onprem_to_hub,
    azurerm_virtual_network_gateway_connection.hub_to_onprem,
    azurerm_application_gateway.lz2,
    azurerm_private_dns_resolver.hub,
    azurerm_private_dns_zone_virtual_network_link.corp_to_hub,
  ]
  name                = "ci-check-onprem-to-lz2"
  resource_group_name = azurerm_resource_group.ca_nonroutable_sample.name
  location            = azurerm_resource_group.ca_nonroutable_sample.location
  ip_address_type     = "None"
  dns_config {
    nameservers = [azurerm_container_group.onprem_resolver.ip_address]
  }
  subnet_ids     = [azurerm_subnet.onprem_aci.id]
  os_type        = "Linux"
  restart_policy = "Never"

  container {
    name   = "util"
    image  = "mcr.microsoft.com/k8se/quickstart:latest"
    cpu    = "1.0"
    memory = "1.0"

    commands = [
      "curl",
      "--fail",
      "http://${azurerm_private_dns_a_record.corp_lz2_hello.fqdn}",
      "-o",
      "/dev/null",
      "--retry",
      "5",
    ]
  }

  lifecycle {
    ignore_changes = [
      ip_address_type,
    ]
  }

  // Waiting for execution
  provisioner "local-exec" {
    command = "sleep 60"
  }
}

resource "azapi_resource_action" "ci_check_onprem_to_lz2_start" {
  type        = "Microsoft.ContainerInstance/containerGroups@2023-05-01"
  resource_id = azurerm_container_group.check_onprem_to_lz2.id
  action      = "start"

  lifecycle {
    replace_triggered_by = [
      null_resource.always_run
    ]
  }

  // Waiting for execution
  provisioner "local-exec" {
    command = "sleep 120"
  }
}


check "onprem_to_lz2" {
  data "azapi_resource" "ci_check_onprem_to_lz2" {
    name      = "ci-check-onprem-to-lz2"
    parent_id = azurerm_resource_group.ca_nonroutable_sample.id
    type      = "Microsoft.ContainerInstance/containerGroups@2023-05-01"

    response_export_values = ["properties.instanceView.state"]
  }

  assert {
    condition     = jsondecode(data.azapi_resource.ci_check_onprem_to_lz2.output).properties.instanceView.state == "Succeeded"
    error_message = "curl check failed: onprem to lz2"
  }
}

resource "azapi_resource" "caj_check_lz1_to_lz2" {
  depends_on = [
    azurerm_application_gateway.lz2,
    azurerm_private_dns_resolver.hub,
    azurerm_private_dns_resolver_virtual_network_link.corp_to_lz1_nonroutable,
  ]
  type                      = "Microsoft.App/jobs@2023-05-01"
  schema_validation_enabled = false
  name                      = "caj-check-lz1-to-lz2"
  parent_id                 = azurerm_resource_group.ca_nonroutable_sample.id
  location                  = azurerm_resource_group.ca_nonroutable_sample.location

  body = jsonencode({
    properties = {
      configuration = {
        manualTriggerConfig = {
          parallelism            = 1
          replicaCompletionCount = 1
        }
        replicaRetryLimit = 0
        replicaTimeout    = 180
        triggerType       = "Manual"
      }
      environmentId = azapi_resource.ca_env_lz1.id
      template = {
        containers = [
          {
            name  = "util"
            image = "mcr.microsoft.com/k8se/quickstart:latest"
            command = [
              "curl",
            ]
            args = [
              "--fail",
              "http://${azurerm_private_dns_a_record.corp_lz2_hello.fqdn}",
              "-o",
              "/dev/null",
              "--retry",
              "5",
            ]
            resources = {
              cpu    = 0.25
              memory = "0.5Gi"
            }
          }
        ]
      }
      workloadProfileName = "Consumption"
    }
  })
}

resource "azapi_resource_action" "caj_check_lz1_to_lz2_start" {
  type                   = "Microsoft.App/jobs@2023-05-01"
  resource_id            = azapi_resource.caj_check_lz1_to_lz2.id
  action                 = "start"
  response_export_values = ["name", "id"]

  lifecycle {
    replace_triggered_by = [
      null_resource.always_run
    ]
  }

  // Waiting for execution
  provisioner "local-exec" {
    command = "sleep 60"
  }
}

check "lz1_to_lz2" {
  data "azapi_resource" "caj_check_lz1_to_lz2_exec" {
    name      = jsondecode(azapi_resource_action.caj_check_lz1_to_lz2_start.output).name
    parent_id = azapi_resource.caj_check_lz1_to_lz2.id
    type      = "Microsoft.App/jobs/executions@2023-05-01"

    response_export_values = ["properties.status"]
  }

  assert {
    condition     = jsondecode(data.azapi_resource.caj_check_lz1_to_lz2_exec.output).properties.status == "Succeeded"
    error_message = "curl check failed: lz1 to lz2"
  }
}

resource "azapi_resource" "caj_check_lz2_to_lz1" {
  depends_on = [
    azurerm_application_gateway.lz1,
    azurerm_private_dns_resolver.hub,
    azurerm_private_dns_resolver_virtual_network_link.corp_to_lz2_nonroutable,
  ]
  type                      = "Microsoft.App/jobs@2023-05-01"
  schema_validation_enabled = false
  name                      = "caj-check-lz2-to-lz1"
  parent_id                 = azurerm_resource_group.ca_nonroutable_sample.id
  location                  = azurerm_resource_group.ca_nonroutable_sample.location

  body = jsonencode({
    properties = {
      configuration = {
        manualTriggerConfig = {
          parallelism            = 1
          replicaCompletionCount = 1
        }
        replicaRetryLimit = 0
        replicaTimeout    = 180
        triggerType       = "Manual"
      }
      environmentId = azapi_resource.ca_env_lz2.id
      template = {
        containers = [
          {
            name  = "util"
            image = "mcr.microsoft.com/k8se/quickstart:latest"
            command = [
              "curl",
            ]
            args = [
              "--fail",
              "http://${azurerm_private_dns_a_record.corp_lz1_nginx.fqdn}",
              "-o",
              "/dev/null",
              "--retry",
              "5",
            ]
            resources = {
              cpu    = 0.25
              memory = "0.5Gi"
            }
          }
        ]
      }
      workloadProfileName = "Consumption"
    }
  })
}

resource "azapi_resource_action" "caj_check_lz2_to_lz1_start" {
  type                   = "Microsoft.App/jobs@2023-05-01"
  resource_id            = azapi_resource.caj_check_lz2_to_lz1.id
  action                 = "start"
  response_export_values = ["name", "id"]

  lifecycle {
    replace_triggered_by = [
      null_resource.always_run
    ]
  }

  // Waiting for execution
  provisioner "local-exec" {
    command = "sleep 60"
  }
}

check "lz2_to_lz1" {
  data "azapi_resource" "caj_check_lz2_to_lz1_exec" {
    name      = jsondecode(azapi_resource_action.caj_check_lz2_to_lz1_start.output).name
    parent_id = azapi_resource.caj_check_lz2_to_lz1.id
    type      = "Microsoft.App/jobs/executions@2023-05-01"

    response_export_values = ["properties.status"]
  }

  assert {
    condition     = jsondecode(data.azapi_resource.caj_check_lz2_to_lz1_exec.output).properties.status == "Succeeded"
    error_message = "curl check failed: lz2 to lz1"
  }
}

resource "azapi_resource" "caj_check_lz1_to_onprem" {
  depends_on = [
    azurerm_virtual_network_gateway_connection.onprem_to_hub,
    azurerm_virtual_network_gateway_connection.hub_to_onprem,
    azurerm_private_dns_resolver.hub,
    azurerm_private_dns_resolver_virtual_network_link.corp_to_lz1_nonroutable,
    azurerm_container_group.onprem_resolver,
    azurerm_linux_virtual_machine.onprem,
  ]
  type                      = "Microsoft.App/jobs@2023-05-01"
  schema_validation_enabled = false
  name                      = "caj-check-lz1-to-onprem"
  parent_id                 = azurerm_resource_group.ca_nonroutable_sample.id
  location                  = azurerm_resource_group.ca_nonroutable_sample.location

  body = jsonencode({
    properties = {
      configuration = {
        manualTriggerConfig = {
          parallelism            = 1
          replicaCompletionCount = 1
        }
        replicaRetryLimit = 0
        replicaTimeout    = 180
        triggerType       = "Manual"
      }
      environmentId = azapi_resource.ca_env_lz1.id
      template = {
        containers = [
          {
            name  = "util"
            image = "mcr.microsoft.com/k8se/quickstart:latest"
            command = [
              "curl",
            ]
            args = [
              "--fail",
              "http://apache.${azurerm_private_dns_resolver_forwarding_rule.hub_onprem_example.domain_name}",
              "-o",
              "/dev/null",
              "--retry",
              "5",
            ]
            resources = {
              cpu    = 0.25
              memory = "0.5Gi"
            }
          }
        ]
      }
      workloadProfileName = "Consumption"
    }
  })
}

resource "azapi_resource_action" "caj_check_lz1_to_onprem_start" {
  type                   = "Microsoft.App/jobs@2023-05-01"
  resource_id            = azapi_resource.caj_check_lz1_to_onprem.id
  action                 = "start"
  response_export_values = ["name", "id"]

  lifecycle {
    replace_triggered_by = [
      null_resource.always_run
    ]
  }

  // Waiting for execution
  provisioner "local-exec" {
    command = "sleep 60"
  }
}

check "lz1_to_onprem" {
  data "azapi_resource" "caj_check_lz1_to_onprem_exec" {
    name      = jsondecode(azapi_resource_action.caj_check_lz1_to_onprem_start.output).name
    parent_id = azapi_resource.caj_check_lz1_to_onprem.id
    type      = "Microsoft.App/jobs/executions@2023-05-01"

    response_export_values = ["properties.status"]
  }

  assert {
    condition     = jsondecode(data.azapi_resource.caj_check_lz1_to_onprem_exec.output).properties.status == "Succeeded"
    error_message = "curl check failed: lz1 to onprem"
  }
}

resource "azapi_resource" "caj_check_lz2_to_onprem" {
  depends_on = [
    azurerm_virtual_network_gateway_connection.onprem_to_hub,
    azurerm_virtual_network_gateway_connection.hub_to_onprem,
    azurerm_private_dns_resolver.hub,
    azurerm_private_dns_resolver_virtual_network_link.corp_to_lz2_nonroutable,
    azurerm_container_group.onprem_resolver,
    azurerm_linux_virtual_machine.onprem,
  ]
  type                      = "Microsoft.App/jobs@2023-05-01"
  schema_validation_enabled = false
  name                      = "caj-check-lz2-to-onprem"
  parent_id                 = azurerm_resource_group.ca_nonroutable_sample.id
  location                  = azurerm_resource_group.ca_nonroutable_sample.location

  body = jsonencode({
    properties = {
      configuration = {
        manualTriggerConfig = {
          parallelism            = 1
          replicaCompletionCount = 1
        }
        replicaRetryLimit = 0
        replicaTimeout    = 180
        triggerType       = "Manual"
      }
      environmentId = azapi_resource.ca_env_lz2.id
      template = {
        containers = [
          {
            name  = "util"
            image = "mcr.microsoft.com/k8se/quickstart:latest"
            command = [
              "curl",
            ]
            args = [
              "--fail",
              "http://apache.${azurerm_private_dns_resolver_forwarding_rule.hub_onprem_example.domain_name}",
              "-o",
              "/dev/null",
              "--retry",
              "5",
            ]
            resources = {
              cpu    = 0.25
              memory = "0.5Gi"
            }
          }
        ]
      }
      workloadProfileName = "Consumption"
    }
  })
}

resource "azapi_resource_action" "caj_check_lz2_to_onprem_start" {
  type                   = "Microsoft.App/jobs@2023-05-01"
  resource_id            = azapi_resource.caj_check_lz2_to_onprem.id
  action                 = "start"
  response_export_values = ["name", "id"]

  lifecycle {
    replace_triggered_by = [
      null_resource.always_run
    ]
  }

  // Waiting for execution
  provisioner "local-exec" {
    command = "sleep 60"
  }
}

check "lz2_to_onprem" {
  data "azapi_resource" "caj_check_lz2_to_onprem_exec" {
    name      = jsondecode(azapi_resource_action.caj_check_lz2_to_onprem_start.output).name
    parent_id = azapi_resource.caj_check_lz2_to_onprem.id
    type      = "Microsoft.App/jobs/executions@2023-05-01"

    response_export_values = ["properties.status"]
  }

  assert {
    condition     = jsondecode(data.azapi_resource.caj_check_lz2_to_onprem_exec.output).properties.status == "Succeeded"
    error_message = "curl check failed: lz2 to onprem"
  }
}

locals {
  vnet_address_space = {
    hub             = "10.0.0.0/16"
    lz1_routable    = "10.1.0.0/16"
    lz1_nonroutable = "100.64.0.0/16"
    lz2_routable    = "10.2.0.0/16"
    lz2_nonroutable = "100.64.0.0/16"
    onprem          = "10.10.0.0/16"
  }

  agw_settings_name_template = {
    gateway_ip_configuration_name   = "gw-ip"
    frontend_port_name              = "fe-port"
    frontend_ip_configuration_name  = "fe-ip"
    frontend_pip_configuration_name = "fe-pip"
  }

  ca_lz1_nginx = {
    agw_settings = {
      http_listener_name         = "nginx-listener"
      backend_address_pool_name  = "nginx-be-pool"
      backend_http_settings_name = "nginx-http-settings"
      request_routing_rule_name  = "nginx-routing-rule"
    }
  }

  ca_lz2_hello = {
    agw_settings = {
      http_listener_name         = "hello-listener"
      backend_address_pool_name  = "hello-be-pool"
      backend_http_settings_name = "hello-http-settings"
      request_routing_rule_name  = "hello-routing-rule"
    }
  }

}

locals {
  split_hostname    = split(".", var.hostname)
  short_hostname    = local.split_hostname[0]
  domain            = join(".", slice(local.split_hostname, 1, length(local.split_hostname)))
  sso_administrator = "administrator@${var.sso_domain_name}"
  stage2_install_body = {
    "spec" = {
      "auto_answer" = true
      "vcsa_embedded" = {
        "ceip_enabled" = true
        "standalone" = {
          "sso_admin_password" = var.administrator_password == "" ? random_password.administrator_password.result : var.administrator_password
          "sso_domain_name"    = var.sso_domain_name
        }
      }
    }
  }
}

resource "random_password" "root_password" {
  length  = 16
  lower = true
  upper = true
  numeric = true
  special = true
  min_lower = 1
  min_upper = 1
  min_numeric = 1
  min_special = 1

}

resource "random_password" "administrator_password" {
  length  = 16
  lower = true
  upper = true
  numeric = true
  special = true
  min_lower = 1
  min_upper = 1
  min_numeric = 1
  min_special = 1
}

data "vsphere_ovf_vm_template" "ova" {
  name              = local.short_hostname
  folder            = var.folder_name
  resource_pool_id  = var.resource_pool_id
  datastore_id      = var.datastore_id
  host_system_id    = var.host_system_id
  remote_ovf_url    = var.ova_uri
  deployment_option = var.deployment_size
  disk_provisioning = "thin"
  ip_protocol       = "IPv4"
  ovf_network_map   = { "Network 1" : var.network_id }
}

resource "vsphere_virtual_machine" "vcsa" {
  name             = data.vsphere_ovf_vm_template.ova.name
  datacenter_id    = var.datacenter_id
  folder           = data.vsphere_ovf_vm_template.ova.folder
  resource_pool_id = data.vsphere_ovf_vm_template.ova.resource_pool_id
  host_system_id   = data.vsphere_ovf_vm_template.ova.host_system_id
  datastore_id     = data.vsphere_ovf_vm_template.ova.datastore_id

  num_cpus               = var.cpu_count_override > 0 ? var.cpu_count_override : data.vsphere_ovf_vm_template.ova.num_cpus
  num_cores_per_socket   = data.vsphere_ovf_vm_template.ova.num_cores_per_socket
  cpu_hot_add_enabled    = data.vsphere_ovf_vm_template.ova.cpu_hot_add_enabled
  cpu_hot_remove_enabled = data.vsphere_ovf_vm_template.ova.cpu_hot_remove_enabled
  nested_hv_enabled      = data.vsphere_ovf_vm_template.ova.nested_hv_enabled
  memory                 = var.memory_override > 0 ? var.memory_override : data.vsphere_ovf_vm_template.ova.memory
  memory_hot_add_enabled = data.vsphere_ovf_vm_template.ova.memory_hot_add_enabled
  annotation             = data.vsphere_ovf_vm_template.ova.annotation
  guest_id               = data.vsphere_ovf_vm_template.ova.guest_id
  alternate_guest_name   = data.vsphere_ovf_vm_template.ova.alternate_guest_name
  scsi_type              = data.vsphere_ovf_vm_template.ova.scsi_type
  scsi_controller_count  = data.vsphere_ovf_vm_template.ova.scsi_controller_count
  sata_controller_count  = data.vsphere_ovf_vm_template.ova.sata_controller_count
  ide_controller_count   = data.vsphere_ovf_vm_template.ova.ide_controller_count
  //swap_placement_policy  = data.vsphere_ovf_vm_template.ova.swap_placement_policy
  //firmware               = data.vsphere_ovf_vm_template.ova.firmware

  enable_logging = true

  network_interface {
    network_id     = var.network_id
    use_static_mac = var.mac_address == "" ? false : true
    mac_address    = var.mac_address
  }

  cdrom {}

  ovf_deploy {
    local_ovf_path    = data.vsphere_ovf_vm_template.ova.local_ovf_path
    disk_provisioning = data.vsphere_ovf_vm_template.ova.disk_provisioning
    ip_protocol       = data.vsphere_ovf_vm_template.ova.ip_protocol
    ovf_network_map   = data.vsphere_ovf_vm_template.ova.ovf_network_map
    deployment_option = data.vsphere_ovf_vm_template.ova.deployment_option
  }

  vapp {
    properties = {
      "guestinfo.cis.appliance.net.addr.family" = "ipv4"
      "guestinfo.cis.appliance.net.mode"        = var.ip_address == "" ? "dhcp" : "static"
      "guestinfo.cis.appliance.net.addr"        = var.ip_address
      "guestinfo.cis.appliance.net.dns.servers" = var.dns
      "guestinfo.cis.appliance.net.prefix"      = var.prefix
      "guestinfo.cis.appliance.net.gateway"     = var.gateway
      "guestinfo.cis.appliance.net.pnid"        = var.hostname
      "guestinfo.cis.appliance.root.passwd"     = var.root_password == "" ? random_password.root_password.result: var.root_password
      "guestinfo.cis.ceip_enabled"              = title(tostring(var.enable_ceip))
    }
  }

  provisioner "local-exec" {
    command = "${path.module}/vcsa-wait-for-stage1.sh "
    environment = {
      VCENTER_HOSTNAME = var.hostname
      VAMI_USERNAME    = "root"
      VAMI_PASSWORD    = var.root_password == "" ? random_password.root_password.result: var.root_password
    }
  }

  provisioner "local-exec" {
    command = "${path.module}/vcsa-stage2.sh "
    environment = {
      VCENTER_HOSTNAME = var.hostname
      VAMI_USERNAME    = "root"
      VAMI_PASSWORD    = var.root_password == "" ? random_password.root_password.result: var.root_password
      BODY             = jsonencode(local.stage2_install_body)
    }
  }

  provisioner "local-exec" {
    command = "${path.module}/vcsa-enable-ssh.sh "
    environment = {
      VCENTER_HOSTNAME = var.hostname
      VAMI_USERNAME    = "root"
      VAMI_PASSWORD    = var.root_password == "" ? random_password.root_password.result: var.root_password
      ENABLE_SSH       = title(tostring(var.enable_ssh))
    }
  }

  lifecycle {
    ignore_changes = [
      // it looks like some of the properties get deleted from the VM after it is deployed
      // just ignore them after the initial deployment
      vapp.0.properties,
      // ignore changes made by DRS or vMotion after deployment
      host_system_id
    ]
  }
}

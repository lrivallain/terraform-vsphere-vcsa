output "administrator_user" {
  value       = local.sso_administrator
  description = "The full username of the default VMware SSO Administrator."
}

output "root_password" {
  value       = var.root_password == "" ? random_password.root_password.result: var.root_password
  sensitive   = true
  description = "The root password that was generated for the vCenter Server Appliance."
}

output "administrator_password" {
  value       = var.administrator_password == "" ? random_password.administrator_password.result : var.administrator_password
  sensitive   = true
  description = "The password of the default VMware SSO Administrator."
}

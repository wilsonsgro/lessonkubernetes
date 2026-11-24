output "namespace" {
  value = local.ns
}

output "dominio" {
  value = var.dominio
}

output "nodeport" {
  value = {
    http   = var.nodeport_http
    https  = var.nodeport_https
    salute = var.nodeport_salute
  }
}

output "utente_accesso" {
  value = var.utente_accesso
}

output "password_accesso" {
  value     = random_password.accesso.result
  sensitive = true
}

output "ca_pem" {
  value = tls_self_signed_cert.ca.cert_pem
}

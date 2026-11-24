resource "kubernetes_namespace_v1" "biodistretto" {
  metadata {
    name = var.namespace
  }
}

resource "random_password" "mariadb_root" {
  length  = 32
  special = false
}

resource "random_password" "mariadb_utente" {
  length  = 32
  special = false
}

resource "random_password" "minio" {
  length  = 32
  special = false
}

resource "random_password" "accesso" {
  length  = 20
  special = false
}

resource "random_password" "sale_accesso" {
  length           = 8
  special          = true
  override_special = "./"
}

resource "htpasswd_password" "accesso" {
  password = random_password.accesso.result
  salt     = random_password.sale_accesso.result
}

resource "random_id" "app_key" {
  byte_length = 32
}

locals {
  app_key = var.app_key != "" ? var.app_key : "base64:${random_id.app_key.b64_std}"
}

resource "kubernetes_secret_v1" "mariadb" {
  metadata {
    name      = "mariadb"
    namespace = kubernetes_namespace_v1.biodistretto.metadata[0].name
  }
  data = {
    MARIADB_ROOT_PASSWORD = random_password.mariadb_root.result
    MARIADB_PASSWORD      = random_password.mariadb_utente.result
  }
}

resource "kubernetes_secret_v1" "minio" {
  metadata {
    name      = "minio"
    namespace = kubernetes_namespace_v1.biodistretto.metadata[0].name
  }
  data = {
    MINIO_ROOT_USER     = "biodistretto-admin"
    MINIO_ROOT_PASSWORD = random_password.minio.result
  }
}

resource "kubernetes_secret_v1" "backend" {
  metadata {
    name      = "backend"
    namespace = kubernetes_namespace_v1.biodistretto.metadata[0].name
  }
  data = {
    APP_KEY             = local.app_key
    DB_PASSWORD         = random_password.mariadb_utente.result
    MINIO_ROOT_USER     = "biodistretto-admin"
    MINIO_ROOT_PASSWORD = random_password.minio.result
  }
}

resource "kubernetes_secret_v1" "accesso" {
  metadata {
    name      = "nginx-accesso"
    namespace = kubernetes_namespace_v1.biodistretto.metadata[0].name
  }
  data = {
    htpasswd = "${var.utente_accesso}:${htpasswd_password.accesso.apr1}\n"
  }
}

resource "tls_private_key" "ca" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_self_signed_cert" "ca" {
  private_key_pem       = tls_private_key.ca.private_key_pem
  is_ca_certificate     = true
  validity_period_hours = 24 * 365 * 3
  allowed_uses          = ["cert_signing", "crl_signing"]
  subject {
    common_name  = "CA laboratorio Biodistretto"
    organization = "Biodistretto Grecanico"
  }
}

resource "tls_private_key" "sito" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_cert_request" "sito" {
  private_key_pem = tls_private_key.sito.private_key_pem
  dns_names       = [var.dominio, "www.${var.dominio}", "backend.${var.dominio}"]
  subject {
    common_name = "www.${var.dominio}"
  }
}

resource "tls_locally_signed_cert" "sito" {
  cert_request_pem      = tls_cert_request.sito.cert_request_pem
  ca_private_key_pem    = tls_private_key.ca.private_key_pem
  ca_cert_pem           = tls_self_signed_cert.ca.cert_pem
  validity_period_hours = 24 * 365
  early_renewal_hours   = 24 * 30
  allowed_uses          = ["digital_signature", "key_encipherment", "server_auth"]
}

resource "kubernetes_secret_v1" "tls" {
  metadata {
    name      = "nginx-tls"
    namespace = kubernetes_namespace_v1.biodistretto.metadata[0].name
  }
  type = "kubernetes.io/tls"
  data = {
    "tls.crt" = "${tls_locally_signed_cert.sito.cert_pem}${tls_self_signed_cert.ca.cert_pem}"
    "tls.key" = tls_private_key.sito.private_key_pem
  }
}

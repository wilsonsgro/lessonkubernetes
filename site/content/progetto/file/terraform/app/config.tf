locals {
  ns          = kubernetes_namespace_v1.biodistretto.metadata[0].name
  docker_conf = "${path.module}/../../../docker/config/nginx"
  url_sito    = "https://www.${var.dominio}"

  nginx_file = {
    "nginx.conf"          = file("${local.docker_conf}/nginx.conf")
    "proxy_common.conf"   = file("${local.docker_conf}/proxy_common.conf")
    "backend_prefix.conf" = file("${local.docker_conf}/backend_prefix.conf")
    "www.conf"            = templatefile("${path.module}/nginx/www.conf.tftpl", { dominio = var.dominio })
    "backend.conf"        = templatefile("${path.module}/nginx/backend.conf.tftpl", { dominio = var.dominio })
    "bordo.conf"          = file("${path.module}/nginx/bordo.conf")
  }

  backend_env = {
    APP_ENV                  = "production"
    APP_DEBUG                = "false"
    APP_URL                  = "${local.url_sito}/backend"
    LOG_LEVEL                = "warning"
    LOG_CHANNEL              = "stderr"
    DB_CONNECTION            = "mysql"
    DB_HOST                  = "mariadb"
    DB_PORT                  = "3306"
    DB_DATABASE              = "biodistretto"
    DB_USERNAME              = "biodistretto"
    CACHE_DRIVER             = "redis"
    CACHE_STORE              = "redis"
    SESSION_DRIVER           = "redis"
    QUEUE_CONNECTION         = "redis"
    REDIS_CLIENT             = "predis"
    REDIS_HOST               = "redis"
    REDIS_PORT               = "6379"
    MAIL_MAILER              = "smtp"
    MAIL_HOST                = "mailhog"
    MAIL_PORT                = "1025"
    FILESYSTEM_DISK          = "minio"
    MINIO_ENDPOINT           = "http://minio:9000"
    MINIO_PUBLIC_URL         = "${local.url_sito}/backend/media"
    MINIO_BUCKET             = "biodistretto"
    ELASTICSEARCH_HOST       = "http://elasticsearch:9200"
    SANCTUM_STATEFUL_DOMAINS = "www.${var.dominio},${var.dominio},backend.${var.dominio}"
  }
}

resource "kubernetes_config_map_v1" "nginx" {
  metadata {
    name      = "nginx"
    namespace = local.ns
  }
  data = local.nginx_file
}

resource "kubernetes_config_map_v1" "backend" {
  metadata {
    name      = "backend"
    namespace = local.ns
  }
  data = local.backend_env
}

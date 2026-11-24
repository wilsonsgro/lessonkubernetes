locals {
  immagine_minio = "wilsonstart/minio:RELEASE.2025-09-07T16-13-09Z-cpuv1"

  var_manifest = {
    ns                = var.namespace
    dominio           = var.dominio
    storage_class     = var.storage_class
    immagine_minio    = local.immagine_minio
    immagine_backend  = var.immagine_backend
    immagine_frontend = var.immagine_frontend
    repliche          = var.repliche_web
    ip_nginx          = var.ip_nginx
    nodeport_http     = var.nodeport_http
    nodeport_https    = var.nodeport_https
    nodeport_salute   = var.nodeport_salute
    checksum_backend  = nonsensitive(sha256(jsonencode([local.backend_env, var.app_key])))
    checksum_nginx    = sha256(jsonencode(local.nginx_file))
  }

  dati = {
    for m in provider::kubernetes::manifest_decode_multi(templatefile("${path.module}/manifests/dati.yaml.tftpl", local.var_manifest)) :
    "${m.kind}/${m.metadata.name}" => m
  }
  app = {
    for m in provider::kubernetes::manifest_decode_multi(templatefile("${path.module}/manifests/app.yaml.tftpl", local.var_manifest)) :
    "${m.kind}/${m.metadata.name}" => m
  }
}

resource "kubernetes_manifest" "dati" {
  for_each = local.dati
  manifest = each.value

  wait {
    rollout = contains(["StatefulSet", "Deployment"], each.value.kind)
  }

  timeouts {
    create = "10m"
    update = "10m"
  }

  depends_on = [kubernetes_namespace_v1.biodistretto, kubernetes_secret_v1.mariadb, kubernetes_secret_v1.minio]
}

resource "kubernetes_manifest" "minio_init" {
  manifest = provider::kubernetes::manifest_decode(templatefile("${path.module}/manifests/minio-init.yaml.tftpl", local.var_manifest))

  wait {
    condition {
      type   = "Complete"
      status = "True"
    }
  }

  timeouts {
    create = "5m"
  }

  depends_on = [kubernetes_manifest.dati]
}

resource "kubernetes_manifest" "app" {
  for_each = local.app
  manifest = each.value

  wait {
    rollout = contains(["StatefulSet", "Deployment"], each.value.kind)
  }

  timeouts {
    create = "10m"
    update = "10m"
  }

  depends_on = [
    kubernetes_manifest.minio_init,
    kubernetes_config_map_v1.backend,
    kubernetes_config_map_v1.nginx,
    kubernetes_secret_v1.backend,
    kubernetes_secret_v1.tls,
    kubernetes_secret_v1.accesso,
  ]
}

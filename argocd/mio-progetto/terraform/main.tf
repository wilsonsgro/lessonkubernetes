# Terraform prepara il terreno (namespace, quote, limiti); cosa ci gira dentro lo decide Argo CD da git.
terraform {
  required_version = ">= 1.5"
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.38"
    }
  }
}

provider "kubernetes" {
  config_path    = var.kubeconfig
  config_context = var.contesto
}

resource "kubernetes_namespace_v1" "sito" {
  metadata {
    name = var.namespace
    labels = {
      "gestito-da" = "terraform"
    }
  }
}

resource "kubernetes_resource_quota_v1" "sito" {
  metadata {
    name      = "quota"
    namespace = kubernetes_namespace_v1.sito.metadata[0].name
  }
  spec {
    hard = {
      pods              = var.max_pod
      "requests.cpu"    = "500m"
      "requests.memory" = "256Mi"
      "limits.cpu"      = "2"
      "limits.memory"   = "1Gi"
    }
  }
}

resource "kubernetes_limit_range_v1" "sito" {
  metadata {
    name      = "default"
    namespace = kubernetes_namespace_v1.sito.metadata[0].name
  }
  spec {
    limit {
      type = "Container"
      default = {
        cpu    = "100m"
        memory = "64Mi"
      }
      default_request = {
        cpu    = "20m"
        memory = "16Mi"
      }
    }
  }
}

output "namespace" {
  value = kubernetes_namespace_v1.sito.metadata[0].name
}

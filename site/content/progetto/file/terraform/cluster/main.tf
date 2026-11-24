# Cluster minikube del Biodistretto: nodi e addon; i workload stanno nello stack ../app.
terraform {
  required_version = ">= 1.8"
  required_providers {
    minikube = {
      source  = "scott-the-programmer/minikube"
      version = "~> 0.8"
    }
  }
}

provider "minikube" {
  kubernetes_version = var.versione_kubernetes
}

resource "minikube_cluster" "biodistretto" {
  cluster_name = var.nome_cluster
  driver       = "docker"
  cni          = "kindnet"
  nodes        = var.nodi
  cpus         = var.cpu
  memory       = var.memoria
  addons       = var.addon
  wait         = ["apiserver", "system_pods", "node_ready"]
}

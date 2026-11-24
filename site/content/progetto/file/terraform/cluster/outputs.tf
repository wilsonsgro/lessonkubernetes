output "nome_cluster" {
  value = minikube_cluster.biodistretto.cluster_name
}

output "host" {
  value = minikube_cluster.biodistretto.host
}

output "client_certificate" {
  value     = minikube_cluster.biodistretto.client_certificate
  sensitive = true
}

output "client_key" {
  value     = minikube_cluster.biodistretto.client_key
  sensitive = true
}

output "cluster_ca_certificate" {
  value     = minikube_cluster.biodistretto.cluster_ca_certificate
  sensitive = true
}

variable "nome_cluster" {
  type    = string
  default = "biodistretto"
}

variable "versione_kubernetes" {
  type    = string
  default = "v1.34.0"
}

variable "nodi" {
  type    = number
  default = 2
}

variable "cpu" {
  type    = string
  default = "2"
}

variable "memoria" {
  type    = string
  default = "3500m"
}

variable "addon" {
  type = list(string)
  default = [
    "default-storageclass",
    "storage-provisioner",
    "metrics-server",
    "volumesnapshots",
    "csi-hostpath-driver",
  ]
}

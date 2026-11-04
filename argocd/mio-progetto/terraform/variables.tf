variable "kubeconfig" {
  type    = string
  default = "~/.kube/config"
}

variable "contesto" {
  type    = string
  default = "lab"
}

variable "namespace" {
  type    = string
  default = "mio-sito"
}

variable "max_pod" {
  type    = string
  default = "6"
}

variable "namespace" {
  type    = string
  default = "biodistretto"
}

variable "dominio" {
  type    = string
  default = "biodistretto.lab"
}

variable "immagine_backend" {
  type = string
}

variable "immagine_frontend" {
  type = string
}

variable "app_key" {
  type      = string
  sensitive = true
  default   = ""
}

variable "storage_class" {
  type    = string
  default = "csi-hostpath-sc"
}

variable "repliche_web" {
  type    = number
  default = 2
}

variable "nodeport_http" {
  type    = number
  default = 30080
}

variable "nodeport_https" {
  type    = number
  default = 30443
}

variable "nodeport_salute" {
  type    = number
  default = 30081
}

variable "ip_nginx" {
  type    = string
  default = "10.96.100.10"
}

variable "utente_accesso" {
  type    = string
  default = "biodistretto"
}

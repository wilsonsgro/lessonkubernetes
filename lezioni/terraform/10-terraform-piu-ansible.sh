#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════
# 10. TERRAFORM + ANSIBLE: CREARE E CONFIGURARE IN UNA SOLA CATENA
# Versione: Terraform 1.17 · provider docker 4.6 + hashicorp/local · ansible-core 2.21
# Livello: 5 — Automazione su scala
# ═══════════════════════════════════════════════════════════════════════════
# Il passaggio di consegne classico:
#   Terraform  crea le macchine (qui container con systemd, in cloud VM)
#              e SCRIVE l'inventario con nomi e indirizzi che solo lui conosce
#   Ansible    legge l'inventario e configura i servizi
#
#   terraform apply ──▶ inventory.yml (local_file + templatefile)
#                  └──▶ ansible-playbook -i inventory.yml site.yml
#
# ALTERNATIVE PER IL PASSAGGIO
#   • local_file con l'inventario (questo lab): semplice, esplicito
#   • inventario dinamico dai TAG del cloud (aws_ec2): Terraform mette il
#     tag Ruolo=web, Ansible trova da sé; niente file da passare
#   • provider ansible/ansible per Terraform: host e gruppi come risorse
#   • cloud-init (user_data) per il bootstrap minimo al primo avvio
#
# MUTABILE O IMMUTABILE? (domanda da colloquio senior)
#   Mutabile: le VM vivono a lungo e Ansible le aggiorna. Rischio: drift di
#   configurazione, "snowflake server" diversi l'uno dall'altro.
#   Immutabile: Packer + Ansible costruiscono un'IMMAGINE (AMI), Terraform
#   sostituisce le VM con quelle nuove; nessuna modifica in esecuzione.
#   Con Kubernetes è il default: l'immagine container è l'artefatto
#   immutabile, Ansible resta per i nodi, le VM fuori dal cluster, la rete.
#
# LAB SU UBUNTU
#   bash 10-terraform-piu-ansible.sh crea && cd catena
#   terraform init && terraform apply -auto-approve
#   cat inventory.yml
#   ansible-playbook -i inventory.yml site.yml
#   terraform apply -auto-approve -var repliche=3    # un nodo in più…
#   ansible-playbook -i inventory.yml site.yml        # …configurato dallo stesso playbook
#   terraform destroy -auto-approve
#
# ── NEL PROGETTO VERO: il Biodistretto su minikube ───────────────────────
#   ~/biodistretto/kubernetes (branch kubernetes). I grep partono da lì:
#   cd ~/biodistretto/kubernetes · come si usa: il README della cartella
#   La catena al contrario: qui è Ansible a lanciare Terraform, con
#   community.general.terraform, e poi a usarne il risultato:
#     grep -n -A6 'community.general.terraform' ansible/roles/cluster/tasks/main.yml
#   Il posto dell'inventario scritto da Terraform lo prende l'elenco dei
#   nodi, che diventa la config di HAProxy:
#     grep -n -A2 -F '{% for nome, ip in nodi %}' ansible/roles/haproxy/templates/haproxy.cfg.j2
#   TRAPPOLA: senza plan_file, il modulo lascia in /tmp un tmp*.tfplan per
#   ogni giro, con dentro lo stato (chiavi e password). Rimedio: TMPDIR
#   privato e pulizia in always.
#     grep -n 'TMPDIR' ansible/roles/cluster/tasks/main.yml ansible/roles/app/tasks/main.yml
#   Per controllarlo: `unzip -l` su un piano, poi cerca le chiavi dentro.
#   Guardare solo i log non basta.

set -euo pipefail
D=./catena

crea() {
  mkdir -p $D

  cat > $D/main.tf <<'EOF'
terraform {
  required_version = ">= 1.10"
  required_providers {
    docker = { source = "kreuzwerker/docker", version = "~> 4.6" }
    local  = { source = "hashicorp/local", version = "~> 2.9" }
  }
}

provider "docker" {}

variable "repliche" {
  type    = number
  default = 2
}

resource "docker_image" "nodo" {
  name         = "geerlingguy/docker-ubuntu2404-ansible:latest"
  keep_locally = true
}

resource "docker_network" "catena" {
  name = "catena"
}

resource "docker_container" "nodo" {
  for_each = toset([for i in range(var.repliche) : format("app%02d", i + 1)])

  name          = "catena-${each.key}"
  hostname      = each.key
  image         = docker_image.nodo.image_id
  privileged    = true # systemd nel container: solo per il lab
  cgroupns_mode = "host"

  volumes {
    host_path      = "/sys/fs/cgroup"
    container_path = "/sys/fs/cgroup"
  }

  networks_advanced {
    name = docker_network.catena.name
  }

  labels {
    label = "ruolo"
    value = "web"
  }
}

resource "local_file" "inventario" {
  filename        = "${path.module}/inventory.yml"
  file_permission = "0644"
  content = templatefile("${path.module}/inventory.yml.tftpl", {
    nodi = {
      for k, c in docker_container.nodo :
      k => { container = c.name, ip = c.network_data[0].ip_address }
    }
  })
}

output "nodi" {
  value = { for k, c in docker_container.nodo : k => c.network_data[0].ip_address }
}
EOF

  cat > $D/inventory.yml.tftpl <<'EOF'
# Generato da Terraform: non modificare a mano
all:
  vars:
    ansible_connection: community.docker.docker
    ansible_python_interpreter: /usr/bin/python3
  children:
    web:
      hosts:
%{ for nome, n in nodi ~}
        ${nome}:
          ansible_host: ${n.container}
          ip_privato: ${n.ip}
%{ endfor ~}
EOF

  cat > $D/site.yml <<'EOF'
- name: Configura i nodi creati da Terraform
  hosts: web
  become: true
  tasks:
    - name: nginx
      ansible.builtin.apt:
        name: nginx
        state: present
        update_cache: true
        cache_valid_time: 3600

    - name: Pagina con i dati di Terraform
      ansible.builtin.copy:
        content: "{{ inventory_hostname }} {{ ip_privato }}\n"
        dest: /var/www/html/index.html
        mode: "0644"

    - name: nginx attivo
      ansible.builtin.systemd_service:
        name: nginx
        state: started
        enabled: true

    - name: Il nodo risponde
      ansible.builtin.uri:
        url: http://localhost/
        return_content: true
      register: r
      failed_when: inventory_hostname not in r.content
EOF
  echo "catena scritta in $D"
}

case "${1:-}" in
  crea) crea ;;
  *) echo "uso: $0 crea" ;;
esac

# ── DOMANDE DA COLLOQUIO ────────────────────────────────────────────────────
# D: Perché non usare i provisioner di Terraform (remote-exec) per configurare?
# R: HashiCorp li indica come ultima risorsa: non sono nel piano, non sono
#    idempotenti, un fallimento marca la risorsa "tainted" e la fa
#    ricreare, e la configurazione cambia più spesso dell'infrastruttura.
#    Meglio cloud-init per il minimo e Ansible (o un'immagine Packer) per il resto.
#
# D: Chi possiede cosa tra Terraform e Ansible?
# R: Confine netto: Terraform il ciclo di vita delle risorse (creare,
#    dimensionare, distruggere, rete, DNS, IAM), Ansible lo stato dentro
#    il sistema operativo. Se tutti e due toccano la stessa cosa (es. un
#    security group) avrai drift e lotte tra tool.
#
# D: Come porti questa catena in CI?
# R: Job terraform (plan in MR, apply su main) che pubblica l'inventario
#    come artefatto (o si usa l'inventario dinamico), poi job ansible con
#    --check --diff in MR e run vero dopo l'apply.

# ══════════════════════════════════════════════════════════════════════════
# RIEPILOGO
# • Terraform crea e scrive l'inventario (local_file + templatefile)
# • Ansible configura; lo stesso playbook copre i nodi aggiunti
# • Alternative: inventario dinamico dai tag, cloud-init, Packer
# • Mutabile (Ansible aggiorna) vs immutabile (immagine nuova, VM nuove)
# • Niente provisioner: il confine tra i due tool deve restare netto
# ══════════════════════════════════════════════════════════════════════════

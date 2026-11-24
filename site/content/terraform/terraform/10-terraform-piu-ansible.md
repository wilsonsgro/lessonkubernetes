# 10 — Terraform + Ansible

Spiegazione di `10-terraform-piu-ansible.sh` (questa cartella). Lezione sul sito: http://127.0.0.1:3000/terraform/10

## In una frase

Lo script mette in fila i due strumenti del corso: **Terraform crea i nodi** (container Ubuntu con systemd, al posto
delle VM) e **scrive l'inventario** con nomi e indirizzi che solo lui conosce; **Ansible lo legge e configura** i nodi.
Poi aggiunge un terzo nodo con `-var repliche=3` e mostra che lo **stesso playbook** lo configura senza toccare gli
altri due, e alla fine distrugge tutto.

## Questo script e la lezione

| File | Che cos'è | Come si usa |
|---|---|---|
| `~/kubernetesprj/terraform/10-terraform-piu-ansible.sh` | **questo**: lo script guidato. Genera la catena, fa `init`/`apply`, lancia il playbook, aggiunge un nodo, distrugge (Invio / s / q) | `bash terraform/10-terraform-piu-ansible.sh` da `~/kubernetesprj` |
| `~/kubernetesprj/lezioni/terraform/10-terraform-piu-ansible.sh` | il file di lezione: uno **script bash** con la teoria nei commenti e una funzione `crea` che scrive `main.tf`, il template dell'inventario e il playbook | si **legge**; lo lancia il runner (`bash … crea`) |

Come nella 08, i due file hanno lo **stesso nome**: quello in `terraform/` è il guidato, quello in `lezioni/terraform/`
il generatore (senza argomenti stampa solo `uso: … crea`).

```bash
cd ~/kubernetesprj
bash terraform/10-terraform-piu-ansible.sh
```

## Com'è fatto lo script

```
source ../lib/passo.sh          → titolo / passo / cartella
export PATH=~/.local/bin:…      → ansible di pipx
cartella iac/10                 → ~/kubernetesprj/lavoro/iac/10
8 × passo                       → crea, template, init+apply, inventario, playbook, +1 nodo, playbook, destroy
```

Il generatore ha `set -euo pipefail` e `D=./catena`: scrive in `~/kubernetesprj/lavoro/iac/10/catena/` tre file,
`main.tf`, `inventory.yml.tftpl` e `site.yml`, e stampa `catena scritta in ./catena`.

Il passo 3 fa `cd catena`. Il runner esegue i comandi con `eval` nella **stessa shell**, quindi da lì in poi tutti i
passi girano dentro `catena/`. Se salti il passo 3 con **s**, i passi dopo cercano i file nella cartella sbagliata e
falliscono.

Non usa i container della lezione 06 (`web1`, `web2`, `db1`) né la sua cartella: crea i suoi.

---

## 1. La teoria nell'intestazione

Versione: **Terraform 1.17 · provider docker 4.6 + hashicorp/local · ansible-core 2.21**. Livello 5 — Automazione
su scala.

### Il passaggio di consegne

```
Terraform  crea le macchine (qui container con systemd, in cloud VM)
           e SCRIVE l'inventario con nomi e indirizzi che solo lui conosce
Ansible    legge l'inventario e configura i servizi

terraform apply ──▶ inventory.yml (local_file + templatefile)
               └──▶ ansible-playbook -i inventory.yml site.yml
```

### Alternative per il passaggio

| Modo | Come |
|---|---|
| `local_file` con l'inventario | **questo lab**: semplice, esplicito |
| inventario dinamico dai **tag** del cloud (`aws_ec2`) | Terraform mette il tag `Ruolo=web`, Ansible trova da sé; niente file da passare (lezione 06) |
| provider `ansible/ansible` per Terraform | host e gruppi come risorse Terraform |
| cloud-init (`user_data`) | il bootstrap minimo al primo avvio |

### Mutabile o immutabile? (domanda da colloquio senior)

- **Mutabile**: le VM vivono a lungo e Ansible le aggiorna. Rischio: **drift** di configurazione, "snowflake server"
  diversi l'uno dall'altro.
- **Immutabile**: Packer + Ansible costruiscono un'**immagine** (AMI), Terraform sostituisce le VM con quelle nuove;
  nessuna modifica in esecuzione.
- Con **Kubernetes** è il default: l'immagine container è l'artefatto immutabile; Ansible resta per i nodi, le VM fuori
  dal cluster, la rete.

### Riquadro «NEL PROGETTO VERO»

In `~/biodistretto/kubernetes` (branch `kubernetes`; come si usa: il README della cartella) la catena è **al
contrario**: è Ansible a lanciare Terraform, con `community.general.terraform`, e poi a usarne il risultato. Al posto
dell'inventario scritto da Terraform c'è l'elenco dei nodi, che diventa la config di HAProxy.

```bash
cd ~/biodistretto/kubernetes
grep -n -A6 'community.general.terraform' ansible/roles/cluster/tasks/main.yml
grep -n -A2 -F '{% for nome, ip in nodi %}' ansible/roles/haproxy/templates/haproxy.cfg.j2
grep -n 'TMPDIR' ansible/roles/cluster/tasks/main.yml ansible/roles/app/tasks/main.yml
```

**Trappola** riportata nel riquadro: senza `plan_file`, il modulo lascia in `/tmp` un `tmp*.tfplan` per ogni giro, con
dentro lo **stato** (chiavi e password). Rimedio: `TMPDIR` privato e pulizia in `always`. Per controllarlo: `unzip -l`
su un piano, poi cerca le chiavi dentro. Guardare solo i log non basta.

---

## 2. `main.tf`, blocco per blocco

### `terraform` e `provider`

```hcl
terraform {
  required_version = ">= 1.10"
  required_providers {
    docker = { source = "kreuzwerker/docker", version = "~> 4.6" }
    local  = { source = "hashicorp/local", version = "~> 2.9" }
  }
}

provider "docker" {}
```

- Due provider: **docker** (kreuzwerker) per immagine, rete e container; **local** (HashiCorp) per scrivere un file sul
  disco del control node.
- `~> 4.6` accetta 4.6, 4.7… ma non 5.0.
- `provider "docker" {}` vuoto: usa il Docker locale.

### La variabile `repliche`

```hcl
variable "repliche" {
  type    = number
  default = 2
}
```

Quanti nodi creare. Il passo 6 la porta a 3 con `-var repliche=3`.

### `docker_image.nodo` e `docker_network.catena`

| Risorsa | Campo | Valore | Perché |
|---|---|---|---|
| `docker_image.nodo` | `name` | `geerlingguy/docker-ubuntu2404-ansible:latest` | la stessa immagine della lezione 06: Ubuntu 24.04 con systemd e Python |
| | `keep_locally` | `true` | al `destroy` l'immagine **resta** sul disco: niente nuovo download la volta dopo |
| `docker_network.catena` | `name` | `catena` | una rete Docker solo per questi nodi |

### `docker_container.nodo` — campo per campo

```hcl
for_each = toset([for i in range(var.repliche) : format("app%02d", i + 1)])
```

`range(2)` = `[0, 1]`; `format("app%02d", i + 1)` → `app01`, `app02`. Con `repliche = 3` si aggiunge `app03`. È
`for_each` su un **insieme di nomi**, non `count`: ogni container è indirizzato dal suo nome
(`docker_container.nodo["app01"]`), e aggiungerne uno non tocca gli altri.

| Campo | Valore | Perché |
|---|---|---|
| `name` | `"catena-${each.key}"` | nome del container: `catena-app01`, `catena-app02` |
| `hostname` | `each.key` | dentro il container: `app01` |
| `image` | `docker_image.nodo.image_id` | il riferimento all'immagine crea anche la **dipendenza**: prima l'immagine, poi i container |
| `privileged` | `true` | systemd nel container: **solo per il lab** (commento del file) |
| `cgroupns_mode` | `"host"` | come `--cgroupns=host` della 06 |
| `volumes` | `/sys/fs/cgroup` → `/sys/fs/cgroup` | come `-v /sys/fs/cgroup:/sys/fs/cgroup` della 06 |
| `networks_advanced.name` | `docker_network.catena.name` | collega il container alla rete `catena` |
| `labels` | `ruolo` = `web` | un'etichetta Docker: è il "tag" che userebbe un inventario dinamico (`community.docker.docker_containers`, lezione 06). Qui non la legge nessuno |

Il blocco del container è lo stesso `docker run` della lezione 06, scritto in HCL.

### `local_file.inventario` — Terraform scrive l'inventario

```hcl
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
```

- `path.module` = la cartella di `main.tf` (`catena/`).
- `templatefile(file, variabili)` riempie il template con una mappa `nodi`: per ogni container, la chiave (`app01`) →
  il nome del container e l'**IP** letto da `network_data[0].ip_address`. L'IP lo assegna Docker alla creazione: per
  questo «solo Terraform lo conosce».
- Il riferimento a `docker_container.nodo` fa sì che il file venga scritto **dopo** i container, e riscritto quando
  cambiano.

### `output "nodi"`

```hcl
output "nodi" {
  value = { for k, c in docker_container.nodo : k => c.network_data[0].ip_address }
}
```

Stampa a fine `apply` la mappa nome → IP. Si rilegge con `terraform output nodi`.

---

## 3. Il template `inventory.yml.tftpl`

```
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
```

- È la sintassi dei **template di Terraform**, non Jinja: `%{ for … }` / `%{ endfor }` per i cicli, `${…}` per i valori.
- Il `~` prima di `}` toglie lo spazio e l'a capo dopo la direttiva: senza, il YAML avrebbe righe vuote in più.
- `ansible_connection: community.docker.docker`: come nella 06, Ansible entra nei container **senza SSH**.
- L'host si chiama `app01` (nome corto, per i log di Ansible), ma `ansible_host: catena-app01` dice alla connessione
  docker in **quale container** entrare.
- `ip_privato` è una variabile nostra: la usa il playbook.

---

## 4. Il playbook `site.yml`

Un play, `hosts: web`, `become: true`:

| Task | Modulo | Cosa fa |
|---|---|---|
| nginx | `ansible.builtin.apt` | installa nginx; `update_cache: true` con `cache_valid_time: 3600` |
| Pagina con i dati di Terraform | `ansible.builtin.copy` | scrive in `/var/www/html/index.html` `{{ inventory_hostname }} {{ ip_privato }}`: il nome e l'IP **arrivati da Terraform** |
| nginx attivo | `ansible.builtin.systemd_service` | `state: started`, `enabled: true` |
| Il nodo risponde | `ansible.builtin.uri` | legge `http://localhost/`; `failed_when: inventory_hostname not in r.content` |

---

## 5. I passi dello script

| Passo | Comando | Cosa vedi / perché |
|---|---|---|
| 1 | `bash $LEZIONI/terraform/10-terraform-piu-ansible.sh crea` | scrive `catena/main.tf`, `catena/inventory.yml.tftpl`, `catena/site.yml` |
| 2 | `cat catena/inventory.yml.tftpl` | il template: Terraform lo riempirà con i nodi creati (`templatefile` + `local_file`) |
| 3 | `cd catena && terraform init && terraform apply -auto-approve` | `init` scarica i provider docker e local; `apply` crea immagine, rete, due container e **scrive `inventory.yml`**. In fondo l'output `nodi` |
| 4 | `cat inventory.yml` | l'inventario generato, con `app01` e `app02`, i loro container e IP: nessuno lo scrive a mano, è un **output di Terraform** |
| 5 | `ansible-playbook -i inventory.yml site.yml` | Ansible configura i nodi appena creati: nginx, pagina, verifica |
| 6 | `terraform apply -auto-approve -var repliche=3 && cat inventory.yml` | Terraform crea **solo** `app03` (gli altri due restano) e riscrive l'inventario, che ora ha tre host |
| 7 | `ansible-playbook -i inventory.yml site.yml` | lo stesso playbook configura `app03`; `app01` e `app02` restano **verdi** (idempotenza) |
| 8 | `terraform destroy -auto-approve` | toglie container, rete e il file `inventory.yml`. L'immagine resta (`keep_locally = true`) |

Nessun passo fallisce apposta.

---

## Trappole

- **Saltare il passo 3** lascia la shell fuori da `catena/`: i passi 4–8 falliscono.
- **`-var repliche=3` non si ricorda**: un `terraform apply` dopo il passo 6 **senza** `-var` torna al default 2 e
  distrugge `app03`. Per renderlo stabile: un file `terraform.tfvars` con `repliche = 3`.
- **Modificare `inventory.yml` a mano non serve**: al prossimo `apply` Terraform lo riscrive dal template (lo dice la
  prima riga del template).
- **`privileged = true`** è solo per il lab: in un ambiente vero i nodi sono VM.
- **Due strumenti sulla stessa cosa** = drift e lotte fra tool (vedi domande).

## Domande da colloquio (dalla coda del file)

- **Perché non usare i provisioner di Terraform (`remote-exec`) per configurare?** HashiCorp li indica come ultima
  risorsa: non sono nel piano, non sono idempotenti, un fallimento marca la risorsa "tainted" e la fa ricreare, e la
  configurazione cambia più spesso dell'infrastruttura. Meglio cloud-init per il minimo e Ansible (o un'immagine
  Packer) per il resto.
- **Chi possiede cosa tra Terraform e Ansible?** Confine netto: Terraform il **ciclo di vita delle risorse** (creare,
  dimensionare, distruggere, rete, DNS, IAM), Ansible lo **stato dentro il sistema operativo**. Se tutti e due toccano
  la stessa cosa (es. un security group) avrai drift e lotte tra tool.
- **Come porti questa catena in CI?** Job terraform (plan in MR, apply su main) che pubblica l'inventario come
  **artefatto** (o si usa l'inventario dinamico), poi job ansible con `--check --diff` in MR e run vero dopo l'apply.

## Dipendenze e pulizia

- **Prima**: lezione 00 (terraform, ansible, `community.docker`), le lezioni 01–05 per Terraform e 06–07 per
  inventario e playbook. Docker funzionante.
- **Pulizia**: il passo 8 (`terraform destroy -auto-approve`). Restano l'immagine
  `geerlingguy/docker-ubuntu2404-ansible:latest`, i file generati e la cartella `.terraform` in
  `~/kubernetesprj/lavoro/iac/10/catena`; per ripartire da zero: `rm -rf ~/kubernetesprj/lavoro/iac/10`.

## Riepilogo

- Terraform **crea** e **scrive l'inventario** (`local_file` + `templatefile`).
- Ansible **configura**; lo stesso playbook copre i nodi aggiunti, e i vecchi restano verdi.
- `for_each` su nomi: aggiungere un nodo non tocca gli altri.
- Alternative: inventario dinamico dai tag, provider ansible, cloud-init, Packer.
- Mutabile (Ansible aggiorna) vs immutabile (immagine nuova, VM nuove).
- Niente provisioner: il confine fra i due tool deve restare netto.

## Prova da solo

1. Dopo il passo 6, `terraform output nodi` e `docker exec catena-app03 cat /var/www/html/index.html`: l'IP scritto nella pagina
   è lo stesso dell'output di Terraform?
2. `terraform plan -var repliche=1`: quali risorse distruggerebbe, e cosa cambierebbe in `local_file.inventario`?
   (Solo `plan`: non applicarlo.)
3. Modifica a mano `inventory.yml` (per esempio cambia `ip_privato` di `app01`), poi `terraform plan -var repliche=3`:
   Terraform se ne accorge? Cosa propone per `local_file.inventario`?

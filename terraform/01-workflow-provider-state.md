# 01 — Workflow, provider e state

Spiegazione di `01-workflow-provider-state.sh` (questa cartella). Lezione sul sito: http://127.0.0.1:3000/terraform/1

## In una frase

Lo script fa girare **tutto il ciclo di Terraform** (init → fmt/validate → plan salvato → apply → destroy) su una
configurazione piccola che usa il **provider docker**, cioè il Docker locale: una rete `lab-iac`, l'immagine
`nginx:1.29-alpine` e un container `lab-web` sulla porta **8088**. In mezzo guarda lo **state** e provoca un **drift**
(ferma il container a mano) per vedere come Terraform se ne accorge e come lo si rimette a posto.

## Questo script e la lezione

| File | Che cos'è |
|---|---|
| `~/kubernetesprj/terraform/01-workflow-provider-state.sh` | **questo**: lo script guidato, da lanciare |
| `~/kubernetesprj/lezioni/terraform/01-workflow-provider-state.tf` | il file di lezione, da **leggere**: la teoria nei commenti e la configurazione HCL che lo script copia come `main.tf` |

Si lancia dalla cartella del progetto:

```bash
cd ~/kubernetesprj
bash terraform/01-workflow-provider-state.sh
```

Come ogni script guidato, per ogni passo stampa la spiegazione e il comando, poi aspetta **Invio** (esegui) ·
**s** (salta) · **q** (esci). `AUTO=1` esegue tutto senza chiedere, `DA=n` parte dal passo n. Se un comando
fallisce compare in rosso `↳ uscita N` e lo script va avanti.

## Com'è fatto lo script

```
source ../lib/passo.sh   → le funzioni titolo / passo / nota / cartella
titolo "01. Workflow, provider e state"
cartella iac/01          → crea ed entra in ~/kubernetesprj/lavoro/iac/01
11 × passo               → copia, init, fmt/validate, plan, apply, curl, state ×2, drift, -replace, destroy
```

Tutto succede nella cartella di lavoro `~/kubernetesprj/lavoro/iac/01`: lì finiscono `main.tf`, `.terraform/`,
`.terraform.lock.hcl`, `piano.tfplan` e `terraform.tfstate`. Il file di lezione resta intatto.

---

## 1. La teoria nell'intestazione

Versione indicata: **Terraform 1.17**, provider **kreuzwerker/docker 4.6**. Livello 0 — Fondamenta IaC.

### Dichiarativo e procedurale

| Famiglia | Esempi citati | Come ragiona |
|---|---|---|
| **dichiarativo** | Terraform, OpenTofu, Pulumi, CloudFormation | descrivi lo **stato finale**; il tool calcola il diff e lo applica |
| **procedurale / di configurazione** | Ansible, Chef, Puppet | descrivi i **passi** (idempotenti) per portare un server in uno stato |

Regola pratica del file: **Terraform CREA** l'infrastruttura (rete, VM, DNS, DB gestiti, cluster), **Ansible
CONFIGURA** ciò che gira dentro. Le due cose si uniscono nella lezione 10.

### Il workflow

| Comando | Cosa fa |
|---|---|
| `terraform init` | scarica provider e moduli, configura il backend |
| `terraform fmt` | formatta (in CI: `fmt -check`) |
| `terraform validate` | sintassi e tipi, senza toccare niente |
| `terraform plan` | legge lo stato, interroga le API (refresh), calcola il **diff** |
| `terraform apply` | esegue il piano (meglio: apply di un piano **salvato**) |
| `terraform destroy` | distrugge tutto ciò che è nello stato |

I simboli del diff nel plan: `+` crea, `~` modifica, `-/+` ricrea, `-` distrugge.

### Lo stato (`terraform.tfstate`)

È la mappa fra gli **indirizzi del codice** (`docker_container.web`) e gli **ID reali** (l'ID del container).

- Senza stato Terraform non sa cosa ha creato → ricreerebbe tutto.
- Contiene **segreti in chiaro** (password generate, chiavi): **mai in git**.
- In team va su un **backend remoto con lock**: lezione 03.

### I comandi LAB dell'intestazione

L'intestazione ripete l'installazione di Terraform (la fa già `00-installa.sh`) e poi il giro a mano:

```bash
mkdir -p ~/iac/01 && cp 01-workflow-provider-state.tf ~/iac/01/main.tf && cd ~/iac/01
terraform init && terraform plan -out=piano.tfplan
terraform apply piano.tfplan
curl -s localhost:8088 | head -3
terraform state list ; terraform state show docker_container.web
docker stop lab-web && terraform plan
terraform apply -replace=docker_container.web
terraform destroy
```

Attenzione alla cartella: a mano l'intestazione usa `~/iac/01`, lo script guidato usa
`~/kubernetesprj/lavoro/iac/01`. Il contenuto è lo stesso.

### Riquadro «NEL PROGETTO VERO»

In `~/biodistretto/kubernetes` (branch `kubernetes`; come si usa: il README della cartella) ci sono **due stack** e
**cinque provider**: `minikube` nello stack *cluster*; `kubernetes`, `random`, `tls`, `htpasswd` nello stack *app*.
Il **lock file è nel repo, lo stato no**:

```bash
cd ~/biodistretto/kubernetes
grep -n 'source' terraform/cluster/main.tf terraform/app/versions.tf
grep -n 'tfstate' .gitignore
terraform -chdir=terraform/app output        # i sensibili appaiono <sensitive>
```

Lo stato lì contiene password, chiavi TLS e la chiave client del cluster, **anche se gli output sono `sensitive`**:
`sensitive` nasconde il valore nell'output, ma **non lo cifra** nello stato.

---

## 2. Il codice HCL, blocco per blocco

### `terraform { … }` — versioni

```hcl
terraform {
  required_version = ">= 1.10"
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 4.6"
    }
  }
}
```

| Campo | Valore | Perché |
|---|---|---|
| `required_version` | `>= 1.10` | la versione minima del binario `terraform` che accetta questa configurazione |
| `source` | `kreuzwerker/docker` | da dove `init` scarica il provider (registro: *namespace/nome*) |
| `version` | `~> 4.6` | vincolo "pessimista": **>= 4.6, < 5.0**. Patch e minor sì, major no |

`init` sceglie una versione che rispetta il vincolo e la scrive in `.terraform.lock.hcl`: i `init` successivi
(tuoi, dei colleghi, della CI) usano **quella**, finché non si aggiorna apposta. Per questo il lock file va in git.

### `provider "docker"`

```hcl
provider "docker" {
  host = "unix:///var/run/docker.sock"
}
```

Il provider **traduce le risorse in chiamate API**, qui le API del Docker locale, raggiunto dal socket Unix. Niente
cloud, niente credenziali: l'utente deve solo poter usare Docker.

### `docker_network.lab`

```hcl
resource "docker_network" "lab" {
  name = "lab-iac"
}
```

Una rete Docker chiamata `lab-iac`. L'**indirizzo** della risorsa in Terraform è `docker_network.lab`
(*tipo.nome-locale*); `name` è il nome che vede Docker.

### `docker_image.nginx`

```hcl
resource "docker_image" "nginx" {
  name         = "nginx:1.29-alpine"
  keep_locally = true
}
```

| Campo | Valore | Perché |
|---|---|---|
| `name` | `nginx:1.29-alpine` | l'immagine da scaricare |
| `keep_locally` | `true` | `destroy` **non** cancella l'immagine dal disco: alla prossima lezione non la riscarichi |

### `docker_container.web` — campo per campo

| Campo | Valore | Perché |
|---|---|---|
| `name` | `lab-web` | il nome del container; è quello che lo script ferma con `docker stop` |
| `image` | `docker_image.nginx.image_id` | un **riferimento** a un'altra risorsa = **dipendenza implicita**: Terraform crea prima l'immagine (e la rete, sotto), poi il container |
| `ports` | `internal = 80`, `external = 8088` | nginx ascolta sulla 80 dentro il container, la pubblichi sulla 8088 dell'host |
| `networks_advanced.name` | `docker_network.lab.name` | collega il container alla rete `lab-iac`; altro riferimento, altra dipendenza |
| `restart` | `unless-stopped` | politica di riavvio di Docker |
| `labels` | `gestito-da = terraform` | un'etichetta Docker: chi guarda `docker inspect` sa chi lo gestisce |
| `lifecycle.ignore_changes` | `[]` | vuoto: nessun campo ignorato (vedi sotto) |

Il commento su `must_run`: il default è `true`, quindi **se il container è fermo il plan lo considera da
sistemare**. È questo che fa vedere il drift del passo 9.

Nessuno ha scritto "prima la rete, poi il container": l'**ordine nasce dai riferimenti**. È il punto del
riepilogo «le dipendenze nascono dai riferimenti tra risorse».

### Il blocco `lifecycle`

Nel file è attivo solo `ignore_changes = []`; le altre due opzioni sono spiegate in commento:

| Opzione | Effetto | Nota del file |
|---|---|---|
| `create_before_destroy` | prima crea il nuovo, poi distrugge il vecchio | **qui fallirebbe**: nome e porta sono unici, servirebbero nomi diversi |
| `prevent_destroy = true` | un plan che distrugge la risorsa **fallisce** | protezione per le risorse preziose |
| `ignore_changes = [labels]` | le modifiche esterne a questi campi vengono ignorate | utile se qualcun altro tocca apposta un campo |

### Gli output

```hcl
output "url" {
  value       = "http://localhost:${docker_container.web.ports[0].external}"
  description = "Indirizzo del container"
}

output "container_id" {
  value = docker_container.web.id
}
```

Gli output si stampano alla fine di `apply` (e con `terraform output`). `url` legge la porta esterna dal **primo**
blocco `ports` del container (`ports[0]`): `http://localhost:8088`. `container_id` è l'ID che Docker ha dato al
container, lo stesso che sta nello stato.

---

## 3. I passi dello script

| # | Comando | Cosa vedi / perché |
|---|---|---|
| 1 | `cp $LEZIONI/terraform/01-workflow-provider-state.tf main.tf && grep -n '^resource\|^terraform\|^provider' main.tf` | copia il file di lezione come `main.tf` e mostra le righe che **iniziano** con `terraform`, `provider`, `resource`: il blocco versioni, il provider e le tre risorse. Gli `output` non compaiono, il grep non li cerca |
| 2 | `terraform init` | scarica il provider docker in `.terraform/` e scrive `.terraform.lock.hcl` (versioni bloccate, va in git) |
| 3 | `terraform fmt -check -diff; terraform validate` | `fmt -check` non riscrive il file: se la formattazione non è quella canonica mostra il diff ed esce con errore. Il `;` fa girare `validate` in ogni caso: controllo di sintassi e tipi, senza toccare niente |
| 4 | `terraform plan -out=piano.tfplan` | calcola le differenze fra codice e realtà e le **salva** nel file `piano.tfplan`. Alla prima volta sono tutte `+` (crea) |
| 5 | `terraform apply piano.tfplan` | esegue **esattamente** quel piano, **senza domanda di conferma**: il piano è già stato approvato. Alla fine stampa gli output |
| 6 | `curl -s localhost:8088 \| head -3` | le prime 3 righe della risposta di nginx: il container risponde sulla 8088 |
| 7 | `terraform state list` | gli indirizzi delle risorse nello stato: è ciò che Terraform ricorda di aver creato |
| 8 | `terraform state show docker_container.web \| head -25` | le prime 25 righe degli attributi del container nello stato (l'elenco è più lungo, il `head` lo taglia) |
| 9 | `docker stop lab-web && terraform plan` | **DRIFT**: fermi il container fuori da Terraform. Il plan se ne accorge e propone di **ricrearlo** (`-/+`) |
| 10 | `terraform apply -replace=docker_container.web -auto-approve && curl -s -o /dev/null -w "HTTP %{http_code}\n" localhost:8088` | `-replace` ricrea la risorsa anche quando il plan non lo chiederebbe; qui rimette a posto il drift. Il `curl` stampa solo il codice HTTP |
| 11 | `terraform destroy -auto-approve` | distrugge tutto quello che è nello stato: container e rete. L'immagine resta sul disco (`keep_locally = true`) |

Nessun passo è pensato per fallire. Attenzione al passo 3: `terraform fmt -check -diff; terraform validate`. Con il
`;` il codice di uscita è quello dell'**ultimo** comando, `validate`. Se `fmt -check` trova differenze di
formattazione **non** compare nessun `↳ uscita` in rosso: il segnale è il diff stampato, che ti dice cosa
cambierebbe `terraform fmt`.

### Perché al passo 9 ricrea e non riavvia

Il commento nel file lo dice: un container fermo **perde le porte pubblicate**. Il provider vede che il container
reale non corrisponde più a quello descritto (e `must_run` è `true`), e la strada che propone è distruggerlo e
ricrearlo (`-/+`), non un semplice riavvio.

### Perché `apply` di un piano salvato (passo 5)

Dalla domanda da colloquio del file: il piano rivisto (in una merge request, o dall'approvatore) è **esattamente** ciò
che viene eseguito. Un `apply` diretto **ricalcola** il piano: se nel frattempo è cambiato qualcosa, applichi una cosa
che nessuno ha visto.

---

## 4. Trappole

- **`-auto-approve`** (passi 10 e 11) salta la conferma. Va bene in un lab; su un'infrastruttura vera prima si legge il plan.
- **Lo stato contiene segreti**: `terraform.tfstate` nella cartella di lavoro non va mai in git. Qui non ci sono
  password, ma l'abitudine si prende adesso.
- **`create_before_destroy` non è gratis**: con nome e porta fissi (`lab-web`, `8088`) due container non possono
  esistere insieme, quindi qui fallirebbe.
- **`-/+` su un database**: dal file, «se è un DB: fermati e ragiona». Ricreare vuol dire perdere ciò che c'è dentro.
- **Porta 8088 occupata** da qualcos'altro: l'apply del passo 5 fallisce. Liberala o cambia `external`.

## 5. Domande da colloquio (dal file)

- **Cos'è il drift e come lo gestisci?** È la differenza fra stato reale e codice (una modifica manuale in console).
  `terraform plan` la mostra; `plan -refresh-only` mostra **solo** ciò che è cambiato fuori, e `apply -refresh-only`
  **accetta la realtà** nello stato. In produzione: un plan schedulato in CI che apre un alert se il diff non è vuoto,
  e permessi di console in sola lettura.
- **`-/+` nel plan: perché vuole ricreare la risorsa?** Hai cambiato un attributo "ForceNew" (immutabile per l'API:
  nome di un bucket, AMI di una VM, qui l'immagine del container). Il plan lo dice con `# forces replacement`.
- **Terraform vs OpenTofu?** OpenTofu è il fork open source (MPL) nato dopo il passaggio di Terraform alla licenza BSL
  nel 2023, ora sotto la Linux Foundation. Stessa sintassi HCL, stessi provider; differenze nelle funzioni nuove (per
  esempio la cifratura dello stato nativa in OpenTofu).
- **Perché `apply` di un piano salvato e non `apply` diretto?** Vedi sopra, passo 5.

## 6. Dipendenze e pulizia

- **Prima**: `00-installa.sh` (Terraform installato) e Docker funzionante per il tuo utente (il provider parla con
  `/var/run/docker.sock`).
- **Dopo**: la lezione 03 porta lo stato su un backend remoto con lock; la 10 unisce Terraform e Ansible.
- **Pulizia**: la fa il passo 11 (`destroy`). Restano l'immagine `nginx:1.29-alpine` (voluto) e la cartella
  `~/kubernetesprj/lavoro/iac/01` con `main.tf`, `piano.tfplan`, lo stato ormai vuoto e `.terraform/`. Per toglierla:
  `rm -rf ~/kubernetesprj/lavoro/iac/01`.

## Riepilogo

- **Dichiarativo**: descrivi lo stato, Terraform calcola il diff.
- **init → fmt → validate → plan -out → apply del piano → destroy**.
- Le **dipendenze nascono dai riferimenti** tra risorse (`docker_image.nginx.image_id`, `docker_network.lab.name`).
- Lo **stato** mappa codice ↔ realtà; contiene segreti; mai in git.
- **Drift**: `plan` lo mostra, `-refresh-only` lo accetta, `-replace` ricrea.

## Prova da solo

1. Dopo l'apply, cambia in `main.tf` il tag di `nginx:1.29-alpine` con un altro tag esistente di nginx e lancia
   `terraform plan`: quali risorse cambiano, quale ha `-/+` e su quale riga compare `# forces replacement`?
2. Ferma il container (`docker stop lab-web`) e invece di `-replace` prova `terraform plan -refresh-only`: che cosa
   propone di cambiare **nello stato**, senza toccare Docker?
3. Aggiungi `prevent_destroy = true` dentro il `lifecycle` di `docker_container.web` e lancia `terraform destroy`:
   che cosa succede, e cosa devi fare per riuscire a distruggere?

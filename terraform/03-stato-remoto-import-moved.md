# 03 — Stato remoto, import e moved

Spiegazione di `03-stato-remoto-import-moved.sh` (questa cartella). Lezione sul sito: http://127.0.0.1:3000/terraform/3

## In una frase

Lo script sposta lo **stato** di Terraform dal file locale a un **PostgreSQL** in Docker (backend `pg`, con lock),
**importa** un container Redis creato a mano (`vecchio-redis`) con un blocco `import`, fa vedere il **lock** con due
terminali e infine **rinomina** una risorsa (`cache` → `sessioni`) senza distruggerla, grazie a un blocco `moved`.

## Questo script e la lezione

| File | Che cos'è |
|---|---|
| `~/kubernetesprj/terraform/03-stato-remoto-import-moved.sh` | **questo**: lo script guidato, da lanciare |
| `~/kubernetesprj/lezioni/terraform/03-stato-remoto-import-moved.tf` | il file di lezione, da **leggere**: teoria su backend, lock, import, moved, removed, e la configurazione che lo script copia come `main.tf` |

```bash
cd ~/kubernetesprj
bash terraform/03-stato-remoto-import-moved.sh
```

Per ogni passo: **Invio** esegue · **s** salta · **q** esce (`AUTO=1` tutto di fila, `DA=n` dal passo n). Un errore
stampa `↳ uscita N` in rosso e lo script prosegue. Per il passo del lock ti serve **un secondo terminale**.

## Com'è fatto lo script

```
titolo "03. Stato remoto, import e moved"
cartella iac/03          → ~/kubernetesprj/lavoro/iac/03
passi 1–4                → Postgres per lo stato, PG_CONN_STR, Redis fatto a mano, il suo ID in TF_VAR_…
passi 5–9                → copia, init sul backend pg, apply con import, lo stato dentro Postgres
nota + passo 10          → il lock con un secondo terminale (il plan fallisce apposta)
passi 11–13              → refactor con moved
passo 14                 → pulizia
```

Le due `export` (passi 2 e 4) restano valide per i passi successivi perché `passo` esegue il comando con `eval`
nella shell dello script. Per lo stesso motivo **non saltarle**: senza `PG_CONN_STR` l'`init` non sa dove sia il
backend, senza `TF_VAR_id_vecchio_redis` il plan chiede una variabile obbligatoria che non c'è.

---

## 1. La teoria nell'intestazione

Versione: **Terraform 1.17**, backend **`pg`** (PostgreSQL), provider docker 4.6. Livello 2 — Stato e refactoring.

### Perché uno stato remoto

In team lo stato locale non funziona: due persone con due stati diversi creano doppioni o si distruggono le risorse a
vicenda. Serve un **backend remoto** con tre proprietà:

| Proprietà | Cosa vuol dire |
|---|---|
| **condiviso** | tutti leggono e scrivono lo stesso stato |
| **lock** | un solo plan/apply alla volta; il secondo aspetta o fallisce con "Error acquiring the state lock" |
| **protetto** | cifrato at-rest, versionato, accesso minimo (contiene segreti) |

### Backend tipici

| Backend | Lock | Nota del file |
|---|---|---|
| `s3` | `use_lockfile = true` | lock nativo su S3 da Terraform 1.10; la tabella DynamoDB è **deprecata**. Bucket con versioning |
| `gcs` / `azurerm` | nativo | |
| `pg` | advisory lock di PostgreSQL | perfetto per il lab |
| `remote` / `cloud` | | HCP Terraform / Terraform Enterprise |

**Il blocco `backend` non accetta variabili**: i valori per ambiente si passano con
`terraform init -backend-config=file.hcl` o con variabili d'ambiente, qui `PG_CONN_STR`.

### I comandi LAB dell'intestazione

```bash
docker run -d --name tfstate -e POSTGRES_PASSWORD=lab -p 5433:5432 postgres:18-alpine
export PG_CONN_STR="postgres://postgres:lab@localhost:5433/postgres?sslmode=disable"
docker run -d --name vecchio-redis redis:8-alpine        # creato A MANO, fuori da Terraform
export TF_VAR_id_vecchio_redis=$(docker inspect -f '{{.Id}}' vecchio-redis)
cd ~/iac/03 && terraform init && terraform apply
psql "$PG_CONN_STR" -c 'select name from terraform_remote_state.states'
```

Due differenze col guidato: l'intestazione usa `~/iac/03` e un `psql` installato sul PC; lo script usa
`~/kubernetesprj/lavoro/iac/03` e il `psql` **dentro** il container (`docker exec tfstate psql …`), così non serve
installarlo.

### Riquadro «NEL PROGETTO VERO»

In `~/biodistretto/kubernetes` (branch `kubernetes`; come si usa: il README della cartella) lo stack *app* legge gli
output dello stack *cluster* con **`terraform_remote_state`** (backend local, path relativo):

```bash
cd ~/biodistretto/kubernetes
grep -n -A4 'terraform_remote_state' terraform/app/versions.tf
grep -n 'sensitive' terraform/cluster/outputs.tf
```

Da colloquio: `remote_state` espone **tutti** gli output dell'altro stack, **compresi i sensibili** (lì la chiave
client del cluster). In un team il backend diventa S3/GCS con locking, e chi legge deve avere il permesso.

---

## 2. Il codice HCL, blocco per blocco

### `terraform` con `backend "pg"`

```hcl
terraform {
  required_version = ">= 1.10"
  required_providers {
    docker = { source = "kreuzwerker/docker", version = "~> 4.6" }
  }
  backend "pg" {
    # conn_str da PG_CONN_STR; schema_name di default: terraform_remote_state
  }
}
```

Il blocco è **vuoto apposta**: la stringa di connessione arriva da `PG_CONN_STR` e lo schema, se non lo indichi, è
`terraform_remote_state`. È lo schema che `init` crea e che il passo 8 interroga.

### `docker_image.redis` e `docker_container.cache`

```hcl
resource "docker_image" "redis" {
  name         = "redis:8-alpine"
  keep_locally = true
}

resource "docker_container" "cache" {
  name    = "lab-cache"
  image   = docker_image.redis.image_id
  command = ["redis-server", "--appendonly", "no"]
}
```

`cache` è la risorsa "nuova" che Terraform crea: un container `lab-cache`. Il commento su `command`: **niente stringhe
vuote**, il provider le rifiuta. È questa risorsa che al passo 11 cambia nome in `sessioni`.

### `variable "id_vecchio_redis"` e il blocco `import`

```hcl
variable "id_vecchio_redis" {
  type        = string
  description = "ID COMPLETO del container: docker inspect -f '{{.Id}}' vecchio-redis"
}

import {
  to = docker_container.legacy
  id = var.id_vecchio_redis
}
```

| Pezzo | Perché |
|---|---|
| **import dichiarativo** (Terraform >= 1.5) | porta sotto Terraform una risorsa creata a mano. Il plan mostra "will be imported" e un eventuale diff fra risorsa reale e codice |
| `to` | l'indirizzo che la risorsa avrà nello stato: `docker_container.legacy` |
| `id` | l'**ID completo** del container. Con il **nome** il plan fallisce con "Cannot import non-existent remote object" (provato, dice il file) |
| `id = var.…` | l'id può essere un'espressione nota al plan, come una variabile (Terraform >= 1.6) |
| la variabile | **senza default**: obbligatoria. Il valore arriva da `TF_VAR_id_vecchio_redis` (passo 4) |

Il file cita anche `terraform plan -generate-config-out=generato.tf`, che scrive il codice al posto tuo partendo dalla
risorsa reale (poi va ripulito). Lo script non lo usa.

### `docker_container.legacy` — la risorsa importata

```hcl
resource "docker_container" "legacy" {
  name  = "vecchio-redis"
  image = docker_image.redis.image_id
  lifecycle {
    ignore_changes = [image, command, entrypoint, env, hostname, user, working_dir, log_driver, log_opts, network_mode]
  }
}
```

Il codice descrive il container **com'è già**, almeno nei campi che contano. Gli altri campi Docker li ha decisi da sé
al `docker run` a mano: se non li ignori, il plan vuole **ricreare** il container appena importato. Per questo la lunga
lista in `ignore_changes`.

Il file avverte (provato): il primo plan dopo l'import mostra comunque un **"update in-place"** su `must_run`,
`start`, `wait`, `logs`…: sono impostazioni del provider, non del container Docker, e **non lo toccano**.

### Il blocco `moved` (commentato nel file)

```hcl
# moved {
#   from = docker_container.cache
#   to   = docker_container.sessioni
# }
```

Rinominare una risorsa nel codice, per Terraform, è "distruggi la vecchia, crea la nuova". `moved` dice che è **la
stessa cosa**: lo stato viene aggiornato, la risorsa reale resta. Funziona anche per entrare in un modulo o passare
da `count` a `for_each`:

```hcl
moved { from = docker_container.web[0]  to = docker_container.web["a"] }
moved { from = docker_container.web     to = module.web.docker_container.this }
```

### Il blocco `removed` (commentato, Terraform >= 1.7)

```hcl
# removed {
#   from = docker_container.legacy
#   lifecycle { destroy = false }
# }
```

Sostituisce `terraform state rm`: la risorsa **esce dalla gestione ma resta** in vita. Lo script non lo usa.

### I comandi sullo stato (di emergenza)

Il file li chiama "di emergenza" perché lasciano traccia solo nei log, non in una merge request:

| Comando | Meglio |
|---|---|
| `terraform state list` / `show ADDR` | (sola lettura) |
| `terraform state mv A B` | un blocco `moved` (rivisto in MR) |
| `terraform state rm ADDR` | un blocco `removed` |
| `terraform state pull > backup.tfstate` | da fare **prima** di qualunque intervento |
| `terraform force-unlock LOCK_ID` | solo se sei **sicuro** che nessuno stia lavorando |
| `terraform plan -refresh-only` | cosa è cambiato fuori da Terraform |

---

## 3. I passi dello script

| # | Comando | Cosa vedi / perché |
|---|---|---|
| 1 | `docker ps -a --format "{{.Names}}" \| grep -qx tfstate \|\| docker run -d --name tfstate -e POSTGRES_PASSWORD=lab -p 5433:5432 postgres:18-alpine; sleep 5` | avvia il PostgreSQL che farà da backend (in azienda: S3 + lock, GCS, Terraform Cloud…), **solo se** non esiste già un container `tfstate` (`grep -qx` = riga esatta, in silenzio). Porta **5433** sull'host. `sleep 5` gli dà il tempo di partire |
| 2 | `export PG_CONN_STR="postgres://postgres:lab@localhost:5433/postgres?sslmode=disable"; echo $PG_CONN_STR` | il backend `pg` legge la connessione da questa variabile, perché il blocco `backend` non accetta variabili Terraform |
| 3 | `docker ps -a … \| grep -qx vecchio-redis \|\| docker run -d --name vecchio-redis redis:8-alpine` | un Redis creato **a mano**, fuori da Terraform: è quello da importare |
| 4 | `export TF_VAR_id_vecchio_redis=$(docker inspect -f '{{.Id}}' vecchio-redis); echo …` | l'ID completo del container, passato a Terraform come `var.id_vecchio_redis` (prefisso `TF_VAR_`) |
| 5 | `cp $LEZIONI/terraform/03-stato-remoto-import-moved.tf main.tf && grep -n '^terraform\|backend\|^import\|^resource\|moved' main.tf` | copia il file; il grep mostra il blocco `terraform`, il `backend`, l'`import`, le risorse e le righe che contengono `moved` (anche quelle nei commenti) |
| 6 | `terraform init` | configura il backend `pg`: crea lo schema `terraform_remote_state` |
| 7 | `terraform apply -auto-approve` | crea `cache` (`lab-cache`) e **importa** `vecchio-redis` nello stato ("will be imported") |
| 8 | `ls terraform.tfstate 2>/dev/null \|\| echo 'nessun terraform.tfstate locale'; docker exec tfstate psql -U postgres -c 'select name from terraform_remote_state.states'` | lo stato **non è più un file locale**: nella cartella non c'è `terraform.tfstate`, ed è una riga nella tabella `states` di PostgreSQL |
| 9 | `terraform state list; terraform state show docker_container.legacy \| head -15` | la risorsa importata ora è gestita da Terraform (le prime 15 righe dei suoi attributi) |
| — | **nota LOCK** | apri un **secondo terminale** e lancia il comando che la nota stampa (sotto); lascialo fermo alla domanda `Enter a value`, poi torna qui |
| 10 | `terraform plan -lock-timeout=0s` | **fallisce apposta** se l'altro apply è aperto: il lock blocca questo plan ("Error acquiring the state lock"). `-lock-timeout=0s` = non aspettare. Se non hai aperto l'altro terminale il plan passa, e va bene lo stesso |
| 11 | `sed -i -e 's/resource "docker_container" "cache"/resource "docker_container" "sessioni"/' -e '/^# moved {/,/^# }/s/^# //' main.tf && grep -n -A3 '^moved' main.tf` | **refactor**: rinomina la risorsa `cache` → `sessioni` e toglie il `# ` dalle righe del blocco `moved` già scritto. Il grep mostra il blocco ora attivo |
| 12 | `terraform plan` | il plan dice **"has moved to"**, 0 to destroy. Senza `moved` distruggerebbe e ricreerebbe il container |
| 13 | `terraform apply -auto-approve && terraform state list` | applica il refactor: nello stato l'indirizzo ora è `docker_container.sessioni` |
| 14 | `terraform destroy -auto-approve; docker rm -f tfstate vecchio-redis` | pulizia: destroy di tutto ciò che è nello stato, poi via il Postgres dello stato (e `vecchio-redis`, se c'è ancora) |

A schermo i passi sono numerati `[01]`…`[14]`; la nota non ha numero e compare fra il `[09]` e il `[10]`.

### La nota del lock, per intero

```
LOCK: apri un SECONDO terminale e lancia:
   cd $LAVORO/iac/03 && export PG_CONN_STR="…" TF_VAR_id_vecchio_redis=$(docker inspect -f '{{.Id}}' vecchio-redis) && terraform apply
lascialo fermo alla domanda 'Enter a value' (tiene il lock), poi torna qui.
```

Il secondo terminale non ha le variabili dello script: per questo il comando le riesporta. `$LAVORO` e il valore di
`PG_CONN_STR` vengono **sostituiti** quando la nota viene stampata, quindi copi un comando già completo. Il
`$(docker inspect …)` invece resta scritto così e viene calcolato nel secondo terminale.

Un `apply` senza `-auto-approve` si ferma alla domanda di conferma **tenendo il lock** per tutto il tempo: è questo
che fa fallire il plan del primo terminale.

### Prima del refactor: libera il lock

Lo script non lo dice, ma serve: finché l'apply del secondo terminale è fermo alla domanda, **il lock resta preso** e
anche i plan/apply successivi del primo terminale falliscono. Dopo aver visto l'errore, nel secondo terminale rispondi
qualcosa che **non** sia `yes` (o premi Ctrl+C): l'apply si annulla e il lock viene rilasciato.

---

## 4. Trappole

- **Non saltare i passi 2 e 4**, e non ripartire con `DA=n` oltre il 2: con `DA` i passi prima di n non girano, e le
  `export` con loro.
- **Il blocco `backend` non accetta variabili** (`var.…`): per questo `PG_CONN_STR`.
- **Import col nome invece che con l'ID**: "Cannot import non-existent remote object".
- **Dopo un import, `ignore_changes`**: senza, il plan vuole ricreare il container appena adottato.
- **Rinominare senza `moved`** = distruggere e ricreare. Su un database vuol dire perdere i dati.
- **`force-unlock`** solo se sei sicuro che nessuno stia lavorando; prima `state pull` come backup.
- **Il destroy del passo 14 distrugge anche `vecchio-redis`**: dopo l'import è una risorsa di Terraform come le altre.
  Se volevi solo lasciarla andare, il blocco giusto era `removed` con `destroy = false`.
- **Lo stato resta in un volume anonimo**: il runner avvia `tfstate` senza `-v`, ma l'immagine `postgres:18-alpine`
  dichiara il volume `/var/lib/postgresql` (misurato con `docker image inspect`). Docker crea quindi un volume
  anonimo, e `docker rm -f tfstate` **senza `-v`** lo lascia lì orfano, con dentro lo stato. Per toglierlo:
  `docker volume ls -f dangling=true` e poi `docker volume rm <id>`. Oppure, alla pulizia, `docker rm -f -v tfstate`.

## 5. Domande da colloquio (dal file)

- **Come organizzi lo stato per più ambienti e team?** Stati **piccoli e separati** per ambiente e per dominio (rete,
  dati, app): un errore ha un raggio limitato e i plan sono veloci. Gli output degli altri si leggono con
  `terraform_remote_state` o, meglio, con data source sulle risorse vere. **Workspaces** solo per copie identiche
  (es. ambienti effimeri per MR), non per dev/prod che divergono.
- **Il lock è rimasto appeso dopo una pipeline cancellata.** Verifica che nessun job stia girando, poi
  `terraform force-unlock` con l'ID dell'errore. Prima: `state pull` come backup.
- **Hai cancellato per sbaglio una risorsa dallo stato.** Terraform ora vuole crearla di nuovo (e fallisce per nome già
  in uso). Si reimporta con un blocco `import`. Con un backend versionato si può anche ripristinare la versione
  precedente dello stato.
- **Data source o `terraform_remote_state`?** Il data source interroga l'API del provider (la realtà) e accoppia solo
  per nome/tag; `remote_state` legge lo stato di un altro progetto e richiede l'accesso a **tutto** quello stato,
  segreti compresi.

## 6. Dipendenze e pulizia

- **Prima**: lezioni 01 e 02 (workflow, variabili, `TF_VAR_` come fonte di valori). Docker funzionante.
- **Dopo**: la lezione 04 usa i moduli; lì torna utile `moved` per spostare risorse dentro un modulo.
- **Pulizia**: il passo 14. Restano le immagini `redis:8-alpine` (`keep_locally`) e
  `postgres:18-alpine`, la cartella `~/kubernetesprj/lavoro/iac/03` e il **volume anonimo** del Postgres (vedi
  trappole).

## Riepilogo

- Backend remoto: **condiviso, con lock, cifrato e versionato**.
- `s3` + `use_lockfile` (niente più DynamoDB); `pg` per il lab, configurato da `PG_CONN_STR`.
- **`import { }`** per adottare risorse esistenti (con l'ID completo); `-generate-config-out` per farsi scrivere il codice.
- **`moved { }`** per rinominare/spostare, **`removed { }`** per lasciar andare senza distruggere.
- Stati piccoli per ambiente e dominio; **`state pull`** prima di toccare.

## Prova da solo

1. Prima del passo 14, lancia `terraform state pull > backup.tfstate` e apri il file: trovi l'ID di `vecchio-redis`?
   Confrontalo con `docker inspect -f '{{.Id}}' vecchio-redis`.
2. Scommenta il blocco `removed` (e togli il blocco `import` e la risorsa `legacy`), poi `terraform plan` e
   `terraform apply`: `vecchio-redis` esiste ancora in `docker ps`? È ancora in `terraform state list`?
3. Rifai l'import mettendo nel blocco `import` il **nome** `vecchio-redis` al posto dell'ID: con quale errore
   fallisce il plan?

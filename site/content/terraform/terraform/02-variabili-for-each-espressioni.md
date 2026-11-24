# 02 — Variabili, for_each ed espressioni

Spiegazione di `02-variabili-for-each-espressioni.sh` (questa cartella). Lezione sul sito: http://127.0.0.1:3000/terraform/2

## In una frase

Lo script mette alla prova il **linguaggio HCL**: variabili tipizzate con `validation` e `sensitive`, `locals` con
espressioni `for` e condizionali, una risorsa ripetuta con **`for_each`** (un container `traefik/whoami:v1.12` per
servizio: `api`, `web`, `admin`), una opzionale con **`count`** (il container `debug`), un blocco **`dynamic`**, gli
output e `terraform console`. Poi passa da `dev` a `prod` e toglie un servizio, per far vedere **perché for_each
e non count**.

## Questo script e la lezione

| File | Che cos'è |
|---|---|
| `~/kubernetesprj/terraform/02-variabili-for-each-espressioni.sh` | **questo**: lo script guidato, da lanciare |
| `~/kubernetesprj/lezioni/terraform/02-variabili-for-each-espressioni.tf` | il file di lezione, da **leggere**: teoria nei commenti e la configurazione che lo script copia come `main.tf` |

```bash
cd ~/kubernetesprj
bash terraform/02-variabili-for-each-espressioni.sh
```

Per ogni passo: **Invio** esegue · **s** salta · **q** esce (`AUTO=1` tutto di fila, `DA=n` dal passo n). Un errore
stampa `↳ uscita N` in rosso e lo script prosegue.

## Com'è fatto lo script

```
titolo "02. Variabili, for_each ed espressioni"
cartella iac/02          → ~/kubernetesprj/lavoro/iac/02
13 × passo               → copia, init, due plan (uno fallisce apposta), apply, output ×3, console,
                           passaggio a prod, tolgo admin, plan, destroy
```

Servono `jq` (passo 6) e `sed -i` nella forma GNU (passo 11): sull'Ubuntu del lab ci sono entrambi.

---

## 1. La teoria nell'intestazione

Versione: **Terraform 1.17**, provider **kreuzwerker/docker 4.6**. Livello 1 — Linguaggio HCL.

### Input, calcoli, output

| Blocco | Ruolo |
|---|---|
| `variable` | l'**interfaccia**: tipo, default, validazione, sensitive |
| `locals` | valori **calcolati una volta** e riusati (DRY) |
| `output` | ciò che esce: per l'utente, per altri moduli, per la CI |

### Precedenza dei valori di una variabile (l'ultima vince)

```
default < TF_VAR_nome (ambiente) < terraform.tfvars < *.auto.tfvars < -var-file=… < -var nome=…
```

Lo script usa solo i due estremi: il `default` e `-var 'ambiente=…'`.

### `count` o `for_each`? (domanda quasi certa)

| | Indice | Cosa succede se togli "b" da `["a","b","c"]` |
|---|---|---|
| `count` | per **posizione**: `web[0]`, `web[1]`, `web[2]` | "c" scala da `[2]` a `[1]`: Terraform **distrugge e ricrea** "c" anche se non è cambiato niente |
| `for_each` | per **chiave**: `web["a"]`, `web["c"]` | tocca **solo** "b" |

Regola: **`for_each` per tutto ciò che ha un'identità**; `count` solo per "0 o 1" (risorsa opzionale) o copie davvero
anonime. Il file applica la regola: `for_each` per i servizi, `count` per `debug`.

### I comandi LAB dell'intestazione

```bash
cp 02-variabili-for-each-espressioni.tf ~/iac/02/main.tf && cd ~/iac/02
terraform init
terraform plan -var 'ambiente=prod'                      # 3 servizi
terraform plan -var 'ambiente=collaudo'                  # errore di validazione
terraform apply -auto-approve
terraform output -json servizi | jq
terraform console      # local.porte · { for k, v in var.servizi : k => v.porta }
terraform apply -auto-approve -var 'ambiente=prod'       # admin esiste solo in prod
```

Poi: togli `admin` da `var.servizi` e rifai il plan con `-var 'ambiente=prod'`: viene distrutto solo `admin` (in dev
non c'era, quindi il plan non cambierebbe niente). Lo script guidato fa la stessa cosa in `~/kubernetesprj/lavoro/iac/02`.

### Riquadro «NEL PROGETTO VERO»

In `~/biodistretto/kubernetes` (branch `kubernetes`; come si usa: il README della cartella) c'è un `for_each` su una
mappa costruita con un'espressione `for`. La chiave è `"Kind/nome"`, quindi nello stato c'è
`kubernetes_manifest.app["Deployment/nginx"]`.

```bash
cd ~/biodistretto/kubernetes
grep -n -F '"${m.kind}/${m.metadata.name}"' terraform/app/workload.tf
grep -n 'checksum_backend' terraform/app/workload.tf
```

**Trappola, presa davvero**: le chiavi di `for_each` devono essere **note al plan**. Un checksum calcolato sui segreti
`random` rendeva ignoto l'intero template ("known only after apply"). Rimedio: checksum solo su config e variabili, e
namespace preso da `var.namespace` invece che dalla risorsa. `nonsensitive()` serve perché `var.app_key` è
sensitive, e un valore sensitive non può stare in chiaro in un'annotazione; l'hash invece sì.

---

## 2. Il codice HCL, blocco per blocco

### `terraform` e `provider`

Stessi vincoli della lezione 01 (`required_version = ">= 1.10"`, `kreuzwerker/docker ~> 4.6`), scritti su una riga.
`provider "docker" {}` è **vuoto**: senza `host` il provider usa il Docker locale di default.

### `variable "ambiente"`

```hcl
variable "ambiente" {
  type        = string
  description = "dev | prod"
  default     = "dev"
  validation {
    condition     = contains(["dev", "prod"], var.ambiente)
    error_message = "ambiente deve essere dev o prod."
  }
}
```

La `validation` gira **prima** di calcolare il piano: un valore non ammesso ferma tutto con `error_message`. È ciò che
fa fallire il passo 4.

### `variable "servizi"` — un tipo strutturato

```hcl
type = map(object({
  porta     = number
  repliche  = optional(number, 1)
  variabili = optional(map(string), {})
}))
```

| Campo | Tipo | Nota |
|---|---|---|
| chiave della mappa | stringa | il **nome** del servizio: diventa la chiave di `for_each` |
| `porta` | `number` | obbligatorio |
| `repliche` | `optional(number, 1)` | facoltativo con default 1 (`optional` con default: Terraform >= 1.3). Nel file non viene usato da nessuna risorsa |
| `variabili` | `optional(map(string), {})` | facoltativo, default mappa vuota |

Il `default` definisce tre servizi:

| Servizio | `porta` | `variabili` |
|---|---|---|
| `api` | 8101 | `LOG_LEVEL = "info"` |
| `web` | 8102 | — |
| `admin` | 8103 | — |

La `validation` usa un'espressione `for` dentro `alltrue`: **tutte** le porte devono stare fra 1024 e 65535.

### `variable "token_api"`

`default = "solo-per-il-lab"`, `sensitive = true`: nascosto in plan e output, ma **nello stato resta in chiaro**
(passi 7 e 8).

### `locals`

| Local | Valore | Cosa fa |
|---|---|---|
| `prefisso` | `"lab-${var.ambiente}"` | `lab-dev` o `lab-prod`: entra nel nome dei container |
| `etichette_comuni` | `{ ambiente = var.ambiente, gestito-da = "terraform" }` | etichette uguali per tutti |
| `servizi_attivi` | `{ for nome, s in var.servizi : nome => s if var.ambiente == "prod" \|\| nome != "admin" }` | espressione `for` **con filtro**: in dev `admin` sparisce |
| `porte` | `[for s in values(local.servizi_attivi) : s.porta]` | la lista delle porte dei servizi attivi |

### `docker_image.whoami`

`traefik/whoami:v1.12`, `keep_locally = true` (destroy non cancella l'immagine).

### `docker_container.servizio` — il `for_each`

| Campo | Valore | Perché |
|---|---|---|
| `for_each` | `local.servizi_attivi` | una istanza per chiave: `each.key` = nome, `each.value` = l'oggetto |
| `name` | `"${local.prefisso}-${each.key}"` | per esempio `lab-dev-api` |
| `image` | `docker_image.whoami.image_id` | dipendenza implicita dall'immagine |
| `command` | `["--name", each.key]` | whoami ascolta sulla 80 e con `--name` scrive il nome nella risposta |
| `ports` | `internal = 80`, `external = each.value.porta` | 8101, 8102, 8103 |
| `env` | `concat([for k, v in each.value.variabili : "${k}=${v}"], each.key == "api" ? ["TOKEN=${var.token_api}"] : [])` | le variabili del servizio in forma `CHIAVE=valore`, più `TOKEN` **solo** per `api` (condizionale `? :`) |
| `dynamic "labels"` | `for_each = merge(local.etichette_comuni, { servizio = each.key })` | genera **un blocco `labels` per ogni coppia** della mappa: `ambiente`, `gestito-da`, `servizio` |

`dynamic` serve quando un **blocco annidato** (qui `labels`) va ripetuto da una collezione. Dentro `content`,
`labels.key` e `labels.value` sono la coppia corrente (l'iteratore prende il nome del blocco).

### `docker_container.debug` — il `count`

```hcl
count = var.ambiente == "dev" ? 1 : 0
```

Risorsa **opzionale**: esiste solo in dev (`lab-dev-debug`), senza porte pubblicate.

### Gli output

| Output | Valore | Nota |
|---|---|---|
| `servizi` | `{ for nome, c in docker_container.servizio : nome => "http://localhost:${c.ports[0].external}" }` | una mappa nome → URL |
| `debug_attivo` | `one(docker_container.debug[*].name) != null` | `[*]` (splat) dà la lista dei nomi; `one()` è `null` se la lista è vuota, l'elemento se ce n'è uno |
| `token` | `var.token_api`, `sensitive = true` | senza `sensitive` l'output fallisce: "Output refers to sensitive values" |

### Funzioni da avere in mano (dal file)

`merge`, `concat`, `flatten`, `lookup(map, k, default)`, `try(expr, fallback)`, `coalesce`, `one`, `toset`,
`keys`/`values`, `zipmap`, `cidrsubnet("10.0.0.0/16", 8, 1)`, `templatefile("cloud-init.tftpl", { … })`,
`jsonencode`/`yamlencode`, `can(regex(...))` dentro una validation.

---

## 3. I passi dello script

| # | Comando | Cosa vedi / perché |
|---|---|---|
| 1 | `cp $LEZIONI/terraform/02-variabili-for-each-espressioni.tf main.tf && grep -n '^variable\|^locals\|^resource\|^output' main.tf` | copia il file e mostra l'elenco dei blocchi: 3 variable, locals, 3 resource, 3 output |
| 2 | `terraform init` | scarica il provider docker |
| 3 | `terraform plan -var 'ambiente=prod'` | in prod il filtro lascia passare tutti: **tre** container `servizio` (`api`, `web`, `admin`) e `debug` a 0 copie |
| 4 | `terraform plan -var 'ambiente=collaudo'` | **fallisce apposta**: `collaudo` non è fra i valori ammessi, la validation dà «Invalid value for variable» e il plan si ferma (lo script dice uscita 1). Non c'è niente da applicare |
| 5 | `terraform apply -auto-approve` | apply con i **default** (`dev`): `lab-dev-api` (8101), `lab-dev-web` (8102), `lab-dev-debug`. Niente `admin` |
| 6 | `terraform output -json servizi \| jq` | l'output `servizi` in JSON, comodo per gli script |
| 7 | `terraform output` | tutti gli output: `token` compare come `<sensitive>` |
| 8 | `terraform output -raw token; echo` | `-raw` lo stampa in chiaro (`solo-per-il-lab`): e **nello stato** è in chiaro. Lo stato è un segreto. L'`echo` va a capo, perché `-raw` non lo fa |
| 9 | `echo 'local.porte' \| terraform console; echo '{ for k, v in var.servizi : k => v.porta }' \| terraform console` | `console` valuta espressioni con i valori veri: `local.porte` sono solo le porte attive in dev (api e web); il `for` su `var.servizi` le ha tutte e tre, admin compreso |
| 10 | `terraform apply -auto-approve -var 'ambiente=prod' && terraform state list` | passaggio a **prod**: nasce `admin`, `count` porta `debug` a 0 (distrutto). `api` e `web` vengono **ricreati**: il nome contiene `lab-<ambiente>` e il nome di un container non si cambia sul posto. `state list` mostra gli indirizzi per chiave, `docker_container.servizio["api"]` ecc. |
| 11 | `sed -i '/admin = { porta = 8103 }/d' main.tf && grep -n 'porta = 81' main.tf` | toglie la riga di `admin` dal default di `var.servizi`; il grep mostra che restano `api` e `web` |
| 12 | `terraform plan -var 'ambiente=prod'` | il plan distrugge **solo** `admin`. Con `count` invece di `for_each` gli indici scalerebbero e cambierebbero anche gli altri |
| 13 | `terraform destroy -auto-approve -var 'ambiente=prod'` | pulizia: distrugge tutto ciò che è nello stato |

Il passo 12 è solo un **plan**: `admin` esiste ancora quando arriva il passo 13, che lo distrugge insieme agli altri.

### Perché al passo 10 api e web vengono ricreati

Non è colpa di `for_each`: le **chiavi** (`api`, `web`) non cambiano, ma cambia il **nome** del container
(`lab-dev-api` → `lab-prod-api`), che Docker non permette di modificare sul posto. Il plan lo mostra con `-/+`.
È la differenza fra **identità per Terraform** (la chiave) e **attributo immutabile** (il nome).

---

## 4. Trappole

- **Le chiavi di `for_each` devono essere note al plan**: non un ID generato da un'altra risorsa
  («Invalid for_each argument»). È la trappola del progetto vero.
- **`for_each` accetta solo mappe o set di stringhe**: una lista di oggetti va trasformata in mappa
  (`{ for o in var.lista : o.nome => o }`).
- **`sensitive` non cifra niente**: nasconde a video, ma `-raw` lo stampa e lo stato lo contiene in chiaro.
- **Un attributo nel nome**: mettere l'ambiente nel nome del container (`lab-${var.ambiente}`) fa ricreare tutto
  al cambio di ambiente.
- **`sed -i` modifica `main.tf`** della cartella di lavoro: se rilanci lo script, il passo 1 lo ricopia intero.

## 5. Domande da colloquio (dal file)

- **Come trasformi una lista di oggetti in una mappa per `for_each`?** `{ for o in var.lista : o.nome => o }`.
  `for_each` accetta solo mappe o set di stringhe, e le chiavi devono essere note al plan.
- **`sensitive` protegge il segreto?** Solo dalla stampa in plan, output e log. Nello stato è in chiaro: il backend va
  cifrato e con accesso ristretto, oppure il segreto non passa da Terraform (lo legge l'app da un secret manager). Da
  Terraform 1.10 esistono anche le risorse **ephemeral** e gli argomenti **write-only**, che non finiscono nello stato.
- **count o for_each?** Vedi la tabella della teoria.

## 6. Dipendenze e pulizia

- **Prima**: lezione 01 (il workflow), Docker funzionante, `jq` installato.
- **Pulizia**: il passo 13. Resta l'immagine `traefik/whoami:v1.12` (`keep_locally`) e la cartella
  `~/kubernetesprj/lavoro/iac/02`. Attenzione: il destroy va fatto con lo stesso `-var 'ambiente=prod'` dell'ultimo
  apply, come fa lo script.

## Riepilogo

- `variable` (tipo, `optional`, `validation`, `sensitive`) · `locals` · `output`.
- **`for_each` per chiave, `count` solo per 0/1**: niente ricreazioni a catena.
- Espressioni **`for`** per filtrare e trasformare; **`dynamic`** per i blocchi ripetuti.
- **`sensitive`** nasconde a video, non nello stato.
- **`terraform console`** per provare le espressioni.

## Prova da solo

1. Lancia `terraform plan -var 'servizi={ api = { porta = 80 } }'`: quale validation scatta, e con quale messaggio?
2. Con lo stato in dev, in `terraform console` prova `local.servizi_attivi` e `keys(local.servizi_attivi)`, poi
   ripeti con `terraform console -var 'ambiente=prod'`: cosa cambia?
3. Riscrivi a mano `docker_container.servizio` con `count = length(local.porte)` e i nomi presi da una lista; poi
   togli il primo servizio e guarda il plan: quanti container vuole ricreare?

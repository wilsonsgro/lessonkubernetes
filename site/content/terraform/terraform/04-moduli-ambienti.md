# 04 — Moduli e ambienti

Spiegazione di `04-moduli-ambienti.sh` (questa cartella). Lezione sul sito: http://127.0.0.1:3000/terraform/4

## In una frase

Lo script fa scrivere al file di lezione la **struttura di un repo Terraform vero**: un **modulo** riusabile
`modules/servizio` (rete + N container `traefik/whoami:v1.12`) e **due ambienti**, `envs/dev` e `envs/prod`, che lo
chiamano con valori diversi (1 replica sulla porta 8201, 3 repliche dalla 8301). Applica dev, guarda output e
indirizzi nello stato, fa solo il **plan** di prod (stato separato) e distrugge dev.

## Questo script e la lezione

| File | Che cos'è |
|---|---|
| `~/kubernetesprj/terraform/04-moduli-ambienti.sh` | **questo**: lo script guidato, da lanciare |
| `~/kubernetesprj/lezioni/terraform/04-moduli-ambienti.sh` | il file di lezione, da **leggere**. Questa volta è uno **script bash**: con l'argomento `crea` scrive i file `.tf` del modulo e dei due ambienti. La teoria è nei commenti in cima e in fondo |

Attenzione ai due file con lo stesso nome: quello in `terraform/` è il guidato, quello in `lezioni/terraform/` è il
generatore che il guidato lancia al passo 1.

```bash
cd ~/kubernetesprj
bash terraform/04-moduli-ambienti.sh
```

Per ogni passo: **Invio** esegue · **s** salta · **q** esce (`AUTO=1` tutto di fila, `DA=n` dal passo n). Un errore
stampa `↳ uscita N` in rosso e lo script prosegue.

## Com'è fatto lo script

```
titolo "04. Moduli e ambienti"
cartella iac/04          → ~/kubernetesprj/lavoro/iac/04
8 × passo                → genera i file, li elenca, legge dev, init+apply dev, output, state list,
                           init+plan prod, destroy dev
```

Tre passi fanno `cd` (4, 7, 8): come le `export` della lezione 03, il `cd` dentro `passo` resta valido per i passi
dopo, perché il comando gira con `eval` nella shell dello script. Se salti il passo 4, i `cd ../prod` e `cd ../dev`
partono dalla cartella sbagliata e falliscono.

---

## 1. La teoria nell'intestazione

Versione: **Terraform 1.17**, provider **kreuzwerker/docker 4.6**. Livello 2 — Stato e refactoring.

### Modulo e root module

Un **modulo** è una cartella di `.tf` con input (`variable`) e output. Il **root module** è quello da cui lanci
`terraform`; gli altri si chiamano con `module "nome" { source = … }`.

```
iac/
├── modules/
│   └── servizio/          un servizio: rete + N container
│       ├── main.tf
│       ├── variables.tf
│       ├── outputs.tf
│       └── versions.tf    required_providers: il MODULO non configura il provider, lo riceve dal root
└── envs/
    ├── dev/main.tf        root: backend dev, modulo con valori dev
    └── prod/main.tf       root: backend prod, modulo con valori prod
```

(L'intestazione descrive il modulo come «rete + N container + healthcheck», ma il codice generato non ha un
healthcheck: ci sono la rete, l'immagine e i container.)

### Source di un modulo

| `source` | Tipo |
|---|---|
| `"../../modules/servizio"` | locale (monorepo): è quello usato qui |
| `"git::https://gitlab.com/org/tf-mod.git//servizio?ref=v1.4.0"` | git + tag (`//servizio` = sottocartella del repo) |
| `"app.terraform.io/org/servizio/docker"`, `version = "~> 1.4"` | registry |

In produzione: **sempre una versione fissa** (tag o `version`), **mai un branch**.

### I comandi LAB dell'intestazione

```bash
bash 04-moduli-ambienti.sh crea
cd iac/envs/dev && terraform init && terraform apply -auto-approve
terraform output                         # output del root ← output del modulo
cd ../prod && terraform init && terraform plan    # stesso modulo, 3 repliche
terraform state list                     # module.negozio.docker_container.replica["0"]…
```

Nell'intestazione `terraform state list` viene **dopo** il `cd ../prod`, dove però si è fatto solo un plan: lo stato di
prod è vuoto. Il guidato lo lancia (giustamente) in **dev**, al passo 6.

### Riquadro «NEL PROGETTO VERO»

In `~/biodistretto/kubernetes` (branch `kubernetes`; come si usa: il README della cartella) il progetto usa **due root
module** e non moduli dentro un'unica root. Il motivo: il provider `kubernetes` si configura con gli **output del
cluster**, e `kubernetes_manifest` vuole il cluster raggiungibile **già al plan**. Nella stessa root il primo plan da
zero fallirebbe.

```bash
cd ~/biodistretto/kubernetes
grep -n -A6 'provider "kubernetes"' terraform/app/versions.tf
```

Esercizio del file: un secondo ambiente lì è un altro dominio e un altro namespace (variabili `dominio` e
`namespace`). Prova `terraform -chdir=terraform/app plan -var dominio=prova.lab` e conta cosa verrebbe sostituito:
certificati, ConfigMap e Pod.

---

## 2. Il generatore: `04-moduli-ambienti.sh crea`

```bash
set -euo pipefail
R=./iac
crea() { … }
case "${1:-}" in
  crea) crea ;;
  *) echo "uso: $0 crea" ;;
esac
```

- `set -euo pipefail`: si ferma al primo errore, a una variabile non definita, o a un errore dentro una pipe.
- `R=./iac` è **relativo alla cartella corrente**: lanciato dal guidato, la struttura finisce in
  `~/kubernetesprj/lavoro/iac/04/iac/`.
- Senza argomento `crea` stampa solo l'uso e non scrive niente.
- I file vengono scritti con `cat > … <<'EOF'`: rilanciarlo li **sovrascrive** uguali.
- Alla fine stampa `struttura scritta in ./iac`.

### `modules/servizio/versions.tf`

```hcl
terraform {
  required_version = ">= 1.10"
  required_providers {
    docker = { source = "kreuzwerker/docker", version = ">= 4.6, < 5.0" }
  }
}
```

Il modulo **dichiara** di quale provider ha bisogno, con un **range** (`>= 4.6, < 5.0`), ma **non** ha un blocco
`provider`: lo riceve dal root. Un range largo nel modulo lascia al root la scelta della versione precisa (i root qui
usano `~> 4.6`, che vuol dire lo stesso intervallo).

### `modules/servizio/variables.tf` — l'interfaccia

| Variabile | Tipo | Default | Validation |
|---|---|---|---|
| `nome` | string | — (obbligatoria) | `can(regex("^[a-z][a-z0-9-]{2,20}$", var.nome))`: minuscole, numeri e trattini, 3-21 caratteri, inizia con una lettera |
| `ambiente` | string | — (obbligatoria) | — |
| `immagine` | string | `traefik/whoami:v1.12` | — |
| `repliche` | number | `1` | fra 1 e 5 |
| `porta_base` | number | — (obbligatoria) | descrizione: «La replica i ascolta su porta_base + i» |

`can(regex(…))` è il trucco citato nella lezione 02: `regex` dà errore se non trova corrispondenza, `can` trasforma
l'errore in `false`.

### `modules/servizio/main.tf` — le risorse

```hcl
locals {
  prefisso = "${var.ambiente}-${var.nome}"
  repliche = { for i in range(var.repliche) : tostring(i) => var.porta_base + i }
}
```

`local.repliche` trasforma un numero in una **mappa** `"0" => porta_base`, `"1" => porta_base+1`, …: chiavi
**stabili** per `for_each` (lezione 02). Con 3 repliche dalla 8301: `{"0"=8301, "1"=8302, "2"=8303}`.

| Risorsa | Campi | Risultato in dev |
|---|---|---|
| `docker_network.this` | `name = "${local.prefisso}-net"` | `dev-negozio-net` |
| `docker_image.this` | `name = var.immagine`, `keep_locally = true` | `traefik/whoami:v1.12`, non cancellata dal destroy |
| `docker_container.replica` | `for_each = local.repliche` | un container per chiave |

Il container, campo per campo:

| Campo | Valore | Perché |
|---|---|---|
| `name` | `"${local.prefisso}-${each.key}"` | `dev-negozio-0` |
| `image` | `docker_image.this.image_id` | dipendenza implicita |
| `command` | `["--name", "${local.prefisso}-${each.key}"]` | whoami scrive il nome nella risposta |
| `ports` | `internal = 80`, `external = each.value` | 8201 in dev; 8301, 8302, 8303 in prod |
| `networks_advanced` | `name = docker_network.this.name`, `aliases = [var.nome]` | sulla rete del servizio, raggiungibile col nome `negozio` dagli altri container della stessa rete |
| `labels` | `ambiente = var.ambiente` | l'ambiente leggibile da `docker inspect` |

Il nome `this` per le risorse uniche di un modulo è una convenzione: dentro un modulo che fa una cosa sola, il nome
locale non aggiunge informazione.

### `modules/servizio/outputs.tf`

| Output | Valore |
|---|---|
| `url` | `[for k, c in docker_container.replica : "http://localhost:${c.ports[0].external}"]`: un URL per replica |
| `rete` | `docker_network.this.name` |

### `envs/dev/main.tf` e `envs/prod/main.tf` — i root module

Il ciclo `for amb in dev prod` scrive lo **stesso** file con valori diversi:

| Ambiente | `repliche` | `porta` (→ `porta_base`) |
|---|---|---|
| dev | 1 | 8201 |
| prod | 3 | 8301 |

Questa volta il heredoc è `<<EOF` **senza virgolette**: bash sostituisce `$amb`, `$repliche` e `$porta` prima di
scrivere. Il file risultante per dev:

```hcl
terraform {
  required_version = ">= 1.10"
  required_providers {
    docker = { source = "kreuzwerker/docker", version = "~> 4.6" }
  }
  # in un repo vero: backend separato per ambiente
  # backend "s3" { bucket = "tfstate-dev" key = "negozio/terraform.tfstate" use_lockfile = true }
}

provider "docker" {}

module "negozio" {
  source = "../../modules/servizio"

  nome       = "negozio"
  ambiente   = "dev"
  repliche   = 1
  porta_base = 8201
}

output "url" {
  value = module.negozio.url
}
```

- Il **root** configura il provider (`provider "docker" {}`) e, in un repo vero, il **backend**: uno per ambiente (qui
  è un commento; lo stato resta un file locale in ogni cartella, quindi dev e prod hanno **stati separati**).
- `module "negozio"` passa gli input al modulo; `source` è il percorso locale.
- `output "url"` **rilancia** l'output del modulo: gli output di un modulo non si vedono dal root se il root non li
  riespone. `rete` infatti non è riesposto e `terraform output` non lo mostra.

---

## 3. I passi dello script

| # | Comando | Cosa vedi / perché |
|---|---|---|
| 1 | `bash $LEZIONI/terraform/04-moduli-ambienti.sh crea` | il generatore scrive `modules/servizio` + `envs/dev` + `envs/prod` sotto `./iac` e stampa `struttura scritta in ./iac` |
| 2 | `find iac -name "*.tf" \| sort` | i sei file: i quattro del modulo (`main`, `outputs`, `variables`, `versions`) e i due `main.tf` degli ambienti. Il modulo ha input (`variables.tf`), risorse (`main.tf`), output (`outputs.tf`); ogni ambiente è un root module |
| 3 | `cat iac/envs/dev/main.tf` | l'ambiente dev chiama il modulo con i **suoi** valori: 1 replica, porta 8201 |
| 4 | `cd iac/envs/dev && terraform init && terraform apply -auto-approve` | `init` vede il modulo locale (oltre a scaricare il provider); l'apply crea rete, immagine e il container `dev-negozio-0` |
| 5 | `terraform output` | `url`: la lista con un solo URL, `http://localhost:8201` |
| 6 | `terraform state list` | gli indirizzi nello stato hanno la forma `module.<nome>.<risorsa>[chiave]`, per esempio `module.negozio.docker_container.replica["0"]` |
| 7 | `cd ../prod && terraform init && terraform plan` | prod: **stesso** modulo, valori diversi (3 repliche, porta 8301), **stato separato**. Solo plan: tutto è da creare (`+`), perché lo stato di prod è vuoto. Niente viene applicato |
| 8 | `cd ../dev && terraform destroy -auto-approve` | pulizia di dev. Prod non ha niente da distruggere |

Nessun passo è pensato per fallire.

---

## 4. Workspaces o cartelle? (dal fondo del file)

`terraform workspace new staging` dà **stesso codice, stato separato**, con `terraform.workspace` usabile come
variabile.

| | |
|---|---|
| **Pro** | zero duplicazione |
| **Contro** | stesso backend e stessi permessi per tutti gli ambienti; l'ambiente su cui lavori è uno stato **invisibile** del terminale («ero in prod?») |

Per dev/staging/prod quasi tutti usano **cartelle** (o **Terragrunt**, che genera backend e input per cartella e riduce
la duplicazione). I workspace vanno bene per **copie effimere identiche**. Questo script usa le cartelle.

## 5. Buoni moduli (dal file)

- piccoli e con uno scopo («rete», «cluster», «database»), non «tutto»;
- input con tipi, validazioni e default sensati; output di ciò che serve a valle (ID, endpoint), non di tutto;
- niente provider configurati dentro; `required_providers` con range;
- versionati con SemVer, CHANGELOG, esempi in `examples/` e test;
- niente «god module» con 80 variabili e un `count` su ogni risorsa.

Il modulo `servizio` ne rispetta parecchi: tipi e validation, nessun provider dentro, range sul provider, due output.

## 6. Trappole

- **Saltare il passo 4** rompe i `cd` dei passi 7 e 8.
- **Un modulo con `provider` dentro** non si può usare con `for_each`/`count` sul modulo e impedisce al root di
  scegliere la configurazione: il file dice «niente provider configurati dentro».
- **`source` su un branch** (`ref=main`): un merge sul modulo cambia i plan di tutti quelli che lo usano.
- **Gli output del modulo non arrivano da soli al root**: vanno riesposti (qui solo `url`).
- **Workspace per dev/prod**: un `terraform apply` nel workspace sbagliato non lo vede nessuno.

## 7. Domande da colloquio (dal file)

- **Cambio il modulo usato da 40 progetti: come lo rilasci in sicurezza?** Nuova versione SemVer (major se rompe
  l'interfaccia); i progetti la adottano uno per uno cambiando `ref`/`version`, con plan in MR. Mai `ref=main`: un
  merge sul modulo cambierebbe 40 plan insieme.
- **Un modulo usa `count` e voglio passare a `for_each` senza ricreare.** Blocchi `moved` per ogni indice:
  `from = x[0]`, `to = x["a"]` (lezione 03).
- **`depends_on` su un modulo?** Si può (Terraform >= 0.13) ma rende «noti dopo l'apply» molti valori e il plan
  diventa pessimista. Meglio passare un output come input: la dipendenza nasce da sola.

## 8. Dipendenze e pulizia

- **Prima**: lezione 02 (`for_each` con chiavi stabili, validation, `can(regex())`) e 03 (`moved`, backend).
- **Pulizia**: il passo 8 distrugge dev. Restano l'immagine `traefik/whoami:v1.12` (`keep_locally`), le cartelle
  `.terraform/` e lo stato (vuoto) in `envs/dev`, la `.terraform/` di `envs/prod`. Per togliere tutto:
  `rm -rf ~/kubernetesprj/lavoro/iac/04`.

## Riepilogo

- **Modulo** = cartella con `variables` / `main` / `outputs` / `versions`.
- Il **root** configura provider e backend, i moduli no.
- **Source versionate** (tag git o registry), mai branch.
- **Ambienti in cartelle separate** (o Terragrunt); workspace per copie effimere.
- Moduli **piccoli, tipizzati, validati, versionati**.

## Prova da solo

1. In `envs/prod/main.tf` porta `repliche` a `6` e lancia `terraform plan`: quale validation scatta, e con quale
   `error_message`?
2. Aggiungi a `envs/dev/main.tf` un `output "rete" { value = module.negozio.rete }`, fai `terraform apply` e poi
   `terraform output`: cosa compare in più?
3. In dev porta `repliche` a `2` e lancia `terraform plan`: quanti container vengono creati e quanti toccati? Con
   quale indirizzo compare il nuovo nello stato (scrivilo tra virgolette se lo passi a `terraform state show`, per
   esempio `terraform state show 'module.negozio.docker_container.replica["1"]'`)?

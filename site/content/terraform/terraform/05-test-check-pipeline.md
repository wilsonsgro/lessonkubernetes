# 05 — Test, check e pipeline

Spiegazione di `05-test-check-pipeline.sh` (questa cartella). Lezione sul sito: http://127.0.0.1:3000/terraform/5

## In una frase

Lo script fa scrivere al file di lezione un piccolo progetto `t05` (un container `traefik/whoami:v1.12` sulla porta
**8401**) con tutti i controlli che Terraform offre: **validation** su una variabile, **precondition** e
**postcondition** sul container, un blocco **`check`** che interroga `/health` dopo ogni plan/apply, e due file di
**`terraform test`**: unitari con **provider finti** (`mock_provider`) e di integrazione su Docker vero. Poi "rompe"
l'app e fa vedere che un `check` **avvisa ma non blocca**.

## Questo script e la lezione

| File | Che cos'è |
|---|---|
| `~/kubernetesprj/terraform/05-test-check-pipeline.sh` | **questo**: lo script guidato, da lanciare |
| `~/kubernetesprj/lezioni/terraform/05-test-check-pipeline.sh` | il file di lezione, da **leggere**. È uno **script bash**: con l'argomento `crea` scrive `t05/main.tf` e i due file di test. La teoria è nei commenti in cima e in fondo |

Due file con lo stesso nome: quello in `terraform/` è il guidato, quello in `lezioni/terraform/` è il generatore che
il guidato lancia al passo 1.

```bash
cd ~/kubernetesprj
bash terraform/05-test-check-pipeline.sh
```

Per ogni passo: **Invio** esegue · **s** salta · **q** esce (`AUTO=1` tutto di fila, `DA=n` dal passo n). Un errore
stampa `↳ uscita N` in rosso e lo script prosegue.

## Com'è fatto lo script

```
titolo "05. Test, check e pipeline"
cartella iac/05          → ~/kubernetesprj/lavoro/iac/05
8 × passo                → genera, legge un test, init, terraform test, apply, rompe /health, plan, destroy
nota                     → lo schema della pipeline
```

Il passo 3 fa `cd t05`: il `cd` resta valido per i passi dopo (il comando gira con `eval` nella shell dello script).
Se lo salti, i passi 4–8 girano nella cartella sbagliata.

---

## 1. La teoria nell'intestazione

Versione: **Terraform 1.17**, provider **docker 4.6**, **hashicorp/http 3.5**. Livello 3 — Qualità e automazione.

### Quattro livelli di controllo, dal più economico

| Livello | Strumenti | Cosa prende |
|---|---|---|
| 1. **statico** | `fmt -check`, `validate`, `tflint` (regole dei provider), `checkov` / `trivy config` | formattazione, sintassi, errori noti dei provider, sicurezza (bucket pubblici, security group `0.0.0.0/0`…) |
| 2. **contratti** | `validation` sulle variabili, `precondition` / `postcondition` sulle risorse | falliscono plan/apply con un messaggio |
| 3. **test** | `terraform test` con file `.tftest.hcl` | `command = plan` → unitari, veloci, nessuna risorsa; `command = apply` → integrazione: crea, verifica, distrugge; `mock_provider` → unitari senza credenziali né API |
| 4. **continui** | blocchi `check` | asserzioni valutate a **ogni** plan/apply, che **avvisano** (warning) senza bloccare: il drift *funzionale* |

Il progetto `t05` li ha tutti tranne il primo (che sta nella pipeline, vedi la nota finale).

### I comandi LAB dell'intestazione

```bash
bash 05-test-check-pipeline.sh crea
cd t05 && terraform init
terraform test                  # unitari con mock + integrazione su Docker
terraform apply -auto-approve   # il check "risponde" passa
curl -X POST -d 500 localhost:8401/health   # whoami: da ora /health risponde 500
terraform plan
terraform destroy -auto-approve
```

Il commento sul `plan` è preciso e vale la pena leggerlo: **0 to change** più **"Warning: Error making request"** dal
check. Il check avvisa e **non blocca**. Il warning non è il messaggio dell'`assert` ma un errore della richiesta,
perché con `retry` il provider http, davanti a un 500, dà **errore** invece di restituire lo status.

Altro fatto dal commento: con `docker stop` invece il check **non scatta**: il container va ricreato e il check
aspetta l'apply.

### Riquadro «NEL PROGETTO VERO»

In `~/biodistretto/kubernetes` (branch `kubernetes`; come si usa: il README della cartella) oggi il controllo dopo il
deploy lo fa **Ansible** (ruolo `verifica`): codici HTTP attesi attraverso HAProxy, e `meta.total > 0` sull'API.

```bash
cd ~/biodistretto/kubernetes
grep -n -E 'atteso:|failed_when' ansible/roles/verifica/tasks/main.yml
```

Esercizio del file: porta un controllo in Terraform con un blocco `check "api" { data "http" … }` nello stack app, e un
`terraform test` con `mock_provider` per la logica dei checksum. Ricorda: un check fallito avvisa ma **non ferma**
l'apply; per fermarlo serve la verifica di Ansible.

---

## 2. Il generatore: `05-test-check-pipeline.sh crea`

```bash
set -euo pipefail
D=./t05
crea() { … }        # mkdir -p ./t05/tests e tre heredoc <<'EOF'
case "${1:-}" in crea) crea ;; *) echo "uso: $0 crea" ;; esac
```

`D=./t05` è relativo alla cartella corrente: lanciato dal guidato, il progetto finisce in
`~/kubernetesprj/lavoro/iac/05/t05/`. Alla fine stampa `progetto scritto in ./t05`. Rilanciarlo sovrascrive i file.

---

## 3. `t05/main.tf`, blocco per blocco

### Provider

Due provider in `required_providers`: `kreuzwerker/docker ~> 4.6` e **`hashicorp/http ~> 3.5`**. Il secondo serve
solo al data source del `check`. Solo `docker` ha un blocco `provider` (vuoto); `http` non ha configurazione.

### Le variabili

| Variabile | Default | Controllo |
|---|---|---|
| `nome` | `t05-web` | — |
| `porta` | `8401` | `validation`: `var.porta > 1024`, altrimenti «Porta privilegiata: usa una porta > 1024.» |
| `immagine` | `traefik/whoami:v1.12` | (la controlla la precondition del container) |

### `docker_image.web` e `docker_container.web`

`docker_image.web`: `name = var.immagine`, `keep_locally = true`. `docker_container.web`: `name = var.nome`, porta
interna 80 pubblicata su `var.porta`. Il pezzo interessante è il `lifecycle`:

```hcl
lifecycle {
  precondition {
    condition     = !endswith(var.immagine, ":latest")
    error_message = "Vietato :latest: usa un tag immutabile."
  }
  postcondition {
    condition     = self.ports[0].external == var.porta
    error_message = "La porta pubblicata non è quella richiesta."
  }
}
```

| Blocco | Quando | Su cosa | Effetto |
|---|---|---|---|
| `precondition` | **prima** di creare/aggiornare la risorsa | gli input (`var.immagine`) | se falsa **blocca** |
| `postcondition` | **dopo**, sul risultato | `self` = la risorsa appena creata | se falsa **blocca** |

`:latest` è vietato perché non è immutabile: oggi e domani può indicare immagini diverse.

### L'output

`url = "http://localhost:${docker_container.web.ports[0].external}"`.

### Il blocco `check "risponde"`

```hcl
check "risponde" {
  data "http" "salute" {
    url = "http://localhost:${var.porta}/health"
    retry { attempts = 3 }
  }
  assert {
    condition     = data.http.salute.status_code == 200
    error_message = "${var.nome} non risponde 200 su /health."
  }
}
```

- Viene valutato a ogni plan/apply **dopo** il resto; un fallimento è un **warning**.
- Dentro c'è un data source **con scope**: `data.http.salute` esiste solo dentro il check (per questo il test di
  integrazione non lo può leggere, sotto).
- `retry { attempts = 3 }`: 3 **ripetizioni**, cioè al massimo 4 richieste (documentazione del provider http: «2 means at most 3 total tries»); i 5xx vengono ripetuti. È anche il motivo per cui, con un 500, il warning è
  «Error making request» e non il messaggio dell'assert.

---

## 4. I test

### `tests/unitari.tftest.hcl` — provider finti

```hcl
mock_provider "docker" {
  mock_resource "docker_image" {
    defaults = { image_id = "sha256:finto" }
  }
  mock_resource "docker_container" {
    defaults = { ports = [{ internal = 80, external = 8401, ip = "0.0.0.0", protocol = "tcp" }] }
  }
}
mock_provider "http" {
  mock_data "http" {
    defaults = { status_code = 200 }
  }
}
```

`mock_provider` sostituisce il provider vero: niente Docker, niente rete. I `defaults` sono i valori che le risorse
finte restituiscono negli attributi calcolati. Il commento del file avverte (provato): **senza** il default
`status_code = 200` il finto `http` dà `status_code` 0 e il check `risponde` fa **fallire** il run, perché **nei test
un check fallito non è un warning**.

I tre `run`, tutti `command = plan`:

| `run` | Cosa prova | Come |
|---|---|---|
| `url_costruito_dalla_porta` | l'output è costruito dalla porta | `assert`: `output.url == "http://localhost:8401"` |
| `porta_privilegiata_rifiutata` | la validation scatta davvero | `variables { porta = 80 }` e `expect_failures = [var.porta]`: il test **passa se la validazione fallisce** |
| `latest_vietato` | la precondition scatta davvero | `variables { immagine = "traefik/whoami:latest" }` e `expect_failures = [docker_container.web]` |

`expect_failures` è il modo di provare che un controllo **morde**: un controllo che non fallisce mai potrebbe anche
non esserci.

### `tests/integrazione.tftest.hcl` — Docker vero

```hcl
variables {
  nome  = "t05-test"
  porta = 8402
}
run "crea_e_risponde" {
  command = apply
  assert { condition = docker_container.web.name == "t05-test" … }
  assert { condition = output.url == "http://localhost:8402" … }
}
```

- Niente `mock_provider`: usa i provider veri. `command = apply` **crea** il container (`t05-test` sulla **8402**, così
  non si scontra con `t05-web` sulla 8401) e alla fine del test lo **distrugge**.
- Il commento: il data source del check **non è raggiungibile** dal test («Reference to scoped resource», provato).
  La prova che l'app risponde è il check stesso: in un test un check fallito fa fallire il run.

---

## 5. I passi dello script

| # | Comando | Cosa vedi / perché |
|---|---|---|
| 1 | `bash $LEZIONI/terraform/05-test-check-pipeline.sh crea` | il generatore scrive `t05/main.tf` (con il check), `t05/tests/unitari.tftest.hcl` (provider finto) e `t05/tests/integrazione.tftest.hcl` |
| 2 | `sed -n "1,30p" t05/tests/unitari.tftest.hcl` | le prime 30 righe del test unitario: i due `mock_provider` e i primi due `run`. Il terzo, `latest_vietato`, sta più sotto e il `sed` lo taglia |
| 3 | `cd t05 && terraform init` | entra nel progetto e scarica i due provider (docker e http) |
| 4 | `terraform test` | esegue gli unitari (mock, nessun container) e l'integrazione (Docker vero, creato e distrutto dal test) |
| 5 | `terraform apply -auto-approve` | crea `t05-web` sulla 8401; il check `risponde` interroga `/health` dopo l'apply e **passa** |
| 6 | `curl -s -X POST -d 500 localhost:8401/health; curl -s -o /dev/null -w "HTTP %{http_code}\n" localhost:8401/health` | **rompe l'app apposta**: whoami, con un POST su `/health`, da quel momento risponde con il codice che gli mandi (500). Il secondo `curl` stampa il codice: 500 |
| 7 | `terraform plan` | **0 to change** ma un **Warning** dal check. Un check **avvisa, non blocca** (al contrario di una precondition). Il plan non fallisce |
| 8 | `terraform destroy -auto-approve` | pulizia: via il container `t05-web` |

Nessun passo dà errore apposta: il "guasto" del passo 6 deve produrre un **warning**, non un `↳ uscita` rosso. Se il
passo 7 finisce in rosso, non è il comportamento che la lezione vuole mostrare.

### La nota finale: la pipeline

```
In pipeline: fmt -check → validate → tflint → test → plan -out (artefatto) → approvazione → apply del piano.
```

Lo schema completo (GitLab CI) è in fondo al file di lezione:

| Momento | Cosa gira |
|---|---|
| **MR** | `fmt -check` · `validate` · `tflint` · `trivy config` · `terraform test`; poi `plan -out=piano.tfplan` → `terraform show -no-color piano.tfplan` commentato nella MR (o `show -json` per una policy OPA/Conftest, es. «niente destroy su risorse con tag critico») |
| **main** | `apply piano.tfplan`: lo **stesso** piano rivisto, job manuale per prod |
| **notte** | `plan -detailed-exitcode` → exit 2 = drift → alert |

E due regole: **credenziali** con OIDC del job verso il cloud (`id_tokens` + ruolo con `AssumeRoleWithWebIdentity`),
mai chiavi statiche nelle variabili CI; **`resource_group`** per non lanciare due apply sullo stesso stato.

`tflint`, `trivy` e `checkov` non li installa `00-installa.sh` e lo script non li usa: compaiono solo nella teoria.

---

## 6. Trappole

- **Nei test un check fallito fa fallire il run** (fuori dai test è un warning): per questo il mock `http` ha
  `status_code = 200`.
- **Il data source di un check non si legge da fuori** («Reference to scoped resource»).
- **Un check non ferma niente**: se il deploy deve fermarsi su un errore, serve una precondition/postcondition o una
  verifica esterna (nel progetto vero, Ansible).
- **Porte 8401 e 8402**: l'integrazione usa la 8402 apposta; se una delle due è occupata l'apply corrispondente fallisce.
- **Il `docker stop` non fa scattare il check**: il plan vuole ricreare il container, e il check aspetta l'apply.

## 7. Domande da colloquio (dal file)

- **Come testi un modulo Terraform?** `terraform test`: run con `command = plan` e `mock_provider` per la logica
  (espressioni, condizionali, validazioni, `expect_failures`), run con `command = apply` in un account/progetto di
  test per l'integrazione. **Terratest** (Go) quando serve verificare il comportamento da fuori.
- **precondition, postcondition, check: differenze?** precondition: **prima** di creare/aggiornare la risorsa,
  blocca. postcondition: **dopo**, sul risultato (`self`), blocca. check: **alla fine**, sull'insieme, **non blocca**:
  avvisa. validation: sulla singola variabile.
- **`-detailed-exitcode`?** plan esce **0** = nessun cambiamento, **1** = errore, **2** = ci sono cambiamenti. È il modo
  di trasformare il drift in un job rosso.

## 8. Dipendenze e pulizia

- **Prima**: lezione 01 (piano salvato, drift), 02 (validation, `can`), 04 (struttura a generatore).
- **Pulizia**: il passo 8. I container del test di integrazione li distrugge `terraform test` da sé. Resta l'immagine
  `traefik/whoami:v1.12` (`keep_locally`) e la cartella `~/kubernetesprj/lavoro/iac/05`.

## Riepilogo

- **Statico** (fmt, validate, tflint, trivy) → **contratti** → **test** → **check**.
- `.tftest.hcl`: **plan + mock** per gli unitari, **apply** per l'integrazione.
- **`expect_failures`** prova che le validazioni scattano davvero.
- **`check { }`** = asserzioni continue che **avvisano** senza bloccare.
- Pipeline: plan in MR, **apply dello stesso piano**, drift notturno con **exit 2**.

## Prova da solo

1. Lancia `terraform plan -var 'porta=80'` (fuori dai test): quale messaggio compare, e il plan fallisce o avvisa?
2. Lancia `terraform plan -var 'immagine=traefik/whoami:latest'`: quale controllo scatta, la validation o la
   precondition? E con quale messaggio?
3. Dopo l'apply e il "guasto" del passo 6, lancia `terraform plan -detailed-exitcode; echo "uscita $?"`: che numero
   esce? Il warning del check conta come cambiamento?

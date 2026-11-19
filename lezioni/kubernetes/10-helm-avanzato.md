# 10 — Helm avanzato: dipendenze, hook, test e registry OCI

Spiegazione di `10-helm-avanzato.sh` (questa cartella). Lezione sul sito: http://127.0.0.1:3000/kubernetes/10

## In una frase

Lo script scrive un **chart "ombrello"** (`./piattaforma`) che usa due volte il chart `eco` della lezione 09 come
**dipendenza** (con due alias: `frontend` e `backend`), ci aggiunge un **Job di migrazione come hook** e un **Pod di
test**, poi fa vedere che un hook fallito **ferma l'upgrade** prima che tocchi i Deployment. Chiude pubblicando `eco`
in un **registry OCI** locale e rileggendolo da lì.

## Due file con lo stesso nome: quale lanciare

| File | Che cos'è | Come si usa |
|---|---|---|
| `~/kubernetesprj/lezioni/kubernetes/10-helm-avanzato.sh` | **questo**: la lezione, con le spiegazioni nei commenti | `bash 10-helm-avanzato.sh crea` · `prova` · `pulisci` |
| `~/kubernetesprj/kubernetes/10-helm-avanzato.sh` | lo script **guidato**: accende il registry, chiama `crea` di questo file ed esegue i comandi uno per volta, spiegando prima di eseguire (Invio / s / q) | `bash kubernetes/10-helm-avanzato.sh` |

Per imparare conviene lo **guidato**. Lavora nella stessa cartella della 09 (`lavoro/helm`) e **si ferma subito** se
`./eco` non c'è: `prima esegui la lezione 09: serve ./eco`. Anche `crea` della lezione fa lo stesso controllo.

## Com'è fatto il file

```
intestazione (commenti)    → chart ombrello, hook e loro annotazioni, LAB, NEL PROGETTO VERO
set -euo pipefail
NS=lab-piattaforma  OMBRELLO=./piattaforma
crea()                     → Chart.yaml con dipendenze, values.yaml, Job hook, Pod di test
prova()                    → dependency update, install, helm test, upgrade che fallisce, package/push OCI
case "$1"                  → crea | prova | pulisci
coda (commenti)            → Helm in un team, Helm o Kustomize, domande da colloquio, riepilogo
```

---

## 1. La teoria nell'intestazione

Versioni: **Helm 4.3 · registry OCI (distribution 3)**. Livello 4 "Packaging e delivery".

Quattro idee:

- un chart **ombrello** mette insieme più componenti;
- gli **hook** eseguono lavori in momenti precisi del ciclo di vita;
- i **test** verificano la release installata;
- il **registry OCI** distribuisce i chart come se fossero immagini.

### Gli hook (annotazione `helm.sh/hook`)

| Annotazione | Valori |
|---|---|
| `helm.sh/hook` | `pre-install` / `post-install` / `pre-upgrade` / `post-upgrade` / `pre-delete` / `post-delete` / `pre-rollback` / `post-rollback` / `test` |
| `helm.sh/hook-weight` | ordine tra hook dello stesso tipo (numeri come stringa, dal più basso) |
| `helm.sh/hook-delete-policy` | `before-hook-creation` · `hook-succeeded` · `hook-failed` |

Il punto da ricordare: **gli oggetti hook non fanno parte della release**. `helm uninstall` non li cancella: per questo
serve la delete-policy. Uso tipico: la migrazione del DB in `pre-upgrade`. Se fallisce, l'upgrade si ferma **prima** di
toccare il Deployment.

### Il laboratorio

```bash
docker run -d --name registry -p 5000:5000 registry:3     # registry OCI locale
bash 10-helm-avanzato.sh crea
bash 10-helm-avanzato.sh prova
```

Il registry è un container Docker **sull'host** (non nel cluster), con l'immagine `registry:3`, sulla porta 5000.

### Riquadro «NEL PROGETTO VERO»

In `~/biodistretto/kubernetes` l'equivalente di un hook `post-install` è il **Job `minio-init`**, che crea il bucket.
Terraform lo lancia dopo i dati e aspetta la condizione `Complete` prima di creare l'app:

```bash
cd ~/biodistretto/kubernetes
grep -n -A6 'resource "kubernetes_manifest" "minio_init"' terraform/app/workload.tf
grep -n -E 'backoffLimit|mc mb' terraform/app/manifests/minio-init.yaml.tftpl
```

Il Job è **idempotente** (`--ignore-existing`): rilanciarlo non rompe niente. Le dipendenze di un chart lì diventano
`depends_on` fra le risorse Terraform.

---

## 2. `crea()` — il chart ombrello

### `Chart.yaml` — dipendenze, alias, condition

```yaml
apiVersion: v2
name: piattaforma
version: 1.0.0
appVersion: "1.0.0"
dependencies:
  - name: eco
    version: "0.1.x"
    repository: "file://../eco"
    alias: frontend
  - name: eco
    version: "0.1.x"
    repository: "file://../eco"
    alias: backend
    condition: backend.enabled
```

| Campo | Perché |
|---|---|
| `name: eco` (due volte) | **la stessa dipendenza due volte**: due servizi dallo stesso chart |
| `version: "0.1.x"` | range SemVer: accetta qualunque patch della 0.1 (il chart eco è 0.1.0) |
| `repository: "file://../eco"` | la cartella del chart scritto nella 09. In produzione sarebbe `oci://registry/charts` |
| `alias` | il nome con cui il subchart compare: cambia `.Chart.Name` dentro il subchart e la chiave dei suoi valori |
| `condition: backend.enabled` | il backend si può **spegnere** dai values |

Con la release `demo`, il helper `eco.fullname` della 09 produce `demo-frontend` e `demo-backend` (la release non
contiene il nome del chart, quindi `<release>-<chart>`, e il nome del chart è l'alias).

### `values.yaml` — come si passano i valori ai subchart

```yaml
global:
  ambiente: lab                 # visibile a tutti i subchart
frontend:                       # valori del subchart "frontend"
  replicaCount: 1
  config: { messaggio: "frontend" }
backend:
  enabled: true
  replicaCount: 2
  config: { messaggio: "backend" }
migrazione:
  fallisci: false
```

- `global:` è l'unico posto che **tutti** i subchart vedono (`.Values.global`).
- I valori di un singolo subchart stanno **sotto il suo nome o alias**: `frontend.replicaCount` diventa
  `.Values.replicaCount` dentro il subchart.
- `migrazione.fallisci` è un interruttore usato dal Job hook per simulare una migrazione rotta.

### `templates/migrazione-job.yaml` — l'hook

| Campo | Valore | Perché |
|---|---|---|
| `name` | `{{ .Release.Name }}-migrazione` → `demo-migrazione` | **nome stabile**: lo stesso a ogni upgrade |
| `helm.sh/hook` | `pre-install,pre-upgrade` | gira prima del primo install **e** prima di ogni upgrade |
| `helm.sh/hook-weight` | `"-5"` | se ci fossero altri hook dello stesso tipo, questo va prima |
| `helm.sh/hook-delete-policy` | `before-hook-creation,hook-succeeded` | cancella il Job del giro prima prima di crearne uno nuovo, e lo cancella se riesce. **`hook-failed` non c'è**: un Job fallito resta, per leggerne i log |
| `backoffLimit` | `0` | nessun nuovo tentativo: un fallimento è subito un fallimento |
| `activeDeadlineSeconds` | `120` | dopo 2 minuti il Job viene fermato comunque |
| `restartPolicy` | `Never` | il container fallito non viene riavviato nello stesso Pod |
| `image` | `busybox:1.37` | |
| `command` | `sh -c` + script | stampa `migrazione schema per lab, revision N`; se `migrazione.fallisci` è vero stampa su stderr `colonna già esistente` ed esce con 1 |

Il blocco `{{- if .Values.migrazione.fallisci }} … {{- end }}` è dentro lo script della shell: Helm decide **al
rendering** se quelle righe esistono.

### `templates/tests/connessione.yaml` — il test

Un Pod (non un Job) con annotazione `helm.sh/hook: test` e la stessa delete-policy. Il container `wget` (busybox:1.37)
esegue:

```sh
wget -qO- http://demo-frontend/api | grep -q hostname
```

Chiama il Service del frontend (porta 80) sul path `/api` di whoami, e controlla che la risposta contenga `hostname`.
`helm test` crea il Pod e guarda **l'exit code**: 0 = test passato.

---

## 3. Il percorso del guidato, passo per passo

Namespace `lab-piattaforma`, cartella `lavoro/helm`.

| # | Comando | Cosa vedi |
|---|---|---|
| 1 | `docker ps --format "{{.Names}}" \| grep -qx registry \|\| docker run -d --name registry -p 5000:5000 registry:3` | accende il registry OCI sulla 5000 **solo se** non c'è già (`grep -qx` = riga esatta, silenzioso) |
| 2 | `bash $LEZIONI/kubernetes/10-helm-avanzato.sh crea` | `chart ombrello scritto in ./piattaforma` |
| 3 | `cat piattaforma/Chart.yaml` | le due dipendenze con alias |
| 4 | `helm dependency update piattaforma && cat piattaforma/Chart.lock` | scarica le dipendenze in `piattaforma/charts/` (i `.tgz`) e scrive **`Chart.lock`** con le versioni esatte. Il lock va in git |
| 5 | `helm upgrade --install demo piattaforma -n lab-piattaforma --create-namespace --wait --timeout 3m` | prima gira il Job `pre-install` (migrazione), poi vengono creati i Deployment |
| 6 | `kubectl -n lab-piattaforma get deploy` | `demo-frontend` (1 replica) e `demo-backend` (2 repliche) |
| 7 | `helm test demo -n lab-piattaforma --logs` | lancia il Pod di test e ne mostra i log |
| 8 | `helm upgrade demo piattaforma -n lab-piattaforma --set migrazione.fallisci=true --set frontend.replicaCount=3 --wait --timeout 2m` | **fallisce apposta**: il Job `pre-upgrade` esce con 1, l'upgrade si **ferma** prima di toccare i Deployment. Il guidato mostra l'uscita ≠ 0 in rosso |
| 9 | `kubectl -n lab-piattaforma get deploy demo-frontend -o jsonpath='repliche={.spec.replicas}{"\n"}'` | `repliche=1`: la richiesta di 3 repliche non è mai arrivata |
| 10 | `kubectl -n lab-piattaforma logs job/demo-migrazione` | il Job fallito **è ancora lì** (manca `hook-failed` nella policy): nei log `colonna già esistente` |
| 11 | `helm package ./eco` | il chart diventa un archivio versionato: `eco-0.1.0.tgz` |
| 12 | `helm push eco-0.1.0.tgz oci://localhost:5000/charts --plain-http` | pubblica l'archivio nel registry. `--plain-http` perché il registry locale non ha TLS |
| 13 | `helm show chart oci://localhost:5000/charts/eco --version 0.1.0 --plain-http` | il `Chart.yaml` letto **dal registry** |
| 14 | `helm template da-oci oci://localhost:5000/charts/eco --version 0.1.0 --plain-http \| grep -m1 image:` | rendering direttamente dal registry: in CI si installa così, senza clonare il repo del chart |

Nota finale del guidato: pulizia con `helm uninstall demo -n lab-piattaforma && kubectl delete ns lab-piattaforma`.
**Il registry resta acceso per la lezione 12**; per toglierlo: `docker rm -f registry`.

### `prova()` nella lezione

Stessa sequenza dal passo 4 al 14, senza pause. Differenze:

- il registry si cambia con una variabile: `REGISTRY="${REGISTRY:-localhost:5000}"` (default la 5000 locale);
- l'upgrade che fallisce è seguito da `|| echo "OK: migrazione fallita, upgrade fermato"` e i log del Job da
  `|| true`, così `set -e` non ferma lo script;
- il registry va acceso a mano prima (`docker run …` dell'intestazione).

---

## 4. Le trappole

- **Hook non ricreato al secondo upgrade.** Gli hook non sono risorse della release: se il Job del giro prima esiste
  ancora, la creazione fallisce. Servono `before-hook-creation` e un nome stabile.
- **`helm uninstall` non cancella gli hook.** Il Job fallito di questa lezione resta finché non lo cancelli tu o un
  nuovo giro con `before-hook-creation`.
- **Un subchart non vede i valori del padre** fuori da `global:`.
- **Alias e nomi.** Con l'alias il subchart si chiama `frontend`, non `eco`: cambiano i nomi degli oggetti e la
  chiave dei valori.
- **`--plain-http`** va bene solo per un registry locale senza TLS. In produzione il registry ha TLS e
  autenticazione.

---

## 5. La coda: Helm in un team, Helm o Kustomize

### Pratiche

- Chart versionati in un **registry OCI**, mai `helm install ./cartella` in produzione; `Chart.lock` in git.
- Un values file per ambiente: `values-dev.yaml`, `values-prod.yaml`.
- **helmfile** (o Argo CD / Flux) per installare N release in modo dichiarativo: lo stato desiderato di **tutte** le
  release in git.
- **post-renderer** (per esempio kustomize) per patchare un chart di terzi senza forkarlo.
- Chart di tipo **library** per condividere gli helper fra i chart del team.
- `helm template | kubeconform -strict` in CI per validare gli schemi.

### Helm o Kustomize? (domanda quasi certa, vedi lezione 11)

| | Helm | Kustomize |
|---|---|---|
| Cosa dà | parametri, packaging, release con storia, hook, ecosistema di chart pubblici | YAML puro + patch, niente template, integrato in kubectl, **nessuno stato nel cluster** |
| Costo | template testuali, YAML generato | niente logica né ciclo di vita |

Spesso si usano **insieme**: chart di terzi con Helm e app interne con Kustomize, oppure Helm + post-renderer
Kustomize, oppure Argo CD che renderizza entrambi.

---

## 6. Comandi e domande da colloquio

### Comandi da sapere

| Comando | A cosa serve |
|---|---|
| `helm dependency update <chart>` | scarica le dipendenze in `charts/` e scrive `Chart.lock` |
| `helm test <release> -n NS --logs` | esegue i Pod di test e mostra i log |
| `kubectl -n NS logs job/<nome>` | log di un Job hook fallito |
| `helm package ./eco` | crea `eco-0.1.0.tgz` |
| `helm push eco-0.1.0.tgz oci://localhost:5000/charts --plain-http` | pubblica nel registry OCI |
| `helm show chart oci://…/eco --version 0.1.0` | legge il chart dal registry |
| `helm template <rel> oci://…/eco --version 0.1.0` | renderizza dal registry |

### Domande

- **Perché il mio Job di migrazione non viene ricreato al secondo upgrade?** Gli hook non sono gestiti come risorse
  della release: se il Job del giro prima esiste ancora, la creazione fallisce. Serve `hook-delete-policy:
  before-hook-creation` (e un nome stabile).
- **Come passi un valore a tutti i subchart?** Sotto `global:`. Per un singolo subchart, sotto la sua chiave (nome o
  alias). Il subchart non vede i valori del padre fuori da `global`.
- **Hook pre-upgrade o initContainer per le migrazioni?** L'initContainer gira **per ogni Pod**: N migrazioni
  concorrenti, serve un lock. Il Job hook gira **una volta** e blocca l'upgrade se fallisce; ma con Argo CD gli hook
  vanno mappati sulle sue sync wave / hook.
- **Cosa conta `helm test`?** L'exit code dei Pod con annotazione `helm.sh/hook: test`.

---

## Riepilogo

- `dependencies` + `alias` + `condition`; `Chart.lock` fissa le versioni.
- `global` per i valori condivisi; i valori di un subchart sotto il suo nome o alias.
- Hook con `hook-weight` e `hook-delete-policy`; un `pre-upgrade` fallito blocca l'upgrade.
- `helm test` = Pod con annotazione `test`, conta l'exit code.
- Distribuzione: `helm package` + `helm push` su un registry OCI.

## Prova da solo

1. Installa con `--set backend.enabled=false` (in un altro namespace o dopo la pulizia): quanti Deployment vedi? Cosa
   è cambiato in `helm template demo piattaforma --set backend.enabled=false`?
2. Rifai l'upgrade che fallisce, poi un upgrade normale (`--set frontend.replicaCount=3` senza `fallisci`): il Job
   vecchio fallito impedisce il nuovo? Quale voce della delete-policy lo spiega?
3. Aggiungi a `global:` una chiave nuova e prova a leggerla da un template del subchart `eco`
   (`{{ .Values.global.ambiente }}`): poi prova con una chiave fuori da `global`. Cosa vede il subchart?

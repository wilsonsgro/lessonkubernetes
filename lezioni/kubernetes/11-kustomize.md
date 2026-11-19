# 11 — Kustomize: base, overlay, patch, generator e component

Spiegazione di `11-kustomize.sh` (questa cartella). Lezione sul sito: http://127.0.0.1:3000/kubernetes/11

## In una frase

Lo script scrive una struttura Kustomize completa (`./kust`: una **base** comune, gli **overlay** `dev` e `prod`, un
**component** di monitoring), la renderizza senza cluster, applica `prod`, e poi fa vedere il trucco del
**configMapGenerator**: cambi un valore di config → la ConfigMap prende un **nome nuovo** (hash) → il Deployment cambia
→ **rollout automatico**.

## Due file con lo stesso nome: quale lanciare

| File | Che cos'è | Come si usa |
|---|---|---|
| `~/kubernetesprj/lezioni/kubernetes/11-kustomize.sh` | **questo**: la lezione, con le spiegazioni nei commenti | `bash 11-kustomize.sh crea` · `prova` · `pulisci` |
| `~/kubernetesprj/kubernetes/11-kustomize.sh` | lo script **guidato**: chiama `crea` di questo file e poi esegue i comandi uno per volta, spiegando prima di eseguire (Invio / s / q) | `bash kubernetes/11-kustomize.sh` |

Per imparare conviene lo **guidato**. Lavora nella cartella `lavoro/kustomize`.

## Com'è fatto il file

```
intestazione (commenti)  → idea di Kustomize, struttura delle cartelle, trasformatori, LAB, NEL PROGETTO VERO
set -euo pipefail
K=./kust
crea()                   → scrive base/, components/monitoring/, overlays/dev/, overlays/prod/
prova()                  → render, apply prod, cambio di config, diff, riapply, elenco ConfigMap
case "$1"                → crea | prova | pulisci
coda (commenti)          → domande da colloquio, riepilogo
```

---

## 1. La teoria nell'intestazione

Versione: **kustomize 5.7**, che è già **dentro kubectl 1.35** (`kubectl apply -k`, `kubectl kustomize`). Livello 4
"Packaging e delivery".

L'idea: **Kustomize non ha template**. Parte da YAML valido (la base) e lo trasforma con overlay dichiarativi. Quello
che vedi in git è YAML vero, applicabile e validabile; le differenze fra ambienti sono **patch piccole**.

```
base/                    ciò che è uguale ovunque
components/monitoring/   un pezzo opzionale, riusabile tra overlay
overlays/dev/            dev  = base + 1 replica + debug
overlays/prod/           prod = base + 3 repliche + risorse + PDB + monitoring
```

### I trasformatori principali (in `kustomization.yaml`)

| Campo | Cosa fa |
|---|---|
| `namespace`, `namePrefix` / `nameSuffix` | si applicano a **tutti** gli oggetti |
| `labels` (con `includeSelectors: false`) | aggiunge label **senza toccare i selector**, che sono immutabili. `commonLabels` invece li tocca |
| `images` | cambia tag o digest di un'immagine senza scrivere una patch |
| `replicas` | cambia le repliche senza patch |
| `patches` | strategic merge oppure JSON 6902 (`op` / `path`) |
| `configMapGenerator` / `secretGenerator` | crea ConfigMap/Secret con un **suffisso hash** nel nome e aggiorna i riferimenti: cambio di config = nome nuovo = rollout |

### Riquadro «NEL PROGETTO VERO»

Kustomize fa ripartire i Pod mettendo un hash nel **nome** della ConfigMap. Il progetto `~/biodistretto/kubernetes`
ottiene lo stesso risultato **tenendo fisso il nome** e mettendo l'hash in un'**annotazione del Pod** (come il
`checksum/config` di Helm nella lezione 09):

```bash
cd ~/biodistretto/kubernetes
grep -n 'checksum_' terraform/app/workload.tf
grep -n 'biodistretto/config' terraform/app/manifests/app.yaml.tftpl
```

Da colloquio: con l'hash nel nome **restano le ConfigMap vecchie**, utili per il rollback ma da potare. Con
l'annotazione no, però il rollback della config passa dal codice.

---

## 2. `crea()` — i file, uno per uno

`find kust -type f | sort` (passo 2 del guidato) mostra:

```
kust/base/deployment.yaml
kust/base/kustomization.yaml
kust/base/service.yaml
kust/components/monitoring/kustomization.yaml
kust/overlays/dev/kustomization.yaml
kust/overlays/dev/namespace.yaml
kust/overlays/prod/kustomization.yaml
kust/overlays/prod/namespace.yaml
kust/overlays/prod/pdb.yaml
kust/overlays/prod/risorse.yaml
```

### La base

**`base/deployment.yaml`** — un Deployment `api` normale, applicabile anche da solo:

| Campo | Valore | Nota |
|---|---|---|
| `replicas` | `1` | gli overlay lo cambiano |
| `selector.matchLabels` / label del template | `app: api` | |
| `image` | `traefik/whoami:v1.11` | in prod diventa `v1.12` con `images:` |
| `args` | `["--port", "8080"]` | |
| `envFrom.configMapRef.name` | `api-config` | il nome "logico": il generator lo riscrive con l'hash |
| porta `http` 8080, `readinessProbe` su `/health` | | |

**`base/service.yaml`** — Service `api`, selector `app: api`, porta 80 → `targetPort: http`.

**`base/kustomization.yaml`**:

```yaml
resources:
  - deployment.yaml
  - service.yaml
labels:
  - pairs:
      app.kubernetes.io/part-of: negozio
    includeSelectors: false
configMapGenerator:
  - name: api-config
    literals:
      - LOG_LEVEL=info
```

- `resources`: i file che fanno parte della base.
- `labels` con `includeSelectors: false`: `app.kubernetes.io/part-of: negozio` finisce nei metadata, **non** in
  `spec.selector` (immutabile su un Deployment esistente).
- `configMapGenerator`: genera la ConfigMap `api-config-<hash>` con `LOG_LEVEL=info`. L'hash è calcolato dal
  **contenuto**: stesso contenuto → stesso nome.

### Il component `monitoring`

```yaml
apiVersion: kustomize.config.k8s.io/v1alpha1
kind: Component
patches:
  - target: { kind: Deployment, name: api }
    patch: |-
      - op: add
        path: /spec/template/metadata/annotations
        value:
          prometheus.io/scrape: "true"
          prometheus.io/port: "8080"
```

Un `Component` (nota: `v1alpha1`, non `v1beta1`) è un pezzo **opzionale** che un overlay attiva con `components:`.
Qui è una patch JSON 6902 che aggiunge al template del Pod le annotazioni `prometheus.io/*` (le usa la lezione 13 per
dire a Prometheus "raccogli le metriche di questo Pod sulla 8080"). Vantaggio: lo stesso pezzo si riusa in più
overlay senza copiarlo.

### L'overlay `dev`

```yaml
namespace: negozio-dev
resources:
  - ../../base
  - namespace.yaml
configMapGenerator:
  - name: api-config
    behavior: merge            # unisce ai valori della base
    literals:
      - LOG_LEVEL=debug
```

- `namespace: negozio-dev`: tutto finisce in quel namespace; `namespace.yaml` crea il Namespace stesso.
- `behavior: merge`: non crea una seconda ConfigMap, **modifica** quella della base: `LOG_LEVEL` diventa `debug`.
- Repliche: quelle della base (1).

### L'overlay `prod`

```yaml
namespace: negozio-prod
resources: [../../base, namespace.yaml, pdb.yaml]
components: [../../components/monitoring]
replicas:
  - name: api
    count: 3
images:
  - name: traefik/whoami
    newTag: v1.12
patches:
  - path: risorse.yaml
  - target: { kind: Deployment, name: api }
    patch: |-
      - op: add
        path: /spec/template/spec/topologySpreadConstraints
        value:
          - maxSkew: 1
            topologyKey: kubernetes.io/hostname
            whenUnsatisfiable: ScheduleAnyway
            labelSelector: { matchLabels: { app: api } }
```

| Pezzo | Cosa fa |
|---|---|
| `components` | attiva il monitoring |
| `replicas` | 3 repliche, senza patch |
| `images` | `name` è il nome dell'immagine **nella base**; `newTag: v1.12` cambia solo il tag. In CI si fa con `kustomize edit set image traefik/whoami:<sha>`, che richiede il binario `kustomize`: **kubectl non ha `edit`** |
| `patches: - path: risorse.yaml` | patch **strategic merge**: si scrive come un pezzo dell'oggetto |
| `patches: - target … op: add` | patch **JSON 6902**: aggiunge una `topologySpreadConstraints` che sparge i Pod sui nodi (`kubernetes.io/hostname`, max differenza 1, ma `ScheduleAnyway`: se non si può, li mette comunque) |

**`risorse.yaml`** (strategic merge):

```yaml
spec:
  template:
    spec:
      containers:
        - name: api              # le liste di container si fondono per "name"
          resources:
            requests: { cpu: 50m, memory: 32Mi }
            limits: { memory: 64Mi }
```

Il punto: in una strategic merge la lista `containers` non viene **sostituita**, ma fusa elemento per elemento usando
`name` come chiave. Per questo basta scrivere `name: api` e i campi da aggiungere.

**`pdb.yaml`** — PodDisruptionBudget `api` con `minAvailable: 2` su `app: api`: con 3 repliche, un drain può togliere
al massimo un Pod alla volta (lezione 05).

---

## 3. Il percorso del guidato, passo per passo

| # | Comando | Cosa vedi |
|---|---|---|
| 1 | `bash $LEZIONI/kubernetes/11-kustomize.sh crea` | `struttura scritta in ./kust` |
| 2 | `find kust -type f \| sort` | i file elencati sopra |
| 3 | `cat kust/overlays/prod/kustomization.yaml` | l'overlay prod |
| 4 | `kubectl kustomize kust/overlays/prod \| grep -E 'name: api-config\|image:\|replicas:\|prometheus.io/scrape'` | render **senza cluster**: il nome con hash `api-config-…` (sia nella ConfigMap sia nel riferimento del Deployment), `image: traefik/whoami:v1.12`, `replicas: 3`, l'annotazione `prometheus.io/scrape` |
| 5 | `diff <(kubectl kustomize kust/overlays/dev) <(kubectl kustomize kust/overlays/prod)` | le differenze riga per riga. **Esce con 1 apposta**: `diff` restituisce 1 quando i file sono diversi |
| 6 | `kubectl apply -k kust/overlays/prod && kubectl -n negozio-prod rollout status deploy/api --timeout=2m` | applica prod e aspetta il rollout |
| 7 | `kubectl -n negozio-prod get deploy api -o jsonpath='{…envFrom[0].configMapRef.name}'` | il nome con hash che usa il Deployment |
| 8 | `sed -i 's/LOG_LEVEL=info/LOG_LEVEL=warn/' kust/base/kustomization.yaml && grep LOG_LEVEL …` | cambia un valore **nella base** |
| 9 | `kubectl diff -k kust/overlays/prod` | cosa cambierebbe nel cluster: una ConfigMap nuova e il riferimento nel Deployment. **Uscita 1 = ci sono differenze**, è normale |
| 10 | `kubectl apply -k kust/overlays/prod && kubectl -n negozio-prod rollout status …` | hash nuovo → nome nuovo → il template del Deployment cambia → **rollout automatico** |
| 11 | `kubectl -n negozio-prod get cm` | **entrambe** le ConfigMap, vecchia e nuova: il rollback del Deployment ritrova la sua |

Pulizia: `kubectl delete ns negozio-prod negozio-dev --ignore-not-found`.

### `prova()` nella lezione

Fa gli stessi passi da 4 a 11 senza pause, e in più salva il nome della ConfigMap **prima** e **dopo** e stampa
`ConfigMap: <prima> → <dopo>`. `kubectl diff -k … || true` evita che l'uscita 1 fermi lo script con `set -e`.
Commento importante: la ConfigMap vecchia resta per il rollback; per pulirla
`kubectl apply -k … --prune -l app.kubernetes.io/part-of=negozio`, oppure Argo CD con prune attivo.

Nota: `prova` non rifà `crea`. Dopo un primo `prova` la base dice già `LOG_LEVEL=warn` e il `sed` non cambia più
niente; per ripetere la dimostrazione rilancia prima `crea`.

---

## 4. Le trappole

- **`commonLabels` su un Deployment già in produzione**: aggiunge le label anche a `spec.selector`, che è immutabile →
  l'apply fallisce. Usa `labels` con `includeSelectors: false`.
- **`diff` e `kubectl diff` escono con 1** quando trovano differenze: non è un errore. In uno script con `set -e`
  serve `|| true`.
- **Le ConfigMap vecchie si accumulano** con il generator: servono `--prune` o un GitOps con prune.
- **`kustomize edit` non è in kubectl**: in CI serve il binario `kustomize`.
- **La patch JSON 6902 `add` su un path** sostituisce il valore se esiste già: qui la base non ha annotazioni né
  `topologySpreadConstraints`, quindi non si perde niente.

---

## 5. Comandi e domande da colloquio

### Comandi da sapere

| Comando | A cosa serve |
|---|---|
| `kubectl kustomize <overlay>` | rendering locale, senza cluster |
| `diff <(kubectl kustomize dev) <(kubectl kustomize prod)` | differenza fra ambienti |
| `kubectl diff -k <overlay>` | cosa cambierebbe nel cluster |
| `kubectl apply -k <overlay>` | applica l'overlay |
| `kustomize edit set image traefik/whoami:<sha>` | aggiorna il tag in CI (binario kustomize) |
| `kubectl apply -k … --prune -l app.kubernetes.io/part-of=negozio` | applica e toglie gli oggetti con quella label non più presenti |

### Domande

- **Perché `commonLabels` è pericoloso su un Deployment già in produzione?** Aggiunge le label anche a
  `spec.selector`, che è immutabile: l'apply fallisce. `labels` con `includeSelectors: false` le mette solo nei
  metadata.
- **Strategic merge patch o JSON 6902?** La strategic merge è leggibile e conosce le chiavi di fusione delle liste
  (`containers` per `name`). La JSON 6902 serve per operazioni precise: `remove`, `add` in un indice, oggetti CRD
  senza schema di merge.
- **Come promuovi la stessa versione da staging a prod in GitOps?** La CI fa `kustomize edit set image app:<sha>`
  nell'overlay di staging e apre una PR; la promozione è una PR che copia lo stesso tag (o digest) nell'overlay di
  prod. L'immagine **non si ricostruisce**.
- **Kustomize con Helm?** `helmCharts:` nella kustomization (con `--enable-helm`) renderizza un chart e poi lo patcha;
  oppure `helm --post-renderer` kustomize (vedi lezione 10).

---

## Riepilogo

- Base in YAML vero + overlay per ambiente; component per i pezzi opzionali.
- `images` e `replicas` senza patch; `patches` strategic merge o JSON 6902.
- `configMapGenerator`: hash nel nome = ogni cambio di config è un rollout.
- `labels` con `includeSelectors: false`, non `commonLabels`.
- `kubectl kustomize` / `diff -k` / `apply -k`; `kustomize edit set image` in CI.

## Prova da solo

1. Applica anche l'overlay dev (`kubectl apply -k kust/overlays/dev`) e confronta
   `kubectl -n negozio-dev get cm -o yaml | grep LOG_LEVEL` con prod: che valore vedi e perché (`behavior: merge`)?
2. Aggiungi `components: [../../components/monitoring]` all'overlay dev e rifai il `diff` del passo 5: quali righe
   spariscono?
3. Fai un rollback del Deployment prod (`kubectl -n negozio-prod rollout undo deploy/api`) e guarda quale ConfigMap
   usa adesso (il jsonpath del passo 7). Perché funziona solo finché la ConfigMap vecchia esiste?

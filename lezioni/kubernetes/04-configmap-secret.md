# 04 — Configurazione: ConfigMap, Secret e come si aggiornano

Spiegazione di `04-configmap-secret.yaml` (questa cartella). Lezione sul sito: http://127.0.0.1:3000/kubernetes/4

## In una frase

Il file crea una **ConfigMap** `app-config`, un **Secret** `db` e un piccolo **Deployment `conf`** (busybox) che li
consuma in **due modi**: come **variabili d'ambiente** e come **file montati**. Il runner cambia la ConfigMap a caldo e
fa vedere la lezione centrale: **il file si aggiorna da solo, la variabile d'ambiente no**; per quella serve un
container nuovo.

## Due file con lo stesso nome: quale lanciare

| File | Che cos'è | Come si usa |
|---|---|---|
| `~/kubernetesprj/lezioni/kubernetes/04-configmap-secret.yaml` | **questo**: i manifest, con la teoria nei commenti | si **legge**; lo applica il runner (o a mano: `kubectl apply -f 04-configmap-secret.yaml`) |
| `~/kubernetesprj/kubernetes/04-configmap-secret.sh` | lo script **guidato**: applica, cambia la ConfigMap, confronta env e file, un passo per volta (Invio / s / q) | `bash kubernetes/04-configmap-secret.sh` |

Il namespace `lab` deve esistere (lo crea la lezione 02).

## Com'è fatto il file

```
intestazione (commenti)  → teoria: twelve-factor, ConfigMap vs Secret, come e quando si aggiornano,
                           comandi LAB, NEL PROGETTO VERO
ConfigMap app-config     → una chiave semplice (LOG_LEVEL) e una chiave-file (app.properties)
Secret db                → username e password, scritti con stringData
Deployment conf          → busybox che dorme; legge la config come env e come volume
commenti                 → i segreti in GitOps, il caso Laravel
coda (commenti)          → domande da colloquio, riepilogo
```

---

## 1. La teoria nell'intestazione

### Twelve-factor: la config fuori dall'immagine

La **stessa immagine** gira in ogni ambiente (dev, staging, produzione); cambia solo la configurazione, che sta fuori.
Kubernetes offre due oggetti quasi identici:

| Oggetto | Per cosa |
|---|---|
| **ConfigMap** | dati non sensibili |
| **Secret** | dati sensibili — ma solo **base64, che NON è cifratura** |

La differenza **vera** fra i due:

- **RBAC separabile**: puoi dare `get` sui ConfigMap e negarlo sui Secret;
- nei volumi un Secret sta in **tmpfs** (in memoria), **mai su disco del nodo**;
- **cifratura at-rest in etcd**, ma solo **se** l'apiserver ha una `EncryptionConfiguration` (sui cloud gestiti: KMS,
  spesso da attivare a mano).

### Come arrivano nel Pod, e quando si aggiornano

| Modo | Quando si aggiorna |
|---|---|
| `env` / `envFrom` | letti **all'avvio del container**: **mai** aggiornati |
| volume | aggiornato dal kubelet al suo **prossimo sync** (da pochi secondi a 1-2 minuti; il file dice: su k3s 5 s), con uno **swap atomico del symlink `..data`** |
| volume + `subPath` | **mai** aggiornato (trappola classica) |
| `immutable: true` | né aggiornabile né osservato: meno carico sull'apiserver; per cambiarlo lo ricrei |

E anche quando il file si aggiorna: un'app che lo legge **solo all'avvio** non vede il cambio. Serve un **reload**
(SIGHUP, watch del file) o un **rollout**.

### Riquadro «NEL PROGETTO VERO»

In `~/biodistretto/kubernetes`:

- La ConfigMap di nginx usa gli **stessi file dello stack docker**, letti con `file()` di Terraform; solo i due vhost
  sono template (`templatefile`):
  ```bash
  grep -n -E 'file\(|templatefile' terraform/app/config.tf
  ```
- Quei file sono montati con **`subPath`**, e un subPath non si aggiorna da solo. Per questo il template del Pod porta il
  **checksum della config**: cambia la ConfigMap → cambia l'annotazione → il Deployment fa il rollout.
  ```bash
  grep -n 'subPath' terraform/app/manifests/app.yaml.tftpl
  grep -n 'biodistretto/config' terraform/app/manifests/app.yaml.tftpl
  ```
- Il backend prende tutta la config con **`envFrom`**, da ConfigMap più Secret:
  ```bash
  grep -n -A4 'envFrom' terraform/app/manifests/app.yaml.tftpl
  ```
- Le password non le scrive nessuno: `random_password`, e CA e certificato dal provider `tls`. Restano però nel
  **tfstate**, che quindi è a sua volta un segreto (e sta nel `.gitignore`):
  ```bash
  grep -n '^resource' terraform/app/segreti.tf
  grep -n 'tfstate' .gitignore
  ```

---

## 2. La ConfigMap `app-config`

```yaml
data:
  LOG_LEVEL: info
  app.properties: |
    feature.x=false
```

Due chiavi, due usi:

- `LOG_LEVEL` è un **valore semplice**: il Deployment lo prende come variabile d'ambiente;
- `app.properties` è un **file intero** (il `|` di YAML conserva l'a capo): il Deployment lo monta come file.

Il nome della chiave diventa il nome del file quando la ConfigMap è montata come volume.

---

## 3. Il Secret `db`

```yaml
type: Opaque
stringData:
  username: app
  password: cambiami-subito
```

| Campo | Perché |
|---|---|
| `type: Opaque` | Secret generico, chiavi libere (altri tipi: TLS, docker-registry…) |
| `stringData` | permette di scrivere i valori **in chiaro** nel manifest; l'apiserver li converte in base64 nel campo `data`. Comodo, ma proprio per questo **questo file non va in git** |

Il runner lo legge con `get secret db -o jsonpath='{.data.password}' | base64 -d` e ottiene `cambiami-subito`:
chiunque abbia `get` sui secret del namespace lo decodifica in un comando.

---

## 4. Il Deployment `conf` — campo per campo

### Template e annotazione di checksum

```yaml
selector:
  matchLabels: { app: conf }
template:
  metadata:
    labels: { app: conf }
    annotations:
      checksum/config: "da-calcolare-in-helm"
```

Il valore qui è un **segnaposto**. In Helm (lezione 09) lo si calcola con `sha256sum` sul ConfigMap: se il contenuto
cambia, cambia l'annotazione → cambia il **pod template** → il Deployment fa un **rollout automatico** (lezione 02: ogni
cambio del template = nuovo ReplicaSet). Scritto a mano e mai cambiato, come qui, non scatena niente.

### Spec del Pod

| Campo | Valore | Perché |
|---|---|---|
| `automountServiceAccountToken` | `false` | l'app non parla con l'API di Kubernetes: niente token montato nel Pod (meno superficie d'attacco, lezione 07) |
| `image` | `busybox:1.37` | un'immagine minima **con la shell**: serve per fare `exec` e `cat` |
| `command` | `["sh", "-c", "while true; do sleep 3600; done"]` | il container non fa niente, resta vivo per farsi ispezionare |
| `resources` | requests `cpu: 10m`, `memory: 16Mi`; limits `memory: 32Mi` | stessa logica della lezione 02 (QoS Burstable) |

### Le variabili d'ambiente

```yaml
env:
  - name: LOG_LEVEL
    valueFrom:
      configMapKeyRef: { name: app-config, key: LOG_LEVEL }
  - name: DB_PASSWORD
    valueFrom:
      secretKeyRef: { name: db, key: password }
```

- `configMapKeyRef` prende **una chiave** di una ConfigMap; `secretKeyRef` una chiave di un Secret.
- Vengono risolte **quando il container parte**. Dopo, sono una fotografia.

Il commento del file avverte: **meglio il segreto come FILE, non come env**. Le env finiscono in `kubectl describe`, nei
crash dump, in `/proc/<pid>/environ` e nei log di chi le stampa. `DB_PASSWORD` qui c'è per farti vedere il modo da
evitare.

### I volumi

```yaml
volumeMounts:
  - name: config
    mountPath: /etc/app
    readOnly: true
  - name: segreti
    mountPath: /run/secrets/db
    readOnly: true
volumes:
  - name: config
    configMap:
      name: app-config
      items:
        - key: app.properties
          path: app.properties
  - name: segreti
    secret:
      secretName: db
      defaultMode: 0400
```

| Volume | Cosa finisce nel container |
|---|---|
| `config` | **solo** la chiave `app.properties` (grazie a `items`), come `/etc/app/app.properties`. Senza `items` comparirebbe anche un file `LOG_LEVEL` |
| `segreti` | ogni chiave del Secret diventa un file: `/run/secrets/db/username` e `/run/secrets/db/password` |

- `readOnly: true`: il container non può scrivere nella config.
- `defaultMode: 0400`: i file del Secret sono leggibili **solo dal proprietario** (in YAML `0400` è un numero ottale).
- Nessun `subPath`: per questo il file **si aggiorna** (la differenza col progetto vero).

Dentro `/etc/app` il kubelet crea una cartella con data e ora (`..2026_…`), un link `..data` che punta a lei, e
`app.properties` che punta a `..data/app.properties`. Per aggiornare scrive una cartella nuova e **sposta il link
`..data` in un colpo solo**: l'app non vede mai un file scritto a metà.

---

## 5. Il runner, passo per passo

`guardia_lab`, poi 10 passi. Importante: `passo` esegue i comandi con `eval` **nella stessa shell**, quindi la
variabile `P` impostata al passo 3 resta valida nei passi successivi.

| # | Comando | Cosa vedi |
|---|---|---|
| 1 | `kubectl apply -f …/04-configmap-secret.yaml` | `configmap/app-config`, `secret/db`, `deployment.apps/conf` creati |
| 2 | `kubectl -n lab rollout status deploy/conf` | il Pod è pronto |
| 3 | `P=$(kubectl -n lab get pod -l app=conf -o name \| head -1); echo $P` | il nome, es. `pod/conf-…` |
| 4 | `exec $P -- sh -c 'echo LOG_LEVEL=$LOG_LEVEL; cat /etc/app/app.properties'` | `LOG_LEVEL=info` e `feature.x=false` |
| 5 | `exec $P -- ls -la /etc/app` | i symlink: `..data -> ..2026_…`, `app.properties -> ..data/app.properties` |
| 6 | `kubectl -n lab patch cm app-config --type merge -p '{"data":{"LOG_LEVEL":"debug","app.properties":"feature.x=true\n"}}'` | `configmap/app-config patched`. Nessun Pod viene riavviato |
| 7 | `sleep 60; exec $P -- sh -c '…'` | **il punto della lezione**: `LOG_LEVEL=info` (la **variabile no**) ma `feature.x=true` (il **file sì**) |
| 8 | `get secret db -o jsonpath='{.data.password}' \| base64 -d; echo` | `cambiami-subito` in chiaro |
| 9 | `rollout restart deploy/conf && rollout status deploy/conf` | Pod nuovo, creato con la ConfigMap già aggiornata |
| 10 | nuovo `P` con `--field-selector=status.phase=Running … \| tail -1`, poi lo stesso `exec` | ora anche `LOG_LEVEL=debug` |

Nessun passo fallisce apposta. Il passo 7 è il "fallimento" concettuale: la variabile d'ambiente **resta vecchia**. Il
`sleep 60` serve ad aspettare il sync del kubelet (da pochi secondi a 1-2 minuti).

La `nota` finale: in git va il manifest del Secret **con valori finti** (`secret.example.yaml`), quello vero sta nel
`.gitignore`. Base64 non cifra; una password finita in un commit **si cambia**, perché `.gitignore` non riscrive la
storia.

Attenzione: il patch del passo 6 resta nel cluster. Se rilanci il runner, il passo 1 (`apply`) rimette `info` e
`feature.x=false`.

---

## 6. I segreti in GitOps

Il problema: in git sta tutto **tranne** i Secret. Le risposte mature:

| Strumento | Come funziona |
|---|---|
| **External Secrets Operator** | il cluster legge da Vault / AWS Secrets Manager / GCP Secret Manager e crea il Secret; in git c'è solo il riferimento (`ExternalSecret` + `SecretStore`) |
| **Sealed Secrets** | in git c'è un `SealedSecret` cifrato con la chiave pubblica del controller nel cluster |
| **SOPS** (+ age/KMS) | file YAML cifrati campo per campo, decifrati da Argo CD/Flux o helm-secrets |
| **CSI Secrets Store driver** | il segreto montato direttamente dal provider come volume, senza Secret Kubernetes |

In tutti i casi **rotazione, audit e revoca stanno nel vault**, non nel cluster.

**Minimo decente in un laboratorio senza vault**: `secret.example.yaml` in git (valori finti, mostra le chiavi
attese) e `secret.yaml` fuori da git (`.gitignore`, valori veri).

**Su EKS**: Secrets Manager + Pod Identity, poi External Secrets (→ Secret, usabile con `envFrom`) o CSI driver (→ file).
Una rotazione non tocca le env dei container già avviati: serve un rollout (esattamente ciò che vedi al passo 7).

### Il caso Laravel

ConfigMap per `APP_ENV`, `APP_URL`, `DB_HOST`…; Secret per `APP_KEY`, `DB_PASSWORD`, token. Entrambi con `envFrom`,
senza `.env` nell'immagine:

```yaml
envFrom:
  - configMapRef: { name: laravel-config }
  - secretRef:    { name: laravel-secret }
```

Con `php artisan config:cache` la cache va **rifatta all'avvio del container**, altrimenti fotografa i valori vecchi
(lo ricorda anche il passo 10 del runner).

---

## 7. Le trappole

| Trappola | Cosa succede | Rimedio |
|---|---|---|
| "Secret = cifrato" | è solo base64 | RBAC stretto, cifratura at-rest (KMS), fonte esterna |
| cambiare la ConfigMap e aspettarsi la nuova env | l'env resta quella dell'avvio | `rollout restart` o checksum nel template |
| volume con `subPath` | il file non si aggiorna **mai** | checksum nel template → rollout |
| app che legge il file solo all'avvio | il file cambia ma l'app no | reload (SIGHUP, watch) o rollout |
| segreti in env | finiscono in describe, dump, `/proc/<pid>/environ`, log | montali come file con `defaultMode` stretto |
| Secret con `stringData` in git | password in chiaro nella storia | `secret.example.yaml` + `.gitignore`; se è già committata, si **cambia** |
| `config:cache` di Laravel nell'immagine | fotografa i valori di build | rifarla all'avvio del container |

---

## 8. La coda: domande da colloquio

- **I Secret di Kubernetes sono sicuri?** Di default no: base64 in etcd e leggibili da chiunque abbia `get` sui secret
  o possa **creare un Pod** nel namespace (montandoli). Servono cifratura at-rest (KMS), RBAC stretto, niente segreti in
  env, e una fonte esterna con rotazione.
- **Ho cambiato il ConfigMap ma l'app usa ancora il valore vecchio.** Env: letta solo all'avvio. Volume con subPath: non
  si aggiorna mai. Volume normale: aggiornato al sync del kubelet, ma l'app deve rileggerlo. Soluzione robusta: config
  **versionata** (hash nel nome o checksum nel template), così ogni cambio è un rollout tracciabile e reversibile.
- **Perché un ConfigMap immutabile?** Il kubelet non lo osserva più: meno watch sull'apiserver nei cluster grandi, e
  nessuno può cambiarlo sotto i piedi a un'app in produzione.

### Comandi da sapere

| Comando | A cosa serve |
|---|---|
| `kubectl -n lab patch cm app-config --type merge -p '{"data":{…}}'` | cambiare una ConfigMap al volo |
| `kubectl -n lab get secret db -o jsonpath='{.data.password}' \| base64 -d` | leggere (e capire quanto è poco protetto) un Secret |
| `kubectl -n lab exec $P -- ls -la /etc/app` | vedere i symlink `..data` |
| `kubectl -n lab rollout restart deploy/conf` | Pod nuovi per prendere le env nuove |

---

## Riepilogo

- ConfigMap e Secret: la config **fuori dall'immagine**.
- Secret = **base64, non cifratura**: servono KMS, RBAC e una fonte esterna.
- **env mai aggiornate, volume sì** (al sync del kubelet), **subPath mai**.
- Config versionata (checksum/hash) = ogni cambio è un **rollout**.
- GitOps: External Secrets, Sealed Secrets o SOPS, **mai Secret in chiaro** in git.

## Prova da solo

1. Entra nel Pod e leggi `/run/secrets/db/password` e i permessi con `ls -la /run/secrets/db/`: che modo vedi, e da
   quale campo del manifest viene? Confrontalo con `echo $DB_PASSWORD`.
2. Aggiungi `immutable: true` alla ConfigMap, riapplica, poi rifai il `patch` del passo 6: che errore dà l'apiserver?
   Come la cambi adesso?
3. Monta `app.properties` con `subPath: app.properties` su `mountPath: /etc/app/app.properties`, riapplica, rifai il
   patch e aspetta 60 s: il file cambia? Poi cambia a mano il valore di `checksum/config` e riapplica: cosa succede ai Pod?

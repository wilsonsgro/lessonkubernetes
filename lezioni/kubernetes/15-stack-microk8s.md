# 15 — Stack completo su MicroK8s: PHP × 3, MariaDB, Redis, Elasticsearch, Ingress e Headlamp

Spiegazione di `15-stack-microk8s.sh` (questa cartella).

## In una frase

Lo script monta **un'applicazione vera** su un cluster **diverso** dal lab minikube: **MicroK8s** sull'Ubuntu
`192.168.1.79`. Tre repliche PHP dietro Service e Ingress parlano con MariaDB e Elasticsearch (StatefulSet + PVC) e
con Redis (cache), e una UI web (Headlamp) legge il cluster con un **token in sola lettura che scade**.

## Due file con lo stesso nome: quale lanciare

| File | Che cos'è | Come si usa |
|---|---|---|
| `~/kubernetesprj/lezioni/kubernetes/15-stack-microk8s.sh` | **questo**: la lezione, con le spiegazioni nei commenti | `bash 15-stack-microk8s.sh installa` · `addon` · `dati` · `app` · `headlamp` · `verifica` · `certificati` · `smonta` |
| `~/kubernetesprj/kubernetes/15-stack-microk8s.sh` | lo script **guidato**: chiama le funzioni di questo file una per volta, spiegando prima di eseguire (Invio / s / q) | `bash kubernetes/15-stack-microk8s.sh` |

Per imparare conviene lo **guidato**. Questo file va **letto** mentre lo guidato gira: i commenti spiegano il perché.

Versioni dichiarate nell'intestazione: **MicroK8s 1.33 · Helm 3 (`microk8s helm`) · Headlamp 0.46**. Livello 6 —
laboratorio completo.

## Com'è fatto il file

```
intestazione (commenti)  → minikube vs MicroK8s vs k3s, quando scegliere cosa, architettura, NEL PROGETTO VERO, uso
set -euo pipefail        → lo script si ferma al primo errore
K, H, NS, NODO           → "microk8s kubectl", "microk8s helm", namespace "stack", IP 192.168.1.79
installa()               → snap + canale bloccato + gruppo microk8s
addon()                  → start, dns, hostpath-storage, ingress
dati()                   → namespace, Secret, MariaDB, Redis, Elasticsearch
app()                    → ConfigMap con index.php, Deployment PHP × 3, Service, Ingress
headlamp()               → chart Helm senza cluster-admin + ServiceAccount in lettura + token a tempo
verifica()               → 6 richieste curl, EndpointSlice, auth can-i
certificati()            → IP nei SAN di server.crt e kubelet.crt
smonta()                 → via Headlamp e namespace, MicroK8s fermo
case "$1"                → sceglie la funzione dall'argomento
coda (commenti)          → domande da colloquio, riepilogo
```

Le variabili in cima:

```bash
K="microk8s kubectl"
H="microk8s helm"
NS=stack
NODO=192.168.1.79
```

Non si usa `kubectl` "normale": `microk8s kubectl` ha **il suo kubeconfig** e quindi **non tocca il contesto `lab`**
del minikube (il runner lo dice nella prima `nota`). Per questo qui non c'è la `guardia_lab` delle altre lezioni.

---

## 1. La teoria nell'intestazione

### minikube, MicroK8s, k3s: stesso Kubernetes, tre mestieri

| | minikube | MicroK8s | k3s |
|---|---|---|---|
| chi | progetto Kubernetes | Canonical | SUSE / Rancher |
| cosa è | un cluster **dentro** una VM o un container (driver docker/kvm) | Kubernetes come **snap** sull'host, servizi systemd veri | un **unico binario** (~70 MB) con tutto dentro, servizio systemd |
| pensato per | sviluppo locale, usa e getta | dev, edge, piccoli cluster di produzione | edge, IoT, ARM, produzione leggera |
| multi-nodo | `--nodes=N`, ma tutti sulla stessa macchina | sì, nodi veri: `add-node` / `join` | sì, nodi veri: token + agent |
| alta disponibilità | no | sì con ≥3 nodi (dqlite, automatica) | sì con etcd embedded o DB esterno |
| datastore | etcd | **dqlite** (SQLite distribuito, Raft) | SQLite (1 nodo), etcd embedded (HA) |
| CNI default | kindnet / bridge | Calico | Flannel |
| ingress | addon ingress-nginx | addon ingress (ingress-nginx) | Traefik già dentro |
| storage | addon storage-provisioner | addon hostpath-storage | local-path-provisioner |
| kubectl | kubectl normale, contesto `lab` | `microk8s kubectl` (kubeconfig suo) | `k3s kubectl`, oppure `/etc/rancher/k3s/k3s.yaml` |
| estensioni | `minikube addons` | `microk8s enable …` (dns, ingress, metallb, …) | manifest in `/var/lib/rancher/k3s/server/manifests` |
| aggiornamenti | `minikube start --kubernetes-version` | canale snap (`1.33/stable`): **snap si aggiorna da solo** | binario nuovo o system-upgrade-controller |
| si cancella | `minikube delete`: sparisce il nodo | `microk8s reset` / `snap remove --purge` | `k3s-uninstall.sh` |

### Quando scegliere cosa (domanda da colloquio)

- **minikube**: provo un manifest o un chart sul portatile, poi butto via. Il nodo è un container: niente porte
  80/443 sull'host, serve `minikube tunnel` o `minikube service`.
- **MicroK8s**: voglio qualcosa che **resti acceso** su una macchina, addon a un comando, HA che arriva da sola
  aggiungendo nodi. Gli upgrade arrivano via snap: in produzione **si fissa il canale** (`snap refresh --hold`),
  altrimenti un aggiornamento automatico cambia il cluster sotto i piedi.
- **k3s**: risorse scarse (Raspberry, edge) o tanti cluster piccoli gestiti da Rancher/Fleet. Pochi pezzi,
  Traefik e ServiceLB inclusi.

Tutti e tre passano i test di conformità CNCF: i manifest della lezione girano identici su ognuno, **cambiano solo
storage class e ingress class**.

### L'architettura

```
browser ──► 192.168.1.79:80 ──► Ingress (controller nginx dell'addon, hostPort 80/443 sul nodo)
                                   │ host: stack.lab
                                   ▼
                         Service php-app (ClusterIP)
                                   ▼
                    php-app  php-app  php-app      Deployment, 3 repliche
                                   ▼
   mariadb:3306            redis:6379             elasticsearch:9200
   StatefulSet + PVC       Deployment (cache,     StatefulSet + PVC
   Secret credenziali      niente persistenza)    single-node, security off (lab)

Headlamp (namespace headlamp, NodePort) ── legge il cluster con il token di un ServiceAccount a sola lettura
```

Scelta voluta: **niente chart di terzi per i dati**. StatefulSet scritti a mano con le immagini ufficiali, così vedi
cosa c'è sotto un chart e riusi le lezioni 04 (Secret) e 05 (StatefulSet e PVC). L'unico chart è quello di Headlamp.

### Riquadro «NEL PROGETTO VERO»

Indica dove lo stesso tipo di stack compare in `~/biodistretto/kubernetes` (branch `kubernetes`; i `grep` partono da
lì, il README della cartella spiega l'uso). Lì gira su **minikube** con il Biodistretto (Laravel + Vue). Cosa cambia:

| Differenza | Dove guardarla |
|---|---|
| **HAProxy sta FUORI dal cluster**, sull'host, come un load balancer del cloud. Inoltra in TCP verso i NodePort, **senza terminare TLS** | `grep -n -E 'mode tcp\|send-proxy-v2' ansible/roles/haproxy/templates/haproxy.cfg.j2` |
| il **TLS lo termina nginx nel cluster**, con una CA del laboratorio fatta da Terraform; nginx accetta il PROXY protocol su 80 e 443 | `grep -n 'proxy_protocol' terraform/app/nginx/bordo.conf` |
| la config di HAProxy la **genera Ansible** dall'elenco dei nodi e la **valida** prima di sostituirla | `grep -n 'validate' ansible/roles/haproxy/tasks/main.yml` |

Il PROXY protocol (`send-proxy-v2`) serve a far arrivare a nginx l'IP vero del client, che altrimenti vedrebbe solo
quello di HAProxy.

---

## 2. `installa` — una volta sola

```bash
sudo snap install microk8s --classic --channel=1.33/stable
sudo snap refresh --hold microk8s
sudo usermod -a -G microk8s "$USER"
mkdir -p ~/.kube && chmod 0700 ~/.kube
```

| Riga | Perché |
|---|---|
| `--classic` | lo snap ha accesso pieno al sistema (serve a un Kubernetes) |
| `--channel=1.33/stable` | scegli la **minor** di Kubernetes: il canale resta su 1.33 |
| `snap refresh --hold` | blocca gli aggiornamenti automatici dello snap: il cluster non cambia da solo |
| `usermod -a -G microk8s` | il tuo utente può usare `microk8s` senza `sudo` |
| `~/.kube` con `0700` | la cartella dei kubeconfig leggibile solo da te |

Il gruppo vale **dalla prossima login**: lo script stampa `ora: newgrp microk8s (oppure esci e rientra)`.
`newgrp` apre una subshell che ha già il gruppo.

---

## 3. `addon` — dns, storage, ingress

```bash
sudo microk8s start
microk8s status --wait-ready >/dev/null
microk8s enable dns
microk8s enable hostpath-storage
microk8s enable ingress
$K get storageclass
$K get ingressclass
```

| Addon | Cosa porta | Perché serve qui |
|---|---|---|
| `dns` | CoreDNS | senza, il nome `mariadb` non si risolve |
| `hostpath-storage` | StorageClass **`microk8s-hostpath`** (cartelle sul nodo) | i PVC di MariaDB ed Elasticsearch. Va bene per **un** nodo; con più nodi serve uno storage di rete (es. addon rook-ceph o NFS) |
| `ingress` | controller nginx in **DaemonSet**, ascolta su **80/443 del nodo** | il browser arriva a `192.168.1.79:80` senza tunnel |

Gli ultimi due `get` ti mostrano i nomi da usare nei manifest: la StorageClass `microk8s-hostpath` e la IngressClass
`public`. Sono proprio "le due cose che cambiano" fra minikube, MicroK8s e k3s.

---

## 4. `dati` — MariaDB, Redis, Elasticsearch

### Namespace e Secret

```bash
$K create namespace $NS --dry-run=client -o yaml | $K apply -f -
$K -n $NS create secret generic mariadb-cred \
  --from-literal=MARIADB_ROOT_PASSWORD="$(openssl rand -hex 16)" \
  --from-literal=MARIADB_DATABASE=appdb \
  --from-literal=MARIADB_USER=app \
  --from-literal=MARIADB_PASSWORD="$(openssl rand -hex 16)" \
  --dry-run=client -o yaml | $K apply -f -
```

- `create … --dry-run=client -o yaml | apply -f -` è il trucco per rendere **idempotente** un `create`: genera lo YAML
  senza crearlo e lo passa ad `apply`, che crea o aggiorna. Rilanci la funzione e non ottieni `AlreadyExists`.
- Le password sono **casuali** (`openssl rand -hex 16`) e **nessuna è scritta nel manifest**.
- Le chiavi hanno i nomi che l'immagine ufficiale `mariadb` legge all'avvio (`MARIADB_ROOT_PASSWORD`, `MARIADB_DATABASE`,
  `MARIADB_USER`, `MARIADB_PASSWORD`): così il Secret si passa intero con `envFrom`.
- Perché in un Secret e non nelle `env` del Deployment: chi può leggere il Deployment **non vede le password**, con
  RBAC separato (lezione 07).

Attenzione: siccome le password sono rigenerate a ogni lancio, rilanciare `dati` **cambia il Secret**, ma MariaDB
inizializza utente e password solo al primo avvio con il PVC vuoto. Sul disco restano quelle vecchie.

### MariaDB: Service headless + StatefulSet

```yaml
kind: Service
metadata: { name: mariadb }
spec:
  clusterIP: None              # headless: DNS stabile mariadb-0.mariadb
  selector: { app: mariadb }
  ports: [{ name: mysql, port: 3306 }]
---
kind: StatefulSet
spec:
  serviceName: mariadb
  replicas: 1
  template:
    spec:
      containers:
        - name: mariadb
          image: mariadb:11.8          # LTS
          envFrom: [{ secretRef: { name: mariadb-cred } }]
          ports: [{ containerPort: 3306, name: mysql }]
          readinessProbe:
            tcpSocket: { port: mysql }
            periodSeconds: 5
          resources:
            requests: { cpu: 100m, memory: 256Mi }
            limits: { memory: 512Mi }
          volumeMounts: [{ name: dati, mountPath: /var/lib/mysql }]
  volumeClaimTemplates:
    - metadata: { name: dati }
      spec:
        accessModes: [ReadWriteOnce]
        storageClassName: microk8s-hostpath
        resources: { requests: { storage: 2Gi } }
```

| Campo | Perché |
|---|---|
| `clusterIP: None` | Service **headless**: niente IP virtuale, il DNS dà l'IP del Pod e un nome stabile `mariadb-0.mariadb` |
| `serviceName: mariadb` | lega lo StatefulSet al Service headless che gli dà i nomi DNS |
| `envFrom: secretRef` | tutte le chiavi del Secret diventano variabili d'ambiente |
| `readinessProbe: tcpSocket` su `mysql` | durante l'init l'entrypoint avvia il server con `--skip-networking`: la porta si **apre solo a database pronto**, quindi basta un controllo TCP |
| `port: mysql` | la probe usa il **nome** della porta, non il numero |
| `limits` solo `memory` | nessun limite di CPU (niente throttling), ma un tetto alla memoria |
| `volumeClaimTemplates` | ogni replica ha il suo PVC (`dati-mariadb-0`), che la segue a ogni riavvio |

### Redis: Deployment, cache pura

```yaml
kind: Deployment
metadata: { name: redis }
spec:
  replicas: 1
  template:
    spec:
      containers:
        - name: redis
          image: redis:8-alpine
          args: ["--save", "", "--appendonly", "no"]
          ports: [{ containerPort: 6379, name: redis }]
          readinessProbe:
            exec: { command: [redis-cli, ping] }
            periodSeconds: 5
          resources:
            requests: { cpu: 50m, memory: 64Mi }
            limits: { memory: 128Mi }
```

- `--save ""` spegne gli snapshot RDB, `--appendonly no` spegne l'AOF: **niente persistenza**, al riavvio riparte
  vuota. Per una cache va bene; se Redis tenesse dati veri → StatefulSet + PVC come MariaDB.
- La probe è di tipo `exec`: `redis-cli ping` dentro il container.
- Il Service `redis` è un normale ClusterIP sulla porta 6379.

### Elasticsearch: StatefulSet single-node

```yaml
spec:
  serviceName: elasticsearch
  replicas: 1
  template:
    spec:
      securityContext:
        fsGroup: 1000
      containers:
        - name: elasticsearch
          image: docker.elastic.co/elasticsearch/elasticsearch:9.1.2
          env:
            - { name: discovery.type, value: single-node }
            - { name: xpack.security.enabled, value: "false" }
            - { name: ES_JAVA_OPTS, value: "-Xms512m -Xmx512m" }
          ports: [{ containerPort: 9200, name: http }]
          readinessProbe:
            httpGet: { path: "/_cluster/health?local=true", port: http }
            periodSeconds: 10
            failureThreshold: 12
          resources:
            requests: { cpu: 250m, memory: 1Gi }
            limits: { memory: 1Gi }
          volumeMounts: [{ name: dati, mountPath: /usr/share/elasticsearch/data }]
  volumeClaimTemplates: … microk8s-hostpath, 5Gi
```

| Campo | Perché |
|---|---|
| `fsGroup: 1000` | i file del volume prendono il gruppo 1000: l'utente `elasticsearch` deve poter **scrivere nel PVC** |
| `discovery.type=single-node` | un nodo solo, e **salta i bootstrap check** (`vm.max_map_count` ecc.). In un cluster vero vanno soddisfatti sul nodo |
| `xpack.security.enabled=false` | niente TLS né password: va bene **solo** in laboratorio |
| `-Xms512m -Xmx512m` | heap = **metà del limite** (1Gi): l'altra metà serve alla page cache |
| `requests = limits` di memoria | 1Gi garantito e mai superato |
| probe `/_cluster/health?local=true` | chiede la salute al nodo stesso; `failureThreshold: 12` × 10 s = fino a 2 minuti per partire, ES è lento |

Il Service `elasticsearch` qui **non è headless** (ha un ClusterIP), a differenza di quello di MariaDB.

### L'attesa

```bash
$K -n $NS rollout status statefulset/mariadb --timeout=180s
$K -n $NS rollout status deployment/redis --timeout=120s
$K -n $NS rollout status statefulset/elasticsearch --timeout=300s
$K -n $NS get pods,svc,pvc
```

Timeout diversi per servizi diversi: Elasticsearch è il più lento (5 minuti). Alla fine vedi i Pod `mariadb-0`,
`elasticsearch-0`, `redis-…`, i tre Service e i PVC `Bound`.

---

## 5. `app` — PHP × 3, Service, Ingress

### La ConfigMap con `index.php`

Il codice sta in una **ConfigMap** montata come file: l'immagine resta quella **ufficiale** (`php:8.4-apache`), niente
build. Lo script parla con i tre servizi **senza estensioni PHP**:

| Servizio | Come lo interroga | Cosa mette nel JSON |
|---|---|---|
| MariaDB | `fsockopen(DB_HOST, 3306)` e legge il **pacchetto di saluto** del server | `mariadb`: la versione presa dal saluto (`substr($hello, 5)` fino al primo `\0`), oppure `KO: …` |
| Redis | `fsockopen(REDIS_HOST, 6379)`, scrive `INCR visite\r\n` a mano (protocollo Redis) | `redis_visite`: il contatore, condiviso da tutti i Pod |
| Elasticsearch | `file_get_contents(ELASTIC_URL)` con timeout 2 s | `elasticsearch`: `version.number` della risposta, oppure `KO` |

In più `pod` = `gethostname()`, cioè **il nome del Pod** che ha risposto.

### Il Deployment

```yaml
kind: Deployment
metadata: { name: php-app }
spec:
  replicas: 3
  template:
    spec:
      containers:
        - name: php
          image: php:8.4-apache
          ports: [{ containerPort: 80, name: http }]
          env:
            - { name: DB_HOST, value: mariadb }
            - { name: REDIS_HOST, value: redis }
            - { name: ELASTIC_URL, value: "http://elasticsearch:9200" }
            - name: DB_USER
              valueFrom: { secretKeyRef: { name: mariadb-cred, key: MARIADB_USER } }
            - name: DB_PASSWORD
              valueFrom: { secretKeyRef: { name: mariadb-cred, key: MARIADB_PASSWORD } }
          readinessProbe:
            httpGet: { path: /, port: http }
            periodSeconds: 5
          resources:
            requests: { cpu: 50m, memory: 64Mi }
            limits: { memory: 128Mi }
          volumeMounts:
            - { name: codice, mountPath: /var/www/html, readOnly: true }
      volumes:
        - name: codice
          configMap: { name: php-app }
```

| Campo | Perché |
|---|---|
| `replicas: 3` | repliche **intercambiabili**: nessuno stato locale |
| `DB_HOST: mariadb` (nome corto) | si risolve **dentro il namespace** grazie al `search` del `resolv.conf` (`stack.svc.cluster.local`) — lezione 19 |
| `secretKeyRef` | prende **una** chiave del Secret, non tutte (a differenza di `envFrom`) |
| `readinessProbe` su `/` | il Pod entra nel Service solo quando Apache risponde |
| `mountPath: /var/www/html` `readOnly` | la ConfigMap diventa la document root: `index.php` è la pagina servita |

Nota: `index.php` fa solo l'handshake con MariaDB, **non fa login**: `DB_USER` e `DB_PASSWORD` sono messe nell'ambiente
per mostrare `secretKeyRef`, ma il codice non le usa.

### Service e Ingress

```yaml
kind: Service
metadata: { name: php-app }
spec:
  selector: { app: php-app }
  ports: [{ name: http, port: 80, targetPort: http }]
---
kind: Ingress
metadata: { name: php-app }
spec:
  ingressClassName: public          # la classe che crea l'addon di MicroK8s
  rules:
    - host: stack.lab
      http:
        paths:
          - path: /
            pathType: Prefix
            backend: { service: { name: php-app, port: { name: http } } }
```

- `targetPort: http` punta alla porta **per nome** del container.
- `ingressClassName: public`: su MicroK8s la classe si chiama `public`, non `nginx` come su minikube. È la differenza
  da cambiare portando i manifest da un cluster all'altro.
- `host: stack.lab`: il controller sceglie la regola dall'header `Host`. Non serve un DNS: basta mandare l'header.

Alla fine: `rollout status deployment/php-app` e `get pods -l app=php-app -o wide` (vedi i 3 Pod con il loro IP).

---

## 6. `headlamp` — UI web senza permessi nel pod

```bash
$H repo add headlamp https://kubernetes-sigs.github.io/headlamp/ 2>/dev/null || true
$H repo update headlamp
$H upgrade --install headlamp headlamp/headlamp \
  -n headlamp --create-namespace \
  --set clusterRoleBinding.create=false \
  --set service.type=NodePort \
  --wait
```

| Opzione | Perché |
|---|---|
| `upgrade --install` | idempotente: installa la prima volta, aggiorna le successive |
| `clusterRoleBinding.create=false` | **la riga che conta**. Di default il chart lega il ServiceAccount **del pod** a `cluster-admin`: chiunque entri nel pod (o sfrutti una falla di Headlamp) ha il cluster. Il pod non deve avere permessi: Headlamp usa il **token che incolli nel login**, quindi i permessi stanno nel token |
| `service.type=NodePort` | la UI si raggiunge da `192.168.1.79:<porta>` |
| `--wait` | aspetta che il rilascio sia pronto |

Poi l'utente di tutti i giorni:

```bash
$K -n headlamp create serviceaccount headlamp-lettore --dry-run=client -o yaml | $K apply -f -
$K create clusterrolebinding headlamp-lettore \
  --clusterrole=view --serviceaccount=headlamp:headlamp-lettore --dry-run=client -o yaml | $K apply -f -
porta="$($K -n headlamp get svc headlamp -o jsonpath='{.spec.ports[0].nodePort}')"
echo "UI:    http://$NODO:$porta"
$K -n headlamp create token headlamp-lettore --duration=8h
```

- `view` è un ClusterRole **built-in**: legge quasi tutto **tranne i Secret**.
- La porta NodePort si legge con `jsonpath`, non si indovina.
- `create token --duration=8h`: un token **a tempo** che **non finisce in nessun Secret**. Lo incolli nel login di
  Headlamp.
- Anti-pattern (dalla 1.24): un token che non scade, cioè un Secret di tipo `service-account-token`. Se esce da un
  laptop vale per sempre.
- Per scrivere da Headlamp: un **secondo** SA con un Role nel **solo** namespace `stack`, non `cluster-admin`.

---

## 7. `verifica` — chi risponde, da quale pod

```bash
for _ in 1 2 3 4 5 6; do
  curl -s -H 'Host: stack.lab' "http://$NODO/" | tr -d '\n '; echo
done
$K -n $NS get endpointslices -l kubernetes.io/service-name=php-app
$K auth can-i get secrets -n $NS --as=system:serviceaccount:headlamp:headlamp-lettore || true
$K auth can-i list pods -n $NS --as=system:serviceaccount:headlamp:headlamp-lettore
```

Cosa vedi (il runner lo riassume così: «cambia il pod che risponde, il contatore Redis sale per tutti, MariaDB ed
Elasticsearch rispondono»):

- 6 righe JSON compattate (`tr -d '\n '`), una per richiesta. Il campo `pod` **cambia**: il Service distribuisce sui
  3 Pod. `redis_visite` **sale di 1 a ogni riga**, chiunque risponda: il contatore sta in Redis, non nel Pod.
  `mariadb` mostra la versione del server, `elasticsearch` `9.1.2`.
- `-H 'Host: stack.lab'` sostituisce la riga in `/etc/hosts`. Dal Mac: `curl -H 'Host: stack.lab' http://192.168.1.79/`.
- L'EndpointSlice del Service `php-app` (etichetta `kubernetes.io/service-name`) elenca i 3 IP dei Pod pronti.
- `can-i get secrets` → **no** (e il `|| true` evita che `set -e` fermi lo script: `can-i` esce con 1 quando la
  risposta è no). `can-i list pods` → **yes**: `view` legge i Pod.
- `--as=system:serviceaccount:<ns>:<nome>` è l'**impersonazione**: chiedi all'apiserver cosa potrebbe fare quell'identità.

---

## 8. `certificati` — gli IP nei SAN

```bash
for c in server kubelet; do
  echo "== $c.crt"
  openssl x509 -in /var/snap/microk8s/current/certs/$c.crt \
    -noout -ext subjectAltName | tr ',' '\n' | grep 'IP Address'
done
sudo microk8s refresh-certs --check
```

MicroK8s mette gli IP del nodo nei **SAN** (Subject Alternative Name) dei certificati **nel momento in cui li genera**.
Se il DHCP cambia l'IP (è successo davvero: `.58 → .79`), `kubectl` remoto e `kubectl exec`/`logs` falliscono con:

```
x509: certificate is valid for 192.168.1.58, not 192.168.1.79
```

Il dettaglio da ricordare: **`exec` e `logs` passano dall'apiserver al kubelet**, quindi per quelli conta
`kubelet.crt`, non `server.crt`. Per questo il ciclo li controlla tutti e due. `refresh-certs --check` mostra le
scadenze.

| Certificato | Cura |
|---|---|
| `server.crt` | `sudo microk8s refresh-certs --cert server.crt` |
| `kubelet.crt` | non è tra i `--cert` supportati: `sudo microk8s stop` → `sudo /snap/microk8s/current/actions/common/utils.sh create_user_certs_and_configs` → `sudo microk8s start` |

Prevenzione: **IP statico** o prenotazione DHCP per i nodi. IP extra stabili vanno in
`/var/snap/microk8s/current/certs/csr.conf.template` (`IP.N = …`) **prima** di rigenerare.

---

## 9. `smonta`

```bash
$H uninstall headlamp -n headlamp || true
$K delete clusterrolebinding headlamp-lettore --ignore-not-found
$K delete namespace $NS headlamp --ignore-not-found --wait
sudo microk8s stop
```

- Il ClusterRoleBinding non sta in un namespace: va cancellato a parte.
- **I PVC degli StatefulSet NON si cancellano con lo StatefulSet**: cadono solo con il namespace (o a mano). È voluto:
  proteggono i dati.
- Ripartire da zero, addon e dati compresi: `sudo microk8s reset`. Togliere tutto: `sudo snap remove microk8s --purge`.

---

## 10. Il runner, passo per passo

| # | Passo | Cosa vedi |
|---|---|---|
| — | `nota` | si usa `microk8s kubectl`, kubeconfig suo, non tocca `lab`. Se MicroK8s non c'è: `bash … installa` e `newgrp microk8s` |
| 1 | `sudo microk8s start && microk8s status --wait-ready \| head -15` | chiede la password di sudo; lo stato e gli addon |
| 2 | `microk8s version; $K get nodes -o wide` | **un solo nodo, che è l'Ubuntu stesso**, non un container come in minikube |
| 3 | `bash $L addon` | dns, hostpath-storage, ingress; StorageClass e IngressClass |
| 4 | `bash $L dati` | MariaDB, Redis, Elasticsearch fino a pronti |
| 5 | `$K -n stack get secret mariadb-cred -o jsonpath='{.data}' \| jq 'keys'` | **solo i nomi** delle chiavi: password casuali, nessuna nel manifest |
| 6 | `$K -n stack get pvc; ls /var/snap/microk8s/common/default-storage/` | i PVC sono **cartelle** sotto `/var/snap/microk8s/common/default-storage` |
| 7 | `bash $L app` | PHP × 3, Service, Ingress su `stack.lab` |
| 8 | `bash $L verifica` | le 6 richieste, EndpointSlice, `can-i` |
| 9 | `bash $L headlamp` | UI con il pod senza permessi, URL e token di 8 ore |
| 10 | `bash $L certificati` | gli IP nei SAN devono comprendere `192.168.1.79` |
| — | `nota` | curl dal Mac; `bash … smonta` per smontare |

Il passo 5 è un buon esempio: per sapere **se** un Secret ha le chiavi giuste si guardano le chiavi, mai i valori.

---

## 11. Trappole

- **Snap che si aggiorna da solo**: senza `snap refresh --hold` il cluster cambia versione sotto i piedi.
- **Gruppo `microk8s`** attivo solo dopo `newgrp` o una nuova login.
- **`hostpath-storage` lega i dati al nodo**: con più nodi il Pod spostato non trova più il suo disco.
- **IngressClass diversa**: `public` su MicroK8s, non `nginx`. Un Ingress con la classe sbagliata non lo serve nessuno.
- **Cambio IP del nodo** → certificati con SAN vecchi; `exec`/`logs` rotti anche se `kubectl get` (via `server.crt`
  rigenerato) va.
- **Chart con `cluster-admin` sul pod della UI**: default di molti chart, privilege escalation pronta.
- **Token che non scade** in un Secret `service-account-token`.
- **Elasticsearch `security off` e `single-node`**: comodi in lab, mai in produzione.
- **Rilanciare `dati`** rigenera le password del Secret ma non quelle già scritte nel PVC di MariaDB.

---

## 12. Domande da colloquio

- **Perché MariaDB è uno StatefulSet e PHP un Deployment?** Il DB ha identità e disco suoi: nome stabile
  (`mariadb-0`), PVC che lo segue a ogni riavvio, avvio e stop ordinati. Le repliche PHP sono intercambiabili: nessuno
  stato locale, si scalano e si sostituiscono.
- **Le 3 repliche PHP condividono le sessioni utente?** Solo se le sessioni non stanno nel filesystem del pod. Qui
  andrebbero in Redis (`session.save_handler=redis`), altrimenti ogni richiesta che cambia pod perde il login. Le
  sticky session sull'ingress mascherano il problema invece di risolverlo.
- **Redis come Deployment senza volume: se il pod muore?** Riparte vuoto. Per una cache va bene, per code o sessioni
  importanti no: StatefulSet + PVC + AOF, o un Redis gestito.
- **MicroK8s a un nodo con hostpath-storage: cosa non hai?** Né HA né storage che segua i pod: il PV è una cartella su
  quel nodo. Con 3 nodi il control plane diventa HA da solo (dqlite), ma i dati restano legati al nodo finché non metti
  uno storage di rete.
- **Headlamp, Dashboard, Lens: dove stanno i permessi?** Nel token con cui l'utente entra, non nel pod della UI. Il pod
  con `cluster-admin` è un privilege escalation pronto: chi raggiunge la UI raggiunge il cluster.
- **Il futuro di ingress-nginx?** Il progetto della comunità Kubernetes è in ritiro (manutenzione fino a marzo 2026). Le
  strade: Gateway API con un'implementazione (Envoy Gateway, Traefik, NGINX Gateway Fabric) o un controller Ingress
  mantenuto (Traefik, HAProxy). Su k3s Traefik c'è già.

### Comandi da sapere

| Comando | A cosa serve |
|---|---|
| `microk8s status --wait-ready` | aspetta che il cluster sia pronto |
| `microk8s enable <addon>` | accende un addon |
| `sudo snap refresh --hold microk8s` | blocca gli aggiornamenti |
| `kubectl create … --dry-run=client -o yaml \| kubectl apply -f -` | `create` reso idempotente |
| `kubectl create token <sa> --duration=8h` | token a tempo, senza Secret |
| `kubectl auth can-i <verbo> <risorsa> --as=system:serviceaccount:ns:sa` | cosa può fare un'identità |
| `kubectl get endpointslices -l kubernetes.io/service-name=<svc>` | i Pod dietro un Service |
| `openssl x509 -in <crt> -noout -ext subjectAltName` | gli IP/nomi validi per un certificato |

---

## Riepilogo

- minikube = cluster usa e getta in un container; MicroK8s = snap con addon e HA via dqlite; k3s = binario unico per
  edge. Stessa API.
- Dati: StatefulSet + PVC + Secret; app stateless: Deployment × 3 dietro Service e Ingress (classe `public` su MicroK8s).
- Headlamp: pod senza permessi, token a tempo di un SA con `view`.
- Cambio IP del nodo → SAN dei certificati: `server.crt` e `kubelet.crt`.
- `snap refresh --hold`: un cluster non si aggiorna da solo in produzione.

## Prova da solo

1. Scala `php-app` a 5 repliche (`microk8s kubectl -n stack scale deploy/php-app --replicas=5`) e rilancia
   `verifica`: quanti nomi di Pod diversi vedi? E quanti indirizzi nell'EndpointSlice?
2. Cancella il Pod di Redis e rilancia `verifica`: da che numero riparte `redis_visite`? Poi cancella `mariadb-0`:
   il PVC `dati-mariadb-0` è ancora lì? È lo stesso di prima?
3. Crea un ServiceAccount `headlamp-scrittore` con un Role nel **solo** namespace `stack` che permette `update` sui
   Deployment, e verifica con `auth can-i` che può scalare `php-app` ma non toccare niente in `kube-system`.

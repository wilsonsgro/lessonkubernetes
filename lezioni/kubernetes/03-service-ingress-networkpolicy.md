# 03 — Rete: Service, Ingress e NetworkPolicy

Spiegazione di `03-service-ingress-networkpolicy.yaml` (questa cartella). Lezione sul sito: http://127.0.0.1:3000/kubernetes/3

## In una frase

Il file mette **davanti al Deployment `web` della lezione 02** un **Service** (nome e IP stabili), un **Ingress**
(ingresso HTTP dall'esterno su `web.lab.local`) e **due NetworkPolicy** (tutto chiuso, poi aperto solo a chi ha la label
`ruolo=client` e al controller ingress). Il runner prova che un Pod autorizzato passa e che un Pod "intruso" no.

## Due file con lo stesso nome: quale lanciare

| File | Che cos'è | Come si usa |
|---|---|---|
| `~/kubernetesprj/lezioni/kubernetes/03-service-ingress-networkpolicy.yaml` | **questo**: i manifest, con la teoria nei commenti | si **legge**; lo applica il runner (o a mano: `kubectl apply -f 03-service-ingress-networkpolicy.yaml`) |
| `~/kubernetesprj/kubernetes/03-service-ingress-networkpolicy.sh` | lo script **guidato**: applica e prova Service, Ingress e policy, un passo per volta (Invio / s / q) | `bash kubernetes/03-service-ingress-networkpolicy.sh` |

**Prerequisito**: la lezione 02 applicata (il Deployment `web` nel namespace `lab` deve esistere).

## Com'è fatto il file

```
intestazione (commenti)  → teoria: Service, ClusterIP, tipi di Service, DNS, comandi LAB, NEL PROGETTO VERO
Service web              → ClusterIP sulla porta 80 → porta "http" dei Pod
Ingress web              → host web.lab.local, path / → Service web
NetworkPolicy default-deny-ingress → chiude l'ingresso a tutti i Pod del namespace
NetworkPolicy web-allow  → riapre web a ruolo=client e al namespace ingress-nginx
commenti                 → la trappola dell'indentazione AND/OR, l'egress e il DNS
coda (commenti)          → domande da colloquio, riepilogo
```

Versioni: Kubernetes 1.34–1.35 (lab 1.34.0), ingress-nginx come addon minikube, Calico come CNI.

---

## 1. La teoria nell'intestazione

### Perché serve un Service

I Pod sono **effimeri** e cambiano IP a ogni ricreazione. Un **Service** dà un **nome DNS** e un **IP virtuale stabili**
davanti a un insieme di Pod, scelto per **label**:

```
Service ──selector──▶ EndpointSlice (IP dei Pod PRONTI) ◀── kube-proxy
```

- Il controller degli EndpointSlice mette dentro **solo i Pod pronti** (readiness probe superata, lezione 02).
- **kube-proxy** su ogni nodo legge gli EndpointSlice e scrive le regole di rete.

### Il ClusterIP non esiste

Il ClusterIP non è assegnato a nessuna interfaccia: è una **regola** iptables / IPVS / nftables che kube-proxy scrive su
ogni nodo e che fa **DNAT** verso un Pod a caso. Per questo **`ping` a un ClusterIP non risponde** (non c'è nessuno
che risponde all'ICMP), mentre `curl` sulla porta del Service sì.

### Tipi di Service

| Tipo | Cosa aggiunge |
|---|---|
| `ClusterIP` | solo dentro il cluster (default) |
| `NodePort` | + una porta **30000-32767** su **ogni** nodo |
| `LoadBalancer` | + un LB esterno del cloud (in locale: MetalLB, `minikube tunnel`) |
| `ExternalName` | un **CNAME** DNS, niente proxy |
| headless | `clusterIP: None` → il DNS restituisce **gli IP dei Pod** (StatefulSet, lezione 05) |

### DNS

Nome completo: `<service>.<namespace>.svc.cluster.local`. Da un Pod in `lab` basta `web`; da un altro namespace
`web.lab`. Per questo i Pod del runner fanno semplicemente `curl web/api`.

### I comandi LAB e il perché dello `sleep`

```bash
kubectl apply -f 03-service-ingress-networkpolicy.yaml
kubectl -n lab get endpointslices -l kubernetes.io/service-name=web
kubectl -n lab run curl --rm -it --image=curlimages/curl:8.23.0 \
    --labels=ruolo=client -- sh -c 'sleep 8; curl -s web/api'      # passa
kubectl -n lab run intruso --rm -it --image=curlimages/curl:8.23.0 \
    -- sh -c 'sleep 8; curl -s -m 3 web/api'                        # bloccato
curl -H 'Host: web.lab.local' http://$(minikube -p lab ip)/api
```

Lo `sleep 8` prima del `curl`: il CNI **impara l'IP di un Pod appena nato con qualche secondo di ritardo**. Senza lo
sleep anche il client **autorizzato** viene bloccato (il file dice: provato su k3s). La lezione per la produzione: un
Pod che chiama una dipendenza al primo istante deve **riprovare**, non morire al primo errore.

### Riquadro «NEL PROGETTO VERO»

In `~/biodistretto/kubernetes` (branch `kubernetes`) **non c'è Ingress**: davanti al cluster c'è **HAProxy sull'host**
(lezione 15), che entra dal Service `nginx` di tipo **NodePort** sulle porte **30080, 30443, 30081**.

```bash
grep -n -A3 'type: NodePort' terraform/app/manifests/app.yaml.tftpl
```

`externalTrafficPolicy: Local` fa sì che un nodo **senza** nginx risponda picche: così il controllo di salute di HAProxy
è davvero per singolo nodo. Senza, kube-proxy girerebbe la richiesta all'altro nodo e **ogni nodo sembrerebbe sano**.
In più conserva l'IP del client.

I servizi interni si trovano per **nome breve** (mariadb, redis…):

```bash
grep -n -E 'DB_HOST|REDIS_HOST' terraform/app/config.tf
```

**Esercizio del riquadro**: il progetto non ha NetworkPolicy. Scrivine una che lasci arrivare a mariadb solo backend e
worker, poi provala con il client "intruso". Prima controlla che **kindnet** (il CNI del progetto) la applichi davvero.

---

## 2. Il Service `web`

```yaml
spec:
  type: ClusterIP
  selector:
    app.kubernetes.io/name: web
  ports:
    - name: http
      port: 80
      targetPort: http
```

| Campo | Valore | Perché |
|---|---|---|
| `type` | `ClusterIP` | raggiungibile solo dall'interno; dall'esterno si passa dall'Ingress |
| `selector` | `app.kubernetes.io/name: web` | **deve combaciare** con le label del pod template della lezione 02. Se sbagli una lettera gli EndpointSlice restano vuoti |
| `ports[].port` | `80` | la porta **del Service**: chi chiama fa `web:80` (o semplicemente `web`) |
| `ports[].targetPort` | `http` | il **nome** della porta nel container (che è la 8080). Se un giorno la porta del container cambia numero ma tiene il nome, il Service non si rompe |

---

## 3. L'Ingress `web`

**Ingress = regole L7** (host, path, TLS). **Da solo non fa niente**: serve un **Ingress Controller** (ingress-nginx,
Traefik, HAProxy Ingress…) scelto con `ingressClassName`. Nel lab è l'addon `ingress` di minikube (lezione 01).

```yaml
spec:
  ingressClassName: nginx
  rules:
    - host: web.lab.local
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: web
                port:
                  name: http
```

| Campo | Valore | Cosa fa |
|---|---|---|
| `ingressClassName` | `nginx` | quale controller deve servire questa regola |
| `host` | `web.lab.local` | il controller sceglie il backend guardando l'header **Host** della richiesta |
| `path` + `pathType` | `/` + `Prefix` | tutto ciò che comincia con `/`. Altri valori: `Exact`, `ImplementationSpecific` |
| `backend.service` | `web`, porta `http` | il Service della sezione 2, indicato per **nome di porta** del Service |

Il nome host non esiste in nessun DNS: per questo il runner fa `curl -H 'Host: web.lab.local'` verso l'IP del nodo
(`minikube -p lab ip`).

**Il successore è la Gateway API** (GatewayClass, Gateway, HTTPRoute): ruoli separati fra chi gestisce il LB e chi
l'app, pesi per il canary, header matching standard senza annotazioni del vendor. Il file avverte che il progetto
**ingress-nginx è stato ritirato** (manutenzione finita a marzo 2026): nei progetti nuovi si sceglie Gateway API o
Traefik. Nel lab lo si usa perché è l'addon pronto di minikube.

---

## 4. Le NetworkPolicy

### Le regole del gioco

- **Di default tutto parla con tutto.**
- Le policy sono **additive**: contengono solo "allow", mai "deny".
- Appena **una** policy seleziona un Pod per `Ingress`, quel Pod accetta **solo** ciò che qualche policy permette.
- Le **applica il CNI**: con un CNI che non le supporta l'`apply` riesce e **non succede niente**. Per questo il lab usa
  **Calico**.

### Policy 1 — `default-deny-ingress`

```yaml
spec:
  podSelector: {}
  policyTypes: [Ingress]
```

`podSelector: {}` = **tutti i Pod del namespace**. `policyTypes: [Ingress]` senza nessuna regola `ingress:` = nessuno
può entrare. Da qui in poi ogni Pod di `lab` è chiuso in ingresso, finché un'altra policy non apre.

### Policy 2 — `web-allow`

```yaml
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: web
  policyTypes: [Ingress]
  ingress:
    - from:
        - podSelector:
            matchLabels:
              ruolo: client
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: ingress-nginx
      ports:
        - port: http
```

| Parte | Significato |
|---|---|
| `podSelector` in cima | a **chi** si applica: i Pod `web` |
| `from` con **due elementi** | **OR**: entra chi ha `ruolo=client` (nello **stesso** namespace `lab`, perché un `podSelector` da solo guarda il namespace della policy) **oppure** qualunque Pod del namespace `ingress-nginx` |
| `kubernetes.io/metadata.name` | label che Kubernetes mette da solo su ogni Namespace con il suo nome: comoda per selezionarlo |
| `ports: - port: http` | la porta **del Pod** (8080, per nome), **non** quella del Service (80). La policy vede il traffico dopo il DNAT |

Senza il ramo `ingress-nginx`, l'Ingress smetterebbe di funzionare: il controller è un Pod in un altro namespace e il
default deny lo bloccherebbe.

### La trappola dell'indentazione

```yaml
- namespaceSelector: {...}       ← UN elemento con DUE condizioni = AND
  podSelector: {...}               (quei Pod DENTRO quel namespace)

- namespaceSelector: {...}       ← DUE elementi = OR
- podSelector: {...}
```

Un trattino in più o in meno cambia completamente chi entra, e l'apply non dà errori in nessuno dei due casi.

### Egress e DNS

Se aggiungi un **default deny in uscita**, ricordati del **DNS**, altrimenti niente risolve più niente:

```yaml
egress:
  - to: [{ namespaceSelector: {}, podSelector: { matchLabels: { k8s-app: kube-dns } } }]
    ports: [{ port: 53, protocol: UDP }, { port: 53, protocol: TCP }]
```

Qui `namespaceSelector: {}` e `podSelector` stanno nello **stesso** elemento: AND = "i Pod `kube-dns` in qualunque
namespace". Questo blocco nel file è solo un commento: non viene applicato.

---

## 5. Il runner, passo per passo

`guardia_lab`, poi 6 passi:

| # | Comando | Cosa vedi |
|---|---|---|
| 1 | `kubectl apply -f …/03-service-ingress-networkpolicy.yaml` | `service/web`, `ingress.networking.k8s.io/web`, `networkpolicy…/default-deny-ingress`, `…/web-allow` creati |
| 2 | `kubectl -n lab get endpointslices -l kubernetes.io/service-name=web` | un EndpointSlice con i **3 IP** dei Pod web sulla porta 8080. Vuoto = selector sbagliato o Pod non ready |
| 3 | `kubectl -n lab run curl --rm -i --quiet --restart=Never --image=curlimages/curl:8.23.0 --labels=ruolo=client -- sh -c 'sleep 8; curl -s web/api'` | **passa**: la risposta JSON di whoami (`/api`) |
| 4 | `kubectl -n lab describe networkpolicy web-allow \| sed -n "/Allowing ingress/,/Allowing egress/p"` | la sezione "Allowing ingress traffic": porta `http`, da `ruolo=client` **oppure** dal namespace `ingress-nginx` |
| 5 | `kubectl -n lab run intruso … -- sh -c 'sleep 8; curl -s -m 3 web/api; echo uscita=\$?'` | **fallisce apposta**: niente risposta, dopo 3 s (`-m 3`) curl si arrende e stampa `uscita=28` (il codice di timeout di curl) |
| 6 | `curl -s -H 'Host: web.lab.local' http://$(minikube -p lab ip)/api` | dall'host, attraverso l'Ingress: risponde whoami. Passa perché il controller sta nel namespace `ingress-nginx` |

Note sulle opzioni di `kubectl run` usate dal runner (diverse dall'intestazione, che usa `-it`):

- `--rm` cancella il Pod alla fine; `--restart=Never` crea un Pod semplice (non riavviato);
- `-i` collega lo stdin senza TTY e `--quiet` toglie i messaggi di kubectl: l'output è solo quello del curl.

Il passo 5 è il fallimento **voluto**: dimostra la policy. Il riquadro rosso di `passo` (uscita ≠ 0) qui di solito non
compare, perché l'ultimo comando dello `sh -c` è `echo`, che esce 0: il fallimento lo leggi in `uscita=28`.

---

## 6. Le trappole

| Trappola | Cosa succede | Rimedio |
|---|---|---|
| selector del Service che non combacia | EndpointSlice vuoti, connessione rifiutata | confronta `selector` e label del template |
| `targetPort` sbagliata | il Service inoltra a una porta chiusa | usa il **nome** della porta |
| CNI senza supporto NetworkPolicy | l'apply va, ma **non blocca niente** | provare sempre con un "intruso" |
| `ports` della policy col numero del Service (80) | traffico bloccato | la porta è quella **del Pod** |
| AND/OR confusi nell'indentazione | entra chi non dovrebbe (o nessuno) | un elemento = AND, due elementi = OR |
| deny in uscita senza DNS | nessun nome risolve | regola egress verso `kube-dns` porta 53 UDP+TCP |
| default deny senza aprire al controller ingress | l'Ingress smette di rispondere | `namespaceSelector` su `ingress-nginx` |
| client che chiama subito all'avvio | bloccato finché il CNI non ha imparato l'IP | retry (nel lab: `sleep 8`) |

---

## 7. La coda: domande da colloquio

- **Un Service non risponde. Ordine dei controlli?** 1) `kubectl get endpointslices`: vuoti → selector sbagliato o Pod
  non ready. 2) `targetPort` giusta? 3) dal Pod: `curl` su `localhost:porta`. 4) DNS: `nslookup web.lab` da un Pod.
  5) NetworkPolicy che blocca.
- **`externalTrafficPolicy: Local` vs `Cluster`?** `Cluster` (default): ogni nodo inoltra a qualunque Pod, con SNAT →
  il Pod vede l'IP del nodo, non del client. `Local`: solo ai Pod del nodo, IP del client preservato, ma i nodi senza
  Pod falliscono l'health check del LB e il carico può sbilanciarsi.
- **Ingress vs Service LoadBalancer?** LoadBalancer = un LB (e un IP, e un costo) per Service, L4. Ingress = un solo LB
  L7 per molti Service, con host/path e TLS.
- **Perché un Pod pronto non riceve traffico subito dopo un rollout?** Propagazione: EndpointSlice → kube-proxy su ogni
  nodo → regole. Sono secondi, ed è lo stesso ritardo che rende necessario il `preStop` allo spegnimento (lezione 02).

### Comandi da sapere

| Comando | A cosa serve |
|---|---|
| `kubectl -n lab get endpointslices -l kubernetes.io/service-name=web` | chi c'è davvero dietro il Service |
| `kubectl -n lab describe networkpolicy web-allow` | chi può entrare, letto come lo legge Kubernetes |
| `kubectl -n lab run … --labels=ruolo=client …` | Pod di prova con una label precisa |
| `curl -H 'Host: web.lab.local' http://$(minikube -p lab ip)/api` | provare un Ingress senza DNS |

---

## Riepilogo

- **Service** = nome + IP virtuale stabile; i Pod li sceglie il **selector**.
- **EndpointSlice** contiene solo i Pod **pronti** (readiness).
- **Ingress** = regole L7, serve un **controller**; il futuro è la **Gateway API**.
- **NetworkPolicy** additive, applicate dal **CNI**; schema: default deny + allow.
- `podSelector` e `namespaceSelector`: **stesso elemento = AND, due elementi = OR**.

## Prova da solo

1. Cambia il `selector` del Service in `app.kubernetes.io/name: webx`, riapplica e guarda gli EndpointSlice. Poi
   ripeti il passo 3 del runner: che errore dà curl? Rimetti il selector giusto.
2. Togli il ramo `namespaceSelector` da `web-allow`, riapplica e ripeti il curl con `-H 'Host: web.lab.local'`
   dall'host: cosa succede all'Ingress, e perché?
3. Riscrivi il `from` di `web-allow` come **un solo elemento** con `namespaceSelector` + `podSelector` (AND) e prova
   sia il Pod `curl` con `ruolo=client` sia l'Ingress: chi passa adesso?

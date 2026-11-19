# 19 — DNS e service discovery: dal nome all'IP, passo per passo

Spiegazione di `19-dns-service-discovery.yaml` (questa cartella).

## In una frase

Il file crea un namespace `lab-dns` con un Service `web` (2 Pod whoami), un Service `vuoto` senza Pod e due Pod
"cassetta degli attrezzi" (`netshoot`: dig, tcpdump, curl), uno con `ndots:5` e uno con `ndots:1`. Con questi segui la
**catena completa** da `curl http://web` fino al Pod: `resolv.conf` → CoreDNS → ClusterIP → regole di kube-proxy →
EndpointSlice. E misuri il **costo nascosto di `ndots:5`**.

## Due file con lo stesso nome: quale lanciare

| File | Che cos'è | Come si usa |
|---|---|---|
| `~/kubernetesprj/lezioni/kubernetes/19-dns-service-discovery.yaml` | **questo**: i manifest, con la teoria nei commenti | `kubectl apply -f 19-dns-service-discovery.yaml` (ma conviene il guidato) |
| `~/kubernetesprj/kubernetes/19-dns-service-discovery.sh` | lo script **guidato**: applica il file e fa le misure una per volta, spiegando prima di eseguire (Invio / s / q) | `bash kubernetes/19-dns-service-discovery.sh` |

Per imparare conviene lo **guidato**. Questo file va **letto** mentre lo guidato gira: i commenti spiegano il perché.

Versione dichiarata: **Kubernetes 1.34–1.35** (il lab minikube gira la **1.34.0**). Livello 1 — Workload.

## Com'è fatto il file

```
intestazione (commenti)  → service discovery, la catena nome→Pod, resolv.conf misurato, i nomi,
                            ndots:5 misurato, rimedi, trappole degli strumenti, dnsPolicy, LAB, NEL PROGETTO VERO
Namespace lab-dns
Deployment web           → 2 repliche whoami, porta con nome http
Service web              → porta con nome "http" → record SRV
Service vuoto            → selector che non combacia: zero endpoint
Pod rete                 → netshoot, ndots di default (5)
Pod rete-ndots1          → netshoot, dnsConfig ndots "1"
coda (commenti)          → domande da colloquio, riepilogo
```

---

## 1. La teoria nell'intestazione

### Service discovery = registrazione + ricerca

In Kubernetes la **registrazione è automatica**: crei un Service, e CoreDNS (che osserva l'apiserver) pubblica il suo
nome. Il client deve solo sapere il nome.

### La catena completa, da `curl http://api` al Pod

1. Il container legge `/etc/resolv.conf` (lo scrive il **kubelet**).
2. Chiede a **CoreDNS** (Service `kube-dns` in `kube-system`, nel lab `10.96.0.10`).
3. CoreDNS risponde con il **ClusterIP** del Service.
4. Il pacchetto verso il ClusterIP viene **riscritto sul nodo da kube-proxy** (regole iptables; nel lab `mode ""` =
   iptables) verso l'IP di un Pod preso dalle **EndpointSlice**.

Il ClusterIP **non è di nessuna interfaccia**: esiste solo nelle regole NAT. Per questo un **ping al ClusterIP non
risponde**, mentre la porta sì.

### Il `resolv.conf` di un Pod (misurato nel lab, namespace `lab`)

```
nameserver 10.96.0.10
search lab.svc.cluster.local svc.cluster.local cluster.local nexxt
options ndots:5
```

| Riga | Da dove viene |
|---|---|
| `nameserver` | il ClusterIP di `kube-dns` |
| `lab.svc.cluster.local` `svc.cluster.local` `cluster.local` | le mette Kubernetes, a partire dal **namespace del Pod** |
| `nexxt` | il dominio di ricerca della **rete di casa**: il nodo lo eredita dall'host e il kubelet lo passa ai Pod |
| `ndots:5` | la soglia di punti sotto la quale si prova prima la search list |

### I nomi

| Nome | Quando |
|---|---|
| `api` | stesso namespace |
| `api.prod` | un altro namespace (basta questo) |
| `api.prod.svc.cluster.local` | nome completo (FQDN) |
| `api.prod.svc.cluster.local.` | FQDN **assoluto**: il punto finale salta la search list |
| `db-0.db.prod.svc.cluster.local` | un Pod di uno StatefulSet dietro un Service headless (lezione 05) |
| `_http._tcp.api.prod.svc.cluster.local` | record **SRV** della porta di nome `http` |

### `ndots:5`, il costo nascosto

Un nome con **meno di 5 punti** viene provato prima con **ogni** search domain, e solo alla fine come assoluto.
`example.com` (1 punto) dal namespace `verifica` ha prodotto, misurato con tcpdump nel lab, **5 domande A**:

```
example.com.verifica.svc.cluster.local.   NXDOMAIN
example.com.svc.cluster.local.            NXDOMAIN
example.com.cluster.local.                NXDOMAIN
example.com.nexxt.                        (esce dal cluster!)
example.com.                              ← quella giusta
```

e altrettante **AAAA**: **10 domande per un nome solo** (curl, resolver musl). Con `example.com.` (punto finale): una A
e una AAAA, e basta. Il penultimo tentativo va al DNS della rete di casa: **una perdita di informazioni e un ritardo**,
non solo traffico.

Vale anche per i nomi interni: `web.lab-dns.svc.cluster.local` ha **4 punti**, meno di 5. Dal log di CoreDNS nel lab,
prima della risposta giusta (**0,2 ms**) sono passate `…cluster.local.cluster.local` e `…nexxt`: quest'ultima è uscita
verso il router di casa e ha impiegato **280 ms**.

**Rimedi**, dal più al meno locale:

- nomi esterni scritti **con il punto finale** nella config dell'app;
- `spec.dnsConfig.options` `ndots: "1"` o `"2"` per i Pod che chiamano soprattutto fuori. Con `ndots:1`, misurato,
  `web.lab-dns` si risolve ancora: il resolver prova prima `web.lab-dns.` assoluto, fallisce, poi passa alla search
  list. Una domanda sprecata per i nomi interni;
- **NodeLocal DNSCache**, cache sul nodo, nei cluster grandi.

### Trappole degli strumenti

- **`nslookup` di busybox** non è affidabile con i nomi corti: misurato, `nslookup web` stampa
  `can't find web.nexxt: NXDOMAIN` (il fallimento sull'ultima voce della search) mentre `wget` nello stesso container
  risolve. Si prova con il nome completo, o con `dig +search`.
- **`dig` senza `+search`** ignora la search list; il resolver dell'app (glibc, musl) la usa con regole sue. Si misura
  con il programma vero.
- **Il DNS risponde anche per un Service SENZA Pod**: il nome c'è, la connessione no. "Risolve" non vuol dire
  "funziona". Misurato: **rifiuto immediato** (curl exit 7), perché kube-proxy mette una regola **REJECT** per i
  Service senza endpoint; non un timeout.
- **Endpoints è deprecato dalla 1.33** (warning nel lab): si guardano le **EndpointSlice** (label
  `kubernetes.io/service-name`).
- Un Pod con **`hostNetwork: true`** usa il DNS del nodo e **non trova i Service**, a meno di
  `dnsPolicy: ClusterFirstWithHostNet`.
- Nel lab il Corefile ha il plugin **`log`**: ogni domanda compare anche in `kubectl -n kube-system logs deploy/coredns`.
- Nel lab CoreDNS ha **una** replica: se cade, cade la risoluzione di tutto il cluster. In produzione almeno 2, con
  anti-affinity e PDB.

### `dnsPolicy`

| Valore | Cosa usa |
|---|---|
| `ClusterFirst` (default) | CoreDNS, poi i nomi esterni inoltrati |
| `ClusterFirstWithHostNet` | come sopra, per Pod con `hostNetwork` |
| `Default` | il `resolv.conf` del **nodo** (nome ingannevole: non è il default) |
| `None` | solo quello che metti in `dnsConfig` |

### Riquadro «NEL PROGETTO VERO»

In `~/biodistretto/kubernetes` (branch `kubernetes`) c'è un caso che **il solo DNS non risolve**. Laravel chiama sé
stesso all'indirizzo pubblico (`https://www.biodistretto.lab`), ma dentro il Pod quel nome non esiste. Soluzione:
**`hostAliases`** verso il ClusterIP di nginx, che per questo è **fissato**:

```bash
grep -n -A2 'hostAliases' terraform/app/manifests/app.yaml.tftpl
grep -n -A3 'variable "ip_nginx"' terraform/app/variables.tf
```

In alternativa: una regola **rewrite di CoreDNS** per `*.biodistretto.lab`. Vale per tutto il cluster ed è più comoda,
però tocca `kube-system`. Il resto usa il nome breve del Service, nello stesso namespace:

```bash
grep -n -E 'REDIS_HOST|ELASTICSEARCH_HOST|MINIO' terraform/app/config.tf
```

`hostAliases` scrive righe in `/etc/hosts` del Pod: per questo serve un IP che non cambi.

---

## 2. I manifest

### Deployment `web`

```yaml
kind: Deployment
metadata: { name: web, namespace: lab-dns }
spec:
  replicas: 2
  template:
    metadata:
      labels: { app: web }
    spec:
      containers:
        - name: app
          image: traefik/whoami:v1.12
          ports:
            - { name: http, containerPort: 80 }
          resources:
            requests: { cpu: 5m, memory: 16Mi }
            limits: { memory: 32Mi }
```

Due repliche: l'EndpointSlice avrà **due** IP, e sul nodo vedrai **due** regole `KUBE-SEP` (una per Pod).

### Service `web`

```yaml
kind: Service
metadata: { name: web, namespace: lab-dns }
spec:
  selector: { app: web }
  ports:
    - { name: http, port: 80, targetPort: http }   # il nome genera il record SRV
```

- `name: http` della porta: CoreDNS pubblica il record SRV `_http._tcp.web.lab-dns.svc.cluster.local`, che dice al
  client anche **la porta**.
- `targetPort: http` punta alla porta del container **per nome**.

### Service `vuoto`

```yaml
kind: Service
metadata:
  name: vuoto                    # nessun Pod ha app=nessuno: zero endpoint
  namespace: lab-dns
spec:
  selector: { app: nessuno }
  ports:
    - port: 80
```

Ha un nome DNS e un ClusterIP, ma **nessun backend**. Serve a dimostrare che "risolve" non vuol dire "funziona".

### Pod `rete` e `rete-ndots1`: la cassetta degli attrezzi

```yaml
kind: Pod
metadata: { name: rete, namespace: lab-dns }
spec:
  containers:
    - name: c
      image: nicolaka/netshoot:v0.13
      command: ["sleep", "infinity"]
      resources:
        requests: { cpu: 5m, memory: 32Mi }
        limits: { memory: 128Mi }
---
kind: Pod
metadata: { name: rete-ndots1, namespace: lab-dns }
spec:
  dnsConfig:
    options:
      - { name: ndots, value: "1" }
  containers:
    - name: c
      … stessa immagine e comando
```

- `netshoot` contiene `dig`, `tcpdump`, `curl`. `sleep infinity` tiene il Pod acceso per farci `exec`.
- `dnsConfig.options` **si aggiunge** al `resolv.conf` generato (con `dnsPolicy` di default `ClusterFirst`): la search
  list resta, cambia solo `ndots`.

---

## 3. Il runner, passo per passo

Nel runner `X='kubectl -n lab-dns exec rete --'`: quasi tutti i comandi girano nel Pod `rete`.

| # | Passo | Cosa vedi |
|---|---|---|
| — | `guardia_lab` | lo script si ferma se il contesto non è `lab` |
| 1 | `kubectl -n kube-system get deploy,svc,endpointslices -l k8s-app=kube-dns` | chi fa il DNS: Deployment `coredns`, Service `kube-dns` (IP fisso), tutti con label `k8s-app=kube-dns` |
| — | `nota` | nel lab CoreDNS ha **una** replica; in produzione ≥2, anti-affinity, PDB |
| 2 | `get cm coredns -o jsonpath="{.data.Corefile}"` | il **Corefile**: plugin `kubernetes` per `cluster.local`, `forward` al DNS del nodo per il resto (e il plugin `log`) |
| 3 | `apply -f $F`, `rollout status deploy/web`, `wait … pod/rete pod/rete-ndots1` | il namespace pronto |
| 4 | `$X cat /etc/resolv.conf` + ClusterIP di `kube-dns` | `nameserver` = ClusterIP di kube-dns, search costruita da `lab-dns`, `ndots:5` |
| — | `nota` | l'ultima voce di search (se c'è) arriva dall'host: il dominio della rete di casa |
| 5 | ciclo su `web`, `web.lab-dns`, `web.lab-dns.svc.cluster.local` con `dig +search +short` | i tre modi di chiamare lo stesso Service danno **lo stesso ClusterIP**, confrontato con `get svc web` |
| 6 | `$X dig +short SRV _http._tcp.web.lab-dns.svc.cluster.local` | il record SRV: anche la **porta** (80) |
| 7 | tcpdump su `udp port 53` mentre `curl http://example.com`, poi `grep -oE "(A\|AAAA)\? …" \| sort \| uniq -c` | le domande di `ndots:5`: `example.com` provato con ogni search domain, A e AAAA |
| 8 | lo stesso con `http://example.com./` e `-H "Host: example.com"` | col punto finale: **una A e una AAAA**, niente search list. L'header `Host` forza il nome senza punto verso il server web, così cambia solo la risoluzione DNS |
| 9 | in `rete-ndots1`: `grep options`, tcpdump, `curl example.com` e `curl web.lab-dns` | `ndots:1`: `example.com` va diretto; `web.lab-dns` risolve ancora, ma prova prima `web.lab-dns.` assoluto |
| 10 | `kubectl run bb --rm -i … busybox:1.37 -- sh -c '… nslookup web …; wget -qO- -T 3 http://web'` | **trappola degli strumenti**: `nslookup` dà NXDOMAIN sul nome corto, `wget` nello stesso container risolve e risponde |
| 11 | `get endpointslices -l kubernetes.io/service-name=web` + IP dei Pod | dietro il nome: l'EndpointSlice elenca gli IP dei **Pod pronti**, gli stessi di `get pods` |
| 12 | `kubectl -n lab-dns get endpoints web` | la vecchia API: funziona ancora ma stampa il **warning** di deprecazione |
| 13 | `dig vuoto`, EndpointSlice di `vuoto`, `curl -s -m 3 http://vuoto` | **fallisce apposta (uscita 7)**: il nome e l'IP ci sono, l'EndpointSlice è vuota, kube-proxy **rifiuta subito** (connessione rifiutata, non timeout) |
| 14 | `curl … -w "porta 80: HTTP %{http_code}"` e `ping -c 2` al ClusterIP | la porta 80 risponde con un codice HTTP, il ping **no**: il ClusterIP non è l'IP di nessuna interfaccia |
| 15 | `mode` dalla ConfigMap `kube-proxy`, poi `minikube -p lab ssh -- sudo iptables -t nat -S \| grep 'lab-dns/web'` | modalità vuota = iptables; le catene **KUBE-SVC** (il Service) e **KUBE-SEP** (una per Pod) sul nodo |
| 16 | `run hn` con `hostNetwork: true`, `head -3 /etc/resolv.conf`, `wget` al FQDN di `web` | **fallisce apposta**: il Pod usa il DNS del nodo e il nome `web.lab-dns.svc.cluster.local` non esiste |
| 17 | `run hn2` con `hostNetwork: true` e `dnsPolicy: ClusterFirstWithHostNet` | il `nameserver` torna quello di CoreDNS e `wget` risponde |
| 18 | `kubectl -n kube-system logs deploy/coredns --since=5m \| grep -E "example.com\|web.lab-dns"` | le stesse domande viste da CoreDNS (grazie al plugin `log`), con i NXDOMAIN e i tempi |
| 19 | `kubectl delete ns lab-dns` | pulizia |

Due tecniche da notare nei passi 7–9:

- `tcpdump … -l … > /tmp/q &` parte in background, `sleep 1` gli dà il tempo di aprire l'interfaccia, poi il comando
  vero, poi `kill %1`. Il conteggio con `uniq -c` mostra quante volte è stata fatta ogni domanda.
- Si misura con **curl**, cioè con il resolver che userebbe un'applicazione, non con `dig` (che ha regole sue).

E nei passi 10, 16, 17: `kubectl run … --rm -i --restart=Never` crea un Pod usa e getta, ne mostra l'output e lo
cancella. `--overrides` aggiunge campi dello spec che `run` non ha come opzioni.

---

## 4. Trappole

- **`ndots:5` e nomi esterni**: 10 domande per `example.com`, una delle quali esce verso il DNS di casa.
- **Nomi interni FQDN senza punto finale**: `web.lab-dns.svc.cluster.local` ha 4 punti, passa comunque dalla search list.
- **Diagnosticare con lo strumento sbagliato**: `nslookup` di busybox e `dig` senza `+search` non si comportano come
  il resolver dell'app.
- **Risolve ≠ funziona**: un Service senza endpoint ha nome e IP; la connessione è rifiutata.
- **Ping al ClusterIP** come prova: non risponde mai, non vuol dire niente.
- **`kubectl get endpoints`**: deprecato, usa le EndpointSlice.
- **`hostNetwork: true`** senza `ClusterFirstWithHostNet`: i Service non si trovano.
- **`dnsPolicy: Default`** non è il default: usa il DNS del nodo.
- **CoreDNS a una replica**: un solo punto di rottura per tutto il cluster.

---

## 5. Comandi e domande da colloquio

### Comandi (dalla sezione LAB del file)

| Comando | A cosa serve |
|---|---|
| `kubectl -n lab-dns exec rete -- cat /etc/resolv.conf` | nameserver, search, ndots del Pod |
| `kubectl -n lab-dns exec rete -- dig +search +short web` | risolvere usando la search list |
| `kubectl -n lab-dns exec rete -- sh -c 'tcpdump -nni eth0 -c 12 udp port 53 & sleep 1; dig +search example.com >/dev/null; wait'` | vedere le domande DNS vere |
| `kubectl -n lab-dns exec rete -- dig +short SRV _http._tcp.web.lab-dns.svc.cluster.local` | il record SRV |
| `kubectl -n lab-dns get endpointslices -l kubernetes.io/service-name=web` | i Pod dietro il Service |
| `kubectl -n kube-system logs deploy/coredns` | le domande viste da CoreDNS (con il plugin `log`) |

### Domande

- **Come trova un Pod il Service `api` di un altro namespace?** Con `api.<namespace>`: il `resolv.conf` ha nella search
  list `svc.cluster.local`, che completa il nome. CoreDNS risponde con il ClusterIP, kube-proxy instrada verso un Pod
  delle EndpointSlice.
- **Che cos'è `ndots:5` e perché rallenta le chiamate esterne?** Sotto i 5 punti il nome viene provato prima con ogni
  search domain: `api.esterna.com` genera 4-5 NXDOMAIN (×2 con AAAA) prima di quella buona. Si usa il punto finale, o
  si abbassa `ndots` per quei Pod.
- **`nslookup` dice NXDOMAIN ma l'app si collega. Chi ha ragione?** L'app. Alcuni strumenti (nslookup di busybox, dig
  senza `+search`) non usano la search list come il resolver dell'app. Si prova con il nome completo o con il programma
  vero.
- **Il nome del Service risolve ma la connessione va in timeout.** Il DNS registra il Service anche senza backend. Si
  guardano le EndpointSlice: vuote = selector che non combacia o Pod non Ready. Poi le NetworkPolicy.
- **Perché il ping al ClusterIP non risponde?** Il ClusterIP è virtuale: esiste solo nelle regole di kube-proxy per le
  porte del Service. ICMP non è tradotto.

---

## Riepilogo

- `resolv.conf`: nameserver = kube-dns, search = `<ns>.svc`, `svc`, `cluster.local` (+ host).
- Nome corto nello stesso namespace, `svc.ns` fuori, punto finale = assoluto.
- `ndots:5`: `example.com` = 5 domande A (una esce verso la rete di casa), più altrettante AAAA.
- Risolve ≠ funziona: EndpointSlice vuote = nessun backend.
- Strumenti diversi, search list diverse: si misura con il resolver dell'app.

## Prova da solo

1. Scala `web` a 3 repliche e rifai i passi 11 e 15: quanti indirizzi nell'EndpointSlice e quante regole `KUBE-SEP`
   per `lab-dns/web`? Poi scala a 0: cosa risponde `curl http://web` dal Pod `rete`, e perché non è un timeout?
2. Dal Pod `rete` rifai la misura del passo 7 con `http://web.lab-dns.svc.cluster.local` e poi con
   `http://web.lab-dns.svc.cluster.local.` (punto finale): quante domande in ciascun caso?
3. Crea un Pod con `dnsPolicy: None` e un `dnsConfig` con `nameservers: [10.96.0.10]` ma **senza** `searches`: da lì
   `curl http://web` funziona? E `curl http://web.lab-dns.svc.cluster.local`?

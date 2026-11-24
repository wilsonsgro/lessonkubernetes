# HAProxy: lezione su reverse proxy, load balancing e TLS

Prima il concetto, poi la struttura, poi il file completo e infine il TLS.

---

## 1. Che cos'è HAProxy

**HAProxy** (*High Availability Proxy*) è un software open source che fa da **reverse proxy** e **load balancer**. Sta dal **lato dei server**: riceve le richieste dei client e decide a quale server inoltrarle.

Le sue caratteristiche principali:

- **Molto veloce e leggero**: un unico processo, con un modello a eventi, gestisce centinaia di migliaia di connessioni contemporanee con poca memoria.
- **Lavora a due livelli**:
  - **livello 4 (TCP)**, con `mode tcp`: inoltra byte senza capire il contenuto. Va bene per qualsiasi protocollo: database, SMTP, TLS cifrato;
  - **livello 7 (HTTP)**, con `mode http`: capisce le richieste HTTP, cioè host, path, header e cookie, e può instradare in base a questi.
- **Alta disponibilità**: controlla di continuo se i server rispondono (*health check*) e smette di mandare traffico a quelli che non stanno bene.

Esiste anche un **Ingress controller** per Kubernetes basato su HAProxy, una delle alternative a ingress-nginx.

---

## 2. La struttura del file `haproxy.cfg`

Il file è diviso in **sezioni**, ognuna con un compito:

| Sezione | Compito |
|---|---|
| `global` | Impostazioni del processo: log, limiti, parametri TLS di default |
| `defaults` | Valori ereditati da tutte le sezioni successive: modo, timeout, log |
| `frontend` | **Il lato rivolto ai client**: su quali IP e porte ascoltare, e regole per scegliere il backend |
| `backend` | **Il gruppo di server** a cui inoltrare: algoritmo di bilanciamento e health check |
| `listen` | Frontend e backend uniti in un solo blocco, comodo per casi semplici come la pagina di statistiche |

Nell'Ingress di Kubernetes "frontend" e "backend" erano concetti impliciti. In HAProxy sono **parole chiave vere** del file di configurazione.

---

## 3. Il percorso di una richiesta

```
client ──► frontend (bind :443) ──► ACL: "host = www.negozio.it e path inizia con /api/?"
                                        │
                        sì ─────────────┴──────────── no
                        ▼                              ▼
                   backend be_api                 backend be_web
                  (leastconn)                     (roundrobin)
                   api1  api2                      web1  web2
```

1. Il **frontend** accetta la connessione.
2. Le **ACL** (*Access Control List*) sono condizioni con un nome: "l'host è questo?", "il path inizia con questo?".
3. **`use_backend ... if <acl>`** sceglie il backend in base alle ACL. **`default_backend`** si usa quando nessuna regola corrisponde.
4. Il **backend** sceglie **un server** con l'algoritmo di bilanciamento, tra quelli che superano l'health check.

---

## 4. Bilanciamento e health check

**Algoritmi più usati** (`balance`):

- `roundrobin`: a turno, uno dopo l'altro. È il default ed è adatto a richieste brevi e simili;
- `leastconn`: al server con **meno connessioni aperte**. Adatto a richieste lunghe o di durata variabile, come API pesanti o WebSocket;
- `source`: lo stesso client finisce sempre sullo stesso server, in base al suo IP.

**Health check**: con `check` sulla riga del server, HAProxy lo interroga periodicamente.

- `inter 3s`: controlla ogni 3 secondi;
- `fall 3`: dopo 3 fallimenti consecutivi il server è **DOWN** e non riceve più traffico;
- `rise 2`: dopo 2 successi consecutivi torna **UP**.

Con `option httpchk` il controllo è una vera richiesta HTTP, per esempio `GET /health`, non solo un'apertura di connessione TCP. È lo stesso concetto della **readinessProbe** in Kubernetes: un server che non è pronto esce dal giro.

---

## 5. Un `haproxy.cfg` completo e commentato

Lo scenario: un negozio online `www.negozio.it`, con due server web e due server API. HAProxy riceve tutto in HTTPS.

```haproxy
#─────────────────────────────────────────────────────────────────────
# GLOBAL: impostazioni del processo
#─────────────────────────────────────────────────────────────────────
global
    log stdout format raw local0
    maxconn 50000

    # Parametri TLS di default per i "bind" (lato client):
    # niente TLS 1.0/1.1, solo cifrari moderni
    ssl-default-bind-options ssl-min-ver TLSv1.2 no-tls-tickets
    ssl-default-bind-ciphersuites TLS_AES_128_GCM_SHA256:TLS_AES_256_GCM_SHA384:TLS_CHACHA20_POLY1305_SHA256
    ssl-default-bind-ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384

    # Parametri TLS di default verso i server (lato backend)
    ssl-default-server-options ssl-min-ver TLSv1.2

#─────────────────────────────────────────────────────────────────────
# DEFAULTS: ereditati da tutti i frontend e backend
#─────────────────────────────────────────────────────────────────────
defaults
    mode http                     # lavoriamo a livello 7
    log global
    option httplog                # log dettagliati delle richieste HTTP
    option forwardfor             # aggiunge X-Forwarded-For: l'IP vero del client
    timeout connect 5s            # tempo massimo per connettersi a un server
    timeout client  30s           # inattività lato client
    timeout server  30s           # inattività lato server
    timeout http-request 10s      # protezione da client lenti (slowloris)

#─────────────────────────────────────────────────────────────────────
# FRONTEND HTTP: porta 80, serve solo a reindirizzare su HTTPS
#─────────────────────────────────────────────────────────────────────
frontend fe_http
    bind :80
    http-request redirect scheme https code 301

#─────────────────────────────────────────────────────────────────────
# FRONTEND HTTPS: porta 443, qui avviene la terminazione TLS
#─────────────────────────────────────────────────────────────────────
frontend fe_https
    # "ssl" = HAProxy decifra il traffico
    # "crt" = certificati: con una DIRECTORY li carica tutti e sceglie
    #         quello giusto in base al nome richiesto dal client (SNI)
    # "alpn" = negozia HTTP/2 o HTTP/1.1 con il client
    bind :443 ssl crt /etc/haproxy/certs/ alpn h2,http/1.1

    # Diciamo ai server che il client era in HTTPS
    http-request set-header X-Forwarded-Proto https
    # HSTS: il browser userà sempre HTTPS per un anno
    http-response set-header Strict-Transport-Security "max-age=31536000"

    # Le condizioni (ACL)
    acl host_negozio hdr(host) -i www.negozio.it
    acl percorso_api path_beg /api/

    # Le regole di instradamento, valutate in ordine
    use_backend be_api if host_negozio percorso_api    # entrambe vere (AND)
    use_backend be_web if host_negozio
    default_backend be_web

#─────────────────────────────────────────────────────────────────────
# BACKEND WEB: HTTP in chiaro verso la rete interna
#─────────────────────────────────────────────────────────────────────
backend be_web
    balance roundrobin
    option httpchk
    http-check send meth GET uri /health
    http-check expect status 200
    server web1 10.0.1.11:8080 check inter 3s fall 3 rise 2
    server web2 10.0.1.12:8080 check inter 3s fall 3 rise 2

#─────────────────────────────────────────────────────────────────────
# BACKEND API: ri-cifratura TLS verso i server (re-encryption)
#─────────────────────────────────────────────────────────────────────
backend be_api
    balance leastconn
    option httpchk
    http-check send meth GET uri /health
    http-check expect status 200
    # "ssl"             = verso il server parliamo di nuovo in TLS
    # "verify required" = verifichiamo il certificato del server...
    # "ca-file"         = ...con la nostra CA interna
    # "sni"             = il nome da presentare al server
    server api1 10.0.2.21:8443 check ssl verify required ca-file /etc/haproxy/ca/interna.pem sni str(api.interno)
    server api2 10.0.2.22:8443 check ssl verify required ca-file /etc/haproxy/ca/interna.pem sni str(api.interno)

#─────────────────────────────────────────────────────────────────────
# STATISTICHE: pagina web con lo stato di frontend, backend e server
#─────────────────────────────────────────────────────────────────────
listen stats
    bind 127.0.0.1:8404           # solo in locale: non esporla su Internet
    stats enable
    stats uri /stats
    stats refresh 10s
```

---

## 6. Come HAProxy gestisce il TLS

Le possibilità sono **tre**, e il file sopra ne usa due.

### 6.1 Terminazione TLS (*TLS offloading*) → `fe_https` + `be_web`

```
client ══ HTTPS ══► HAProxy ── HTTP in chiaro ──► web1 / web2
                    (decifra)
```

- HAProxy **decifra** il traffico con il certificato e la chiave privata.
- Inoltra ai server in **HTTP in chiaro**.

**Vantaggi**: i certificati stanno in **un solo posto**. I server non spendono CPU per la crittografia. E soprattutto, siccome HAProxy **vede la richiesta in chiaro**, può instradare per **host e path**, aggiungere header, fare cache e redirect. Il `path_beg /api/` funziona **solo perché** il traffico è stato decifrato.

**Svantaggio**: tra HAProxy e i server il traffico viaggia in chiaro. Va bene solo su una rete interna fidata.

È lo stesso modello dell'Ingress di Kubernetes con la sezione `tls`.

**Il formato dei certificati**: HAProxy vuole un **unico file PEM** che contiene certificato, catena intermedia e chiave privata, uno dopo l'altro:

```bash
cat negozio.it.crt intermedia.crt negozio.it.key > /etc/haproxy/certs/negozio.it.pem
chmod 600 /etc/haproxy/certs/negozio.it.pem
```

Con `crt /etc/haproxy/certs/`, cioè una directory, HAProxy carica tutti i PEM. Poi, per ogni connessione, sceglie quello giusto grazie allo **SNI** (*Server Name Indication*): il nome del sito che il client invia **all'inizio** dell'handshake TLS. Così un solo HAProxy sulla porta 443 serve tanti siti con certificati diversi.

### 6.2 Ri-cifratura (*re-encryption* o *TLS bridging*) → `be_api`

```
client ══ HTTPS ══► HAProxy ══ HTTPS ══► api1 / api2
                    (decifra, ispeziona, ri-cifra)
```

- HAProxy **decifra**, quindi può ancora ispezionare e instradare.
- Poi **ri-cifra** verso i server, con `ssl` sulla riga `server`.

Il dettaglio di sicurezza da non dimenticare è **`verify required`** con il `ca-file`. Senza, HAProxy cifrerebbe ma **non controllerebbe chi c'è dall'altra parte**, e un attaccante nella rete interna potrebbe spacciarsi per il server. Con `verify none` hai cifratura ma **nessuna autenticazione**.

Si usa quando i dati sono sensibili o la rete interna non è considerata sicura (requisiti di compliance, *zero trust*).

### 6.3 Passthrough → un frontend diverso

```
client ══════════ HTTPS (non toccato) ══════════► server
                  HAProxy legge solo lo SNI
```

HAProxy **non decifra niente**: lavora in `mode tcp` e inoltra i byte cifrati così come sono. Il TLS viene terminato **dal server finale**. Può comunque scegliere il backend leggendo lo **SNI**, che nel primo messaggio dell'handshake viaggia in chiaro:

```haproxy
frontend fe_passthrough
    mode tcp
    bind :443                                     # niente "ssl": non decifriamo
    tcp-request inspect-delay 5s                  # aspetta il primo messaggio TLS...
    tcp-request content accept if { req_ssl_hello_type 1 }   # ...cioè il ClientHello
    use_backend be_pagamenti if { req_ssl_sni -i pagamenti.negozio.it }
    default_backend be_web_tls

backend be_pagamenti
    mode tcp
    server pay1 10.0.3.31:443 check

backend be_web_tls
    mode tcp
    server web1 10.0.1.11:443 check
```

- **Vantaggi**: la chiave privata **non lascia mai il server**, ed è una scelta forte per sistemi di pagamento o requisiti legali. Inoltre la cifratura è davvero da un capo all'altro.
- **Svantaggi**: HAProxy è "cieco". Non vede path, header o cookie, quindi **niente routing per path**, niente `X-Forwarded-For`, niente HSTS aggiunto dal proxy. Può instradare **solo per SNI**.

Questo frontend è un'**alternativa** a `fe_https`: non possono ascoltare entrambi sulla stessa porta 443 dello stesso indirizzo.

### Confronto delle tre modalità

| | Terminazione | Ri-cifratura | Passthrough |
|---|---|---|---|
| HAProxy decifra? | Sì | Sì | **No** |
| Routing per host/path/header | Sì | Sì | **Solo SNI** |
| Traffico verso i server | HTTP in chiaro | HTTPS | HTTPS originale |
| Dove sta la chiave privata | HAProxy | HAProxy (+ certificati sui server) | **Solo sui server** |
| Carico CPU su HAProxy | Medio | Alto | Basso |

---

## 7. Comandi da conoscere

```bash
haproxy -c -f /etc/haproxy/haproxy.cfg    # verifica la sintassi PRIMA di ricaricare
systemctl reload haproxy                  # ricarica senza interrompere le connessioni
```

Fai sempre `-c` prima del reload: un errore di sintassi in produzione significa un servizio che non riparte.

Per controllare il TLS dall'esterno:

```bash
openssl s_client -connect www.negozio.it:443 -servername www.negozio.it </dev/null
```

`-servername` invia lo SNI. Togliendolo, vedi quale certificato HAProxy presenta di default.

---

## 8. Domande d'esame

**D: Perché con il passthrough non posso instradare `/api/` verso un backend diverso?**
R: Perché il path è dentro la richiesta HTTP, che è cifrata. HAProxy vede in chiaro solo lo SNI dell'handshake.

**D: Qual è il rischio di `server ... ssl verify none`?**
R: Il traffico è cifrato, ma HAProxy non verifica l'identità del server, quindi un attacco man-in-the-middle nella rete interna è possibile.

**D: Come fa un solo HAProxy a servire più siti HTTPS sulla stessa porta?**
R: Con lo SNI. Il client dichiara il nome del sito nell'handshake, e HAProxy sceglie il certificato corrispondente tra quelli caricati con `crt`.

**D: Che differenza c'è tra `roundrobin` e `leastconn`?**
R: Il primo distribuisce a turno, il secondo sceglie il server con meno connessioni attive. `leastconn` è migliore quando le richieste hanno durate molto diverse.

**D: Perché si usa `option forwardfor`?**
R: Perché i server vedono come mittente l'IP di HAProxy. L'header `X-Forwarded-For` trasmette l'IP reale del client, utile per log, sicurezza e limitazioni per IP.

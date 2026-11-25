### In una frase

`kubectl get` e `kubectl top` dicono come stanno le cose **adesso**; **Prometheus** raccoglie le metriche a intervalli
(modello *pull*), le conserva come serie temporali e le fa interrogare in **PromQL**, **Grafana** le disegna e
**Alertmanager** instrada gli alert. Con **Prometheus Operator** anche la raccolta diventa dichiarativa: un
`ServiceMonitor` dice che cosa raccogliere, una `PrometheusRule` quando preoccuparsi.

### Chi fa cosa

| Pezzo | Che cosa fa | Che cosa **non** fa |
|---|---|---|
| metrics-server | Resource Metrics API: `kubectl top` e l'HPA su CPU/RAM della lezione 06 | storico, PromQL, metriche applicative |
| Prometheus | scrape di `/metrics`, serie temporali, PromQL, valutazione delle regole | grafici curati, invio delle notifiche |
| Grafana | dashboard sopra Prometheus (e altre sorgenti), ha anche alert suoi | raccogliere o conservare le metriche |
| Alertmanager | riceve gli alert, li raggruppa, li silenzia, li instrada ai receiver | decidere quando una condizione è vera |
| kube-state-metrics | lo stato degli oggetti Kubernetes: repliche, fasi dei Pod, restart | l'uso di CPU e memoria |
| node-exporter | il sistema operativo dei nodi: CPU, RAM, dischi, rete | lo stato delle API Kubernetes |

Installare Prometheus **non** sposta l'HPA su Prometheus: per scalare su metriche applicative serve un adapter
o KEDA.

### Tre selettori, tre punti dove la catena si spezza

```text
Prometheus      serviceMonitorSelector: release=monitoring
   ↓
ServiceMonitor  selector: app=demo-metrics · endpoints[].port: metrics
   ↓
Service         selector: app=demo-metrics · porta con nome "metrics"
   ↓
Pod             :8000/metrics
```

- `endpoints[].port` è il **nome della porta del Service**, non un numero.
- Un `ServiceMonitor` creato non vuol dire selezionato; un target selezionato non vuol dire scrape riuscito; e
  `up=1` non vuol dire che l'app funzioni per l'utente.
- È lo stesso guasto del Service con il selector sbagliato della lezione 08, un livello più su.

### PromQL: le quattro cose da saper spiegare

- **Counter** sale sempre (e riparte da zero se il processo riparte); **Gauge** sale e scende.
- `rate(contatore[5m])` è l'aumento al secondo nella finestra: `demo_requests_total` cresce sempre, il suo `rate()`
  scende appena il traffico rallenta. `rate()` sopporta il ritorno a zero del contatore; su una Gauge non ha senso.
- `rate(container_cpu_usage_seconds_total[5m])` è in **core**: `0.25` è un quarto di CPU, ×1000 i millicore.
- La media nasconde le richieste lente: P95 e P99 vogliono un **istogramma** con i bucket, che l'app demo non ha.

### L'alert, dalla regola al messaggio

`Inactive → Pending → Firing`: con `for: 1m` la condizione deve restare vera per un minuto di valutazioni prima di
diventare Firing. Se torna falsa mentre è Pending, l'alert torna Inactive senza mai partire. Firing non vuol dire
email: serve un receiver in Alertmanager. E la regola deve essere scelta dal `ruleSelector` di Prometheus, come i
ServiceMonitor dal loro.

### HAProxy della lezione 21, visto nel tempo

Le due repliche di HAProxy hanno connessioni, contatori e **stick-table locali**. In Grafana va deciso se un
pannello mostra una replica o la somma delle due, guardando le label delle metriche esportate: è per questo che il
rate limit di `limitato.lab.local` può contare in modo diverso sulle due repliche. La pagina `/stats;csv` non è un
endpoint `/metrics`: nomi di endpoint e metriche si verificano sulla versione del controller installata.

### Prima di portarlo fuori dal laboratorio

- **Sicurezza**: qui si entra con `port-forward`; fuori servono autenticazione, TLS, NetworkPolicy e RBAC.
- **Persistenza**: senza PVC le serie si perdono quando il Pod di Prometheus viene sostituito (lezione 05).
- **Cardinalità**: ogni combinazione di label è una serie; `user_id`, `request_id` o URL con ID fanno esplodere
  memoria e disco.

### Verifica rapida (Prometheus e Grafana)

1. Perché `kubectl top` funziona anche senza Prometheus, e perché l'HPA non usa Prometheus da solo?
2. Che cosa distingue kube-state-metrics da node-exporter?
3. Quali tre selettori devono combaciare perché il Pod `demo-metrics` diventi un target?
4. Che cosa garantisce `up=1`, e che cosa no?
5. Perché si usa `rate()` su un Counter, e perché il suo valore può scendere mentre il contatore sale?
6. Che cosa succede a un alert con `for: 1m` se la condizione resta vera solo trenta secondi?
7. Perché due repliche di HAProxy possono mostrare contatori diversi per lo stesso rate limit?
8. Quale label non metteresti mai su una metrica, e perché?

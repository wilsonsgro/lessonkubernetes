# 09 — Helm: un chart scritto da zero, install, upgrade e rollback

Spiegazione di `09-helm-chart.sh` (questa cartella). Lezione sul sito: http://127.0.0.1:3000/kubernetes/9

## In una frase

Lo script **scrive un chart Helm completo** (`./eco`: Chart.yaml, values.yaml, values.schema.json, template) e poi
lo porta in giro per tutto il **ciclo di vita di una release**: lint, rendering locale, install, upgrade, upgrade
fallito con rollback automatico, rollback manuale. Alla fine ti fa vedere **dove Helm tiene la storia**: nei Secret
del namespace.

## Due file con lo stesso nome: quale lanciare

| File | Che cos'è | Come si usa |
|---|---|---|
| `~/kubernetesprj/lezioni/kubernetes/09-helm-chart.sh` | **questo**: la lezione, con le spiegazioni nei commenti | `bash 09-helm-chart.sh crea` · `prova` · `pulisci` |
| `~/kubernetesprj/kubernetes/09-helm-chart.sh` | lo script **guidato**: chiama `crea` di questo file e poi esegue i comandi Helm uno per volta, spiegando prima di eseguire (Invio / s / q) | `bash kubernetes/09-helm-chart.sh` |

Per imparare conviene lo **guidato**. Lavora nella cartella `lavoro/helm` (funzione `cartella helm` di `passo.sh`):
è lì che finisce il chart `./eco`, che servirà anche alla lezione 10 (come dipendenza) e alla 12 (deploy).

## Com'è fatto il file

```
intestazione (commenti)  → i tre problemi che Helm risolve, novità di Helm 4, NEL PROGETTO VERO
set -euo pipefail        → lo script si ferma al primo errore
CHART=./eco  NS=lab-helm → dove scrive il chart, in quale namespace installa
crea()                   → scrive tutti i file del chart con dei heredoc (cat > file <<'EOF')
prova()                  → lint, template, install, upgrade, rollback (in sequenza, senza pause)
case "$1"                → crea | prova | pulisci
coda (commenti)          → funzioni di template, precedenza dei valori, domande da colloquio, riepilogo
```

I heredoc sono scritti con `<<'EOF'` (EOF **tra apici**): la shell non tocca il testo, quindi `{{ ... }}` e `$(MESSAGGIO)`
arrivano nei file così come sono.

---

## 1. La teoria nell'intestazione

Versioni dichiarate: **Helm 4.3 · Kubernetes 1.35**, livello 4 "Packaging e delivery". Sull'Ubuntu del lab c'è
`helm v4.3.1`.

### I tre problemi che `kubectl apply` non risolve

| Problema | Come lo risolve Helm |
|---|---|
| **Parametri** | un solo set di template, valori diversi per ambiente |
| **Release** | un nome che raggruppa tutti gli oggetti installati, con una storia numerata (**revision**) salvata nel cluster come Secret di tipo `helm.sh/release.v1` |
| **Ciclo di vita** | install, upgrade, rollback, uninstall, hook, test |

### Helm 4 rispetto al 3 (uscito a novembre 2025)

| Cosa cambia | Perché conta |
|---|---|
| **server-side apply di default** per le release nuove | il server registra chi possiede ogni campo (field ownership, vedi lezione 01): conflitti espliciti invece di sovrascritture silenziose |
| `--atomic` → `--rollback-on-failure` | stesso significato, nome nuovo: se l'upgrade fallisce, torna indietro da solo |
| `--force` → `--force-replace` | il nome dice cosa fa: ricrea gli oggetti invece di aggiornarli |
| `--wait` ha **strategie**: `watcher` (kstatus, il default con `--wait`), `legacy` e `hookOnly` (il default quando `--wait` manca) | il watcher usa le regole di kstatus per decidere quando un oggetto è "pronto" |
| plugin in WebAssembly; chart **v2 invariati** | i chart scritti per Helm 3 funzionano ancora |

### Riquadro «NEL PROGETTO VERO»

In `~/biodistretto/kubernetes` (branch `kubernetes`) **Helm non c'è**. Il progetto usa YAML con `${variabili}`, resi
da `templatefile` di Terraform e spezzati in oggetti con `manifest_decode_multi`:

```bash
cd ~/biodistretto/kubernetes
grep -n 'manifest_decode_multi' terraform/app/workload.tf
grep -n -F '${repliche}' terraform/app/manifests/app.yaml.tftpl
```

Le stesse idee, a confronto:

| Helm | Progetto (Terraform) |
|---|---|
| `values.yaml` | `variables.tf` |
| release e revision | `tfstate` |
| `helm rollback` | `git revert` + `apply` |

Perché lì va bene così: i segreti e la CA li crea Terraform **nello stesso grafo**, senza doverli passare a Helm.
Esercizio proposto dal file: trasforma `app.yaml.tftpl` in un chart (`${x}` → `{{ .Values.x }}`) e confronta l'output
di `helm template` con quello che c'è nel cluster.

---

## 2. `crea()` — il chart, file per file

Alla fine `find eco -type f | sort` (passo 3 del guidato) mostra:

```
eco/.helmignore
eco/Chart.yaml
eco/templates/NOTES.txt
eco/templates/_helpers.tpl
eco/templates/configmap.yaml
eco/templates/deployment.yaml
eco/templates/ingress.yaml
eco/templates/service.yaml
eco/values.schema.json
eco/values.yaml
```

### `Chart.yaml` — la carta d'identità

| Campo | Valore | Perché |
|---|---|---|
| `apiVersion` | `v2` | formato dei chart di Helm 3 e 4 |
| `name` | `eco` | nome del chart, finisce in `.Chart.Name` |
| `type` | `application` | installabile. `library` = solo helper, non si installa |
| `version` | `0.1.0` | SemVer **del chart**: si alza a ogni modifica del chart |
| `appVersion` | `"v1.12"` | versione **dell'app**; usata come tag immagine di default |

`version` e `appVersion` sono due cose diverse: puoi cambiare un template (chart 0.1.1) senza cambiare l'app.

### `values.yaml` — l'interfaccia pubblica

```yaml
replicaCount: 2
image:
  repository: traefik/whoami
  tag: ""                # vuoto = appVersion
  pullPolicy: IfNotPresent
service:
  port: 80
config:
  messaggio: "ciao dal chart"
resources:
  requests: { cpu: 20m, memory: 16Mi }
  limits: { memory: 32Mi }
ingress:
  enabled: false
  host: eco.lab.local
```

Tutto quello che chi usa il chart può cambiare con `--set` o `-f` sta qui. Quello che non c'è, non si cambia senza
toccare i template. `tag: ""` è un trucco comune: lasciato vuoto, il template usa `appVersion`.

### `values.schema.json` — validazione prima del rendering

Uno schema JSON (draft-07): `replicaCount` e `image` sono obbligatori, `replicaCount` deve essere un **intero ≥ 1**,
`image.repository` una stringa non vuota. Helm lo applica **prima** di renderizzare: un valore sbagliato si ferma lì,
non arriva mai al cluster.

### `templates/_helpers.tpl` — i `define` riusabili

I file che cominciano con `_` **non producono YAML**: contengono solo definizioni.

| Define | Cosa restituisce |
|---|---|
| `eco.fullname` | se il nome della release **contiene** già il nome del chart, usa solo la release; altrimenti `<release>-<chart>`. Sempre tagliato a 63 caratteri (`trunc 63`) e senza `-` finale (`trimSuffix "-"`) |
| `eco.selectorLabels` | `app.kubernetes.io/name` (chart) e `app.kubernetes.io/instance` (release): le label **stabili**, usate nei selector |
| `eco.labels` | le selectorLabels + `app.kubernetes.io/version`, `app.kubernetes.io/managed-by` (`.Release.Service`, cioè Helm) e `helm.sh/chart: eco-0.1.0` |

Esempi: release `eco` → oggetti chiamati `eco`; release `prova` (usata da `helm template prova`) → `prova-eco`.
Il limite di 63 viene dai nomi DNS di Kubernetes.

Perché due insiemi di label: il `selector` di un Deployment **non si può cambiare** dopo la creazione. Se ci mettessi
la versione, ogni upgrade romperebbe il selector. Per questo nel selector vanno solo le label che non cambiano.

### `templates/configmap.yaml`

Una ConfigMap con nome `eco.fullname` e una sola chiave: `MESSAGGIO: {{ .Values.config.messaggio | quote }}`.
`quote` mette le virgolette, così un valore come `yes` o `0.1` resta una stringa.

`labels: {{- include "eco.labels" . | nindent 4 }}`: `include` restituisce il testo del define, `nindent 4` va a capo e
lo indenta di 4 spazi. Il `{{-` mangia lo spazio prima, così il blocco finisce al posto giusto sotto `labels:`.

### `templates/deployment.yaml` — il cuore

| Riga | Cosa fa |
|---|---|
| `replicas: {{ .Values.replicaCount }}` | numero di Pod dai valori |
| `matchLabels: {{- include "eco.selectorLabels" . \| nindent 6 }}` | il selector con le sole label stabili |
| `checksum/config: {{ include (print $.Template.BasePath "/configmap.yaml") . \| sha256sum }}` | renderizza la ConfigMap e ne calcola l'hash. Cambia la config → cambia l'hash → cambia il template del Pod → **rollout**. Senza questo, cambiare una ConfigMap non fa ripartire i Pod |
| `image: "{{ .Values.image.repository }}:{{ .Values.image.tag \| default .Chart.AppVersion }}"` | con `tag: ""` diventa `traefik/whoami:v1.12` |
| `args: ["--port", "8080", "--name", "$(MESSAGGIO)"]` | whoami ascolta sulla 8080; `$(MESSAGGIO)` lo espande **Kubernetes** (non la shell) con la variabile d'ambiente del container |
| `envFrom: configMapRef` | tutte le chiavi della ConfigMap diventano variabili d'ambiente: da qui arriva `MESSAGGIO` |
| `ports: name: http, containerPort: 8080` | porta con nome, usata da probe e Service |
| `readinessProbe: httpGet /health, port: http` | il Pod riceve traffico solo quando `/health` risponde |
| `{{- with .Values.resources }} resources: {{- toYaml . \| nindent 12 }} {{- end }}` | se `resources` c'è, lo copia **intero** come YAML; `with` cambia il contesto `.` nel blocco |

### `templates/service.yaml`

Service con selector sulle selectorLabels, porta `{{ .Values.service.port }}` (80) verso `targetPort: http`, cioè la
porta con nome del container (8080). Cambiare il numero nel container non richiede di toccare il Service.

### `templates/ingress.yaml` — opzionale

Tutto il file è dentro `{{- if .Values.ingress.enabled }} … {{- end }}`: con il default `false` **non produce niente**.
Con `ingress.enabled=true` esce un Ingress con `ingressClassName: nginx`, path `/` di tipo `Prefix` verso il Service
sulla porta `http`. L'host usa `required`:

```
{{ required "ingress.host è obbligatorio con ingress.enabled" .Values.ingress.host }}
```

Se l'host manca, il rendering **fallisce** con quel messaggio invece di produrre un Ingress senza host.

### `templates/NOTES.txt`

Non è un manifest: è il testo che Helm stampa **dopo** install e upgrade. Qui dice nome e revision della release e il
comando `kubectl -n <ns> port-forward svc/<nome> 8080:80` per provarla.

### `.helmignore`

Come `.gitignore`: `.git/` e `*.tgz` non finiscono nel pacchetto del chart.

---

## 3. Il percorso del guidato, passo per passo

Il guidato non chiama `prova`: esegue gli stessi comandi uno alla volta (più qualche `cat`/`find`), nel namespace
`lab-helm`.

| # | Comando | Cosa vedi |
|---|---|---|
| 1 | `helm version` | la versione: sul lab è la 4, con server-side apply di default |
| 2 | `bash $LEZIONI/kubernetes/09-helm-chart.sh crea` | `chart scritto in ./eco` |
| 3 | `find eco -type f \| sort` | i file elencati sopra |
| 4 | `cat eco/values.yaml` | l'interfaccia pubblica |
| 5 | `helm lint eco --strict` | errori di struttura e di template **prima** di toccare il cluster. `--strict` tratta anche gli avvisi come errori |
| 6 | `helm template prova eco --set ingress.enabled=true \| grep ^kind:; helm template prova eco --set ingress.enabled=true --show-only templates/ingress.yaml` | i manifest renderizzati **in locale, senza cluster**: è quello che finirebbe nell'apply. Gli oggetti si chiamano `prova-eco`. Prima l'elenco dei tipi (ConfigMap, Service, Deployment, Ingress), poi solo l'Ingress acceso con `--set`: `--show-only` rende un template solo. Tutto intero è lungo: l'Ingress comincia alla riga 87 |
| 7 | `helm template prova eco --set replicaCount=0` | **fallisce apposta**: lo schema JSON rifiuta `replicaCount=0` (minimo 1) **prima** del rendering. Il guidato stampa l'uscita ≠ 0 in rosso: è voluto |
| 8 | `helm upgrade --install eco eco -n lab-helm --create-namespace --wait --timeout 2m` | installa (la release non c'è ancora), crea il namespace, aspetta che i Pod siano pronti. Stampa le NOTES |
| 9 | `helm -n lab-helm history eco` | revision 1, `deployed` |
| 10 | `helm upgrade eco eco -n lab-helm --reuse-values --set config.messaggio='seconda versione' --wait --timeout 2m` | cambia solo il messaggio. Cambia la ConfigMap → cambia il checksum → i Pod ripartono. Revision 2 |
| 11 | `helm upgrade eco eco -n lab-helm --reuse-values --set image.tag=v9.9.9 --rollback-on-failure --timeout 60s` | **fallisce apposta**: l'immagine `traefik/whoami:v9.9.9` non esiste, i Pod nuovi non diventano mai pronti. Dopo 60 s Helm dichiara il fallimento e **torna da solo** alla versione buona |
| 12 | `helm -n lab-helm history eco` | revision 3 `failed`, revision 4 = rollback automatico alla 2 |
| 13 | `helm -n lab-helm get values eco` | solo i valori **passati dall'utente** (qui `config.messaggio`), non i default del chart |
| 14 | `helm -n lab-helm get manifest eco \| grep -m1 'image:'` | il manifest effettivamente installato: l'immagine in uso è di nuovo quella buona, non la `v9.9.9` |
| 15 | `helm -n lab-helm rollback eco 1 --wait` | rollback manuale alla revision 1. Un rollback **non cancella** la storia: aggiunge una revision nuova con il contenuto della 1 |
| 16 | `kubectl -n lab-helm get secret -l owner=helm` | un Secret per revision, tipo `helm.sh/release.v1`: è la storia della release |

Nota finale del guidato: il chart `./eco` serve alla lezione 10 (dipendenza) e alla 12 (deploy). Pulizia:
`helm uninstall eco -n lab-helm && kubectl delete ns lab-helm`.

### `prova()` nella lezione: le stesse cose in un colpo

`prova` fa la stessa sequenza (dal lint al `get secret`) ma senza pause e con due accorgimenti per non fermarsi con
`set -e` sui passi che falliscono apposta:

```bash
helm template prova $CHART --set replicaCount=0 && exit 1 || echo "OK: replicaCount=0 rifiutato"
helm upgrade … --set image.tag=v9.9.9 --rollback-on-failure --timeout 60s || echo "OK: upgrade fallito e annullato"
```

Il primo si legge così: se il template **riesce**, è un errore (lo schema non funziona) ed esce con 1; se fallisce,
stampa OK. Prima di tutto controlla a mano che il contesto sia `lab`, come la guardia della lezione 01.
`pulisci` fa `helm uninstall eco -n lab-helm; kubectl delete ns lab-helm`.

---

## 4. Le trappole

- **L'indentazione.** `{{-` e `-}}` tolgono spazi e a capo prima/dopo. Un `nindent` sbagliato o un trattino in più
  producono YAML valido ma sbagliato (o non valido). È il bug Helm più comune: per questo `helm template` prima di
  tutto.
- **`--reuse-values` ignora i nuovi default del chart.** Riusa i valori della release precedente; se il chart nuovo
  aggiunge un valore con un default, quel default non arriva. `--reset-then-reuse-values` unisce correttamente.
- **`lookup` in `helm template` è vuoto**: legge il cluster, ma il rendering locale il cluster non lo vede.
- **Il selector non si cambia**: mettici solo label stabili (name + instance), mai la versione.
- **Cambiare una ConfigMap non fa ripartire i Pod** se non c'è un `checksum/config` (o qualcosa di simile) nel
  template del Pod.
- **Helm interrotto a metà** lascia la release in `pending-*` e blocca ogni operazione successiva (vedi domande).

---

## 5. La coda: template e precedenza dei valori

### Le cose dei template che ti chiedono

| Costrutto | A cosa serve |
|---|---|
| `{{-  -}}` | tolgono spazi/a capo prima/dopo |
| `include` vs `template` | `include` restituisce una **stringa**, quindi puoi metterlo in pipe (`\| nindent`); `template` no |
| `toYaml . \| nindent N` | per blocchi interi (resources, tolerations) |
| `required "msg" .X` | fa fallire il rendering se manca un valore |
| `default`, `quote`, `tpl`, `lookup` | valore di ripiego, virgolette, rendering di una stringa come template, lettura dal cluster (vuoto in `helm template`) |
| `.Release .Chart .Values .Capabilities .Template .Files` | gli oggetti disponibili nei template |

### Precedenza dei valori (l'ultimo vince)

```
values.yaml del chart  <  values del chart padre  <  -f file1  <  -f file2  <  --set
```

---

## 6. Comandi e domande da colloquio

### Comandi da sapere

| Comando | A cosa serve |
|---|---|
| `helm lint eco --strict` | controllo statico del chart |
| `helm template <rel> eco --set …` | rendering locale |
| `helm upgrade --install … --wait --timeout 2m` | install idempotente, la forma da usare in CI |
| `helm upgrade … --rollback-on-failure` | upgrade che si annulla da solo se fallisce |
| `helm -n NS history eco` | la storia delle revision |
| `helm -n NS get values eco` / `get manifest eco` | valori dell'utente / manifest installato |
| `helm -n NS rollback eco 1 --wait` | torna a una revision |
| `kubectl -n NS get secret -l owner=helm` | i Secret della storia |

### Domande

- **Dove salva Helm lo stato? Cosa succede se cancello quel Secret?** Un Secret per revision, nel namespace della
  release. Cancellandoli Helm "dimentica" la release, ma gli oggetti restano nel cluster: un install successivo
  fallisce per conflitto di ownership (oppure serve `--take-ownership`).
- **Un upgrade è rimasto in `pending-upgrade` e ogni nuovo upgrade fallisce.** Un processo Helm è morto a metà (per
  esempio una CI cancellata). `helm history` mostra lo stato; si fa `helm rollback` all'ultima `deployed`. Se è
  `pending-install` non c'è una revision a cui tornare: `helm uninstall` e si reinstalla. È successo davvero
  preparando la lezione 13: Helm interrotto a metà → `another operation (install/upgrade/rollback) is in progress`.
  Per prevenirlo: `--rollback-on-failure` e timeout in CI.
- **Come rivedi cosa cambierà prima di un upgrade?** `helm template` + diff in PR, oppure il plugin helm-diff
  (`helm diff upgrade`), oppure `--dry-run=server`, che passa anche dall'admission del cluster.
- **Differenza fra `version` e `appVersion`?** La prima è la versione del chart (SemVer, cambia a ogni modifica del
  chart), la seconda dell'applicazione (qui il tag di default dell'immagine).

---

## Riepilogo

- Chart = template + values + Chart.yaml; release = un'installazione con storia.
- `_helpers.tpl` per nomi e label; `checksum/config` per i rollout quando cambia la config.
- `values.schema.json` e `required`: errori **prima** del cluster.
- In CI: `upgrade --install`, `--wait`, `--rollback-on-failure` (Helm 4).
- `history` / `rollback` / `get values` / `get manifest`; la storia sta nei Secret `owner=helm`.

## Prova da solo

1. `helm template prova eco --set ingress.enabled=true --set ingress.host=` : che errore ti dà? Da quale riga del
   chart arriva?
2. Fai un upgrade con `--set replicaCount=3`, poi `helm -n lab-helm history eco` e
   `kubectl -n lab-helm get secret -l owner=helm`: quante revision e quanti Secret vedi adesso?
3. Cambia `config.messaggio` con un upgrade **senza** toccare altro e confronta l'annotazione `checksum/config` del
   Deployment prima e dopo (`kubectl -n lab-helm get deploy eco -o yaml | grep checksum`). Poi rifai l'upgrade con lo
   stesso messaggio: i Pod ripartono?

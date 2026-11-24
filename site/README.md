# Corso Kubernetes — sito didattico

Sito statico in italiano delle lezioni 01–09 e degli approfondimenti 21 (HAProxy), 22 (Terraform), 23 (Ansible) e 24 (un progetto reale, il Biodistretto su minikube).
Una volta generato funziona offline: niente CDN, niente chiamate esterne, niente backend.
Indirizzo sul lab: <http://lessons.kubernates.local>

## Requisiti

- Docker, e basta: Node e npm girano nel container `node:25-alpine3.23`, non si installano sul PC
- Docker Compose v2 per servire il sito con nginx

## Installazione, build, test

Tutti i comandi `npm` di questo README si lanciano dentro il container:

```bash
docker run -it --rm -u root -p 127.0.0.1:8080:8080 -e HOST=0.0.0.0 \
  -v /home/wilsonsgro/kubernetesprj:/app \
  -v /home/wilsonsgro/biodistretto:/biodistretto:ro node:25-alpine3.23 sh

cd /app/site
npm ci           # dipendenze a versione fissa: marked, highlight.js
npm run build    # genera dist/
npm test         # importatore, parser dei passi, simulazioni, build
npm run serve    # anteprima su http://127.0.0.1:8080 dell'host
```

Si monta tutta `kubernetesprj`, non solo `site`: i test di fedeltà e `npm run importa:terraform` leggono
`../lezioni` e `../terraform`. Montando solo `site` quei 2 test vengono saltati (`skipped 2`) invece di fallire.
Il secondo `-v` (sola lettura) serve alla lezione 24: senza, il suo test di fedeltà viene saltato (`skipped 1`).
`-u root` lascia `node_modules/` e `dist/` di proprietà di root sull'host; `-u node` (uid 1000) li lascerebbe all'utente.

## Pubblicazione con nginx

```bash
cd ~/kubernetesprj/site/docker
docker compose up -d          # nginx:1.27 sulla porta 80, serve ../dist in sola lettura
```

`docker/config/default.conf` è la configurazione di nginx (`server_name lessons.kubernates.local`, tipi MIME
per `.mjs` e per le sorgenti `.md/.sh/.yaml` mostrate come testo). Dopo un `npm run build` non serve riavviare:
nginx legge direttamente `dist/`.

## Da dove vengono i contenuti

| File | Contenuto |
|---|---|
| `content/corso.md` | il corso completo: spiegazioni e **sorgenti originali** integrali (copia di `request/39.md`) |
| `content/quiz/quiz-NN.json` | domande per lezione; `tipo` distingue `didattica` da `esito-lab` |
| `content/glossario.json` | termini, definizioni, lezioni collegate, alias |
| `content/flashcard.json` | carte domanda/risposta per il ripasso |
| `content/terraform/` | lezioni 22 e 23: i file delle parti 00–10 di `~/kubernetesprj/terraform/` e `lezioni/terraform/` copiati tali e quali, più gli appunti di sintesi (`appunti.md` per la 22, `appunti-23.md` per la 23) e `mappa.json` (collegamenti alle altre lezioni) |
| `content/progetto/` | lezione 24: `file/` con i 37 file di `~/biodistretto/kubernetes` (IP del laboratorio mascherato), `appunti-24.md`, `comandi.passi` (i comandi del README) e `mappa.json` |
| `content/approfondimenti/` | materiale integrativo fuori dal repository del laboratorio, reso in fondo alla Spiegazione della lezione (oggi: `21-haproxy-cfg-tls.md`, haproxy.cfg e TLS, con il suo quiz `quiz/quiz-21-tls.json`); si collega in `APPROFONDIMENTI` di `src/build.mjs` |

`src/importa.mjs` legge `content/corso.md` in modo deterministico: ogni `### Fonte originale: <percorso>` diventa
una sorgente della lezione (spiegazione `.md`, script dei passi `kubernetes/NN-*.sh`, manifest o script della
lezione). Lo script dei passi viene scomposto in passi `perché → comando` per la vista **Laboratorio**.
Il build (`src/build.mjs`) produce le pagine, l'indice di ricerca (`dati/cerca.json`) e copia ogni sorgente
in `dist/fonti/` per lo scaricamento.

Le lezioni 22 e 23 non passano da `corso.md`: `src/terraform.mjs` legge `content/terraform/` e, secondo `CAPITOLI`,
costruisce la 22 dalle parti 00–05 (Terraform) e la 23 dalle parti 06–10 (Ansible, e la catena Terraform + Ansible).
Ogni parte ha spiegazione, script guidato e, dalla 01, file di lezione. Le righe `cartella` degli script diventano la
cartella di lavoro mostrata nel Laboratorio.

Nel glossario `soloLezioni: true` limita l'aggancio di un termine alle sue lezioni, `tranneLezioni` lo spegne in
quelle elencate: nella 23 «service», «deploy», «drain» e «secret» hanno un altro significato che in Kubernetes.

La lezione 24 non passa né da `corso.md` né da `terraform.mjs`: `src/progetto.mjs` prende da `content/progetto/` il
README del Biodistretto (la lezione), 36 file del progetto (Ansible, Terraform, manifest, nginx, Docker), gli appunti
`appunti-24.md`, i comandi del README in `comandi.passi` e `mappa.json`. L'elenco dei file è fisso (`FILE`): lo state
di Terraform, i piani, `docker/.env`, `.cache/` e il certificato restano fuori (`VIETATI`, controllato prima di
scrivere), e ogni indirizzo `192.168.x.y` diventa `IP-DEL-LAB`.

## Fedeltà alle sorgenti

`test/importa.test.mjs` confronta con SHA-256 ogni sorgente in `content/corso.md` con il file vero in
`../lezioni/kubernetes/` e `../kubernetes/`. Se quelle cartelle mancano (build su un'altra macchina) il test
viene saltato e lo segnala; sul lab deve passare, non essere saltato.
`test/terraform.test.mjs` fa lo stesso per i 32 file di `content/terraform/` (17 della 22, 15 della 23) contro
`../terraform/` e `../lezioni/terraform/`. `test/progetto.test.mjs` confronta i 37 file di `content/progetto/file/`
con `~/biodistretto/kubernetes` passato dalla stessa maschera dell'IP (cartella diversa: variabile `PROGETTO`).

## Aggiornare il corso

1. Modifica i file in `~/kubernetesprj/lezioni/kubernetes/` o `~/kubernetesprj/kubernetes/`.
2. Riporta le stesse modifiche nei blocchi corrispondenti di `content/corso.md`.
3. `npm test` (il test di fedeltà segnala i blocchi rimasti indietro), poi `npm run build`.
4. Se cambia il contenuto di una lezione, rivedi quiz e flashcard della lezione.

Per Terraform e Ansible (lezioni 22 e 23) non si copia a mano: `npm run importa:terraform` ricopia da
`~/kubernetesprj` i file delle parti 00–10 in `content/terraform/`, poi `npm test` e `npm run build`. Gli appunti
(`appunti.md`, `appunti-23.md`), i quiz `quiz-22.json` e `quiz-23.json` e le voci del glossario si rivedono a mano.

Per il progetto reale (lezione 24): `npm run importa:progetto` ricopia i file da `/biodistretto/kubernetes`
(o dalla cartella passata come argomento), rifiuta i file vietati e gli IP non mascherati; `appunti-24.md`,
`comandi.passi` e `quiz-24.json` si rivedono a mano.

## Sicurezza

Il sito **non esegue** comandi: `kubectl`, `helm`, `minikube`, `docker` e gli script si copiano e si lanciano a
mano. Le righe distruttive (`delete`, `drain`, `--force`, `taint`, `rollout restart`, `helm uninstall`, `deploy.sh distruggi`) sono
evidenziate con un'etichetta. Le simulazioni girano solo nel browser, su dati finti. Progressi, note e preferiti
restano nel `localStorage` del browser (esportabili dalla pagina Preferiti).

La lezione 24 pubblica file di un progetto vero: l'elenco è fisso (`FILE` in `src/progetto.mjs`), lo state di
Terraform, i piani, `.env`, `.cache/` e i certificati non entrano mai, e ogni `192.168.x.y` diventa `IP-DEL-LAB`.
I suoi file si scaricano da `/fonti/biodistretto/`, separati da quelli delle altre lezioni.

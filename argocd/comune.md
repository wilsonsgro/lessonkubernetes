# comune.sh — variabili e aiuti degli script di Argo CD

Spiegazione di `comune.sh` (questa cartella). Non si lancia: lo caricano con `source` tutti gli script `01`…`05` e
`99` di questa cartella.

## In una frase

Carica la libreria degli script guidati (`../lib/passo.sh`), fissa i percorsi e l'indirizzo di Gitea, e definisce
due funzioni: una riaccende il collegamento ad Argo CD, l'altra fa il push e aspetta che Argo applichi.

## Riga per riga

| Riga | Cosa fa |
|---|---|
| `source "$(dirname "${BASH_SOURCE[0]}")/../lib/passo.sh"` | le funzioni `titolo`, `passo`, `nota`, `guardia_lab` e le variabili `PRJ` (= `~/kubernetesprj`) e `LAVORO` (= `~/kubernetesprj/lavoro`). `BASH_SOURCE[0]` è il percorso di **questo** file anche quando viene caricato da un altro script |
| `export PATH="$HOME/.local/bin:$PATH"` | la CLI `argocd` la installa lo script 01 in `~/.local/bin` |
| `ARGO="$PRJ/argocd"` | questa cartella: da qui si leggono `gitea.yaml` e il modello `mio-progetto/` |
| `REPO="$LAVORO/argocd/mio-progetto"` | la **copia di lavoro** del progetto, che diventa un repository git (script 02). I commit si fanno lì, non nel modello |
| `GITEA="http://$(minikube -p lab ip 2>/dev/null):30300"` | Gitea **visto dall'Ubuntu**: IP del nodo minikube (192.168.49.x) e NodePort 30300 |
| `GITEA_PASS_FILE="$LAVORO/argocd/.gitea-pass"` | il file con la password dell'utente `wilson` di Gitea (la crea lo script 02) |

## `assicura_argocd()`

```bash
pgrep -f 'port-forward --address 0.0.0.0 svc/argocd-server' >/dev/null || {
  nohup kubectl -n argocd port-forward --address 0.0.0.0 svc/argocd-server 8083:443 >/tmp/argocd-port-forward.log 2>&1 &
  sleep 3
}
argocd account get-user-info >/dev/null 2>&1 || argocd login localhost:8083 --username admin --insecure --grpc-web --password "…"
```

1. Se il port-forward verso Argo CD **non** è acceso (per esempio dopo un riavvio del PC), lo riaccende in
   background: la 443 del Service `argocd-server` diventa la **8083** dell'Ubuntu. `nohup … &` lo fa sopravvivere
   alla fine dello script; il log va in `/tmp/argocd-port-forward.log`.
2. Se la CLI non è più loggata, rifà il login come `admin`, prendendo la password dal Secret
   `argocd-initial-admin-secret` (decodificata con `base64 -d`).

La usano gli script 04 e 05 all'inizio: per questo il README dice che dopo un riavvio «lo riaccendono da soli».

## `push_e_refresh()`

```bash
git -C "$REPO" push -q origin main && argocd app get mio-sito --refresh >/dev/null && argocd app wait mio-sito --sync --health --timeout 180 >/dev/null
```

Push su Gitea, poi `--refresh` (Argo rilegge git subito invece di aspettare il suo giro di 2–3 minuti), poi attesa
che l'Application sia **Synced** e **Healthy**, al massimo 180 s.

Nota: nessuno degli script di questa cartella la chiama (`grep push_e_refresh *.sh` la trova solo qui). Fanno gli stessi tre comandi scritti per intero dentro i
loro passi, così li vedi a schermo.

## Trappole

- `GITEA` si calcola **quando lo script parte**. Se il cluster `lab` è spento, `minikube ip` non risponde e l'indirizzo
  diventa `http://:30300`: tutti i passi git verso Gitea falliscono. Accendi prima il cluster (`minikube -p lab start`).
- Il port-forward ascolta su `0.0.0.0`: la UI di Argo CD è raggiungibile da **tutta la rete di casa** sulla 8083
  (comodo dal Mac, ma ricordalo).

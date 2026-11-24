# Come studiare con kubernetesprj

Un percorso a fasi per **Kubernetes, Helm, Terraform, Ansible e Argo CD** su questo Ubuntu (`192.168.1.79`).
Per ogni passo: cosa leggere, cosa lanciare, come controllare che abbia funzionato, come pulire.
Il funzionamento degli script (Invio · s · q, `AUTO=1`, `DA=n`) e i guasti più comuni sono nel `README.md`.

Tutti i comandi si lanciano da `~/kubernetesprj`.

---

## Il metodo: una lezione in 6 mosse

| # | Mossa | Dove |
|---|---|---|
| 1 | **Leggi la lezione sul sito** | dal Mac: `http://127.0.0.1:3000/kubernetes/N` oppure `/terraform/N` |
| 2 | **Leggi la spiegazione** del file | `lezioni/kubernetes/NN-….md`, `terraform/NN-….md`, `argocd/NN-….md` |
| 3 | **Lancia lo script guidato** e leggi ogni passo prima di premere Invio | `bash kubernetes/NN-….sh`, `bash terraform/NN-….sh`, `bash argocd/NN-….sh` |
| 4 | **Tieni aperto il file della lezione** mentre lo script lo applica: i commenti spiegano il perché | `lezioni/kubernetes/NN-…`, `lezioni/terraform/NN-…` |
| 5 | **Rifai a mano** i comandi principali e gli esercizi «Prova da solo» in fondo al `.md` | un secondo terminale |
| 6 | **Scrivi nel diario** cosa hai capito e cosa non torna; poi **pulisci** | `appunti_kubernetes.md`; il passo «Pulizia» in fondo allo script |

Una riga rossa `↳ uscita N` non vuol dire sempre un guasto: molti passi falliscono **apposta**. La spiegazione del
passo e il `.md` dicono quali.

**Una lezione pesante alla volta.** Il PC ha 12 CPU e 15 GB. Il cluster `lab` usa 2 nodi da 4 GB, la lezione 13
aggiunge circa 1,5 GB, e MicroK8s è un cluster in più. Quando chiudi una sessione: `minikube -p lab stop`.

---

## Fase 0 — Preparazione (una volta sola)

| Cosa | Comando | Controllo |
|---|---|---|
| Leggi | `README.md`, sezioni 1, 2 e 9 | — |
| Controlla gli strumenti | `for c in docker kubectl helm minikube terraform ansible jq curl; do printf '%-10s ' $c; command -v $c \|\| echo MANCA; done` | nessun `MANCA` |
| Docker senza sudo | `docker ps` | risponde senza errore |
| Terraform e Ansible | leggi `terraform/00-installa.md`, poi `bash terraform/00-installa.sh` | `terraform version`, `ansible --version` (oggi sono già installati: i passi diranno che c'è già) |
| Terminale nuovo | — | `command -v ansible` → `~/.local/bin/ansible` |

---

## Fase 1 — Kubernetes: le fondamenta

Obiettivo: capire la **riconciliazione** (stato desiderato contro stato osservato), i Pod, i Deployment, la rete.

| Passo | Leggi | Lancia | Cosa devi aver capito |
|---|---|---|---|
| 1.1 | `/kubernetes/1` · `lezioni/kubernetes/01-architettura-e-lab.md` | `bash kubernetes/01-architettura-e-lab.sh` (crea il cluster `lab`: qualche minuto) | control plane e nodo; perché i Pod si ricreano da soli; i tre IP (nodo, Pod, Service); Capacity del nodo contro cgroup |
| 1.2 | `/kubernetes/2` · `02-deployment-rollout-probe.md` | `bash kubernetes/02-deployment-rollout-probe.sh` | rolling update, rollback, probe, QoS |
| 1.3 | `/kubernetes/3` · `03-service-ingress-networkpolicy.md` | `bash kubernetes/03-service-ingress-networkpolicy.sh` (**serve la 02 applicata**) | Service, EndpointSlice, Ingress, NetworkPolicy |
| 1.4 | `/kubernetes/17` · `17-pod-multicontainer.md` | `bash kubernetes/17-pod-multicontainer.sh` | init container, sidecar nativo, SIGTERM e PID 1 |
| 1.5 | `/kubernetes/19` · `19-dns-service-discovery.md` | `bash kubernetes/19-dns-service-discovery.sh` (scarica circa 200 MB) | `resolv.conf`, `ndots:5`, come un nome diventa un IP |
| 1.6 | `lezioni/kubernetes/21-architettura-e-haproxy.md` | prima `minikube -p lab stop`, poi `bash kubernetes/21-architettura-e-haproxy.sh` (crea un cluster **suo**, `lab-haproxy`: 5 nodi da 1 GiB) | HAProxy come Ingress controller via Helm, traffico diretto ai Pod, Runtime API senza reload, rate limit per replica |

Controllo prima di cominciare ogni giorno:

```bash
kubectl config current-context     # deve dire: lab
kubectl get nodes                  # lab e lab-m02, Ready
```

Se il cluster è spento: `minikube -p lab start`. Se non c'è più: rilancia la 01.

## Fase 2 — Kubernetes: configurazione e dati

| Passo | Leggi | Lancia | Cosa devi aver capito |
|---|---|---|---|
| 2.1 | `/kubernetes/4` · `04-configmap-secret.md` | `bash kubernetes/04-configmap-secret.sh` | ConfigMap come variabile e come file; la variabile non si aggiorna finché non ci sono Pod nuovi |
| 2.2 | `/kubernetes/5` · `05-statefulset-storage-pdb.md` | `bash kubernetes/05-statefulset-storage-pdb.sh` | StatefulSet, un PVC per Pod, DNS stabile, drain con PDB |

## Fase 3 — Kubernetes: risorse, squadre e sicurezza

| Passo | Leggi | Lancia | Cosa devi aver capito |
|---|---|---|---|
| 3.1 | `/kubernetes/6` · `06-scheduling-autoscaling.md` | `bash kubernetes/06-scheduling-autoscaling.sh` | requests, distribuzione sui nodi, taint, HPA |
| 3.2 | `/kubernetes/18` · `18-namespace-quote.md` | `bash kubernetes/18-namespace-quote.sh` | ResourceQuota e LimitRange; rete fra namespace |
| 3.3 | `/kubernetes/7` · `07-rbac-pod-security.md` | `bash kubernetes/07-rbac-pod-security.sh` | ServiceAccount, Role, `auth can-i`, Pod Security |
| 3.4 | `/kubernetes/20` · `20-api-crd-threat-model.md` | `bash kubernetes/20-api-crd-threat-model.sh` | l'API REST, 401 contro 403, un CRD, STRIDE |

## Fase 4 — Ripasso: diagnosticare e uno stack vero

| Passo | Leggi | Lancia | Cosa devi aver capito |
|---|---|---|---|
| 4.1 | `/kubernetes/8` · `08-troubleshooting.md` | `bash kubernetes/08-troubleshooting.sh` | il metodo per 5 guasti: ImagePull, CrashLoop, OOM, Pending, Service senza endpoint |
| 4.2 | `README.md` sezione 4 · `stack/stack.yaml` | `bash stack/stack.sh` | una catena HAProxy → nginx → PHP → Redis + MariaDB, il bilanciamento, un Pod cancellato senza errori |

Esercizio di fine fase: cambia repliche o configurazione in `stack/stack.yaml`, riapplica con
`kubectl apply -f stack/stack.yaml` e **prevedi** cosa vedrai prima di guardare.
Pulizia: `kubectl delete namespace stack-web`.

## Fase 5 — Helm e Kustomize

| Passo | Leggi | Lancia | Cosa devi aver capito |
|---|---|---|---|
| 5.1 | `/kubernetes/9` · `09-helm-chart.md` | `bash kubernetes/09-helm-chart.sh` | un chart da zero: lint, template, install, upgrade, rollback |
| 5.2 | `/kubernetes/10` · `10-helm-avanzato.md` | `bash kubernetes/10-helm-avanzato.sh` (**usa il chart `eco` della 09**) | chart ombrello, hook, `helm test`, registry OCI |
| 5.3 | `/kubernetes/11` · `11-kustomize.md` | `bash kubernetes/11-kustomize.sh` | base e overlay, configMapGenerator, `kubectl diff` |

## Fase 6 — Terraform

Non serve il cluster: i laboratori usano Docker. Spegnilo pure (`minikube -p lab stop`).

| Passo | Leggi | Lancia | Cosa devi aver capito |
|---|---|---|---|
| 6.1 | `/terraform/1` · `terraform/01-workflow-provider-state.md` | `bash terraform/01-workflow-provider-state.sh` | init, plan, apply, state, drift, destroy |
| 6.2 | `/terraform/2` · `terraform/02-variabili-for-each-espressioni.md` | `bash terraform/02-variabili-for-each-espressioni.sh` | variabili con validation, `for_each`, output |
| 6.3 | `/terraform/3` · `terraform/03-stato-remoto-import-moved.md` | `bash terraform/03-stato-remoto-import-moved.sh` (**ti serve un secondo terminale** per il lock) | state su PostgreSQL con lock, import, `moved` |
| 6.4 | `/terraform/4` · `terraform/04-moduli-ambienti.md` | `bash terraform/04-moduli-ambienti.sh` | un modulo, due ambienti con state separati |
| 6.5 | `/terraform/5` · `terraform/05-test-check-pipeline.md` | `bash terraform/05-test-check-pipeline.sh` | `terraform test` con mock, blocco `check` |

## Fase 7 — Ansible, e Terraform insieme ad Ansible

| Passo | Leggi | Lancia | Cosa devi aver capito |
|---|---|---|---|
| 7.1 | `/terraform/6` · `terraform/06-ansible-inventario-adhoc.md` | `bash terraform/06-ansible-inventario-adhoc.sh` (crea `web1`, `web2`, `db1`, che **restano accesi** per 07–09) | inventario, comandi ad-hoc, idempotenza |
| 7.2 | `/terraform/7` · `terraform/07-ansible-playbook.md` | `bash terraform/07-ansible-playbook.sh` | playbook, check e diff, handler, tag, lint |
| 7.3 | `/terraform/8` · `terraform/08-ansible-ruoli-collection.md` | `bash terraform/08-ansible-ruoli-collection.sh` | un ruolo con argument_specs |
| 7.4 | `/terraform/9` · `terraform/09-ansible-vault-rolling-update.md` | `bash terraform/09-ansible-vault-rolling-update.sh` (**serve anche la 07**: nginx sulla porta 80) | segreti con Vault, rolling update a lotti |
| 7.5 | `/terraform/10` · `terraform/10-terraform-piu-ansible.md` | `bash terraform/10-terraform-piu-ansible.sh` | Terraform crea i nodi e scrive l'inventario, Ansible li configura |

Pulizia: `docker rm -f web1 web2 db1`.

## Fase 8 — CI/CD e GitOps con Argo CD

Serve il cluster `lab` acceso, e le fasi 5 (il chart `eco`) e 6 (Terraform).

| Passo | Leggi | Lancia | Cosa devi aver capito |
|---|---|---|---|
| 8.1 | `/kubernetes/12` · `12-cicd-gitops.md` | `bash kubernetes/12-cicd-gitops.sh` (**usa la 09**) | build → scansione con Trivy → push → deploy con Helm |
| 8.2 | `/kubernetes/16` · `lezioni/kubernetes/16-argocd-gitops.md` | — (la lezione **si legge**: il laboratorio è `argocd/`) | Application, sync, self-heal, prune |
| 8.3 | `argocd/comune.md`, `argocd/01-installa-argocd.md` | `bash argocd/01-installa-argocd.sh` | i pezzi di Argo CD, la UI su `https://192.168.1.79:8083` dal Mac |
| 8.4 | `argocd/gitea.md`, `argocd/02-git-locale.md` | `bash argocd/02-git-locale.sh` | git come fonte di verità, Gitea nel cluster |
| 8.5 | `argocd/03-terraform-e-sito.md` | `bash argocd/03-terraform-e-sito.sh` | cosa fa Terraform e cosa Argo CD |
| 8.6 | `argocd/04-gitops.md` | `bash argocd/04-gitops.sh` | una versione = un commit, rollback = `git revert`, la quota vale anche per Argo |
| 8.7 | `argocd/05-stack-con-argocd.md` | `bash argocd/05-stack-con-argocd.sh` (facoltativo) | uno stack esistente sotto Argo, `prune: true` |
| 8.8 | `argocd/99-pulizia.md` | `bash argocd/99-pulizia.sh` | l'ordine giusto per smontare |

I commit della fase 8 si fanno in `lavoro/argocd/mio-progetto`, non in `argocd/mio-progetto` (che è il modello).

## Fase 9 — Osservabilità (pesante: una alla volta)

| Passo | Leggi | Lancia | Cosa devi aver capito |
|---|---|---|---|
| 9.1 | `/kubernetes/13` · `13-observability.md` | `bash kubernetes/13-observability.sh` (circa 1,5 GB in più) | Prometheus, ServiceMonitor, PromQL, alert, Grafana |
| 9.2 | `/kubernetes/14` · `14-logging-alerting.md` | `bash kubernetes/14-logging-alerting.sh` | Loki, LogQL, Alertmanager, burn rate |

Prima della 13 togli i laboratori precedenti (la «Pulizia» in fondo a ogni script, `argocd/99-pulizia.sh`).
Grafana dal Mac: `README.md` sezione 3.3. Gli alert `TargetDown` ed `etcd…` sono normali su minikube (README sezione 9).

## Fase 10 — Un'altra distribuzione: MicroK8s

| Passo | Leggi | Lancia | Cosa devi aver capito |
|---|---|---|---|
| 10.1 | `/kubernetes/15` · `15-stack-microk8s.md` · `README.md` sezione 3.4 | prima `minikube -p lab stop`, poi `bash kubernetes/15-stack-microk8s.sh` | le differenze fra minikube, MicroK8s e k3s |

MicroK8s è già installato (`snap list microk8s`). Tienine acceso **uno** fra minikube e MicroK8s.
Pulizia: `bash lezioni/kubernetes/15-stack-microk8s.sh smonta`.

## Fase 11 — Il progetto vero

Il riquadro «NEL PROGETTO VERO» in fondo all'intestazione di ogni file in `lezioni/` dice dove lo stesso concetto
compare nel Biodistretto su minikube (`~/biodistretto/kubernetes`, branch `kubernetes`), con un `grep` da lanciare.
Rileggi le lezioni nell'ordine della tabella del `README.md` sezione 10 e fai gli esercizi sul cluster vero.

---

## Errori noti nelle lezioni (non sono colpa tua)

Trovati scrivendo le spiegazioni e non ancora misurati sul cluster; i `.md` li segnalano. Gli altri (Kubernetes 09
e 13, Terraform 01, 03, 07 e 09, Argo CD 99) sono stati corretti nelle lezioni. Se vedi qualcosa di diverso da quello
che promette lo script, guarda prima qui:

| Lezione | Cosa succede |
|---|---|
| Kubernetes 05 | (da verificare) con lo storage `standard` di minikube su 2 nodi, una replica spostata su un altro nodo può non ritrovare i dati |
| Kubernetes 06 | (da verificare) il Deployment `api` parte con 1 replica: al passo 2 puoi vedere un solo Pod |

## Alla fine di ogni giornata

```bash
minikube -p lab stop        # il cluster si ferma e si conserva
docker ps                   # restano solo i container che vuoi tu
```

Spegnere tutto e tornare a un PC pulito: `README.md` sezione 8.

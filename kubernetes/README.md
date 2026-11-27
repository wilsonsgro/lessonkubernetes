# Script guidati delle lezioni Kubernetes

Ogni script esegue una lezione un passo alla volta: stampa cosa sta per fare e il comando, poi aspetta
**Invio** (esegui) · **s** (salta) · **q** (esci). Variabili: `AUTO=1` esegue tutto, `DA=n` parte dal passo n.
Come funziona e cosa fare se qualcosa non va: `../README.md`, sezioni 1, 3 e 9.

La **spiegazione** di ogni lezione sta in `../lezioni/kubernetes/NN-….md`: la teoria, gli oggetti campo per campo,
la tabella dei passi di questo script (cosa vedi, quali falliscono apposta), le domande da colloquio e gli esercizi.
Il file della lezione vero e proprio (`.sh` o `.yaml`) è accanto alla spiegazione.

| Script | Cosa impari | Dipende da | Spiegazione |
|---|---|---|---|
| `01-architettura-e-lab.sh` | crea il cluster `lab` (2 nodi, Calico, ingress, metrics-server); control plane, Pod statici, etcd, risorse vere del container-nodo, auto-riparazione, i tre IP | — | [01](../lezioni/kubernetes/01-architettura-e-lab.md) |
| `02-deployment-rollout-probe.sh` | Deployment, rolling update, rollback, probe, QoS | 01 | [02](../lezioni/kubernetes/02-deployment-rollout-probe.md) |
| `03-service-ingress-networkpolicy.sh` | Service, EndpointSlice, Ingress, NetworkPolicy (un Pod passa, l'altro no) | **la 02 applicata** | [03](../lezioni/kubernetes/03-service-ingress-networkpolicy.md) |
| `04-configmap-secret.sh` | ConfigMap come variabile d'ambiente e come file, aggiornamento a caldo, Secret | 01 | [04](../lezioni/kubernetes/04-configmap-secret.md) |
| `05-statefulset-storage-pdb.sh` | StatefulSet, un PVC per Pod, DNS stabile, drain con PDB | 01 | [05](../lezioni/kubernetes/05-statefulset-storage-pdb.md) |
| `06-scheduling-autoscaling.sh` | distribuzione sui nodi, taint, HPA che sale sotto carico | 01 | [06](../lezioni/kubernetes/06-scheduling-autoscaling.md) |
| `07-rbac-pod-security.sh` | ServiceAccount, Role, `auth can-i`, Pod Security "restricted" | 01 | [07](../lezioni/kubernetes/07-rbac-pod-security.md) |
| `08-troubleshooting.sh` | 5 guasti creati apposta (ImagePull, CrashLoop, OOM, Pending, Service senza endpoint) e il metodo per diagnosticarli | 01 | [08](../lezioni/kubernetes/08-troubleshooting.md) |
| `09-helm-chart.sh` | un chart scritto da zero: lint, template, install, upgrade, rollback | 01 | [09](../lezioni/kubernetes/09-helm-chart.md) |
| `10-helm-avanzato.sh` | chart ombrello, hook, `helm test`, registry OCI | **la 09** (usa il chart `eco`) | [10](../lezioni/kubernetes/10-helm-avanzato.md) |
| `11-kustomize.sh` | base e overlay dev/prod, configMapGenerator, `kubectl diff` | 01 | [11](../lezioni/kubernetes/11-kustomize.md) |
| `12-cicd-gitops.sh` | build → scansione con Trivy → push → deploy con Helm; Argo CD con self-heal | **la 09** | [12](../lezioni/kubernetes/12-cicd-gitops.md) |
| `13-observability.sh` | kube-prometheus-stack, ServiceMonitor, PromQL, alert, Grafana | 01 (pesante: circa 1,5 GB) | [13](../lezioni/kubernetes/13-observability.md) |
| `14-logging-alerting.sh` | Loki, LogQL, Alertmanager con inhibit e silence, burn rate | 01 | [14](../lezioni/kubernetes/14-logging-alerting.md) |
| `15-stack-microk8s.sh` | uno stack completo su **MicroK8s**, con le differenze rispetto a minikube e k3s | `../README.md` sezione 3.4 | [15](../lezioni/kubernetes/15-stack-microk8s.md) |
| *(nessuno script)* | **16 — Argo CD: GitOps sul tuo sito**. Il laboratorio guidato è in `../argocd/` (script 01…05) | — | [16](../lezioni/kubernetes/16-argocd-gitops.md) |
| `17-pod-multicontainer.sh` | init container, sidecar nativo (`restartPolicy: Always`), Job che finisce col sidecar acceso, SIGTERM e PID 1, Pod quasi immutabile | 01 | [17](../lezioni/kubernetes/17-pod-multicontainer.md) |
| `18-namespace-quote.sh` | ResourceQuota e LimitRange, Deployment fermo a 3/6 per la quota, rete fra Namespace aperta finché una NetworkPolicy non la chiude | 01 | [18](../lezioni/kubernetes/18-namespace-quote.md) |
| `19-dns-service-discovery.sh` | `resolv.conf`, search list e `ndots:5` misurati con tcpdump e con il log di CoreDNS, record SRV, Service senza Pod, iptables di kube-proxy | 01 (scarica netshoot, circa 200 MB) | [19](../lezioni/kubernetes/19-dns-service-discovery.md) |
| `20-api-crd-threat-model.sh` | l'API REST con `kubectl proxy` e curl (201/409/404, 401 contro 403), un CRD con schema, STRIDE con le difese misurate su due Pod | 01 | [20](../lezioni/kubernetes/20-api-crd-threat-model.md) |
| `21-architettura-e-haproxy.sh` | cluster `lab-haproxy` (5 nodi da 1 GiB, `--force`), HAProxy come Ingress controller con Helm al posto di ingress-nginx, `haproxy.cfg` scritto dal controller, `add server` senza reload, rate limit 429 | nessuna: cluster suo, a `lab` spento | [21](../lezioni/kubernetes/21-architettura-e-haproxy.md) |
| `22-architettura-haproxy-prometheus-grafana.sh` | cluster `lab-monitoring` (3 nodi da 3 GiB), kube-prometheus-stack con Helm sopra lo HAProxy della 21: PodMonitor per replica (il ServiceMonitor del chart si rompe con i NodePort), app con ServiceMonitor dietro HAProxy, PromQL, dashboard da ConfigMap, alert pending → firing con 503 | 21: i manifest della 21; cluster suo, gli altri spenti | [22](../lezioni/kubernetes/22-architettura-haproxy-prometheus-grafana.md) |
| `23-architettura-e-haproxy-ansible.sh` | cluster `lab-ansible` (5 nodi da 1 GiB), la 21 con Headlamp rifatta da un **playbook Ansible** (`kubernetes.core`): un tag per passo, `uri`+`assert` al posto dei curl, seconda corsa `changed=0`, deriva con `--check --diff` | 21: i manifest della 21; ansible-core in pipx; cluster suo, gli altri spenti | [23](../lezioni/kubernetes/23-architettura-e-haproxy-ansible.md) |

Dalla cartella principale: `cd ~/kubernetesprj && bash kubernetes/01-architettura-e-lab.sh`.

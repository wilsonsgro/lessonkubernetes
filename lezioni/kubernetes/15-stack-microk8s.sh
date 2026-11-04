#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════
# 15. STACK COMPLETO SU MICROK8S: PHP × 3, MARIADB, REDIS, ELASTICSEARCH,
#     INGRESS E HEADLAMP
# Versione: MicroK8s 1.33 · Helm 3 (microk8s helm) · Headlamp 0.46
# Livello: 6 — Laboratorio completo
# ═══════════════════════════════════════════════════════════════════════════
# Le lezioni 01–14 girano su minikube (profilo "lab", 2 nodi, Calico).
# Qui si mette insieme tutto su un cluster DIVERSO, MicroK8s, sull'Ubuntu
# 192.168.1.79: un'applicazione vera con i suoi servizi, come la si
# monterebbe su un nodo on-prem.
#
# ── MINIKUBE, MICROK8S, K3S: STESSO KUBERNETES, TRE MESTIERI ──────────────
#
#                 minikube              MicroK8s               k3s
#   chi           progetto Kubernetes   Canonical              SUSE / Rancher
#   cosa è        un cluster DENTRO     Kubernetes come snap   un unico binario
#                 una VM o un container sull'host, servizi     (~70 MB) con tutto
#                 (driver docker/kvm)   systemd veri           dentro, servizio
#                                                              systemd
#   pensato per   sviluppo locale,      dev, edge, piccoli     edge, IoT, ARM,
#                 usa e getta           cluster di produzione  produzione leggera
#   multi-nodo    --nodes=N, ma tutti   sì, nodi veri:         sì, nodi veri:
#                 sulla stessa macchina add-node / join        token + agent
#   alta          no                    sì con ≥3 nodi         sì con etcd
#   disponibilità                       (dqlite, automatica)   embedded o DB esterno
#   datastore     etcd                  dqlite (SQLite         SQLite (1 nodo),
#                                       distribuito, Raft)     etcd embedded (HA)
#   CNI default   kindnet / bridge      Calico                 Flannel
#   ingress       addon ingress-nginx   addon ingress          Traefik già dentro
#                                       (ingress-nginx)
#   storage       addon storage-        addon hostpath-        local-path-
#                 provisioner           storage                provisioner
#   kubectl       kubectl normale,      microk8s kubectl       k3s kubectl, oppure
#                 contesto "lab"        (kubeconfig suo)       /etc/rancher/k3s/
#                                                              k3s.yaml
#   estensioni    minikube addons       microk8s enable …      manifest in
#                                       (dns, ingress,         /var/lib/rancher/
#                                       metallb, …)            k3s/server/manifests
#   aggiornamenti minikube start        canale snap            binario nuovo o
#                 --kubernetes-version  (1.33/stable): snap    system-upgrade-
#                                       si aggiorna da solo    controller
#   si cancella   minikube delete:      microk8s reset /       k3s-uninstall.sh
#                 sparisce il nodo      snap remove --purge
#
# QUANDO SCEGLIERE COSA (la domanda da colloquio):
#   • minikube: provo un manifest o un chart sul portatile, poi butto via.
#     Il nodo è un container: niente porte 80/443 sull'host, serve
#     `minikube tunnel` o `minikube service`.
#   • MicroK8s: voglio qualcosa che resti acceso su una macchina, con
#     addon a un comando e HA che arriva da sola aggiungendo nodi. Gli
#     upgrade arrivano via snap: in produzione si FISSA il canale
#     (snap refresh --hold), o un aggiornamento automatico cambia il
#     cluster sotto i piedi.
#   • k3s: risorse scarse (Raspberry, edge) o tanti cluster piccoli
#     gestiti da Rancher/Fleet. Pochi pezzi, Traefik e ServiceLB inclusi.
#   Tutti e tre passano i test di conformità CNCF: i manifest di questa
#   lezione girano identici su ognuno, cambiano solo storage class e
#   ingress class.
#
# ── ARCHITETTURA ───────────────────────────────────────────────────────────
#
#   browser ──► 192.168.1.79:80 ──► Ingress (controller nginx dell'addon,
#                                     hostPort 80/443 sul nodo)
#                                        │ host: stack.lab
#                                        ▼
#                               Service php-app (ClusterIP)
#                               ┌────────┼────────┐
#                               ▼        ▼        ▼
#                            php-app  php-app  php-app   Deployment, 3 repliche
#                               │        │        │
#             ┌─────────────────┼────────┴────────┼──────────────┐
#             ▼                 ▼                 ▼              │
#      mariadb:3306       redis:6379      elasticsearch:9200     │
#      StatefulSet + PVC  Deployment      StatefulSet + PVC      │
#      Secret per le      (cache, niente  single-node,           │
#      credenziali        persistenza)    security off (lab)     │
#                                                                │
#   Headlamp (namespace headlamp, NodePort) ── legge il cluster con il
#   token di un ServiceAccount a sola lettura
#
# Niente chart di terzi per i dati: StatefulSet scritti a mano con le
# immagini ufficiali. Si vede cosa c'è sotto un chart e si riusa quello
# che hai fatto nelle lezioni 04 (Secret) e 05 (StatefulSet e PVC).
#
# USO (sull'Ubuntu, utente nel gruppo microk8s):
#   bash 15-stack-microk8s.sh installa    # una volta: snap + gruppo
#   bash 15-stack-microk8s.sh addon       # dns, hostpath-storage, ingress
#   bash 15-stack-microk8s.sh dati        # MariaDB, Redis, Elasticsearch
#   bash 15-stack-microk8s.sh app         # PHP × 3 + Ingress
#   bash 15-stack-microk8s.sh headlamp    # UI + ServiceAccount in lettura
#   bash 15-stack-microk8s.sh verifica    # chi risponde, da quale pod
#   bash 15-stack-microk8s.sh certificati # SAN dopo un cambio di IP
#   bash 15-stack-microk8s.sh smonta      # via namespace, cluster fermo

set -euo pipefail
K="microk8s kubectl"
H="microk8s helm"
NS=stack
NODO=192.168.1.79

installa() {
  sudo snap install microk8s --classic --channel=1.33/stable
  sudo snap refresh --hold microk8s
  sudo usermod -a -G microk8s "$USER"
  mkdir -p ~/.kube && chmod 0700 ~/.kube
  # il gruppo vale dalla prossima login; newgrp lo apre in una subshell
  echo "ora: newgrp microk8s   (oppure esci e rientra)"
}

addon() {
  sudo microk8s start
  microk8s status --wait-ready >/dev/null
  # dns:             CoreDNS, senza non si risolve "mariadb"
  # hostpath-storage: StorageClass microk8s-hostpath (cartelle sul nodo,
  #                   va bene per UN nodo; con più nodi serve uno storage
  #                   di rete, es. addon rook-ceph o NFS)
  # ingress:         controller nginx in DaemonSet, ascolta su 80/443 del nodo
  microk8s enable dns
  microk8s enable hostpath-storage
  microk8s enable ingress
  $K get storageclass
  $K get ingressclass
}

dati() {
  $K create namespace $NS --dry-run=client -o yaml | $K apply -f -

  # Le credenziali in un Secret, non nelle env del Deployment: chi può
  # leggere il Deployment non vede le password (RBAC separato, lezione 07).
  $K -n $NS create secret generic mariadb-cred \
    --from-literal=MARIADB_ROOT_PASSWORD="$(openssl rand -hex 16)" \
    --from-literal=MARIADB_DATABASE=appdb \
    --from-literal=MARIADB_USER=app \
    --from-literal=MARIADB_PASSWORD="$(openssl rand -hex 16)" \
    --dry-run=client -o yaml | $K apply -f -

  $K -n $NS apply -f - <<'EOF'
apiVersion: v1
kind: Service
metadata:
  name: mariadb
spec:
  clusterIP: None              # headless: DNS stabile mariadb-0.mariadb
  selector: { app: mariadb }
  ports: [{ name: mysql, port: 3306 }]
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: mariadb
spec:
  serviceName: mariadb
  replicas: 1
  selector: { matchLabels: { app: mariadb } }
  template:
    metadata: { labels: { app: mariadb } }
    spec:
      containers:
        - name: mariadb
          image: mariadb:11.8          # LTS
          envFrom: [{ secretRef: { name: mariadb-cred } }]
          ports: [{ containerPort: 3306, name: mysql }]
          # durante l'init l'entrypoint avvia il server con
          # --skip-networking: la porta apre solo a database pronto
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
---
apiVersion: v1
kind: Service
metadata:
  name: redis
spec:
  selector: { app: redis }
  ports: [{ name: redis, port: 6379 }]
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: redis
spec:
  replicas: 1
  selector: { matchLabels: { app: redis } }
  template:
    metadata: { labels: { app: redis } }
    spec:
      containers:
        - name: redis
          image: redis:8-alpine
          # cache pura: niente RDB/AOF, al riavvio riparte vuota.
          # Se Redis tiene dati veri → StatefulSet + PVC come MariaDB.
          args: ["--save", "", "--appendonly", "no"]
          ports: [{ containerPort: 6379, name: redis }]
          readinessProbe:
            exec: { command: [redis-cli, ping] }
            periodSeconds: 5
          resources:
            requests: { cpu: 50m, memory: 64Mi }
            limits: { memory: 128Mi }
---
apiVersion: v1
kind: Service
metadata:
  name: elasticsearch
spec:
  selector: { app: elasticsearch }
  ports: [{ name: http, port: 9200 }]
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: elasticsearch
spec:
  serviceName: elasticsearch
  replicas: 1
  selector: { matchLabels: { app: elasticsearch } }
  template:
    metadata: { labels: { app: elasticsearch } }
    spec:
      securityContext:
        fsGroup: 1000                 # l'utente elasticsearch deve scrivere nel PVC
      containers:
        - name: elasticsearch
          image: docker.elastic.co/elasticsearch/elasticsearch:9.1.2
          env:
            # single-node salta i bootstrap check (vm.max_map_count ecc.):
            # in un cluster vero vanno soddisfatti sul nodo
            - { name: discovery.type, value: single-node }
            - { name: xpack.security.enabled, value: "false" }
            # heap = metà del limite: l'altra metà serve alla page cache
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
  volumeClaimTemplates:
    - metadata: { name: dati }
      spec:
        accessModes: [ReadWriteOnce]
        storageClassName: microk8s-hostpath
        resources: { requests: { storage: 5Gi } }
EOF

  $K -n $NS rollout status statefulset/mariadb --timeout=180s
  $K -n $NS rollout status deployment/redis --timeout=120s
  $K -n $NS rollout status statefulset/elasticsearch --timeout=300s
  $K -n $NS get pods,svc,pvc
}

app() {
  # index.php in una ConfigMap: l'immagine resta quella ufficiale.
  # Parla con i tre servizi senza estensioni PHP: handshake MariaDB,
  # protocollo Redis a mano, HTTP verso Elasticsearch.
  $K -n $NS apply -f - <<'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: php-app
data:
  index.php: |
    <?php
    header('Content-Type: application/json');
    $r = ['pod' => gethostname()];

    $s = @fsockopen(getenv('DB_HOST'), 3306, $en, $em, 2);
    if ($s) {
        $hello = fread($s, 256);
        $r['mariadb'] = explode("\0", substr($hello, 5))[0];
        fclose($s);
    } else { $r['mariadb'] = "KO: $em"; }

    $s = @fsockopen(getenv('REDIS_HOST'), 6379, $en, $em, 2);
    if ($s) {
        fwrite($s, "INCR visite\r\n");
        $r['redis_visite'] = (int) trim(fgets($s), ":\r\n");
        fclose($s);
    } else { $r['redis_visite'] = "KO: $em"; }

    $es = @file_get_contents(getenv('ELASTIC_URL'), false,
        stream_context_create(['http' => ['timeout' => 2]]));
    $r['elasticsearch'] = $es ? json_decode($es, true)['version']['number'] : 'KO';

    echo json_encode($r, JSON_PRETTY_PRINT), "\n";
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: php-app
spec:
  replicas: 3
  selector: { matchLabels: { app: php-app } }
  template:
    metadata: { labels: { app: php-app } }
    spec:
      containers:
        - name: php
          image: php:8.4-apache
          ports: [{ containerPort: 80, name: http }]
          env:
            # nome corto: risolto dentro il namespace grazie al search
            # del resolv.conf (stack.svc.cluster.local)
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
---
apiVersion: v1
kind: Service
metadata:
  name: php-app
spec:
  selector: { app: php-app }
  ports: [{ name: http, port: 80, targetPort: http }]
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: php-app
spec:
  ingressClassName: public          # la classe che crea l'addon di MicroK8s
  rules:
    - host: stack.lab
      http:
        paths:
          - path: /
            pathType: Prefix
            backend: { service: { name: php-app, port: { name: http } } }
EOF
  $K -n $NS rollout status deployment/php-app --timeout=120s
  $K -n $NS get pods -l app=php-app -o wide
}

headlamp() {
  $H repo add headlamp https://kubernetes-sigs.github.io/headlamp/ 2>/dev/null || true
  $H repo update headlamp

  # Di default il chart lega il ServiceAccount DEL POD a cluster-admin:
  # chiunque entri nel pod (o sfrutti una falla di Headlamp) ha il
  # cluster. Il pod non deve avere permessi: Headlamp usa il token che
  # incolli nel login, quindi i permessi stanno nel token.
  $H upgrade --install headlamp headlamp/headlamp \
    -n headlamp --create-namespace \
    --set clusterRoleBinding.create=false \
    --set service.type=NodePort \
    --wait

  # Utente di tutti i giorni: ClusterRole "view" (built-in), legge quasi
  # tutto tranne i Secret.
  $K -n headlamp create serviceaccount headlamp-lettore \
    --dry-run=client -o yaml | $K apply -f -
  $K create clusterrolebinding headlamp-lettore \
    --clusterrole=view --serviceaccount=headlamp:headlamp-lettore \
    --dry-run=client -o yaml | $K apply -f -

  local porta
  porta="$($K -n headlamp get svc headlamp -o jsonpath='{.spec.ports[0].nodePort}')"
  echo "UI:    http://$NODO:$porta"
  echo "token (scade fra 8 ore, non finisce in nessun Secret):"
  $K -n headlamp create token headlamp-lettore --duration=8h
  # Un token che non scade (Secret di tipo service-account-token) è un
  # anti-pattern dal 1.24: se esce da un laptop vale per sempre.
  # Per scrivere da Headlamp: un secondo SA con un Role nel SOLO
  # namespace stack, non cluster-admin.
}

verifica() {
  # 6 richieste: il Service distribuisce sui 3 pod, Redis conta per tutti
  for _ in 1 2 3 4 5 6; do
    curl -s -H 'Host: stack.lab' "http://$NODO/" | tr -d '\n '; echo
  done
  # dal Mac, senza toccare /etc/hosts:
  #   curl -H 'Host: stack.lab' http://192.168.1.79/
  echo "--- endpoint dietro al Service:"
  $K -n $NS get endpointslices -l kubernetes.io/service-name=php-app
  echo "--- il token di sola lettura non legge i Secret:"
  $K auth can-i get secrets -n $NS --as=system:serviceaccount:headlamp:headlamp-lettore || true
  $K auth can-i list pods -n $NS --as=system:serviceaccount:headlamp:headlamp-lettore
}

certificati() {
  # MicroK8s mette gli IP del nodo nei SAN dei certificati AL MOMENTO in
  # cui li genera. Se il DHCP cambia l'IP (successo davvero: .58 → .79),
  # kubectl remoto e `kubectl exec`/`logs` falliscono con
  #   x509: certificate is valid for 192.168.1.58, not 192.168.1.79
  # exec e logs passano dall'apiserver al KUBELET: per quelli conta
  # kubelet.crt, non server.crt.
  for c in server kubelet; do
    echo "== $c.crt"
    openssl x509 -in /var/snap/microk8s/current/certs/$c.crt \
      -noout -ext subjectAltName | tr ',' '\n' | grep 'IP Address'
  done
  sudo microk8s refresh-certs --check
  # Cura:
  #   server.crt   sudo microk8s refresh-certs --cert server.crt
  #   kubelet.crt  (non è tra i --cert supportati)
  #                sudo microk8s stop
  #                sudo /snap/microk8s/current/actions/common/utils.sh \
  #                     create_user_certs_and_configs
  #                sudo microk8s start
  # Prevenzione: IP statico o prenotazione DHCP per i nodi. Gli IP extra
  # stabili vanno in /var/snap/microk8s/current/certs/csr.conf.template
  # (IP.N = …) prima di rigenerare.
}

smonta() {
  $H uninstall headlamp -n headlamp || true
  $K delete clusterrolebinding headlamp-lettore --ignore-not-found
  # i PVC dei StatefulSet NON si cancellano con lo StatefulSet: cadono
  # solo con il namespace (o a mano). È voluto: proteggono i dati.
  $K delete namespace $NS headlamp --ignore-not-found --wait
  sudo microk8s stop
  # Ripartire da zero, addon e dati compresi:  sudo microk8s reset
  # Togliere tutto:                            sudo snap remove microk8s --purge
}

case "${1:-}" in
  installa) installa ;;
  addon) addon ;;
  dati) dati ;;
  app) app ;;
  headlamp) headlamp ;;
  verifica) verifica ;;
  certificati) certificati ;;
  smonta) smonta ;;
  *) echo "uso: $0 installa|addon|dati|app|headlamp|verifica|certificati|smonta" ;;
esac

# ── DOMANDE DA COLLOQUIO ───────────────────────────────────────────────────
# D: Perché MariaDB è uno StatefulSet e PHP un Deployment?
# R: Il DB ha identità e disco suoi: nome stabile (mariadb-0), PVC che lo
#    segue a ogni riavvio, avvio e stop ordinati. Le repliche PHP sono
#    intercambiabili: nessuno stato locale, si scalano e si sostituiscono.
#
# D: Le 3 repliche PHP condividono le sessioni utente?
# R: Solo se le sessioni non stanno nel filesystem del pod. Qui andrebbero
#    in Redis (session.save_handler=redis): altrimenti ogni richiesta che
#    cambia pod perde il login. In alternativa sticky session sull'ingress,
#    che però maschera il problema invece di risolverlo.
#
# D: Redis come Deployment senza volume: cosa succede se il pod muore?
# R: Riparte vuoto. Per una cache va bene, per code o sessioni importanti
#    no: StatefulSet + PVC + AOF, o un Redis gestito.
#
# D: Su MicroK8s a un nodo con hostpath-storage, cosa non hai?
# R: Né HA né storage che segua i pod: il PV è una cartella su QUEL nodo.
#    Con 3 nodi MicroK8s il control plane diventa HA da solo (dqlite), ma
#    i dati restano legati al nodo finché non metti uno storage di rete.
#
# D: Headlamp, Dashboard, Lens: dove stanno i permessi?
# R: Nel token con cui l'utente entra, non nel pod della UI. Il pod con
#    cluster-admin è la configurazione di default di molti chart ed è un
#    privilege escalation pronto: chi raggiunge la UI raggiunge il cluster.
#
# D: Il controller dell'addon ingress di MicroK8s è ingress-nginx. Cosa
#    sai del suo futuro?
# R: Il progetto ingress-nginx della comunità Kubernetes è stato messo in
#    ritiro (manutenzione fino a marzo 2026). Le strade: Gateway API con
#    un'implementazione (Envoy Gateway, Traefik, NGINX Gateway Fabric) o
#    un controller Ingress mantenuto (Traefik, HAProxy — vedi il corso
#    HAProxy & Traefik). Su k3s Traefik c'è già.

# ══════════════════════════════════════════════════════════════════════════
# RIEPILOGO
# • minikube = cluster usa e getta in un container; MicroK8s = snap con
#   addon e HA via dqlite; k3s = binario unico per edge. Stessa API.
# • Dati: StatefulSet + PVC + Secret; app stateless: Deployment × 3 dietro
#   Service e Ingress (classe "public" su MicroK8s)
# • Headlamp: pod senza permessi, token a tempo di un SA con "view"
# • Cambio IP del nodo → SAN dei certificati: server.crt e kubelet.crt
# • snap refresh --hold: un cluster non si aggiorna da solo in produzione
# ══════════════════════════════════════════════════════════════════════════

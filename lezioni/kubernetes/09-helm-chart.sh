#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════
# 09. HELM: UN CHART SCRITTO DA ZERO, INSTALL, UPGRADE E ROLLBACK
# Versione: Helm 4.3 · Kubernetes 1.35
# Livello: 4 — Packaging e delivery
# ═══════════════════════════════════════════════════════════════════════════
# Helm risolve tre problemi che kubectl apply non risolve:
#   1. PARAMETRI     un solo set di template, valori diversi per ambiente
#   2. RELEASE       un nome che raggruppa tutti gli oggetti installati,
#                    con una storia numerata (revision) salvata nel cluster
#                    come Secret di tipo helm.sh/release.v1
#   3. CICLO DI VITA install, upgrade, rollback, uninstall, hook, test
#
# HELM 4 (novembre 2025) rispetto al 3, da sapere al colloquio:
#   • server-side apply di default per le release nuove (field ownership)
#   • --atomic → --rollback-on-failure, --force → --force-replace
#   • --wait ha strategie: watcher (kstatus, default con --wait), legacy
#   • plugin in WebAssembly, chart v2 invariati (i chart Helm 3 funzionano)
#
# LAB (sul tuo Ubuntu c'è helm v4.3.1)
#   bash 09-helm-chart.sh crea       # scrive ./eco
#   bash 09-helm-chart.sh prova      # lint, template, install, upgrade, rollback
#
# ── NEL PROGETTO VERO: il Biodistretto su minikube ───────────────────────
#   ~/biodistretto/kubernetes (branch kubernetes). I grep partono da lì:
#   cd ~/biodistretto/kubernetes · come si usa: il README della cartella
#   Il progetto NON usa Helm. Usa YAML con ${variabili}, resi da
#   templatefile e separati in oggetti con manifest_decode_multi:
#     grep -n 'manifest_decode_multi' terraform/app/workload.tf
#     grep -n -F '${repliche}' terraform/app/manifests/app.yaml.tftpl
#   Le stesse cose, a confronto: values.yaml ↔ variables.tf;
#   release e revision ↔ tfstate; rollback ↔ git revert e apply.
#   Perché qui va bene così: i segreti e la CA li crea Terraform nello
#   stesso grafo, senza passarli a Helm.
#   ESERCIZIO: trasforma app.yaml.tftpl in un chart (${x} → {{ .Values.x }}),
#   poi confronta l'output di `helm template` con quello che c'è nel cluster.

set -euo pipefail
CHART=./eco
NS=lab-helm

crea() {
  mkdir -p $CHART/templates

  # ── Chart.yaml: version = versione del CHART, appVersion = dell'APP ─────
  cat > $CHART/Chart.yaml <<'EOF'
apiVersion: v2
name: eco
description: Un servizio HTTP di esempio
type: application        # "library" = solo helper, non installabile
version: 0.1.0           # SemVer del chart: si alza a ogni modifica del chart
appVersion: "v1.12"      # versione dell'app, usata come tag di default
EOF

  # ── values.yaml: l'interfaccia pubblica del chart ───────────────────────
  cat > $CHART/values.yaml <<'EOF'
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
EOF

  # ── values.schema.json: valida i valori PRIMA di renderizzare ───────────
  cat > $CHART/values.schema.json <<'EOF'
{
  "$schema": "https://json-schema.org/draft-07/schema#",
  "type": "object",
  "required": ["replicaCount", "image"],
  "properties": {
    "replicaCount": { "type": "integer", "minimum": 1 },
    "image": {
      "type": "object",
      "required": ["repository"],
      "properties": { "repository": { "type": "string", "minLength": 1 } }
    }
  }
}
EOF

  # ── _helpers.tpl: i "define" riusabili; i file con _ non producono YAML ─
  cat > $CHART/templates/_helpers.tpl <<'EOF'
{{- define "eco.fullname" -}}
{{- if contains .Chart.Name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name .Chart.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{- define "eco.selectorLabels" -}}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "eco.labels" -}}
{{ include "eco.selectorLabels" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version }}
{{- end -}}
EOF

  cat > $CHART/templates/configmap.yaml <<'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ include "eco.fullname" . }}
  labels: {{- include "eco.labels" . | nindent 4 }}
data:
  MESSAGGIO: {{ .Values.config.messaggio | quote }}
EOF

  cat > $CHART/templates/deployment.yaml <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ include "eco.fullname" . }}
  labels: {{- include "eco.labels" . | nindent 4 }}
spec:
  replicas: {{ .Values.replicaCount }}
  selector:
    matchLabels: {{- include "eco.selectorLabels" . | nindent 6 }}
  template:
    metadata:
      labels: {{- include "eco.selectorLabels" . | nindent 8 }}
      annotations:
        # cambia il ConfigMap → cambia l'hash → cambia il template → rollout
        checksum/config: {{ include (print $.Template.BasePath "/configmap.yaml") . | sha256sum }}
    spec:
      containers:
        - name: eco
          image: "{{ .Values.image.repository }}:{{ .Values.image.tag | default .Chart.AppVersion }}"
          imagePullPolicy: {{ .Values.image.pullPolicy }}
          args: ["--port", "8080", "--name", "$(MESSAGGIO)"]
          envFrom:
            - configMapRef:
                name: {{ include "eco.fullname" . }}
          ports:
            - name: http
              containerPort: 8080
          readinessProbe:
            httpGet: { path: /health, port: http }
          {{- with .Values.resources }}
          resources: {{- toYaml . | nindent 12 }}
          {{- end }}
EOF

  cat > $CHART/templates/service.yaml <<'EOF'
apiVersion: v1
kind: Service
metadata:
  name: {{ include "eco.fullname" . }}
  labels: {{- include "eco.labels" . | nindent 4 }}
spec:
  selector: {{- include "eco.selectorLabels" . | nindent 4 }}
  ports:
    - name: http
      port: {{ .Values.service.port }}
      targetPort: http
EOF

  cat > $CHART/templates/ingress.yaml <<'EOF'
{{- if .Values.ingress.enabled }}
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: {{ include "eco.fullname" . }}
  labels: {{- include "eco.labels" . | nindent 4 }}
spec:
  ingressClassName: nginx
  rules:
    - host: {{ required "ingress.host è obbligatorio con ingress.enabled" .Values.ingress.host }}
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: {{ include "eco.fullname" . }}
                port: { name: http }
{{- end }}
EOF

  cat > $CHART/templates/NOTES.txt <<'EOF'
{{ .Release.Name }} installato (revision {{ .Release.Revision }}).
  kubectl -n {{ .Release.Namespace }} port-forward svc/{{ include "eco.fullname" . }} 8080:{{ .Values.service.port }}
EOF

  cat > $CHART/.helmignore <<'EOF'
.git/
*.tgz
EOF
  echo "chart scritto in $CHART"
}

prova() {
  [[ "$(kubectl config current-context)" == "lab" ]] || { echo "STOP: contesto non 'lab'" >&2; exit 1; }

  helm lint $CHART --strict
  # template = rendering locale, senza cluster: è ciò che si rivede in PR
  helm template prova $CHART --set ingress.enabled=true | head -40
  # lo schema blocca i valori sbagliati prima di toccare il cluster
  helm template prova $CHART --set replicaCount=0 && exit 1 || echo "OK: replicaCount=0 rifiutato"

  # install idempotente: upgrade --install è la forma da usare in CI
  helm upgrade --install eco $CHART -n $NS --create-namespace \
    --wait --timeout 2m
  helm -n $NS history eco

  # upgrade con un valore diverso: il checksum fa ripartire i Pod
  helm upgrade eco $CHART -n $NS --reuse-values \
    --set config.messaggio="seconda versione" --wait --timeout 2m

  # upgrade che fallisce: immagine inesistente → rollback automatico
  helm upgrade eco $CHART -n $NS --reuse-values \
    --set image.tag=v9.9.9 --rollback-on-failure --timeout 60s \
    || echo "OK: upgrade fallito e annullato"
  helm -n $NS history eco             # revision 3 failed, 4 = rollback alla 2

  helm -n $NS get values eco          # i valori forniti dall'utente
  helm -n $NS get manifest eco | grep -m1 'image:'
  helm -n $NS rollback eco 1 --wait   # torna alla prima revision
  kubectl -n $NS get secret -l owner=helm   # dove Helm salva la storia
}

case "${1:-}" in
  crea) crea ;;
  prova) prova ;;
  pulisci) helm uninstall eco -n lab-helm; kubectl delete ns lab-helm ;;
  *) echo "uso: $0 crea|prova|pulisci" ;;
esac

# ── TEMPLATE: LE COSE CHE TI CHIEDONO ───────────────────────────────────────
#   {{-  -}}           tolgono gli spazi/a capo prima/dopo: l'indentazione
#                      sbagliata è il bug Helm più comune
#   include vs template  include restituisce una stringa → si può fare
#                      | nindent; template no
#   toYaml . | nindent N  per blocchi interi (resources, tolerations)
#   required "msg" .X  fallisce il rendering se manca un valore
#   default, quote, tpl, lookup (legge il cluster: vuoto in `helm template`)
#   .Release .Chart .Values .Capabilities .Template .Files
#
# PRECEDENZA DEI VALORI (l'ultimo vince)
#   values.yaml del chart < values del chart padre < -f file1 < -f file2 < --set
#   --reuse-values riusa i valori della release ma IGNORA i nuovi default
#   del chart; --reset-then-reuse-values li unisce correttamente.

# ── DOMANDE DA COLLOQUIO ────────────────────────────────────────────────────
# D: Dove salva Helm lo stato? Cosa succede se cancello quel Secret?
# R: Un Secret per revision nel namespace della release. Cancellandoli
#    Helm "dimentica" la release ma gli oggetti restano nel cluster: un
#    install successivo fallisce per conflitto di ownership (o serve
#    --take-ownership).
#
# D: Un upgrade è rimasto in "pending-upgrade" e ogni nuovo upgrade fallisce.
# R: Un processo Helm è morto a metà (CI cancellata). `helm history`
#    mostra lo stato; si fa `helm rollback` all'ultima deployed. Se è
#    "pending-install" non c'è una revision a cui tornare: `helm uninstall`
#    e si reinstalla (successo davvero preparando la lezione 13: helm
#    interrotto a metà → "another operation (install/upgrade/rollback) is
#    in progress"). Per prevenirlo: --rollback-on-failure e timeout in CI.
#
# D: Come rivedi cosa cambierà prima di un upgrade?
# R: helm template + diff in PR, oppure il plugin helm-diff
#    (`helm diff upgrade`), oppure `--dry-run=server` che passa
#    dall'admission del cluster.

# ══════════════════════════════════════════════════════════════════════════
# RIEPILOGO
# • Chart = template + values + Chart.yaml; release = installazione con storia
# • _helpers.tpl per nomi e label; checksum/config per i rollout da config
# • values.schema.json e required: errori prima del cluster
# • upgrade --install, --wait, --rollback-on-failure (Helm 4) in CI
# • history / rollback / get values / get manifest
# ══════════════════════════════════════════════════════════════════════════

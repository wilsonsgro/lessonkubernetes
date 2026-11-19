#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════
# 10. HELM AVANZATO: DIPENDENZE, HOOK, TEST E REGISTRY OCI
# Versione: Helm 4.3 · registry OCI (distribution 3)
# Livello: 4 — Packaging e delivery
# ═══════════════════════════════════════════════════════════════════════════
# Un chart "ombrello" mette insieme più componenti; gli hook eseguono
# lavori in momenti precisi del ciclo di vita; i test verificano la
# release installata; il registry OCI distribuisce i chart come immagini.
#
# HOOK (annotazione helm.sh/hook)
#   pre-install / post-install / pre-upgrade / post-upgrade
#   pre-delete / post-delete / pre-rollback / post-rollback / test
#   helm.sh/hook-weight          ordine tra hook dello stesso tipo
#   helm.sh/hook-delete-policy   before-hook-creation | hook-succeeded | hook-failed
# Gli oggetti hook NON fanno parte della release: `helm uninstall` non li
# cancella, per questo serve la delete-policy.
# Uso tipico: migrazione del DB in pre-upgrade. Se fallisce, l'upgrade si
# ferma prima di toccare il Deployment.
#
# LAB (richiede la lezione 09: usa ./eco come dipendenza)
#   docker run -d --name registry -p 5000:5000 registry:3     # registry OCI locale
#   bash 10-helm-avanzato.sh crea
#   bash 10-helm-avanzato.sh prova
#
# ── NEL PROGETTO VERO: il Biodistretto su minikube ───────────────────────
#   ~/biodistretto/kubernetes (branch kubernetes). I grep partono da lì:
#   cd ~/biodistretto/kubernetes · come si usa: il README della cartella
#   L'equivalente di un hook post-install è il Job minio-init, che crea il
#   bucket. Terraform lo lancia dopo i dati e aspetta la condizione
#   Complete prima di creare l'app:
#     grep -n -A6 'resource "kubernetes_manifest" "minio_init"' terraform/app/workload.tf
#     grep -n -E 'backoffLimit|mc mb' terraform/app/manifests/minio-init.yaml.tftpl
#   Il Job è idempotente (--ignore-existing), così rilanciarlo non rompe.
#   Le dipendenze del chart diventano depends_on fra le risorse.

set -euo pipefail
NS=lab-piattaforma
OMBRELLO=./piattaforma

crea() {
  [[ -d ./eco ]] || { echo "prima: bash 09-helm-chart.sh crea" >&2; exit 1; }
  mkdir -p $OMBRELLO/templates/tests

  cat > $OMBRELLO/Chart.yaml <<'EOF'
apiVersion: v2
name: piattaforma
version: 1.0.0
appVersion: "1.0.0"
dependencies:
  # la stessa dipendenza due volte con alias diversi: due servizi
  - name: eco
    version: "0.1.x"            # range SemVer: accetta le patch
    repository: "file://../eco" # in produzione: oci://registry/charts
    alias: frontend
  - name: eco
    version: "0.1.x"
    repository: "file://../eco"
    alias: backend
    condition: backend.enabled  # spegnibile da values
EOF

  cat > $OMBRELLO/values.yaml <<'EOF'
global:
  ambiente: lab                 # .Values.global è visibile a tutti i subchart
frontend:                       # i valori di un subchart stanno sotto il suo nome/alias
  replicaCount: 1
  config: { messaggio: "frontend" }
backend:
  enabled: true
  replicaCount: 2
  config: { messaggio: "backend" }
migrazione:
  fallisci: false
EOF

  # ── HOOK: migrazione prima di ogni install/upgrade ─────────────────────
  cat > $OMBRELLO/templates/migrazione-job.yaml <<'EOF'
apiVersion: batch/v1
kind: Job
metadata:
  name: {{ .Release.Name }}-migrazione
  annotations:
    "helm.sh/hook": pre-install,pre-upgrade
    "helm.sh/hook-weight": "-5"
    "helm.sh/hook-delete-policy": before-hook-creation,hook-succeeded
spec:
  backoffLimit: 0
  activeDeadlineSeconds: 120
  template:
    spec:
      restartPolicy: Never
      containers:
        - name: migra
          image: busybox:1.37
          command:
            - sh
            - -c
            - |
              echo "migrazione schema per {{ .Values.global.ambiente }}, revision {{ .Release.Revision }}"
              {{- if .Values.migrazione.fallisci }}
              echo "colonna già esistente" >&2; exit 1
              {{- end }}
EOF

  # ── TEST: `helm test` crea questo Pod e guarda l'exit code ──────────────
  cat > $OMBRELLO/templates/tests/connessione.yaml <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: {{ .Release.Name }}-test-connessione
  annotations:
    "helm.sh/hook": test
    "helm.sh/hook-delete-policy": before-hook-creation,hook-succeeded
spec:
  restartPolicy: Never
  containers:
    - name: wget
      image: busybox:1.37
      command: ["sh", "-c", "wget -qO- http://{{ .Release.Name }}-frontend/api | grep -q hostname"]
EOF
  echo "chart ombrello scritto in $OMBRELLO"
}

prova() {
  [[ "$(kubectl config current-context)" == "lab" ]] || { echo "STOP: contesto non 'lab'" >&2; exit 1; }
  local REGISTRY="${REGISTRY:-localhost:5000}"

  # Chart.lock fissa le versioni esatte; charts/ contiene i .tgz
  helm dependency update $OMBRELLO
  cat $OMBRELLO/Chart.lock

  helm upgrade --install demo $OMBRELLO -n $NS --create-namespace --wait --timeout 3m
  kubectl -n $NS get deploy
  helm test demo -n $NS --logs

  # hook che fallisce: l'upgrade si ferma, i Deployment restano com'erano
  helm upgrade demo $OMBRELLO -n $NS --set migrazione.fallisci=true \
    --set frontend.replicaCount=3 --wait --timeout 2m \
    || echo "OK: migrazione fallita, upgrade fermato"
  kubectl -n $NS get deploy demo-frontend -o jsonpath='repliche={.spec.replicas}{"\n"}'  # ancora 1
  kubectl -n $NS logs job/demo-migrazione || true      # resta per il debug: hook-failed non è nella policy

  # ── DISTRIBUZIONE: chart come artefatto OCI ────────────────────────────
  helm package ./eco                                    # eco-0.1.0.tgz
  helm push eco-0.1.0.tgz "oci://$REGISTRY/charts" --plain-http
  helm show chart "oci://$REGISTRY/charts/eco" --version 0.1.0 --plain-http
  helm template da-oci "oci://$REGISTRY/charts/eco" --version 0.1.0 --plain-http | grep -m1 image:
}

case "${1:-}" in
  crea) crea ;;
  prova) prova ;;
  pulisci) helm uninstall demo -n $NS; kubectl delete ns $NS ;;
  *) echo "uso: $0 crea|prova|pulisci" ;;
esac

# ── HELM IN UN TEAM: PRATICHE ───────────────────────────────────────────────
#   • chart versionati in un registry OCI, mai "helm install ./cartella"
#     in produzione; Chart.lock in git
#   • un values file per ambiente: values-dev.yaml, values-prod.yaml
#   • helmfile (o Argo CD / Flux) per installare N release in modo
#     dichiarativo: lo stato desiderato di TUTTE le release in git
#   • post-renderer (es. kustomize) per patchare un chart di terzi senza
#     forkarlo
#   • chart "library" per condividere gli helper tra i chart del team
#   • `helm template | kubeconform -strict` in CI per validare gli schemi
#
# HELM O KUSTOMIZE? (domanda quasi certa, vedi lezione 11)
#   Helm: parametri, packaging, release con storia, hook, ecosistema di
#         chart pubblici. Costo: template testuali, YAML generato.
#   Kustomize: YAML puro + patch, niente template, integrato in kubectl,
#         nessuno stato nel cluster. Costo: niente logica né ciclo di vita.
#   Spesso insieme: chart di terzi con Helm, app interne con Kustomize, o
#   Helm + post-renderer Kustomize, o Argo CD che renderizza entrambi.

# ── DOMANDE DA COLLOQUIO ────────────────────────────────────────────────────
# D: Perché il mio Job di migrazione non viene ricreato al secondo upgrade?
# R: Gli hook non sono gestiti come risorse della release: se il Job del
#    giro prima esiste ancora, la creazione fallisce. Serve
#    hook-delete-policy before-hook-creation (e un nome stabile).
#
# D: Come passi un valore a tutti i subchart?
# R: Sotto `global:`. Per un singolo subchart, sotto la sua chiave (nome
#    o alias). Il subchart non vede i valori del padre fuori da global.
#
# D: Hook pre-upgrade o initContainer per le migrazioni?
# R: L'initContainer gira per ogni Pod (N migrazioni concorrenti, serve
#    un lock); il Job hook gira una volta e blocca l'upgrade se fallisce,
#    ma con Argo CD gli hook vanno mappati sulle sue sync wave/hook.

# ══════════════════════════════════════════════════════════════════════════
# RIEPILOGO
# • dependencies + alias + condition; Chart.lock fissa le versioni
# • global per i valori condivisi; i subchart sotto il loro nome
# • hook con weight e delete-policy; pre-upgrade blocca l'upgrade
# • helm test = Pod con annotazione test, conta l'exit code
# • Distribuzione: helm package + helm push su registry OCI
# ══════════════════════════════════════════════════════════════════════════

# Libreria comune: ogni comando viene spiegato, mostrato e poi eseguito su conferma.
#   AUTO=1 bash script.sh   → esegue tutto senza fermarsi
#   DA=5   bash script.sh   → salta i primi 4 passi

PRJ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LEZIONI="$PRJ/lezioni"
LAVORO="$PRJ/lavoro"
N_PASSO=0

titolo() {
  printf '\n\033[1;35m══════════════════════════════════════════════════════════════════\n'
  printf ' %s\n' "$@"
  printf '══════════════════════════════════════════════════════════════════\033[0m\n'
}

nota() {
  printf '\n\033[0;37m  %s\033[0m\n' "$@"
}

passo() {
  local spiega="$1" cmd="$2" r=""
  N_PASSO=$((N_PASSO + 1))
  (( N_PASSO < ${DA:-1} )) && return 0
  printf '\n\033[1;36m[%02d] %s\033[0m\n' "$N_PASSO" "$spiega"
  printf '\033[1;33m  $ %s\033[0m\n' "$cmd"
  if [[ -n "${AUTO:-}" && "$cmd" == *port-forward* && "$cmd" != *'&'* ]]; then
    echo "     (AUTO: saltato, resterebbe in primo piano)"; return 0
  fi
  if [[ -z "${AUTO:-}" ]]; then
    read -rp "     [Invio] esegui · [s] salta · [q] esci › " r </dev/tty
    case "$r" in
      s|S) echo "     saltato"; return 0 ;;
      q|Q) echo "     uscita"; exit 0 ;;
    esac
  fi
  local rc=0
  eval "$cmd" || rc=$?
  (( rc == 0 )) || printf '\033[0;31m     ↳ uscita %d (in alcuni passi è voluto: leggi la spiegazione)\033[0m\n' "$rc"
  return 0
}

guardia_lab() {
  local attuale
  attuale="$(kubectl config current-context 2>/dev/null || echo nessuno)"
  if [[ "$attuale" != "lab" ]]; then
    printf '\033[1;31mSTOP: kubectl punta a "%s", non a "lab".\033[0m\n' "$attuale"
    echo "      crea o accendi il cluster:  bash $PRJ/kubernetes/01-architettura-e-lab.sh"
    echo "      oppure:                     kubectl config use-context lab"
    exit 1
  fi
}

cartella() {
  mkdir -p "$LAVORO/$1"
  cd "$LAVORO/$1"
  nota "cartella di lavoro: $PWD"
}

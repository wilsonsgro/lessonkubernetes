// Lesson 25: Prometheus and Grafana from the integration material in content/monitoraggio; the YAML files are the lesson's own blocks, checked byte for byte by the test.
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const CONTENUTO = join(dirname(fileURLToPath(import.meta.url)), '..', 'content', 'monitoraggio');

export const FILE = [
  { percorso: 'lezione-25.md', lingua: 'markdown', ruolo: 'lezione' },
  { percorso: 'file/values-monitoring.yaml', lingua: 'yaml', ruolo: 'manifest', sezione: '## 5.3 ' },
  { percorso: 'file/demo-metrics.yaml', lingua: 'yaml', ruolo: 'manifest', sezione: '## 8.1 ' },
  { percorso: 'file/demo-alert.yaml', lingua: 'yaml', ruolo: 'manifest', sezione: '## 10.1 ' },
];

const leggi = p => readFileSync(join(CONTENUTO, p), 'utf8');

export function bloccoDellaSezione(md, sezione) {
  const da = md.indexOf(`\n${sezione}`);
  if (da < 0) throw new Error(`sezione assente: ${sezione}`);
  const m = /^```yaml\n([\s\S]*?)^```$/m.exec(md.slice(da));
  if (!m) throw new Error(`nessun blocco yaml dopo ${sezione}`);
  return m[1];
}

export function caricaMonitoraggio() {
  const fonti = FILE.map(({ percorso, lingua, ruolo }) => {
    const testo = leggi(percorso);
    return { nome: percorso.split('/').pop(), percorso, scarica: `monitoraggio/${percorso.split('/').pop()}`, lingua, ruolo, testo, righe: testo.replace(/\n$/, '').split('\n').length };
  });
  return {
    id: '25',
    titolo: 'Prometheus, Grafana e metriche Kubernetes',
    breve: 'Prometheus e Grafana',
    sommario: 'Osservare il cluster nel tempo: kube-prometheus-stack con Helm, PromQL, un\'app con /metrics e ServiceMonitor, una dashboard, un alert e il ponte verso HAProxy della lezione 21.',
    radice: '~/kubernetesprj/site/content/monitoraggio/',
    introFonti: 'Il testo della lezione e i tre file YAML che contiene, estratti tali e quali in file a sé per scaricarli. Il materiale è didattico: nessun comando è stato eseguito sul cluster del laboratorio, output e numeri sono illustrativi. Nessun comando viene eseguito dal sito.',
    titoloPassi: 'Il laboratorio, dall\'installazione alla pulizia',
    passi: { percorso: 'comandi.passi', testo: leggi('comandi.passi') },
    introPassi: 'Raccolti dalle sezioni 5–10 della lezione, nell\'ordine in cui si lanciano; la pulizia finale è un\'aggiunta del sito. I file <code>values-monitoring.yaml</code>, <code>demo-metrics.yaml</code> e <code>demo-alert.yaml</code> si scaricano dalla vista «Sorgenti originali».',
    spiegazione: leggi('appunti-25.md'),
    fonti,
    traccia: '',
  };
}

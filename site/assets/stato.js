// Student progress in localStorage only: completed lessons, favourites, notes, quiz scores, theme.
const CHIAVE = 'k8s-lezioni:v1';
const vuoto = () => ({ completate: {}, preferite: {}, note: {}, quiz: {}, carte: {} });

export function leggi() {
  try { return { ...vuoto(), ...JSON.parse(localStorage.getItem(CHIAVE) || '{}') }; } catch { return vuoto(); }
}
export function scrivi(s) {
  try { localStorage.setItem(CHIAVE, JSON.stringify(s)); } catch { /* storage pieno o disabilitato: il sito resta usabile */ }
  document.dispatchEvent(new CustomEvent('stato:cambiato'));
}
export function aggiorna(fn) { const s = leggi(); fn(s); scrivi(s); return s; }
export function esporta() { return JSON.stringify(leggi(), null, 2); }
export function importa(testo) {
  const d = JSON.parse(testo);
  if (typeof d !== 'object' || !d) throw new Error('file non valido');
  scrivi({ ...vuoto(), ...d });
}
export function azzera() { scrivi(vuoto()); }

export const ORDINE = ['01', '02', '03', '04', '05', '06', '07', '08', '09', '21', '22', '23', '24'];

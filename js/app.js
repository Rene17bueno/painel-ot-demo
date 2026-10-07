// Painel OT Demo — núcleo compartilhado (cliente Supabase, navegação, formatação, regras DPO)
// A chave abaixo é a "publishable" (pública por design); a proteção está nas políticas RLS do banco.
const SUPABASE_URL = 'https://tuciclxzfcbsaauphryk.supabase.co';
const SUPABASE_KEY = 'sb_publishable_7cckd9kEEIauypKnEoJ9Iw_yoSakOeQ';
const sb = supabase.createClient(SUPABASE_URL, SUPABASE_KEY);

// ---------- formatação ----------
const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const hhmm = m => { if (m == null || isNaN(m)) return '—'; m = Math.round(m); const s = m < 0 ? '-' : ''; m = Math.abs(m); return s + String(Math.floor(m / 60)).padStart(2, '0') + ':' + String(m % 60).padStart(2, '0'); };
const nf = (v, d = 1) => (v == null || isNaN(v)) ? '—' : Number(v).toLocaleString('pt-BR', { minimumFractionDigits: d, maximumFractionDigits: d });
const pct = (v, d = 1) => (v == null || isNaN(v)) ? '—' : nf(v, d) + '%';
const sgn = (v, d = 1) => (v == null || isNaN(v)) ? '—' : (v > 0 ? '+' : '') + nf(v, d) + '%';
const brl = v => Number(v || 0).toLocaleString('pt-BR', { style: 'currency', currency: 'BRL' });
const fmtData = d => d ? d.split('-').reverse().join('/') : '—';
const addDias = (d, n) => { const t = new Date(d + 'T12:00:00'); t.setDate(t.getDate() + n); return t.toISOString().slice(0, 10); };

// ---------- acesso a dados ----------
async function all(make) {                       // pagina além do limite de 1000 linhas do PostgREST
  let out = [], from = 0;
  for (;;) {
    const { data, error } = await make().range(from, from + 999);
    if (error) throw error;
    out = out.concat(data);
    if (data.length < 1000) return out;
    from += 1000;
  }
}
async function ultimaData() {
  const { data } = await sb.from('mapas').select('data').order('data', { ascending: false }).limit(1);
  return data?.[0]?.data || new Date().toISOString().slice(0, 10);
}
async function carregarRevendas(sel, { todas = false, valor } = {}) {
  const { data, error } = await sb.from('revendas').select('*').order('codigo');
  if (error) throw error;
  sel.innerHTML = (todas ? '<option value="">Todas as revendas</option>' : '') +
    data.map(r => `<option value="${esc(r.id)}">${esc(r.codigo)} — ${esc(r.nome)}</option>`).join('');
  if (valor) sel.value = valor;
  return data;
}
function aviso(el, texto, tipo = 'danger') { el.innerHTML = texto ? `<div class="alert alert-${tipo} py-2 mb-3">${esc(texto)}</div>` : ''; }

// ---------- regras DPO (agregação ponderada sobre v_kpi_dia) ----------
function agregar(rows) {
  const s = k => rows.reduce((a, r) => a + (+r[k] || 0), 0);
  const nHr = s('n_hr'), nKm = s('n_km'), mapas = s('mapas');
  const d = (a, b) => b ? a / b : null;
  return {
    mapas, validos: nHr, entregas: s('s_entregas'),
    tml: d(s('s_tml'), nHr), tr: d(s('s_tr'), nHr), ti: d(s('s_ti'), nHr), jl: d(s('s_jl'), nHr),
    okTml: d(s('ok_tml') * 100, nHr), okTr: d(s('ok_tr') * 100, nHr), okTi: d(s('ok_ti') * 100, nHr), okJl: d(s('ok_jl') * 100, nHr),
    dispT: d(s('s_disp_t'), nHr), dispKm: d(s('s_disp_km'), nKm),
    ocup: d(s('s_cx') * 100, s('s_cap')), improd: d(s('n_improdutivos') * 100, mapas),
    invalidosHr: mapas - nHr, invalidosKm: mapas - nKm,
  };
}
const corMeta = (ok, meta = 80) => ok == null ? '' : ok >= meta ? 'text-success' : ok >= meta - 15 ? 'text-warning' : 'text-danger';

// narrativa por Mapa (texto descritivo + "O que fazer"), regras sobre dado já calculado — sem limiar novo
function narrativa(m) {
  if (!m.valido_hr) return { txt: `Mapa ${m.numero} (${m.placa}, ${m.grupo}) com horários inconsistentes (saída = entrada ou sem tempo previsto): fora da medição DPO (mapa inválido).`, acoes: ['Corrigir o apontamento de saída/entrada na origem do dado'] };
  const p = [], a = [];
  p.push(`Mapa ${m.numero} (${m.placa}, ${m.grupo}) saiu às ${hhmm(m.sai_min)}: TML de ${hhmm(m.tml_min)}${m.tml_min > m.meta_tml_min ? `, acima da meta de ${hhmm(m.meta_tml_min)}.` : ', dentro da meta.'}`);
  if (m.tml_min > m.meta_tml_min) a.push('Revisar a sequência de carregamento e a liberação na portaria');
  p.push(`Tempo em rota de ${hhmm(m.tr_min)} contra ${hhmm(m.tempo_prev_min)} previstos — dispersão de ${sgn(m.disp_tempo_pct)} (${m.disp_tempo_min > 0 ? 'atrasado' : 'adiantado'}).`);
  if (Math.abs(m.disp_tempo_pct) >= 15) a.push('Revisar o tempo estimado de atendimento dos PDVs e a roteirização');
  if (m.tr_min > m.meta_tr_min) p.push(`TR acima da meta de ${hhmm(m.meta_tr_min)}.`);
  if (m.ti_min > m.meta_ti_min) { p.push(`Tempo interno de ${hhmm(m.ti_min)} (meta ${hhmm(m.meta_ti_min)}).`); a.push('Agilizar a prestação de contas física e financeira'); }
  if (m.jl_min > m.meta_jl_min) { p.push(`Jornada líquida de ${hhmm(m.jl_min)}, acima da meta de ${hhmm(m.meta_jl_min)}.`); a.push('Risco de estouro de jornada: reavaliar carga e roteiro'); }
  if (m.valido_km) {
    p.push(`KM real de ${nf(m.km_real)} contra ${nf(m.km_prev)} previstos (${sgn(m.disp_km_pct)}).`);
    if (Math.abs(m.disp_km_pct) >= 15) a.push('Validar coordenadas dos PDVs e a rota planejada');
  } else p.push('KM inconsistente: fora da medição de dispersão de KM.');
  p.push(`Ocupação de ${pct(m.ocupacao_pct, 0)}${m.ocupacao_pct < 70 && m.tr_min < 300 ? ' — mapa improdutivo (<70% de ocupação e <5h em rota).' : '.'}`);
  return { txt: p.join(' '), acoes: a };
}

// ---------- navegação ----------
const PAGINAS = [['index.html', 'Dashboard DPO'], ['mapas.html', 'Relatório de Rotas'], ['devolucao.html', 'Devolução'],
  ['tratativas.html', 'Diário de Tratativas'], ['revendas.html', 'Revendas'], ['dpo.html', 'Metodologia DPO']];
function nav(atual) {
  document.body.insertAdjacentHTML('afterbegin', `
  <nav class="navbar navbar-expand-lg navbar-dark app-nav"><div class="container-xl">
    <a class="navbar-brand fw-semibold" href="index.html">Painel OT <span class="badge text-bg-warning ms-1 align-middle">DEMO</span></a>
    <button class="navbar-toggler" data-bs-toggle="collapse" data-bs-target="#nv" aria-label="Menu"><span class="navbar-toggler-icon"></span></button>
    <div class="collapse navbar-collapse" id="nv"><ul class="navbar-nav ms-auto">
      ${PAGINAS.map(([h, t]) => `<li class="nav-item"><a class="nav-link ${h === atual ? 'active' : ''}" href="${h}">${t}</a></li>`).join('')}
    </ul></div></div></nav>
  <div class="demo-faixa">Portfólio com <strong>dados 100% fictícios</strong> — revendas, mapas, clientes e valores simulados. Não representa nenhuma empresa real.</div>`);
}

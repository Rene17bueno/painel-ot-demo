-- Painel OT Demo — schema multi-revenda (dados 100% fictícios)
-- Regras DPO: TML/TR/TI/JL, dispersões, devolução por PDV. Metas parametrizáveis por revenda.

create extension if not exists pgcrypto;

create table revendas (
  id uuid primary key default gen_random_uuid(),
  codigo text not null unique check (codigo ~ '^[A-Z0-9]{2,4}$'),
  nome text not null check (char_length(nome) between 3 and 80),
  cidade text not null check (char_length(cidade) between 2 and 60),
  uf char(2) not null check (uf ~ '^[A-Z]{2}$'),
  meta_tml_min int not null default 30  check (meta_tml_min between 1 and 240),
  meta_tr_min  int not null default 560 check (meta_tr_min  between 60 and 900),
  meta_ti_min  int not null default 30  check (meta_ti_min  between 1 and 240),
  demo_base boolean not null default false,          -- revendas semente: protegidas contra edição/exclusão
  criado_em timestamptz not null default now()
);

create table veiculos (
  id uuid primary key default gen_random_uuid(),
  revenda_id uuid not null references revendas on delete cascade,
  placa text not null,
  grupo text not null check (grupo in ('Depósito','PA','Spot')),
  capacidade_cx int not null check (capacidade_cx > 0),
  unique (revenda_id, placa)
);

create table clientes (
  id uuid primary key default gen_random_uuid(),
  revenda_id uuid not null references revendas on delete cascade,
  codigo int not null,
  nome text not null,
  cidade text not null,
  unique (revenda_id, codigo)
);

create table mapas (
  id uuid primary key default gen_random_uuid(),
  revenda_id uuid not null references revendas on delete cascade,
  numero int not null,
  data date not null,
  placa text not null,
  grupo text not null check (grupo in ('Depósito','PA','Spot')),
  sai_min int not null check (sai_min between 0 and 1439),   -- minutos desde 00:00
  entr_min int not null check (entr_min between 0 and 1439),
  ti_min int not null default 0,
  tempo_prev_min int not null,
  km_prev numeric(7,1) not null,
  km_real numeric(7,1) not null,
  entregas int not null,
  cx_carreg int not null,
  capacidade_cx int not null,
  nu_entregador int not null default 1,
  -- DPO: TML = saída − 07:00 | TR = entrada − saída | JL = TML + TR + TI
  tr_min int generated always as (entr_min - sai_min) stored,
  tml_min int generated always as (greatest(sai_min - 420, 0)) stored,
  jl_min int generated always as (greatest(sai_min - 420, 0) + (entr_min - sai_min) + ti_min) stored,
  unique (revenda_id, numero)
);
create index on mapas (revenda_id, data);

create table atendimentos (
  id bigint generated always as identity primary key,
  mapa_id uuid not null references mapas on delete cascade,
  cliente_id uuid not null references clientes,
  ordem int not null,
  est_chegada_min int not null,
  chegou_min int not null,
  final_min int not null
);
create index on atendimentos (mapa_id);

create table devolucoes (
  id bigint generated always as identity primary key,
  mapa_id uuid not null references mapas on delete cascade,
  cliente_id uuid not null references clientes,
  nota int not null,
  motivo text not null,
  valor numeric(10,2) not null,
  volume_hl numeric(6,2) not null
);
create index on devolucoes (mapa_id);

create table tratativas (
  id uuid primary key default gen_random_uuid(),
  revenda_id uuid not null references revendas on delete cascade,
  mapa_numero int,
  data date not null default current_date,
  tipo text not null check (tipo in ('On Time','Dispersão de KM','Dispersão de Tempo','Devolução','Outro')),
  descricao text not null check (char_length(descricao) between 3 and 500),
  acao text check (char_length(acao) <= 500),
  responsavel text check (char_length(responsavel) <= 80),
  status text not null default 'Aberta' check (status in ('Aberta','Em andamento','Resolvida')),
  criado_em timestamptz not null default now()
);
create index on tratativas (revenda_id, data desc);

-- limite de revendas (demo pública)
create function trg_limite_revendas() returns trigger language plpgsql as $$
begin
  if (select count(*) from revendas) >= 12 then raise exception 'limite de 12 revendas na demo'; end if;
  new.demo_base := false;   -- cliente nunca cria revenda protegida
  return new;
end $$;
create trigger revendas_limite before insert on revendas
  for each row when (current_user in ('anon','authenticated')) execute function trg_limite_revendas();

-- ============ VIEWS (security_invoker: respeitam RLS) ============
create view v_mapas with (security_invoker = true) as
select m.*, r.codigo as revenda, r.meta_tml_min, r.meta_tr_min, r.meta_ti_min,
  (r.meta_tml_min + r.meta_tr_min + r.meta_ti_min) as meta_jl_min,
  (m.tr_min > 0 and m.sai_min <> m.entr_min and m.tempo_prev_min > 0) as valido_hr,           -- DPO: mapa inválido (hr)
  (m.km_prev > 1 and m.km_real > 0 and m.km_real <= 600) as valido_km,                        -- DPO: mapa inválido (km)
  m.tr_min - m.tempo_prev_min as disp_tempo_min,
  round(((m.tr_min::numeric / nullif(m.tempo_prev_min,0)) - 1) * 100, 1) as disp_tempo_pct,   -- + atrasado
  round(((m.km_real / nullif(m.km_prev,0)) - 1) * 100, 1) as disp_km_pct,                     -- + rodou mais
  round(m.cx_carreg::numeric / m.capacidade_cx * 100, 1) as ocupacao_pct
from mapas m join revendas r on r.id = m.revenda_id;

-- agregado diário por revenda×grupo: o front soma e divide (média ponderada correta)
create view v_kpi_dia with (security_invoker = true) as
select revenda_id, revenda, data, grupo,
  count(*) as mapas,
  count(*) filter (where valido_hr) as n_hr,
  sum(tml_min) filter (where valido_hr) as s_tml, sum(tr_min) filter (where valido_hr) as s_tr,
  sum(ti_min) filter (where valido_hr) as s_ti,  sum(jl_min) filter (where valido_hr) as s_jl,
  count(*) filter (where valido_hr and tml_min <= meta_tml_min) as ok_tml,
  count(*) filter (where valido_hr and tr_min  <= meta_tr_min)  as ok_tr,
  count(*) filter (where valido_hr and ti_min  <= meta_ti_min)  as ok_ti,
  count(*) filter (where valido_hr and jl_min  <= meta_jl_min)  as ok_jl,
  sum(abs(disp_tempo_pct)) filter (where valido_hr) as s_disp_t,
  count(*) filter (where valido_km) as n_km,
  sum(abs(disp_km_pct)) filter (where valido_km) as s_disp_km,
  sum(cx_carreg) as s_cx, sum(capacidade_cx) as s_cap, sum(entregas) as s_entregas,
  count(*) filter (where ocupacao_pct < 70 and tr_min < 300) as n_improdutivos
from v_mapas group by revenda_id, revenda, data, grupo;

-- REGRA: PDV devolvido é a unidade principal (1x por mapa), NF/valor são complementares
create view v_dev_dia with (security_invoker = true) as
select m.revenda_id, m.data, count(distinct (d.mapa_id, d.cliente_id)) as pdvs, count(*) as nfs,
  sum(d.valor) as valor, sum(d.volume_hl) as volume_hl
from devolucoes d join mapas m on m.id = d.mapa_id group by m.revenda_id, m.data;

create view v_devolucoes_det with (security_invoker = true) as
select d.id, m.revenda_id, m.data, m.numero as mapa, m.placa, c.codigo as cod_cliente, c.nome as cliente,
  d.nota, d.motivo, d.valor, d.volume_hl
from devolucoes d join mapas m on m.id = d.mapa_id join clientes c on c.id = d.cliente_id;

create view v_atendimentos_det with (security_invoker = true) as
select a.mapa_id, a.ordem, c.codigo as cod_cliente, c.nome as cliente, a.est_chegada_min, a.chegou_min, a.final_min,
  a.chegou_min - a.est_chegada_min as atraso_min
from atendimentos a join clientes c on c.id = a.cliente_id;

-- ============ RLS ============
alter table revendas, veiculos, clientes, mapas, atendimentos, devolucoes, tratativas enable row level security;

create policy leitura on revendas     for select using (true);
create policy leitura on veiculos     for select using (true);
create policy leitura on clientes     for select using (true);
create policy leitura on mapas        for select using (true);
create policy leitura on atendimentos for select using (true);
create policy leitura on devolucoes   for select using (true);
create policy leitura on tratativas   for select using (true);

-- escrita pública só em revendas (não-semente) e tratativas; demais tabelas só via função
create policy cadastro on revendas for insert to anon, authenticated with check (not demo_base);
create policy edicao   on revendas for update to anon, authenticated using (not demo_base) with check (not demo_base);
create policy exclusao on revendas for delete to anon, authenticated using (not demo_base);
create policy escrita_ins on tratativas for insert to anon, authenticated with check (true);
create policy escrita_upd on tratativas for update to anon, authenticated using (true) with check (true);
create policy escrita_del on tratativas for delete to anon, authenticated using (true);

revoke all on all tables in schema public from anon, authenticated;
grant select on all tables in schema public to anon, authenticated;
grant insert, update, delete on revendas, tratativas to anon, authenticated;

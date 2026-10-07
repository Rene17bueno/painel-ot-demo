-- Gera dados fictícios determinísticos-por-faixa para uma revenda (clientes, frota, mapas, PDVs, devoluções, tratativas).
-- Usada no seed e pelo botão "Gerar dados fictícios" da tela de cadastro. Limite: 60 dias, só revenda vazia.
create function gerar_demo(p_revenda uuid, p_dias int default 60) returns int
language plpgsql security definer set search_path = public as $$
declare v_cidade text; v_n int;
begin
  if p_dias < 1 or p_dias > 60 then raise exception 'dias deve ser 1..60'; end if;
  select cidade into v_cidade from revendas where id = p_revenda;
  if v_cidade is null then raise exception 'revenda inexistente'; end if;
  if exists (select 1 from mapas where revenda_id = p_revenda) then raise exception 'revenda já possui dados'; end if;

  insert into clientes(revenda_id, codigo, nome, cidade)
  select p_revenda, 1000 + g,
    (array['Bar do','Mercadinho','Empório','Padaria','Restaurante','Lanchonete','Adega','Supermercado','Armazém','Conveniência'])[1 + floor(random()*10)::int]
    || ' ' || (array['Zé','Central','Santa Luzia','Boa Vista','Primavera','Esquina','Do Povo','Estrela','Bom Preço','Três Irmãos','Aurora','Cruzeiro'])[1 + floor(random()*12)::int],
    v_cidade
  from generate_series(1, 120) g;

  insert into veiculos(revenda_id, placa, grupo, capacidade_cx)
  select p_revenda,
    chr(65+floor(random()*26)::int) || chr(65+floor(random()*26)::int) || chr(65+floor(random()*26)::int)
      || floor(random()*10)::int || chr(65+floor(random()*26)::int) || lpad(g::text, 2, '0'),
    case when g <= 12 then 'Depósito' when g <= 15 then 'PA' else 'Spot' end,
    (array[320,400,480,520])[1 + floor(random()*4)::int]
  from generate_series(1, 18) g;

  with dias as (
    select d::date as dia from generate_series(current_date - p_dias, current_date - 1, interval '1 day') d
    where extract(dow from d) <> 0
  ), base as (
    select v.placa, v.grupo, v.capacidade_cx as cap, dias.dia,
      random() r_ativo, random() r_tail, random() r1, random() r2, random() r3,
      random() r4, random() r5, random() r6, random() r7, random() r8, random() r9
    from veiculos v cross join dias where v.revenda_id = p_revenda
  ), m as (
    select *, 438 + floor(r1*28)::int + case when r_tail < .12 then 25 else 0 end as sai,
      (400 + r2*140)::int as prev,
      row_number() over (order by dia, placa) as rn
    from base where r_ativo < case when extract(dow from dia) = 6 then .6 else .9 end
  )
  insert into mapas(revenda_id, numero, data, placa, grupo, sai_min, entr_min, ti_min, tempo_prev_min,
                    km_prev, km_real, entregas, cx_carreg, capacidade_cx, nu_entregador)
  select p_revenda, 500000 + rn, dia, placa, grupo, sai,
    case when r9 < .03 then sai else least(sai + (prev * (1 + (r3 - .42) * .3))::int, 1439) end,   -- 3% inválidos (hr)
    12 + floor(r4*30)::int, prev,
    round((55 + r5*110)::numeric, 1),
    case when r9 between .03 and .05 then 0 else round(((55 + r5*110) * (1 + (r6 - .4) * .45))::numeric, 1) end,  -- 2% inválidos (km)
    7 + floor(r7*15)::int, (cap * (.55 + r8*.45))::int, cap, case when r8 < .35 then 2 else 1 end
  from m;

  with s as (
    select m.id as mapa_id, m.revenda_id, g as ordem, m.entregas, m.sai_min, m.tempo_prev_min as prev, m.tr_min,
      1001 + floor(random()*120)::int as cod, random() ra, random() rb
    from mapas m cross join lateral generate_series(1, m.entregas) g where m.revenda_id = p_revenda
  ), s2 as (
    select *, (sai_min + prev * (ordem - .5) / entregas * .9)::int as est,
      (case when tr_min <= 0 then 0 else (tr_min - prev) * ordem::numeric / entregas end + (ra - .5) * 16)::int as delay
    from s
  )
  insert into atendimentos(mapa_id, cliente_id, ordem, est_chegada_min, chegou_min, final_min)
  select s2.mapa_id, c.id, ordem, least(est, 1439), least(est + delay, 1439), least(est + delay + 6 + floor(rb*20)::int, 1439)
  from s2 join clientes c on c.revenda_id = s2.revenda_id and c.codigo = s2.cod;

  insert into devolucoes(mapa_id, cliente_id, nota, motivo, valor, volume_hl)
  select a.mapa_id, a.cliente_id, 70000 + (random()*29999)::int,
    (array['NF ERRADA','CLIENTE FECHADO','PEDIDO DUPLICADO','PRODUTO AVARIADO','CLIENTE RECUSOU','SEM DINHEIRO'])[1 + floor(random()*6)::int],
    round((80 + random()*1700)::numeric, 2), round((random()*3)::numeric, 2)
  from atendimentos a join mapas m on m.id = a.mapa_id cross join generate_series(1, 2) as k(n)
  where m.revenda_id = p_revenda and abs(hashint8(a.id * 3 + k.n)) % 1000 < case when k.n = 1 then 22 else 4 end;

  insert into tratativas(revenda_id, mapa_numero, data, tipo, descricao, acao, responsavel, status)
  select p_revenda, numero, data, 'Dispersão de Tempo',
    format('Dispersão de tempo de %s%% no mapa %s (placa %s).', disp_tempo_pct, numero, placa),
    (array['Revisar tempo estimado de atendimento dos PDVs','Conferir sequência da roteirização','Orientar motorista sobre ordem de visita'])[1 + floor(random()*3)::int],
    (array['Analista 1','Analista 2','Supervisor de Logística'])[1 + floor(random()*3)::int],
    (array['Aberta','Em andamento','Resolvida','Resolvida'])[1 + floor(random()*4)::int]
  from (select * from v_mapas where revenda_id = p_revenda and valido_hr order by abs(disp_tempo_pct) desc limit 12) w;

  insert into tratativas(revenda_id, mapa_numero, data, tipo, descricao, acao, responsavel, status)
  select p_revenda, numero, data, 'Dispersão de KM',
    format('Dispersão de KM de %s%% no mapa %s (real %s km × previsto %s km).', disp_km_pct, numero, km_real, km_prev),
    'Validar cadastro de coordenadas dos PDVs e rota planejada',
    (array['Analista 1','Analista 2','Supervisor de Logística'])[1 + floor(random()*3)::int],
    (array['Aberta','Em andamento','Resolvida'])[1 + floor(random()*3)::int]
  from (select * from v_mapas where revenda_id = p_revenda and valido_km order by abs(disp_km_pct) desc limit 6) w;

  select count(*) into v_n from mapas where revenda_id = p_revenda;
  return v_n;
end $$;

-- VistorIA · novembro/2026
-- 1) Novos preços (Essencial R$ 39 com 20 diagnósticos, Profissional R$ 79) e pacote avulso sem mensalidade
--    (10 diagnósticos por R$ 29,90, válidos por 12 meses).
-- 2) Fotos extras no diagnóstico.
-- 3) Código de autenticidade dos laudos (QR Code no PDF + página validar.html).

-- ---------- 1. pacote de créditos ----------
alter table public.vist_contas add column if not exists creditos int not null default 0;
alter table public.vist_contas add column if not exists creditos_ate timestamptz;
alter table public.vist_analises add column if not exists credito boolean not null default false;
alter table public.vist_pagamentos add column if not exists creditos int;

create or replace function public.vist_limite(p_plano text, p_em_teste boolean)
returns integer language sql immutable set search_path to '' as $$
  select case when p_em_teste then 5 when p_plano = 'essencial' then 20 when p_plano = 'profissional' then 150 else 0 end
$$;

create or replace function public.vist_tabela_planos()
returns jsonb language sql immutable as $$
  select '{"essencial-mensal":{"plano":"essencial","dias":31,"valor":39},
           "essencial-anual":{"plano":"essencial","dias":366,"valor":390},
           "profissional-mensal":{"plano":"profissional","dias":31,"valor":79},
           "profissional-anual":{"plano":"profissional","dias":366,"valor":790},
           "pacote-10":{"plano":"creditos","dias":365,"valor":29.90,"creditos":10}}'::jsonb
$$;

-- saldo de créditos ainda válido
create or replace function public.vist_saldo(c public.vist_contas)
returns int language sql stable set search_path to '' as $$
  select case when c.creditos > 0 and c.creditos_ate > now() then c.creditos else 0 end
$$;

create or replace function public.vist_pedir_plano(p_chave text)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $$
declare u uuid:=auth.uid(); pl jsonb:=public.vist_tabela_planos()->p_chave; cod text;
begin
  if u is null then raise exception 'login_necessario' using errcode='28000'; end if;
  if pl is null then raise exception 'plano_invalido' using errcode='22023'; end if;
  update public.vist_pagamentos set status='cancelado' where user_id=u and status='pendente';
  loop
    cod:='VI-'||upper(substr(md5(random()::text||clock_timestamp()::text),1,8));
    exit when not exists(select 1 from public.vist_pagamentos where codigo=cod);
  end loop;
  insert into public.vist_pagamentos(codigo,user_id,chave,plano,dias,valor,creditos)
    values(cod,u,p_chave,pl->>'plano',(pl->>'dias')::int,(pl->>'valor')::numeric,(pl->>'creditos')::int);
  return jsonb_build_object('codigo',cod,'chave',p_chave,'valor',(pl->>'valor')::numeric);
end $$;

create or replace function public.vist_confirmar_interno(p_codigo text, p_valor numeric default null)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $$
declare r public.vist_pagamentos; em text; ate timestamptz;
begin
  select * into r from public.vist_pagamentos where codigo=upper(btrim(p_codigo)) for update;
  if not found then return jsonb_build_object('status','nao_encontrado'); end if;
  if r.status='pago' then return jsonb_build_object('status','ja_pago','codigo',r.codigo); end if;
  if p_valor is not null and p_valor + 0.01 < r.valor then return jsonb_build_object('status','valor_menor','esperado',r.valor); end if;
  update public.vist_pagamentos set status='pago', pago_em=now() where codigo=r.codigo;
  if r.plano = 'creditos' then
    insert into public.vist_contas (user_id, plano, plano_ate, em_teste) values (r.user_id, 'teste', now(), true) on conflict (user_id) do nothing;
    update public.vist_contas
       set creditos = public.vist_saldo(vist_contas) + coalesce(r.creditos, 0),
           creditos_ate = now() + make_interval(days => r.dias)
     where user_id = r.user_id
    returning creditos_ate into ate;
    return jsonb_build_object('status','ativado','codigo',r.codigo,'plano','creditos','creditos',r.creditos,'valido_ate',ate);
  end if;
  select email into em from auth.users where id=r.user_id;
  ate:=public.vist_ativar_plano(em, r.plano, r.dias);
  return jsonb_build_object('status','ativado','codigo',r.codigo,'plano',r.plano,'valido_ate',ate);
end $$;

-- usa a cota do plano; se acabou (ou não há plano), usa um crédito do pacote
create or replace function public.vist_reservar_analise()
returns jsonb language plpgsql security definer set search_path to '' as $$
declare v_id uuid := auth.uid(); c public.vist_contas; v_usados int; v_lim int; v_novo bigint; v_saldo int;
begin
  if v_id is null then raise exception 'não autenticado'; end if;
  select * into c from public.vist_contas where user_id = v_id for update;
  if not found then return jsonb_build_object('ok', false, 'motivo', 'sem_conta'); end if;
  v_saldo := public.vist_saldo(c);
  if c.plano_ate is not null and c.plano_ate > now() then
    v_lim := public.vist_limite(c.plano, c.em_teste);
    select count(*) into v_usados from public.vist_analises where user_id = v_id and not credito and criado_em >= public.vist_inicio_cota(c);
    if v_usados < v_lim then
      insert into public.vist_analises (user_id) values (v_id) returning id into v_novo;
      return jsonb_build_object('ok', true, 'id', v_novo, 'restantes', v_lim - v_usados - 1 + v_saldo);
    end if;
  end if;
  if v_saldo > 0 then
    update public.vist_contas set creditos = creditos - 1 where user_id = v_id;
    insert into public.vist_analises (user_id, credito) values (v_id, true) returning id into v_novo;
    return jsonb_build_object('ok', true, 'id', v_novo, 'restantes', v_saldo - 1, 'credito', true);
  end if;
  if c.plano_ate is null or c.plano_ate <= now() then return jsonb_build_object('ok', false, 'motivo', 'expirado'); end if;
  return jsonb_build_object('ok', false, 'motivo', 'limite', 'limite', v_lim);
end $$;

-- falha da IA: devolve a análise (e o crédito, se foi crédito)
create or replace function public.vist_devolver_analise(p_id bigint)
returns void language plpgsql security definer set search_path to '' as $$
declare a public.vist_analises;
begin
  delete from public.vist_analises where id = p_id returning * into a;
  if a.credito then update public.vist_contas set creditos = creditos + 1 where user_id = a.user_id; end if;
end $$;
revoke all on function public.vist_devolver_analise(bigint) from public, anon, authenticated;

create or replace function public.vist_status()
returns jsonb language plpgsql security definer set search_path to '' as $$
declare v_id uuid := auth.uid(); v_email text; c public.vist_contas; r record; v_usados int; v_lim int;
begin
  if v_id is null then raise exception 'não autenticado'; end if;
  if not exists (select 1 from public.vist_contas where user_id = v_id) then
    insert into public.vist_contas (user_id, plano, plano_ate, em_teste) values (v_id, 'teste', now() + interval '7 days', true) on conflict do nothing;
    select email into v_email from auth.users where id = v_id;
    for r in select evento_id, plano, dias from public.pagamentos
             where status = 'sem_conta' and produto = 'vistoria' and lower(email) = lower(v_email) and plano is not null and dias is not null order by criado_em
    loop
      perform public.vist_ativar_plano(v_email, r.plano, r.dias);
      update public.pagamentos set status = 'ativado', detalhe = 'ativado no primeiro acesso ao VistorIA' where evento_id = r.evento_id;
    end loop;
  end if;
  select * into c from public.vist_contas where user_id = v_id;
  v_lim := public.vist_limite(c.plano, c.em_teste);
  select count(*) into v_usados from public.vist_analises where user_id = v_id and not credito and criado_em >= public.vist_inicio_cota(c);
  return jsonb_build_object('plano', c.plano, 'plano_ate', c.plano_ate, 'em_teste', c.em_teste,
    'ativo', c.plano_ate is not null and c.plano_ate > now(), 'limite', v_lim, 'usados', v_usados,
    'restantes', greatest(v_lim - v_usados, 0), 'creditos', public.vist_saldo(c), 'creditos_ate', c.creditos_ate,
    'perfil', c.perfil);
end $$;

-- quem usou um crédito nas últimas 24 h pode salvar o diagnóstico mesmo sem plano
create or replace function public.vist_pode_salvar_diag()
returns boolean language sql stable security definer set search_path to '' as $$
  select public.vist_ativo() or exists (select 1 from public.vist_analises a where a.user_id = (select auth.uid()) and a.criado_em > now() - interval '24 hours')
$$;
drop policy if exists "vist_diag: criar com plano ativo" on public.vist_diagnosticos;
create policy "vist_diag: criar com plano ativo ou crédito" on public.vist_diagnosticos for insert to authenticated
  with check ((select auth.uid()) = user_id and (select public.vist_pode_salvar_diag()));

-- ---------- 2. fotos extras ----------
alter table public.vist_diagnosticos add column if not exists fotos_extras text; -- JSON: [{"img": base64, "legenda": "..."}]

-- ---------- 3. autenticidade ----------
create table if not exists public.vist_laudos (
  codigo text primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  tipo text not null check (tipo in ('diagnostico','vistoria')),
  ref_id uuid not null,
  titulo text, local text, emissor text, registro text, risco text,
  emitido_em timestamptz not null default now(),
  unique (user_id, ref_id)
);
alter table public.vist_laudos enable row level security;
drop policy if exists "vist_laudos: ler os próprios" on public.vist_laudos;
create policy "vist_laudos: ler os próprios" on public.vist_laudos for select to authenticated using ((select auth.uid()) = user_id);

-- registra (ou reaproveita) o código do laudo; só para o dono do diagnóstico/vistoria
create or replace function public.vist_registrar_laudo(p_tipo text, p_ref uuid, p_titulo text, p_local text, p_emissor text, p_registro text, p_risco text)
returns text language plpgsql security definer set search_path to 'public', 'pg_temp' as $$
declare u uuid := auth.uid(); cod text;
begin
  if u is null then raise exception 'login_necessario' using errcode='28000'; end if;
  if p_tipo = 'diagnostico' then
    if not exists (select 1 from public.vist_diagnosticos where id = p_ref and user_id = u) then raise exception 'nao_encontrado'; end if;
  elsif p_tipo = 'vistoria' then
    if not exists (select 1 from public.vist_vistorias where id = p_ref and user_id = u) then raise exception 'nao_encontrado'; end if;
  else raise exception 'tipo_invalido'; end if;
  select codigo into cod from public.vist_laudos where user_id = u and ref_id = p_ref;
  if cod is not null then
    update public.vist_laudos set emissor = left(p_emissor,160), registro = left(p_registro,80) where codigo = cod;
    return cod;
  end if;
  loop
    cod := 'VL-' || upper(substr(md5(random()::text || clock_timestamp()::text), 1, 8));
    exit when not exists (select 1 from public.vist_laudos where codigo = cod);
  end loop;
  insert into public.vist_laudos (codigo, user_id, tipo, ref_id, titulo, local, emissor, registro, risco)
    values (cod, u, p_tipo, p_ref, left(p_titulo,200), left(p_local,200), left(p_emissor,160), left(p_registro,80), left(p_risco,30));
  return cod;
end $$;
revoke all on function public.vist_registrar_laudo(text,uuid,text,text,text,text,text) from public, anon;
grant execute on function public.vist_registrar_laudo(text,uuid,text,text,text,text,text) to authenticated;

-- consulta pública: só os dados de identificação do documento (sem endereço, fotos ou conteúdo)
create or replace function public.vist_validar_laudo(p_codigo text)
returns jsonb language sql stable security definer set search_path to 'public', 'pg_temp' as $$
  select coalesce((
    select jsonb_build_object('valido', true, 'codigo', l.codigo, 'tipo', l.tipo, 'titulo', l.titulo, 'local', l.local,
      'emissor', l.emissor, 'registro', l.registro, 'risco', l.risco, 'emitido_em', l.emitido_em,
      'existe', case when l.tipo = 'diagnostico' then exists (select 1 from public.vist_diagnosticos d where d.id = l.ref_id)
                     else exists (select 1 from public.vist_vistorias v where v.id = l.ref_id) end)
    from public.vist_laudos l where l.codigo = upper(btrim(p_codigo))), jsonb_build_object('valido', false))
$$;
grant execute on function public.vist_validar_laudo(text) to anon, authenticated;

-- VistorIA · Pix automático pelo app (central de pagamentos Foster: asaas-cobrar + asaas-webhook).
-- O app cria o pedido (vist_pedir_plano), a função asaas-cobrar gera o Pix com externalReference "fostervist:<codigo>"
-- e o webhook chama vist_confirmar_interno quando o Pix cai. Não depende do e-mail usado no pagamento.

create table if not exists public.vist_pagamentos(
  codigo text primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  chave text not null,
  plano text not null,
  dias int not null,
  valor numeric(10,2) not null,
  status text not null default 'pendente' check (status in ('pendente','pago','cancelado','reembolsado')),
  solicitado_em timestamptz not null default now(),
  pago_em timestamptz,
  asaas_id text,
  asaas_url text);
create index if not exists vist_pagamentos_user on public.vist_pagamentos(user_id, status);
alter table public.vist_pagamentos enable row level security;
revoke all on public.vist_pagamentos from anon, authenticated;
drop policy if exists vist_pag_ler on public.vist_pagamentos;
create policy vist_pag_ler on public.vist_pagamentos for select to authenticated using (user_id = auth.uid());
grant select on public.vist_pagamentos to authenticated;

create or replace function public.vist_tabela_planos() returns jsonb language sql immutable as $$
  select '{"essencial-mensal":{"plano":"essencial","dias":31,"valor":49},"essencial-anual":{"plano":"essencial","dias":366,"valor":490},
           "profissional-mensal":{"plano":"profissional","dias":31,"valor":89},"profissional-anual":{"plano":"profissional","dias":366,"valor":890}}'::jsonb
$$;

-- Cria (ou troca) o pedido de pagamento do usuário logado
create or replace function public.vist_pedir_plano(p_chave text) returns jsonb language plpgsql volatile security definer set search_path=public,pg_temp as $$
declare u uuid:=auth.uid(); pl jsonb:=public.vist_tabela_planos()->p_chave; cod text;
begin
  if u is null then raise exception 'login_necessario' using errcode='28000'; end if;
  if pl is null then raise exception 'plano_invalido' using errcode='22023'; end if;
  update public.vist_pagamentos set status='cancelado' where user_id=u and status='pendente';
  loop
    cod:='VI-'||upper(substr(md5(random()::text||clock_timestamp()::text),1,8));
    exit when not exists(select 1 from public.vist_pagamentos where codigo=cod);
  end loop;
  insert into public.vist_pagamentos(codigo,user_id,chave,plano,dias,valor) values(cod,u,p_chave,pl->>'plano',(pl->>'dias')::int,(pl->>'valor')::numeric);
  return jsonb_build_object('codigo',cod,'chave',p_chave,'valor',(pl->>'valor')::numeric);
end $$;

-- Confirmação do pagamento (só o servidor chama: webhook do Asaas)
create or replace function public.vist_confirmar_interno(p_codigo text, p_valor numeric default null) returns jsonb language plpgsql volatile security definer set search_path=public,pg_temp as $$
declare r public.vist_pagamentos; em text; ate timestamptz;
begin
  select * into r from public.vist_pagamentos where codigo=upper(btrim(p_codigo)) for update;
  if not found then return jsonb_build_object('status','nao_encontrado'); end if;
  if r.status='pago' then return jsonb_build_object('status','ja_pago','codigo',r.codigo); end if;
  if p_valor is not null and p_valor + 0.01 < r.valor then return jsonb_build_object('status','valor_menor','esperado',r.valor); end if;
  update public.vist_pagamentos set status='pago', pago_em=now() where codigo=r.codigo;
  select email into em from auth.users where id=r.user_id;
  ate:=public.vist_ativar_plano(em, r.plano, r.dias);
  return jsonb_build_object('status','ativado','codigo',r.codigo,'plano',r.plano,'valido_ate',ate);
end $$;

revoke all on function public.vist_pedir_plano(text), public.vist_confirmar_interno(text,numeric), public.vist_tabela_planos() from public, anon, authenticated;
grant execute on function public.vist_pedir_plano(text) to authenticated;
grant execute on function public.vist_confirmar_interno(text,numeric) to service_role;

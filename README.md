# Painel OT — Demo (portfólio)

Painel de indicadores de rota no padrão **DPO** (TML, TR, TI, JL, dispersões de tempo/KM, ocupação, devolução por PDV) para operações de distribuição, multi-revenda, **100% online e com dados fictícios**.

**Stack:** HTML5 · CSS · JavaScript (ES6) · Bootstrap 5 · Chart.js · Supabase (PostgreSQL + RLS) · SQL (colunas geradas, views `security_invoker`, função `plpgsql`).

## Telas
| Página | O que mostra |
|---|---|
| `index.html` | Dashboard DPO: KPIs, % de mapas na meta por revenda, série diária, tabela Macro por revenda × origem (Depósito/PA/Spot) |
| `mapas.html` | Relatório diário de rotas: ranking de dispersão, narrativa por Mapa com "O que fazer", PDV causador |
| `devolucao.html` | Devolução com regra do PDV devolvido (1× por mapa), motivos e PDVs reincidentes |
| `tratativas.html` | Diário de Tratativas (CRUD) |
| `revendas.html` | Cadastro de revenda com metas parametrizáveis + gerador de dados fictícios |
| `dpo.html` | Documentação das fórmulas e regras |

## Banco (`sql/`)
1. `01_schema.sql` — tabelas, colunas geradas (TML/TR/JL), views de KPI, RLS
2. `02_gerar_demo.sql` — função que gera clientes, frota, mapas, PDVs, devoluções e tratativas fictícios
3. `03_seed.sql` — 4 revendas semente

## Rodar
Site estático: abra `index.html` por qualquer servidor (`python -m http.server`) ou GitHub Pages. Para usar seu próprio Supabase, rode os 3 SQLs e troque `SUPABASE_URL`/`SUPABASE_KEY` em `js/app.js`.

## Segurança
- A chave no front é a *publishable* (pública por design); a proteção é por **RLS**: leitura aberta, escrita só em `revendas` (não-semente) e `tratativas`.
- Todo texto vindo do banco é escapado (`esc()`) antes de ir ao HTML; entradas validadas por `CHECK` no banco.
- Limite de 12 revendas e 60 dias por geração. Ambiente de demonstração: para uso real, adicionar Supabase Auth e políticas por usuário/revenda.

> Projeto independente, sem vínculo com qualquer empresa. Nenhum dado real é utilizado.

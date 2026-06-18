# StreamFlow — Projeto de Banco de Dados (MySQL)

Documentação de apoio aos scripts SQL, já alinhada com a **Aula 18 —
Engenharia de Requisitos do Sistema** (RN/RF/RNF).

## Arquivos e ordem de execução

Execute **nesta ordem**, sempre o script inteiro (no Workbench: ícone
do raio "Execute (all or selection)", ou `Ctrl+Shift+Enter`):

| # | Arquivo | O que faz |
|---|---|---|
| 1 | `01_ddl_criacao_banco.sql` | Cria o banco, todas as tabelas, constraints e triggers |
| 2 | `04_view_lgpd.sql` | Cria a view mascarada (precisa existir antes do script 3) |
| 3 | `02_seguranca_privilegios.sql` | Cria os usuários e concede os privilégios (inclui GRANT sobre a view) |
| 4 | `05_dados_exemplo.sql` | (opcional, só para teste) insere um punhado de linhas para você ver resultado de verdade |
| 5 | `03_consultas_bi_e_performance.sql` | Roda os relatórios de BI + cria os índices de performance |
| 6 | `06_teste_regras_negocio.sql` | **Não rode de uma vez.** Comandos isolados, feitos para dar erro de propósito, provando que cada regra está ativa |

Se ao rodar o script 1 a base já existir de uma vez anterior, sem
problema: a primeira linha é `DROP DATABASE IF EXISTS streamflow_db;`
— ele recria tudo do zero a cada execução.

---

## Onde abrir/rodar

São arquivos `.sql` (texto puro). Para só **ler**, qualquer editor de
texto serve (VS Code, Notepad++, Sublime...). Para **executar** de
fato contra um banco, você precisa de um cliente conectado a um
servidor MySQL — Workbench, DBeaver, HeidiSQL, phpMyAdmin ou o
terminal (`mysql -u root -p < 01_ddl_criacao_banco.sql`) funcionam.
Veja a observação abaixo sobre SQL fiddles online: muitos não
suportam bem `DELIMITER`/`TRIGGER`/`CHECK` completos — prefira um
MySQL real (8.0.16+).

---

## Rastreabilidade — Requisitos da Aula 18 → Implementação

### Requisitos de Negócio (RN)

| Requisito | Onde está implementado |
|---|---|
| **RN01** — saldo nunca negativo | Coluna `assinantes.saldo_conta DECIMAL(10,2)` + `CHECK (saldo_conta >= 0)`. Toda movimentação passa por `transacoes_financeiras`; o trigger `trg_transacoes_aplica_saldo` atualiza o saldo, e se isso violar o CHECK, **a transação inteira (incluindo o lançamento) é desfeita** — o débito simplesmente não acontece. Teste 1 do arquivo `06`. |
| **RN02** — toda ação de consumo vinculada a categoria rastreável | `CHECK chk_sessoes_item_unico` / `chk_historico_item_unico` / `chk_logs_item_unico`: exatamente um entre `filme_id`/`episodio_id` deve estar preenchido — nunca os dois, nunca nenhum. Teste 5 do arquivo `06`. |
| **RN03** — histórico/log definitivo (imutável) | `historico_reproducao` e `logs_acesso` têm triggers `BEFORE UPDATE`/`BEFORE DELETE` que **sempre** lançam erro, mais a ausência de qualquer privilégio de UPDATE/DELETE para a aplicação (script 02). Vale mesmo que o conteúdo seja removido do catálogo, porque a cadeia de FKs `titulos → filmes/series → episodios → historico/sessoes` usa `ON DELETE RESTRICT` em toda a extensão (nunca cascata destrutiva). Testes 2, 3 e 6 do arquivo `06`. |

### Requisitos Funcionais (RF)

| Requisito | Onde está implementado |
|---|---|
| **RF01** — até 5 perfis por assinante | Trigger `trg_perfis_limite_5` (`BEFORE INSERT` em `perfis`). Teste 4 do arquivo `06`. |
| **RF02** — log automático de IP/dispositivo/timestamp no Play | Tabela `logs_acesso`: `endereco_ip`, `tipo_dispositivo` (enviados pela app) + `data_hora_evento TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP` (carimbo gerado pelo próprio banco, não pela app). |
| **RF03** — "Continuar Assistindo" | Query 1 de `03_consultas_bi_e_performance.sql`, lendo de `sessoes_reproducao` (estado mutável de retomada) filtrando `concluido = FALSE`, ordenado por `atualizada_em DESC`. |
| **RF04** — minutos/horas consumidos por produtora num período | Query 2 de `03`, somando `historico_reproducao.segundos_consumidos` (ledger imutável) filtrado por mês/ano, com `HAVING > 5000 horas`. |
| **RF05** — auditoria de tráfego por UF + dispositivo | Query 3 de `03`, agregando `logs_acesso` por `assinantes.uf` e `tipo_dispositivo`. |

### Requisitos Não Funcionais (RNF)

| Requisito | Onde está implementado |
|---|---|
| **RNF01** — tabelas no plural, PK sempre `id` | Aplicado em todas as 10 tabelas (`assinantes`, `perfis`, `produtoras`, `titulos`, `filmes`, `series`, `episodios`, `sessoes_reproducao`, `historico_reproducao`, `logs_acesso`, `transacoes_financeiras`). |
| **RNF02** — sem ponto flutuante em valores financeiros/agregações de tempo | `saldo_conta` e `valor` (transações) são `DECIMAL(10,2)`, nunca `FLOAT`/`DOUBLE`. Durações são `INT UNSIGNED` (segundos, inteiro exato). Nas queries de faturamento, o resultado é explicitamente `CAST(... AS DECIMAL(14,2))`. |
| **RNF03** — RBAC: app sem DDL e sem acesso total a logs de auditoria | `app_streamflow` nunca recebe `CREATE`/`ALTER`/`DROP`. Ele **não tem nenhum privilégio** em `historico_reproducao` (só é populado por trigger interno) e só tem `INSERT` — sem `SELECT` — em `logs_acesso`. Quem lê os dois é só `auditor_streamflow`. |
| **RNF04** — mascaramento LGPD | View `vw_analistas_engajamento` (script 04): expõe `perfil_id`, `idade` (calculada), `regiao` e métricas agregadas — nunca CPF/e-mail/nome. `analista_dados` só recebe `GRANT` sobre a view, nunca sobre as tabelas-base. |
| **RNF05** — sem full table scan na tela inicial | Índice composto `idx_sessoes_continuar_assistindo (perfil_id, concluido, atualizada_em DESC)`, com `EXPLAIN` antes/depois no script 03 mostrando a mudança de `type: ALL` para `type: ref`. |

---

## 1. Raciocínio arquitetural — Filmes vs. Séries (herança)

Adotei o padrão **Class Table Inheritance**: `titulos` é o super-tipo
(atributos comuns + `tipo ENUM('FILME','SERIE')`), `filmes` e `series`
são sub-tipos 1:1 (mesma PK, que também é FK para `titulos.id`), e
`episodios` é uma tabela de **composição** (N:1 com `series`), já que
um episódio só existe dentro de uma série.

Vantagens em vez de uma tabela única genérica (com colunas como
`temporada` sempre nulas para filmes):

- Cada subtipo só tem as colunas que fazem sentido para ele.
- `NOT NULL` continua significativo (`duracao_segundos` é obrigatório
  em `filmes`, sem precisar virar opcional para acomodar séries).
- A simetria entre `titulos.tipo` e a existência da linha no subtipo é
  garantida pelos triggers `trg_filmes_valida_tipo` /
  `trg_series_valida_tipo`.

O **item efetivamente assistido** (filme OU episódio) aparece em
`sessoes_reproducao`, `historico_reproducao` e `logs_acesso` como
**duas FKs nuláveis + CHECK de exclusividade mútua** — o jeito
relacional "limpo" de modelar uma associação polimórfica sem perder
FK real (essencial para RN02 e para a integridade do Cenário B).

## 2. Por que separar `sessoes_reproducao` de `historico_reproducao`

Esse é o ponto mais importante da revisão feita após a Aula 18. O
enunciado original pedia um "histórico" que alimentasse a tela
"Continuar Assistindo" (precisa **mudar** a cada segundo assistido) —
mas a RN03 da Aula 18 exige que "logs **e históricos** de reprodução"
sejam **definitivos** (não podem mudar nunca). As duas exigências são
incompatíveis para uma única tabela. A solução:

- **`sessoes_reproducao`** (mutável) = "onde o perfil parou" — um
  ponteiro de retomada, atualizado a cada avanço. É puramente estado
  de interface, não é o registro fiscal. Atende RF03.
- **`historico_reproducao`** (imutável) = ledger contábil de consumo,
  **gerado automaticamente** pelos triggers `trg_sessoes_insert_gera_historico`
  e `trg_sessoes_update_gera_historico` a cada novo avanço em
  `sessoes_reproducao` (cada linha = um incremento real assistido).
  Nunca é editado/apagado (RN03), e é a fonte usada no faturamento das
  produtoras (RF04).

Como os triggers rodam com `SQL SECURITY DEFINER` (padrão do MySQL),
eles escrevem em `historico_reproducao` com o privilégio de quem os
**criou** (o DBA/root), não com o privilégio de quem disparou o
`UPDATE` (a aplicação). Por isso a aplicação não precisa — e não
recebe — nenhum privilégio direto nessa tabela (RNF03).

## 3. Configuração de cascata — Cenário B / RN03

Regra única em todo o schema: **nunca existe `ON DELETE CASCADE`**
saindo de conteúdo, histórico ou log. Toda a cadeia usa
`ON DELETE RESTRICT`:

```
produtoras ← titulos ← filmes/series ← episodios
                                    ↑
                  sessoes_reproducao / historico_reproducao / logs_acesso
```

Remoção de catálogo é sempre **soft delete**:
`UPDATE titulos SET ativo = FALSE, removido_em = NOW() WHERE id = ...`.
O filme/episódio continua existindo fisicamente; só some das telas de
navegação (que devem filtrar `WHERE ativo = TRUE`), enquanto histórico
e faturamento continuam intactos. O mesmo raciocínio vale para
`assinantes`/`perfis`: cancelamento é `status_assinatura = 'CANCELADA'`,
nunca `DELETE`.

## 4. RN01 em detalhe — controle financeiro

`assinantes.saldo_conta` é um *cache* sempre mantido consistente pelo
trigger `trg_transacoes_aplica_saldo`. Toda movimentação real passa
por `transacoes_financeiras` (que também é imutável — correções se
fazem com um lançamento de reversão, nunca editando o original, como
em contabilidade de verdade). Se um débito deixaria o saldo negativo,
o `CHECK chk_assinantes_saldo_nao_negativo` rejeita a operação e o
`INSERT` original em `transacoes_financeiras` também é desfeito
(atomicidade da transação) — ou seja, **o lançamento que causaria o
problema nem chega a ser gravado**.

## 5. Escolha de tipos de dados (RNF02)

| Campo | Tipo | Por quê |
|---|---|---|
| `duracao_segundos`, `posicao_segundos`, `segundos_consumidos` | `INT UNSIGNED` (segundos) | **Não usei `TIME`**: `SUM()` sobre uma coluna `TIME` no MySQL soma o valor numérico `HHMMSS`, não "tempo" — quebraria o relatório de faturamento. Inteiro em segundos torna `SUM`/`AVG`/percentual triviais e exatos; conversão para `HH:MM:SS` fica só na exibição (`SEC_TO_TIME()`). |
| `saldo_conta`, `valor` (transações) | `DECIMAL(10,2)` | RNF02 explicitamente proíbe ponto flutuante em valores monetários (risco de perda de centavos por arredondamento). |
| `id` (todas as tabelas) | `BIGINT UNSIGNED AUTO_INCREMENT` | Volume esperado é alto (milhões de eventos); evita esgotar o intervalo de `INT` em poucos anos. |
| `cpf` | `CHAR(11)` | Tamanho sempre fixo (11 dígitos), mais eficiente para índice B-Tree que `VARCHAR`; só dígitos, sem máscara. |
| `endereco_ip` | `VARCHAR(45)` | Cabe IPv4 e IPv6 em notação textual completa. |
| `tipo_dispositivo`, `tipo` (filme/série, transação), `metodo_pagamento`, `status_assinatura` | `ENUM(...)` | Restringe o domínio (equivalente a `CHECK IN (...)`), 1 byte de armazenamento. |
| `uf` | `CHAR(2)` + `CHECK (CHAR_LENGTH(uf) = 2)` | Sigla de estado é sempre 2 letras. |
| flags booleanas | `BOOLEAN` (alias de `TINYINT(1)`) | Padrão idiomático no MySQL. |

## 6. Qualidade das consultas

- **"Continuar Assistindo"**: `LEFT JOIN` nos dois braços (filme/episódio), já que cada linha só preenche um dos dois.
- **Faturamento por produtora**: `JOIN` interno, pois todo item assistido obrigatoriamente pertence a uma produtora.
- **View LGPD**: agregações pré-computadas em subconsultas derivadas (`hist`, `sess`) antes do `JOIN` final com `perfis`, evitando o problema de "fan-out" que ocorreria juntando `historico_reproducao` e `sessoes_reproducao` diretamente na mesma linha (multiplicaria contagens).
- Filtros em `WHERE` antes do `GROUP BY`; `HAVING` reservado só para o filtro pós-agregação (>5.000 horas).

## 7. O desafio dos milissegundos (RNF05)

- **Antes**: `WHERE perfil_id = ? AND concluido = FALSE ORDER BY atualizada_em DESC` sem índice adequado → `EXPLAIN` mostra `type: ALL` (varredura completa), possivelmente `Using filesort`.
- **Índice criado**: `(perfil_id, concluido, atualizada_em DESC)` — segue a regra do prefixo mais à esquerda (duas igualdades + a coluna de ordenação), eliminando o filesort.
- **Depois**: `EXPLAIN` passa a usar o índice (`type: ref`/`range`), sem `Using filesort`/`Using temporary`.

## 8. Sobre o script de dados do professor

Como o script de carga massiva ainda não foi fornecido, os nomes de
tabela/coluna seguem convenções claras e documentadas aqui. Se o
script oficial usar nomes diferentes, normalmente basta ajustar os
`INSERT`s para os nomes definidos neste projeto, ou usar
`ALTER TABLE ... RENAME COLUMN` (MySQL 8.0+).

`05_dados_exemplo.sql` é só um punhado de linhas para você testar
localmente antes da carga oficial — pode ser ignorado/sobrescrito.

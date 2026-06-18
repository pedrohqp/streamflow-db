-- =====================================================================
-- STREAMFLOW - POLÍTICA DE PRIVILÉGIOS (RBAC)  [RNF03]
-- =====================================================================
-- IMPORTANTE: o MySQL NÃO possui o comando DENY (isso é T-SQL/SQL
-- Server). No MySQL a negação é IMPLÍCITA: tudo que não foi GRANT-ado
-- já está bloqueado por padrão. Por isso este script usa apenas GRANT
-- e REVOKE; o REVOKE aparece em alguns pontos de forma redundante só
-- para deixar a intenção de segurança documentada no próprio script.
--
-- Execute este script DEPOIS de 01_ddl_criacao_banco.sql e
-- 04_view_lgpd.sql (a view precisa existir antes do GRANT sobre ela).
-- =====================================================================

USE streamflow_db;

-- =====================================================================
-- 1. APP_STREAMFLOW — aplicação que atende o usuário final
--    RNF03: não pode ter DDL (CREATE/ALTER/DROP) nem acesso total aos
--    logs/histórico de auditoria.
-- =====================================================================
DROP USER IF EXISTS 'app_streamflow'@'%';
CREATE USER 'app_streamflow'@'%' IDENTIFIED BY 'TROCAR_ESSA_SENHA_FORTE!1';

-- Nunca concedemos nenhum privilégio de DDL (CREATE, ALTER, DROP,
-- INDEX, TRIGGER...) para este usuário — por omissão, já fica bloqueado.

-- Assinantes: pode ler e criar conta, e atualizar SOMENTE colunas
-- cadastrais. saldo_conta e cpf ficam de fora do GRANT de UPDATE:
-- saldo só muda via trigger (disparado por INSERT em
-- transacoes_financeiras) e cpf não deve ser editável pela app (RN01).
GRANT SELECT, INSERT ON streamflow_db.assinantes TO 'app_streamflow'@'%';
GRANT UPDATE (nome_completo, email, uf, metodo_pagamento, status_assinatura)
    ON streamflow_db.assinantes TO 'app_streamflow'@'%';

-- Perfis: CRUD básico, sem DELETE (perfil com histórico não pode ser
-- removido fisicamente).
GRANT SELECT, INSERT, UPDATE ON streamflow_db.perfis TO 'app_streamflow'@'%';

-- Catálogo: somente leitura (cadastro de conteúdo é processo de
-- back-office, fora do escopo da app de consumo).
GRANT SELECT ON streamflow_db.produtoras TO 'app_streamflow'@'%';
GRANT SELECT ON streamflow_db.titulos    TO 'app_streamflow'@'%';
GRANT SELECT ON streamflow_db.filmes     TO 'app_streamflow'@'%';
GRANT SELECT ON streamflow_db.series     TO 'app_streamflow'@'%';
GRANT SELECT ON streamflow_db.episodios  TO 'app_streamflow'@'%';

-- Sessões de reprodução (estado mutável de "Continuar Assistindo"):
-- a app lê, cria e atualiza a posição. Nunca apaga.
GRANT SELECT, INSERT, UPDATE ON streamflow_db.sessoes_reproducao TO 'app_streamflow'@'%';

-- Histórico de reprodução (ledger imutável, RN03): a app NÃO recebe
-- NENHUM privilégio aqui. Ele é populado automaticamente pelos
-- triggers (que rodam com privilégio de quem os criou, SQL SECURITY
-- DEFINER), não pela aplicação diretamente. Isso é o que cumpre, na
-- prática, a exigência da RNF03 de que a app não tenha "acesso total
-- aos logs históricos de auditoria" — aqui ela não tem acesso nenhum.

-- Logs de acesso (RF02): a app só registra o evento de "Play".
-- Sem SELECT (não precisa consultar), sem UPDATE/DELETE (imutável).
GRANT INSERT ON streamflow_db.logs_acesso TO 'app_streamflow'@'%';

-- Transações financeiras: a app registra cobranças/créditos, mas não
-- edita nem apaga lançamentos já feitos (RN01/RN03).
GRANT SELECT, INSERT ON streamflow_db.transacoes_financeiras TO 'app_streamflow'@'%';

-- =====================================================================
-- 2. AUDITOR_STREAMFLOW — auditoria fiscal / direitos autorais
--    Só leitura dos registros definitivos (RN03). Sem acesso a dados
--    pessoais (assinantes/perfis) nem a transações financeiras.
-- =====================================================================
DROP USER IF EXISTS 'auditor_streamflow'@'%';
CREATE USER 'auditor_streamflow'@'%' IDENTIFIED BY 'OUTRA_SENHA_FORTE!2';

GRANT SELECT ON streamflow_db.logs_acesso         TO 'auditor_streamflow'@'%';
GRANT SELECT ON streamflow_db.historico_reproducao TO 'auditor_streamflow'@'%';

-- =====================================================================
-- 3. ANALISTA_DADOS — marketing / BI demográfico
--    RNF04 (LGPD): só pode ver a VIEW mascarada, nunca as tabelas-base
--    que contêm CPF, e-mail ou nome real.
-- =====================================================================
DROP USER IF EXISTS 'analista_dados'@'%';
CREATE USER 'analista_dados'@'%' IDENTIFIED BY 'SENHA_ANALISTA!3';

GRANT SELECT ON streamflow_db.vw_analistas_engajamento TO 'analista_dados'@'%';
-- Nenhum GRANT direto em assinantes/perfis/transacoes_financeiras.

-- =====================================================================
-- Alternativa avançada (mencionada, não usada como padrão): o MySQL
-- permite GRANT em nível de COLUNA, ex.:
--   GRANT SELECT (id, nome_exibicao, data_nascimento) ON perfis TO 'x'@'%';
-- Optamos por VIEW para o analista de marketing porque ela também
-- calcula idade e agrega métricas — o privilégio de coluna não faz isso.
-- Já usamos GRANT de coluna acima, em assinantes, para proteger
-- especificamente saldo_conta/cpf da app.
-- =====================================================================

FLUSH PRIVILEGES;

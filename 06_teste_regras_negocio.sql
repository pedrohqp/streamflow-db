-- =====================================================================
-- STREAMFLOW - TESTES DE REGRA DE NEGÓCIO
-- =====================================================================
-- ATENÇÃO: os comandos abaixo são feitos para DAR ERRO de propósito.
-- Não rode este arquivo inteiro de uma vez (o Workbench vai parar no
-- primeiro erro). Rode UM comando por vez, selecione a linha e aperte
-- Ctrl+Enter (ou o raio "Execute current statement") para ver, na
-- prática, cada regra de negócio sendo bloqueada pelo banco.
--
-- Pré-requisito: já ter rodado 01, 04, 02 e 05 (dados de exemplo).
-- =====================================================================
USE streamflow_db;

-- -----------------------------------------------------------------
-- TESTE 1 — RN01: saldo não pode ficar negativo
-- O assinante 1 tem saldo_conta = 20.10 (depois do 05). Tentar debitar
-- 100,00 deve ser REJEITADO pelo CHECK de assinantes.saldo_conta.
-- -----------------------------------------------------------------
INSERT INTO transacoes_financeiras (assinante_id, tipo, valor, descricao)
VALUES (1, 'DEBITO', 100.00, 'Tentativa de débito maior que o saldo (deve falhar)');
-- Esperado: Error Code 3819 (Check constraint 'chk_assinantes_saldo_nao_negativo'
-- is violated) E a linha em transacoes_financeiras também NÃO é gravada
-- (a transação inteira é desfeita).

-- -----------------------------------------------------------------
-- TESTE 2 — RN03: histórico de reprodução é definitivo
-- -----------------------------------------------------------------
UPDATE historico_reproducao SET segundos_consumidos = 999999 WHERE id = 1;
-- Esperado: erro disparado por trg_historico_bloqueia_update.

DELETE FROM historico_reproducao WHERE id = 1;
-- Esperado: erro disparado por trg_historico_bloqueia_delete.

-- -----------------------------------------------------------------
-- TESTE 3 — RN03: logs de acesso são imutáveis
-- -----------------------------------------------------------------
DELETE FROM logs_acesso WHERE id = 1;
-- Esperado: erro disparado por trg_logs_acesso_bloqueia_delete.

-- -----------------------------------------------------------------
-- TESTE 4 — RF01: máximo de 5 perfis por assinante
-- -----------------------------------------------------------------
INSERT INTO perfis (assinante_id, nome_exibicao, data_nascimento) VALUES (1, 'Perfil 3', '1995-01-01');
INSERT INTO perfis (assinante_id, nome_exibicao, data_nascimento) VALUES (1, 'Perfil 4', '1995-01-01');
INSERT INTO perfis (assinante_id, nome_exibicao, data_nascimento) VALUES (1, 'Perfil 5', '1995-01-01');
-- até aqui são 5 perfis no total (2 do script 05 + estes 3) -> ok
INSERT INTO perfis (assinante_id, nome_exibicao, data_nascimento) VALUES (1, 'Perfil 6', '1995-01-01');
-- Esperado: erro disparado por trg_perfis_limite_5 neste 6º INSERT.

-- -----------------------------------------------------------------
-- TESTE 5 — RN02: ação de consumo sempre vinculada a uma categoria
-- (não pode registrar sessão "genérica", sem filme nem episódio, ou
-- com os dois ao mesmo tempo).
-- -----------------------------------------------------------------
INSERT INTO sessoes_reproducao (perfil_id, filme_id, episodio_id, posicao_segundos)
VALUES (1, NULL, NULL, 10);
-- Esperado: erro de CHECK chk_sessoes_item_unico.

INSERT INTO sessoes_reproducao (perfil_id, filme_id, episodio_id, posicao_segundos)
VALUES (1, 1, 1, 10);
-- Esperado: erro de CHECK chk_sessoes_item_unico (os dois preenchidos).

-- -----------------------------------------------------------------
-- TESTE 6 — Cenário B: não dá para apagar fisicamente um filme com
-- histórico/sessões associadas (remoção de catálogo deve ser via
-- UPDATE titulos SET ativo = FALSE, não DELETE).
-- -----------------------------------------------------------------
DELETE FROM filmes WHERE id = 1;
-- Esperado: erro de FK (RESTRICT) — bloqueado por sessoes_reproducao
-- e/ou historico_reproducao referenciando este filme.

-- Forma CORRETA de "remover" o filme do catálogo (não dá erro):
-- UPDATE titulos SET ativo = FALSE, removido_em = NOW() WHERE id = 1;

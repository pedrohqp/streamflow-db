-- =====================================================================
-- STREAMFLOW - DADOS DE EXEMPLO (só para você testar localmente)
-- =====================================================================
-- O professor vai fornecer um script com milhares de registros
-- simulados — este aqui é só um punhado de linhas para você conseguir
-- abrir o 03_consultas_bi_e_performance.sql e ver resultado de verdade,
-- em vez de tabelas vazias. Pode ser descartado/sobrescrito quando o
-- script oficial do professor chegar.
--
-- Execute DEPOIS de: 01_ddl_criacao_banco.sql, 04_view_lgpd.sql,
-- 02_seguranca_privilegios.sql.
-- =====================================================================
USE streamflow_db;

-- ---------- Produtoras (ids 1 e 2) ----------
INSERT INTO produtoras (nome, pais_origem, contrato_ativo, data_inicio_contrato)
VALUES
('Estúdio Aurora', 'Brasil', TRUE, '2023-01-01'),
('Galaxy Films',   'EUA',    TRUE, '2022-06-15');

-- ---------- Títulos (id 1 = filme da Aurora, id 2 = série da Galaxy) ----------
INSERT INTO titulos (produtora_id, nome, tipo, classificacao_indicativa, ano_lancamento)
VALUES
(1, 'Noite Sem Fim',        'FILME', 14, 2023),
(2, 'Fronteiras do Amanhã', 'SERIE', 12, 2022);

-- ---------- Subtipos ----------
INSERT INTO filmes (id, duracao_segundos) VALUES (1, 7140);          -- ~1h59
INSERT INTO series (id, total_temporadas) VALUES (2, 1);

-- ---------- Episódios da série (id 2) ----------
INSERT INTO episodios (serie_id, temporada, numero_episodio, nome_episodio, duracao_segundos)
VALUES
(2, 1, 1, 'O Despertar', 2700),   -- 45 min
(2, 1, 2, 'A Travessia', 2580);   -- 43 min

-- ---------- Assinante (id 1) ----------
INSERT INTO assinantes (nome_completo, email, cpf, uf, metodo_pagamento, status_assinatura)
VALUES ('Joana Pereira', 'joana.pereira@example.com', '12345678901', 'SP', 'CARTAO_CREDITO', 'ATIVA');

-- ---------- Perfis do assinante 1 (ids 1 e 2) ----------
INSERT INTO perfis (assinante_id, nome_exibicao, data_nascimento, perfil_infantil, classificacao_indicativa_max)
VALUES
(1, 'Joana',  '1990-04-12', FALSE, 18),
(1, 'Pedrinho','2016-08-30', TRUE,  10);

-- ---------- Movimentação financeira (RN01) ----------
-- Crédito de saldo (ex.: cashback/promoção) e débito da mensalidade.
INSERT INTO transacoes_financeiras (assinante_id, tipo, valor, descricao)
VALUES (1, 'CREDITO', 50.00, 'Crédito promocional de boas-vindas');

INSERT INTO transacoes_financeiras (assinante_id, tipo, valor, descricao)
VALUES (1, 'DEBITO', 29.90, 'Mensalidade do plano padrão');

-- Confira o saldo atualizado automaticamente pelo trigger:
SELECT id, nome_completo, saldo_conta FROM assinantes WHERE id = 1;
-- Esperado: saldo_conta = 20.10

-- ---------- Logs de acesso (RF02) ----------
INSERT INTO logs_acesso (perfil_id, filme_id, episodio_id, endereco_ip, tipo_dispositivo)
VALUES
(1, 1, NULL, '189.45.12.10', 'SMART_TV'),
(2, NULL, 1, '189.45.12.10', 'TABLET');

-- ---------- Sessões de reprodução (RF03) ----------
-- Joana (perfil 1) começa a assistir o filme e ainda não terminou.
INSERT INTO sessoes_reproducao (perfil_id, filme_id, episodio_id, posicao_segundos, concluido)
VALUES (1, 1, NULL, 1800, FALSE);   -- assistiu 30 min de ~1h59

-- Pedrinho (perfil 2) começa o episódio 1 da série.
INSERT INTO sessoes_reproducao (perfil_id, filme_id, episodio_id, posicao_segundos, concluido)
VALUES (2, NULL, 1, 2700, TRUE);    -- assistiu o episódio inteiro (concluído)

-- Joana volta depois e avança mais 900s no mesmo filme (UPDATE, não INSERT).
-- Isso dispara o trigger trg_sessoes_update_gera_historico, que grava
-- automaticamente o INCREMENTO (900s) no ledger imutável.
UPDATE sessoes_reproducao
   SET posicao_segundos = 2700
 WHERE perfil_id = 1 AND filme_id = 1;

-- ---------- Verificações ----------
-- O ledger (historico_reproducao) deve ter 3 linhas geradas
-- automaticamente: 1800 (insert inicial de Joana), 2700 (insert
-- inicial de Pedrinho) e 900 (delta do avanço de Joana).
SELECT * FROM historico_reproducao ORDER BY id;

-- "Continuar assistindo" de Joana já deve aparecer com 2700s (45min)
-- assistidos de 7140s totais, ~37.8%.
SELECT perfil_id, filme_id, episodio_id, posicao_segundos, concluido, atualizada_em
FROM sessoes_reproducao
WHERE perfil_id = 1;

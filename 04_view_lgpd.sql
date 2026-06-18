-- =====================================================================
-- STREAMFLOW - CONFORMIDADE LGPD: VIEW DE DADOS MASCARADOS  [RNF04]
-- =====================================================================
-- Marketing e analistas de dados NUNCA devem ver cpf, e-mail ou nome
-- real do assinante. Esta view expõe apenas:
--   - um identificador (perfil_id) sem nenhum dado de identificação direta
--   - idade calculada a partir da data de nascimento
--   - região (UF)
--   - métricas de engajamento agregadas (vindas do ledger imutável)
--
-- Execute este script DEPOIS de 01_ddl_criacao_banco.sql.
-- =====================================================================
USE streamflow_db;

CREATE OR REPLACE VIEW vw_analistas_engajamento AS
SELECT
    pf.id                                                  AS perfil_id,
    TIMESTAMPDIFF(YEAR, pf.data_nascimento, CURDATE())     AS idade,
    a.uf                                                    AS regiao,
    pf.perfil_infantil,
    COALESCE(hist.qtd_titulos_distintos, 0)                 AS qtd_titulos_distintos_assistidos,
    COALESCE(hist.total_segundos, 0)                        AS total_segundos_consumidos,
    COALESCE(sess.qtd_concluidos, 0)                        AS qtd_titulos_concluidos
FROM perfis pf
JOIN assinantes a ON a.id = pf.assinante_id
LEFT JOIN (
    -- CONCAT com separador evita que um filme id=1 e um episódio id=1
    -- sejam contados como "o mesmo título" (são sequências de
    -- auto-incremento independentes, então colidem se só usarmos COALESCE).
    SELECT perfil_id,
           COUNT(DISTINCT CONCAT(COALESCE(filme_id, -1), '|', COALESCE(episodio_id, -1))) AS qtd_titulos_distintos,
           SUM(segundos_consumidos)                          AS total_segundos
    FROM historico_reproducao
    GROUP BY perfil_id
) hist ON hist.perfil_id = pf.id
LEFT JOIN (
    SELECT perfil_id, COUNT(*) AS qtd_concluidos
    FROM sessoes_reproducao
    WHERE concluido = TRUE
    GROUP BY perfil_id
) sess ON sess.perfil_id = pf.id;

-- Acesso concedido em 02_seguranca_privilegios.sql:
-- GRANT SELECT ON streamflow_db.vw_analistas_engajamento TO 'analista_dados'@'%';

-- Exemplo de uso pelo analista (nunca toca em cpf/email/nome):
-- SELECT regiao, AVG(idade), AVG(total_segundos_consumidos)/3600 AS horas_media
-- FROM vw_analistas_engajamento
-- GROUP BY regiao;

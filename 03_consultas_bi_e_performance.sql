-- =====================================================================
-- STREAMFLOW - PARTE 2: CONSULTAS DE BI  [RF03, RF04, RF05, RNF05]
-- =====================================================================
-- Execute DEPOIS de 01, 04, 02 e (se quiser ver resultado) 05.
-- =====================================================================
USE streamflow_db;

-- =====================================================================
-- RF03 — "CONTINUAR ASSISTINDO" (tela inicial de um perfil)
-- Lê de sessoes_reproducao (estado MUTÁVEL de retomada), não do
-- ledger imutável — ver README seção 2.
-- =====================================================================
SET @perfil_id_consulta = 1;  -- troque pelo id do perfil desejado

SELECT
    s.id                                                 AS sessao_id,
    COALESCE(t_filme.nome, t_serie.nome)                 AS titulo_obra,
    CASE WHEN s.filme_id IS NOT NULL THEN 'FILME' ELSE 'EPISODIO' END AS tipo_conteudo,
    e.temporada,
    e.numero_episodio,
    e.nome_episodio,
    s.posicao_segundos,
    COALESCE(f.duracao_segundos, e.duracao_segundos)      AS duracao_total_segundos,
    ROUND(
        s.posicao_segundos
        / COALESCE(f.duracao_segundos, e.duracao_segundos) * 100, 1
    )                                                      AS percentual_assistido,
    s.atualizada_em
FROM sessoes_reproducao s
LEFT JOIN filmes      f       ON s.filme_id     = f.id
LEFT JOIN titulos     t_filme ON f.id           = t_filme.id
LEFT JOIN episodios   e       ON s.episodio_id  = e.id
LEFT JOIN series      sr      ON e.serie_id     = sr.id
LEFT JOIN titulos     t_serie ON sr.id          = t_serie.id
WHERE s.perfil_id = @perfil_id_consulta
  AND s.concluido = FALSE
ORDER BY s.atualizada_em DESC;


-- =====================================================================
-- RF04 — FATURAMENTO DOS ESTÚDIOS
-- Soma a partir do ledger IMUTÁVEL (historico_reproducao), que é a
-- fonte de verdade fiscal/auditável. CAST para DECIMAL (RNF02: nunca
-- usar tipo de ponto flutuante em agregação financeira/de tempo).
-- =====================================================================
SET @ano_consulta = 2026;
SET @mes_consulta  = 6;

SELECT
    p.nome                                              AS produtora,
    CAST(SUM(h.segundos_consumidos) / 60   AS DECIMAL(14,2)) AS minutos_consumidos,
    CAST(SUM(h.segundos_consumidos) / 3600 AS DECIMAL(14,2)) AS horas_consumidas
FROM historico_reproducao h
LEFT JOIN filmes    f ON h.filme_id    = f.id
LEFT JOIN episodios e ON h.episodio_id = e.id
LEFT JOIN series    s ON e.serie_id    = s.id
JOIN titulos   t ON t.id = COALESCE(f.id, s.id)
JOIN produtoras p ON p.id = t.produtora_id
WHERE YEAR(h.registrado_em)  = @ano_consulta
  AND MONTH(h.registrado_em) = @mes_consulta
GROUP BY p.id, p.nome
HAVING SUM(h.segundos_consumidos) / 3600 > 5000
ORDER BY horas_consumidas DESC;

-- Observação: com a base de exemplo (05_dados_exemplo.sql) esta query
-- retorna VAZIO de propósito — são poucos segundos de consumo, muito
-- abaixo do corte de 5.000 horas. Isso é esperado e não é erro; o
-- filtro HAVING está funcionando. Quando o professor carregar a base
-- massiva, produtoras de fato relevantes aparecerão aqui.


-- =====================================================================
-- RF05 — AUDITORIA DE TRÁFEGO POR REGIÃO E DISPOSITIVO
-- =====================================================================
SELECT
    a.uf                AS estado,
    l.tipo_dispositivo,
    COUNT(*)             AS total_acessos
FROM logs_acesso l
JOIN perfis     pf ON pf.id = l.perfil_id
JOIN assinantes a  ON a.id  = pf.assinante_id
GROUP BY a.uf, l.tipo_dispositivo
ORDER BY a.uf, total_acessos DESC;


-- =====================================================================
-- RNF05 — TUNING DE PERFORMANCE ("O TESTE DE FOGO")
-- =====================================================================

-- PASSO 1: EXPLAIN ANTES do índice. Em base massiva, esperado:
-- "type: ALL" (full table scan) e/ou "Using filesort".
EXPLAIN
SELECT *
FROM sessoes_reproducao s
WHERE s.perfil_id = 1
  AND s.concluido = FALSE
ORDER BY s.atualizada_em DESC;

-- PASSO 2: índice composto, ordem seguindo a regra do prefixo mais à
-- esquerda:
--   1) perfil_id    -> igualdade (sempre usado)
--   2) concluido     -> igualdade (alta seletividade combinada)
--   3) atualizada_em -> usado tanto para faixa quanto ORDER BY,
--                        eliminando o filesort. DESC suportado
--                        nativamente a partir do MySQL 8.0.
CREATE INDEX idx_sessoes_continuar_assistindo
    ON sessoes_reproducao (perfil_id, concluido, atualizada_em DESC);

-- PASSO 3: EXPLAIN DEPOIS do índice. Esperado: "type: ref" (ou
-- "range"), "key: idx_sessoes_continuar_assistindo", sem
-- "Using filesort" / "Using temporary".
EXPLAIN
SELECT *
FROM sessoes_reproducao s
WHERE s.perfil_id = 1
  AND s.concluido = FALSE
ORDER BY s.atualizada_em DESC;

-- Índices de apoio para os outros relatórios (evitam scans completos
-- nas junções de BI/auditoria; não eram o "teste de fogo" em si):
CREATE INDEX idx_historico_registrado_em ON historico_reproducao (registrado_em);
CREATE INDEX idx_logs_perfil             ON logs_acesso (perfil_id);
CREATE INDEX idx_assinantes_uf           ON assinantes (uf);

-- =====================================================================
-- STREAMFLOW - SCRIPT DE CRIAÇÃO DO BANCO DE DADOS (DDL)
-- SGBD alvo: MySQL 8.0+ (testado para MySQL Workbench)
-- Rastreabilidade: cada bloco indica qual(is) requisito(s) da Aula 18
-- (RN/RF/RNF) ele atende, para facilitar a homologação.
-- =====================================================================
-- CHECK constraints exigem MySQL 8.0.16+ para serem de fato aplicados
-- (antes disso são aceitos na sintaxe, porém ignorados).
-- =====================================================================

DROP DATABASE IF EXISTS streamflow_db;
CREATE DATABASE streamflow_db
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_unicode_ci;

USE streamflow_db;

-- =====================================================================
-- 1. ASSINANTES  [RNF01 nomenclatura | RN01 controle de saldo | RNF02 DECIMAL]
-- =====================================================================
CREATE TABLE assinantes (
    id                  BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    nome_completo        VARCHAR(150)    NOT NULL,
    email                VARCHAR(150)    NOT NULL,
    cpf                  CHAR(11)        NOT NULL COMMENT 'Somente dígitos, sem máscara',
    uf                   CHAR(2)         NOT NULL,
    metodo_pagamento     ENUM('CARTAO_CREDITO','BOLETO','PIX','PAYPAL') NOT NULL DEFAULT 'CARTAO_CREDITO',
    status_assinatura    ENUM('ATIVA','INADIMPLENTE','CANCELADA') NOT NULL DEFAULT 'ATIVA',

    -- RN01: saldo nunca pode ficar negativo. DECIMAL (não FLOAT/DOUBLE)
    -- por exigência da RNF02 (precisão exata para valores monetários).
    saldo_conta          DECIMAL(10,2)   NOT NULL DEFAULT 0.00,

    data_cadastro        DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT uq_assinantes_email UNIQUE (email),
    CONSTRAINT uq_assinantes_cpf   UNIQUE (cpf),
    CONSTRAINT chk_assinantes_uf   CHECK (CHAR_LENGTH(uf) = 2),
    -- Barreira estrutural do RN01: qualquer UPDATE que tente deixar o
    -- saldo negativo é rejeitado pelo próprio SGBD.
    CONSTRAINT chk_assinantes_saldo_nao_negativo CHECK (saldo_conta >= 0)
) ENGINE=InnoDB;

-- =====================================================================
-- 2. PERFIS  [RF01 - até 5 perfis por assinante]
-- =====================================================================
CREATE TABLE perfis (
    id                          BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    assinante_id                BIGINT UNSIGNED NOT NULL,
    nome_exibicao                VARCHAR(80)     NOT NULL,
    data_nascimento              DATE            NOT NULL,
    perfil_infantil              BOOLEAN         NOT NULL DEFAULT FALSE,
    classificacao_indicativa_max TINYINT UNSIGNED NOT NULL DEFAULT 18,
    data_criacao                 DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,

    -- RESTRICT: não se apaga assinante com perfil/histórico vinculado.
    -- Cancelamento = status_assinatura = 'CANCELADA' (soft delete).
    CONSTRAINT fk_perfis_assinante FOREIGN KEY (assinante_id)
        REFERENCES assinantes(id)
        ON UPDATE CASCADE
        ON DELETE RESTRICT
) ENGINE=InnoDB;

DELIMITER $$
CREATE TRIGGER trg_perfis_limite_5
BEFORE INSERT ON perfis
FOR EACH ROW
BEGIN
    DECLARE qtd_perfis INT;
    SELECT COUNT(*) INTO qtd_perfis
      FROM perfis
     WHERE assinante_id = NEW.assinante_id;

    IF qtd_perfis >= 5 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Limite de 5 perfis por assinante excedido (RF01).';
    END IF;
END$$
DELIMITER ;

-- =====================================================================
-- 3. PRODUTORAS
-- =====================================================================
CREATE TABLE produtoras (
    id                    BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    nome                   VARCHAR(150) NOT NULL,
    pais_origem            VARCHAR(60),
    contrato_ativo         BOOLEAN      NOT NULL DEFAULT TRUE,
    data_inicio_contrato   DATE,
    data_fim_contrato      DATE,

    CONSTRAINT uq_produtoras_nome UNIQUE (nome)
) ENGINE=InnoDB;

-- =====================================================================
-- 4. TÍTULOS (super-tipo) + FILMES / SERIES (sub-tipos) + EPISODIOS
-- Cenário B / herança: ver README, seção 1.
-- =====================================================================
CREATE TABLE titulos (
    id                          BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    produtora_id                 BIGINT UNSIGNED NOT NULL,
    nome                          VARCHAR(200)    NOT NULL,
    tipo                          ENUM('FILME','SERIE') NOT NULL,
    classificacao_indicativa      TINYINT UNSIGNED NOT NULL DEFAULT 0,
    ano_lancamento                SMALLINT UNSIGNED NOT NULL,
    ativo                         BOOLEAN         NOT NULL DEFAULT TRUE COMMENT 'FALSE = removido do catálogo ativo',
    removido_em                   DATETIME        NULL,

    CONSTRAINT fk_titulos_produtora FOREIGN KEY (produtora_id)
        REFERENCES produtoras(id)
        ON UPDATE CASCADE
        ON DELETE RESTRICT
) ENGINE=InnoDB;

CREATE TABLE filmes (
    id                  BIGINT UNSIGNED PRIMARY KEY,
    duracao_segundos     INT UNSIGNED NOT NULL,

    CONSTRAINT fk_filmes_titulo FOREIGN KEY (id)
        REFERENCES titulos(id) ON UPDATE CASCADE ON DELETE RESTRICT
) ENGINE=InnoDB;

CREATE TABLE series (
    id                  BIGINT UNSIGNED PRIMARY KEY,
    total_temporadas     SMALLINT UNSIGNED NOT NULL DEFAULT 1,

    CONSTRAINT fk_series_titulo FOREIGN KEY (id)
        REFERENCES titulos(id) ON UPDATE CASCADE ON DELETE RESTRICT
) ENGINE=InnoDB;

CREATE TABLE episodios (
    id                  BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    serie_id              BIGINT UNSIGNED NOT NULL,
    temporada             SMALLINT UNSIGNED NOT NULL,
    numero_episodio       SMALLINT UNSIGNED NOT NULL,
    nome_episodio         VARCHAR(200)    NOT NULL,
    duracao_segundos      INT UNSIGNED    NOT NULL,

    CONSTRAINT fk_episodios_serie FOREIGN KEY (serie_id)
        REFERENCES series(id) ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT uq_episodios_serie_temp_num UNIQUE (serie_id, temporada, numero_episodio)
) ENGINE=InnoDB;

DELIMITER $$
CREATE TRIGGER trg_filmes_valida_tipo
BEFORE INSERT ON filmes
FOR EACH ROW
BEGIN
    DECLARE v_tipo VARCHAR(10);
    SELECT tipo INTO v_tipo FROM titulos WHERE id = NEW.id;
    IF v_tipo IS NULL OR v_tipo <> 'FILME' THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'O título referenciado não está marcado como FILME em titulos.tipo.';
    END IF;
END$$

CREATE TRIGGER trg_series_valida_tipo
BEFORE INSERT ON series
FOR EACH ROW
BEGIN
    DECLARE v_tipo VARCHAR(10);
    SELECT tipo INTO v_tipo FROM titulos WHERE id = NEW.id;
    IF v_tipo IS NULL OR v_tipo <> 'SERIE' THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'O título referenciado não está marcado como SERIE em titulos.tipo.';
    END IF;
END$$
DELIMITER ;

-- =====================================================================
-- 5. SESSOES_REPRODUCAO  [RF03 - estado MUTÁVEL de "Continuar Assistindo"]
--
-- Isto é o "ponteiro de retomada": ONDE o perfil parou em cada item.
-- É atualizado a cada avanço de reprodução. NÃO é o histórico fiscal
-- (esse é a tabela historico_reproducao, abaixo, que é imutável).
-- Separar os dois conceitos é o que permite cumprir RF03 (precisa
-- mudar) e RN03 (precisa nunca mudar) sem contradição.
-- =====================================================================
CREATE TABLE sessoes_reproducao (
    id                  BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    perfil_id             BIGINT UNSIGNED NOT NULL,
    filme_id              BIGINT UNSIGNED NULL,
    episodio_id           BIGINT UNSIGNED NULL,
    posicao_segundos      INT UNSIGNED    NOT NULL DEFAULT 0 COMMENT 'Posição atual do "play head"',
    concluido              BOOLEAN        NOT NULL DEFAULT FALSE,
    iniciada_em             DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    atualizada_em           DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP
                                            ON UPDATE CURRENT_TIMESTAMP,

    CONSTRAINT fk_sessoes_perfil FOREIGN KEY (perfil_id)
        REFERENCES perfis(id) ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_sessoes_filme FOREIGN KEY (filme_id)
        REFERENCES filmes(id) ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_sessoes_episodio FOREIGN KEY (episodio_id)
        REFERENCES episodios(id) ON UPDATE CASCADE ON DELETE RESTRICT,

    -- RN02: toda ação de consumo deve estar vinculada a EXATAMENTE uma
    -- categoria rastreável (filme OU episódio, nunca ambos, nunca nenhum).
    CONSTRAINT chk_sessoes_item_unico CHECK (
        (filme_id IS NOT NULL AND episodio_id IS NULL) OR
        (filme_id IS NULL AND episodio_id IS NOT NULL)
    ),
    CONSTRAINT uq_sessoes_perfil_filme    UNIQUE (perfil_id, filme_id),
    CONSTRAINT uq_sessoes_perfil_episodio UNIQUE (perfil_id, episodio_id)
) ENGINE=InnoDB;

-- =====================================================================
-- 6. HISTORICO_REPRODUCAO  [RN02 + RN03 - ledger IMUTÁVEL de consumo]
--
-- Cada linha = um INCREMENTO definitivo de consumo, gerado
-- automaticamente (via trigger) a partir da evolução de
-- sessoes_reproducao. É a fonte de verdade para faturamento (RF04) e
-- auditoria fiscal de direitos autorais. Uma vez gravada, a linha
-- nunca é alterada nem apagada — mesmo que o vídeo seja removido do
-- catálogo (FK RESTRICT na cadeia titulos->filmes/series->episodios
-- garante isso, ver seção 4 do README).
-- =====================================================================
CREATE TABLE historico_reproducao (
    id                  BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    perfil_id             BIGINT UNSIGNED NOT NULL,
    filme_id              BIGINT UNSIGNED NULL,
    episodio_id           BIGINT UNSIGNED NULL,
    segundos_consumidos   INT UNSIGNED    NOT NULL,
    registrado_em          DATETIME       NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT fk_historico_perfil FOREIGN KEY (perfil_id)
        REFERENCES perfis(id) ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_historico_filme FOREIGN KEY (filme_id)
        REFERENCES filmes(id) ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_historico_episodio FOREIGN KEY (episodio_id)
        REFERENCES episodios(id) ON UPDATE CASCADE ON DELETE RESTRICT,

    CONSTRAINT chk_historico_item_unico CHECK (
        (filme_id IS NOT NULL AND episodio_id IS NULL) OR
        (filme_id IS NULL AND episodio_id IS NOT NULL)
    )
) ENGINE=InnoDB;

-- Geração automática do ledger a partir de sessoes_reproducao.
-- SQL SECURITY DEFINER (padrão) -> o trigger grava em historico_reproducao
-- com o privilégio de quem o CRIOU (ex.: root/DBA), não com o privilégio
-- de quem dispara o UPDATE/INSERT (a aplicação). Por isso a aplicação não
-- precisa (e não deve, RNF03) ter privilégio direto de escrita nessa
-- tabela: ela só escreve em sessoes_reproducao, e o ledger é derivado.
DELIMITER $$
CREATE TRIGGER trg_sessoes_insert_gera_historico
AFTER INSERT ON sessoes_reproducao
FOR EACH ROW
BEGIN
    IF NEW.posicao_segundos > 0 THEN
        INSERT INTO historico_reproducao (perfil_id, filme_id, episodio_id, segundos_consumidos)
        VALUES (NEW.perfil_id, NEW.filme_id, NEW.episodio_id, NEW.posicao_segundos);
    END IF;
END$$

CREATE TRIGGER trg_sessoes_update_gera_historico
AFTER UPDATE ON sessoes_reproducao
FOR EACH ROW
BEGIN
    DECLARE delta INT;
    SET delta = NEW.posicao_segundos - OLD.posicao_segundos;
    -- só registra avanço real; retrocesso (usuário voltou o vídeo) não
    -- gera consumo negativo no ledger.
    IF delta > 0 THEN
        INSERT INTO historico_reproducao (perfil_id, filme_id, episodio_id, segundos_consumidos)
        VALUES (NEW.perfil_id, NEW.filme_id, NEW.episodio_id, delta);
    END IF;
END$$

-- RN03: bloqueio explícito de UPDATE/DELETE no ledger, em qualquer
-- circunstância (defesa em profundidade além dos privilégios).
CREATE TRIGGER trg_historico_bloqueia_update
BEFORE UPDATE ON historico_reproducao
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000'
    SET MESSAGE_TEXT = 'Histórico de reprodução é definitivo (RN03) e não pode ser alterado.';
END$$

CREATE TRIGGER trg_historico_bloqueia_delete
BEFORE DELETE ON historico_reproducao
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000'
    SET MESSAGE_TEXT = 'Histórico de reprodução é definitivo (RN03) e não pode ser excluído.';
END$$
DELIMITER ;

-- =====================================================================
-- 7. LOGS_ACESSO  [RF02 - metadados técnicos do "Play" | RN03 imutável]
-- =====================================================================
CREATE TABLE logs_acesso (
    id                  BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    perfil_id             BIGINT UNSIGNED NOT NULL,
    filme_id              BIGINT UNSIGNED NULL,
    episodio_id           BIGINT UNSIGNED NULL,
    endereco_ip           VARCHAR(45)     NOT NULL COMMENT 'Suporta IPv4 e IPv6 em texto',
    tipo_dispositivo       ENUM('SMART_TV','SMARTPHONE','TABLET','WEB','CONSOLE','OUTRO') NOT NULL,
    data_hora_evento       TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT fk_logs_perfil FOREIGN KEY (perfil_id)
        REFERENCES perfis(id) ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_logs_filme FOREIGN KEY (filme_id)
        REFERENCES filmes(id) ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_logs_episodio FOREIGN KEY (episodio_id)
        REFERENCES episodios(id) ON UPDATE CASCADE ON DELETE RESTRICT,

    CONSTRAINT chk_logs_item_unico CHECK (
        (filme_id IS NOT NULL AND episodio_id IS NULL) OR
        (filme_id IS NULL AND episodio_id IS NOT NULL)
    )
) ENGINE=InnoDB;

DELIMITER $$
CREATE TRIGGER trg_logs_acesso_bloqueia_update
BEFORE UPDATE ON logs_acesso
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000'
    SET MESSAGE_TEXT = 'Registros de log de acesso são imutáveis (RN03) e não podem ser alterados.';
END$$

CREATE TRIGGER trg_logs_acesso_bloqueia_delete
BEFORE DELETE ON logs_acesso
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000'
    SET MESSAGE_TEXT = 'Registros de log de acesso são imutáveis (RN03) e não podem ser excluídos.';
END$$
DELIMITER ;

-- =====================================================================
-- 8. TRANSACOES_FINANCEIRAS  [RN01 - controle preventivo de endividamento]
--
-- Ledger de créditos/débitos da conta do assinante. O saldo em
-- assinantes.saldo_conta é só um "cache" denormalizado, sempre mantido
-- consistente por trigger. A aplicação NUNCA deve dar UPDATE direto em
-- saldo_conta (ver 02_seguranca_privilegios.sql) — todo movimento
-- financeiro passa por aqui, e o CHECK em assinantes garante que um
-- débito que deixaria o saldo negativo é rejeitado pelo banco,
-- revertendo também o INSERT nesta tabela (atomicidade da transação).
-- =====================================================================
CREATE TABLE transacoes_financeiras (
    id                  BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    assinante_id          BIGINT UNSIGNED NOT NULL,
    tipo                   ENUM('CREDITO','DEBITO') NOT NULL,
    valor                  DECIMAL(10,2)  NOT NULL COMMENT 'Sempre positivo; sinal vem de "tipo"',
    descricao              VARCHAR(200),
    registrada_em           DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT fk_transacoes_assinante FOREIGN KEY (assinante_id)
        REFERENCES assinantes(id) ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT chk_transacoes_valor_positivo CHECK (valor > 0)
) ENGINE=InnoDB;

DELIMITER $$
CREATE TRIGGER trg_transacoes_aplica_saldo
AFTER INSERT ON transacoes_financeiras
FOR EACH ROW
BEGIN
    IF NEW.tipo = 'CREDITO' THEN
        UPDATE assinantes SET saldo_conta = saldo_conta + NEW.valor WHERE id = NEW.assinante_id;
    ELSE
        -- Se este UPDATE deixar saldo_conta < 0, o CHECK da tabela
        -- assinantes dispara um erro e TODA a transação (incluindo o
        -- INSERT original em transacoes_financeiras) é desfeita.
        UPDATE assinantes SET saldo_conta = saldo_conta - NEW.valor WHERE id = NEW.assinante_id;
    END IF;
END$$

-- Ledger financeiro também é definitivo: correções se fazem com um
-- novo lançamento de reversão ("CREDITO" compensatório), nunca editando
-- o lançamento original (princípio contábil básico, reforça RN01/RN03).
CREATE TRIGGER trg_transacoes_bloqueia_update
BEFORE UPDATE ON transacoes_financeiras
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000'
    SET MESSAGE_TEXT = 'Lançamentos financeiros são definitivos; registre uma transação de reversão.';
END$$

CREATE TRIGGER trg_transacoes_bloqueia_delete
BEFORE DELETE ON transacoes_financeiras
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000'
    SET MESSAGE_TEXT = 'Lançamentos financeiros são definitivos e não podem ser excluídos.';
END$$
DELIMITER ;

-- =====================================================================
-- FIM DO SCRIPT DE CRIAÇÃO
-- Próximos passos: 04_view_lgpd.sql -> 02_seguranca_privilegios.sql ->
-- 05_dados_exemplo.sql (opcional, para teste) -> 03_consultas_bi_e_performance.sql
-- =====================================================================

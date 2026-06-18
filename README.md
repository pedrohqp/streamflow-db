# 🎬 Projeto Integrador: Banco de Dados StreamFlow

Este repositório contém a minha entrega para o **Desafio StreamFlow (Aula 18)**. Projetei essa arquitetura de banco de dados (MySQL) focando em resolver os problemas reais da empresa, garantindo integridade financeira, segurança de logs e performance para o time de Business Intelligence.

Abaixo, detalho como estruturei os scripts e como resolvi cada um dos requisitos exigidos no escopo do projeto.

---

## 📂 Ordem de Execução dos Scripts

Para testar a minha solução no seu ambiente (Workbench, DBeaver, etc.), por favor, execute os arquivos `.sql` exatamente nesta ordem. 


| Ordem | Arquivo | O que ele faz no banco? |
| :--- | :--- | :--- |
| **1º** | `01_ddl_criacao_banco.sql` | Cria o banco, as 10 tabelas, relacionamentos (FKs), restrições (CHECKs) e os Triggers de regra de negócio. |
| **2º** | `04_view_lgpd.sql` | Cria a *View* mascarada para a equipe de marketing (precisa ser rodada antes de dar as permissões). |
| **3º** | `02_seguranca_privilegios.sql` | Cria os usuários institucionais e aplica o RBAC (separando o que a App, o Auditor e o Analista podem ver/fazer). |
| **4º** | `05_dados_exemplo.sql` | *(Opcional)* Insere uma pequena carga de dados fictícios para testar as queries antes de rodar o seu script massivo. |
| **5º** | `03_consultas_bi_e_performance.sql` | Contém as consultas analíticas de BI e a criação dos Índices de Tuning. |
| **6º** | `06_teste_regras_negocio.sql` | Bateria de testes operacionais. **Não rode de uma vez.** Execute comando por comando para ver os bloqueios do banco em ação. |

---

## 🎯 Como resolvi os Cenários do Desafio (Parte 1)

### Cenário A: Contas Compartilhadas (Até 5 perfis)
* **A Solução:** Criei a tabela `assinantes` (dono da conta) e `perfis` vinculada a ela. Para barrar a criação do sexto perfil no banco, não confiei apenas na aplicação: implementei a Trigger `trg_perfis_limite_5` (no `BEFORE INSERT`). Se tentar inserir mais de 5 perfis, o banco lança um erro e aborta.

### Cenário B: A Dor do Catálogo Dinâmico (Perda de Histórico)
* **A Solução:** Padronizei toda a cadeia de chaves estrangeiras com `ON DELETE RESTRICT`. Se um filme tem visualizações, é fisicamente impossível deletá-lo. 
* A remoção do catálogo ocorre via **Soft Delete**: o sistema dá um `UPDATE titulos SET ativo = FALSE`. O conteúdo some da interface do usuário, mas os logs e relatórios da auditoria permanecem intactos.

### Cenário C: Logs Imutáveis e Prevenção de Fraudes
* **A Solução:** Criei a tabela `logs_acesso`. O carimbo de data/hora usa `CURRENT_TIMESTAMP` gerado pelo próprio motor do banco no instante do *Play*, não pela máquina do usuário.
* Apliquei Triggers `BEFORE UPDATE` e `BEFORE DELETE` para bloquear alterações. Além disso, no script de privilégios, o usuário `app_streamflow` só tem permissão de `INSERT` nessa tabela, garantindo imutabilidade total.

---

## 🏗️ Decisões de Arquitetura e Tipagem

Tive que tomar algumas decisões importantes de design para equilibrar as regras de negócio com o desempenho:

* **Sessões vs. Histórico (O Grande Dilema):** O projeto exigia uma tela de "Continuar Assistindo" (que muda o tempo todo) e um log fiscal (que não pode mudar nunca, RN03). Resolvi isso dividindo em duas tabelas:
  1. `sessoes_reproducao` (Mutável): Onde o usuário parou o vídeo.
  2. `historico_reproducao` (Imutável): O "livro-caixa" definitivo. Criei Triggers que escutam os avanços na sessão e gravam automaticamente os incrementos de tempo no histórico.
* **Herança (Filmes vs. Séries):** Usei *Class Table Inheritance*. A tabela `titulos` guarda o que é comum (nome, produtora). `filmes` e `series` herdam dela (relacionamento 1:1), e `episodios` pertence às séries. Isso elimina colunas nulas e mantém a integridade.
* **Tipos de Dados:**
  * **Tempo (`INT UNSIGNED`):** Guardei os tempos em *segundos* inteiros, e não no formato `TIME`. Fazer `SUM()` em campos de tempo quebra facilmente. Com inteiros, as agregações matemáticas do BI ficam rápidas e exatas.
  * **Dinheiro (`DECIMAL(10,2)`):** Cumprindo a RNF02, evitei `FLOAT` para impedir perda de centavos em arredondamentos nos pagamentos e cobranças.

---

## 🚀 Performance e Extração de Dados (Parte 2)

As consultas que você pediu estão mapeadas no script `03_consultas_bi_e_performance.sql`. Aqui destaco os dois pontos críticos da entrega:

### 1. Conformidade LGPD (Marketing vs. Dados Pessoais)
Para impedir que o time de marketing visse e-mails e CPFs (RNF04), construí a View `vw_analistas_engajamento`. Ela consolida informações das tabelas base, calcula a idade dinamicamente usando `TIMESTAMPDIFF` a partir da data de nascimento, e expõe apenas o estado (`UF`), dispositivo e horas totais. O usuário `analista_dados` só tem acesso a essa view.

### 2. O Teste de Fogo (Tuning em Milissegundos)
A consulta da tela inicial ("Continuar Assistindo") sofria de *Full Table Scan* (`type: ALL` no plano de execução) ao procurar onde o perfil parou. 
* **Minha Solução:** Criei um Índice Composto Non-Clustered: `CREATE INDEX idx_sessoes_continuar_assistindo ON sessoes_reproducao (perfil_id, concluido, atualizada_em DESC);`
* **Resultado:** Respeitando a regra do prefixo mais à esquerda, o banco agora vai direto nos ponteiros exatos do usuário, eliminando o *filesort* e reduzindo a busca na base massiva para milissegundos.

/* ============================================================
   Portal B2B - consultas de conferência
   ------------------------------------------------------------
   Produz os números citados no README. Rodar o arquivo inteiro
   de uma vez: não há GO entre os blocos, e a variável do topo
   é usada por várias consultas.

   Cada bloco devolve um resultado. Na ordem:
     1. Volumetria das tabelas de origem
     2. Movimento descartado pela view fato
     3. Efeito do filtro de venda válida na última compra
     4. Situação de compra do cliente
     5. Faturamento e participação do canal, ano a ano
     6. Grão da tabela ponte
     7. Registros incompletos preservados e rotulados
   ============================================================ */

USE PortalB2B;

DECLARE @ref DATE = (SELECT MAX(DAT_EMISSAO) FROM MOVNFS);


/* 1 -----------------------------------------------------------
   Volumetria. Confronte com o resumo impresso pelo gerador:
   qualquer divergência indica linha perdida na carga.
   ------------------------------------------------------------ */
SELECT '1. Volumetria' AS bloco;

SELECT 'CADCID' AS tabela, COUNT(*) AS linhas FROM CADCID
UNION ALL SELECT 'CADGRP', COUNT(*) FROM CADGRP
UNION ALL SELECT 'CADSUP', COUNT(*) FROM CADSUP
UNION ALL SELECT 'CADVEN', COUNT(*) FROM CADVEN
UNION ALL SELECT 'CADCLI', COUNT(*) FROM CADCLI
UNION ALL SELECT 'VINEST', COUNT(*) FROM VINEST
UNION ALL SELECT 'MOVNFS', COUNT(*) FROM MOVNFS
UNION ALL SELECT 'vw_f_Vendas', COUNT(*) FROM vw_f_Vendas;


/* 2 -----------------------------------------------------------
   Quanto do movimento bruto a view fato descarta, e por quê.
   As causas se sobrepõem: uma nota pode ser cancelada E de tipo
   diferente de venda. Por isso o total descartado é menor que a
   soma das causas.
   ------------------------------------------------------------ */
SELECT '2. Movimento descartado' AS bloco;

SELECT
    COUNT(*) AS total_movimento,
    SUM(CASE WHEN DAT_EMISSAO IS NULL THEN 1 ELSE 0 END)          AS sem_data,
    SUM(CASE WHEN DAT_CANCELAMENTO IS NOT NULL THEN 1 ELSE 0 END) AS canceladas,
    SUM(CASE WHEN TIP_SAIDA <> 'V' THEN 1 ELSE 0 END)             AS nao_venda,
    SUM(CASE WHEN DAT_EMISSAO IS NOT NULL
                  AND DAT_CANCELAMENTO IS NULL
                  AND TIP_SAIDA = 'V' THEN 1 ELSE 0 END)          AS venda_valida,
    CAST(100.0 * SUM(CASE WHEN DAT_EMISSAO IS NULL
                             OR DAT_CANCELAMENTO IS NOT NULL
                             OR TIP_SAIDA <> 'V' THEN 1 ELSE 0 END)
         / COUNT(*) AS DECIMAL(5,2))                              AS pct_descartado
FROM MOVNFS;

SELECT TIP_SAIDA, COUNT(*) AS qtd FROM MOVNFS GROUP BY TIP_SAIDA;


/* 3 -----------------------------------------------------------
   O achado central sobre qualidade de dado.
   Compara a última compra calculada sem os filtros de venda
   válida contra a calculada com eles. A diferença é a quantidade
   de clientes que seriam classificados na fila errada do plano
   de ação.
   ------------------------------------------------------------ */
SELECT '3. Efeito do filtro na ultima compra' AS bloco;

WITH SemFiltro AS (
    SELECT COD_CLIENTE, MAX(CAST(DAT_EMISSAO AS DATE)) AS data_max
    FROM MOVNFS
    WHERE DAT_EMISSAO IS NOT NULL
    GROUP BY COD_CLIENTE
),
ComFiltro AS (
    SELECT COD_CLIENTE, MAX(CAST(DAT_EMISSAO AS DATE)) AS data_max
    FROM MOVNFS
    WHERE DAT_EMISSAO IS NOT NULL
      AND DAT_CANCELAMENTO IS NULL
      AND TIP_SAIDA = 'V'
    GROUP BY COD_CLIENTE
)
SELECT
    COUNT(*) AS clientes_com_movimento,
    SUM(CASE WHEN c.data_max IS NULL OR s.data_max <> c.data_max
             THEN 1 ELSE 0 END) AS ultima_compra_difere,
    SUM(CASE WHEN c.data_max IS NULL THEN 1 ELSE 0 END) AS sem_nenhuma_venda_valida,
    AVG(CASE WHEN c.data_max IS NOT NULL AND s.data_max <> c.data_max
             THEN DATEDIFF(DAY, c.data_max, s.data_max) END) AS atraso_medio_dias,
    MAX(CASE WHEN c.data_max IS NOT NULL AND s.data_max <> c.data_max
             THEN DATEDIFF(DAY, c.data_max, s.data_max) END) AS atraso_maximo_dias
FROM SemFiltro s
LEFT JOIN ComFiltro c ON c.COD_CLIENTE = s.COD_CLIENTE;


/* 4 -----------------------------------------------------------
   As três situações que a view de última compra permite separar,
   e que a view fato sozinha confundiria.
   ------------------------------------------------------------ */
SELECT '4. Situacao de compra do cliente' AS bloco;

SELECT
    COUNT(*) AS total_clientes,
    SUM(CASE WHEN uc.[Flag Comprou Geral] = 0
             THEN 1 ELSE 0 END) AS nunca_comprou,
    SUM(CASE WHEN uc.[Flag Comprou Geral] = 1 AND f.cod IS NULL
             THEN 1 ELSE 0 END) AS comprou_so_fora_da_janela,
    SUM(CASE WHEN f.cod IS NOT NULL
             THEN 1 ELSE 0 END) AS ativo_na_janela,
    SUM(CASE WHEN uc.[Flag Comprou PORTALB2B] = 1
             THEN 1 ELSE 0 END) AS ja_comprou_pelo_canal
FROM vw_d_UltimaCompraCliente uc
LEFT JOIN (SELECT DISTINCT [Codigo Cliente] AS cod FROM vw_f_Vendas) f
       ON f.cod = uc.[Codigo Cliente];


/* 5 -----------------------------------------------------------
   Faturamento e participação do canal nos dois anos da janela.
   ------------------------------------------------------------ */
SELECT '5. Faturamento ano a ano' AS bloco;

SELECT
    CASE WHEN v.[Data Emissao] > DATEADD(YEAR, -1, @ref)
         THEN 'Ano atual' ELSE 'Ano anterior' END AS periodo,
    COUNT(*) AS notas,
    CAST(SUM(v.[Valor Venda]) AS DECIMAL(18,2)) AS faturamento_total,
    CAST(SUM(CASE WHEN v.[Flag Venda PORTALB2B] = 1
                  THEN v.[Valor Venda] ELSE 0 END) AS DECIMAL(18,2)) AS faturamento_canal,
    CAST(100.0 * SUM(CASE WHEN v.[Flag Venda PORTALB2B] = 1
                          THEN v.[Valor Venda] ELSE 0 END)
         / SUM(v.[Valor Venda]) AS DECIMAL(5,2)) AS pct_canal,
    COUNT(DISTINCT CASE WHEN v.[Flag Venda PORTALB2B] = 1
                        THEN v.[Codigo Cliente] END) AS clientes_no_canal
FROM vw_f_Vendas v
GROUP BY CASE WHEN v.[Data Emissao] > DATEADD(YEAR, -1, @ref)
              THEN 'Ano atual' ELSE 'Ano anterior' END;


/* 6 -----------------------------------------------------------
   Confirma que a tabela ponte não tem grão de cliente, e
   quantifica o excedente que exige DISTINCTCOUNT no modelo.
   ------------------------------------------------------------ */
SELECT '6. Grao da tabela ponte' AS bloco;

SELECT
    COUNT(*)                              AS linhas_na_view,
    COUNT(DISTINCT [Codigo Cliente])      AS clientes_distintos,
    COUNT(*) - COUNT(DISTINCT [Codigo Cliente]) AS excedente,
    SUM(CASE WHEN [Codigo Estabelecimento] IS NULL
             THEN 1 ELSE 0 END)           AS sem_vinculo
FROM vw_d_ClienteVendedorEstabelecimento;


/* 7 -----------------------------------------------------------
   Registros incompletos que foram rotulados em vez de removidos.
   Cada número justifica um LEFT JOIN ou um ELSE nas views.
   ------------------------------------------------------------ */
SELECT '7. Registros incompletos preservados' AS bloco;

SELECT
    (SELECT COUNT(*) FROM vw_d_Clientes
      WHERE [Grupo Cliente] = 'Sem grupo')            AS clientes_sem_grupo,
    (SELECT COUNT(*) FROM vw_d_Clientes
      WHERE Cidade = 'Não informado')                 AS clientes_cidade_orfa,
    (SELECT COUNT(*) FROM vw_d_Clientes
      WHERE [Status Cliente] = 'Não informado')       AS clientes_status_nulo,
    (SELECT COUNT(*) FROM vw_d_Clientes
      WHERE [Status Cliente] = 'Bloqueado')           AS clientes_bloqueados,
    (SELECT COUNT(*) FROM vw_d_Vendedores
      WHERE [Nome Supervisor] = 'Sem supervisor')     AS vendedores_sem_supervisor,
    (SELECT COUNT(*) FROM vw_f_Vendas
      WHERE [Layout Pedido] = 'Sem layout cadastrado') AS notas_sem_layout;


/* 8 -----------------------------------------------------------
   Limitação conhecida da base sintética: nenhum cliente
   bloqueado possui histórico de compra. Na realidade, o bloqueio
   costuma vir depois de um período comprando. Documentado no README.
   ------------------------------------------------------------ */
SELECT '8. Limitacao conhecida' AS bloco;

SELECT
    c.[Status Cliente],
    COUNT(*) AS clientes,
    SUM(uc.[Flag Comprou Geral]) AS ja_compraram
FROM vw_d_Clientes c
JOIN vw_d_UltimaCompraCliente uc
     ON uc.[Codigo Cliente] = c.[Codigo Cliente]
GROUP BY c.[Status Cliente];
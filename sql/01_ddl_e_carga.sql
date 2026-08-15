/* ============================================================
   Portal B2B - tabelas de origem (ERP ficticio)
   ------------------------------------------------------------
   Estas tabelas imitam a origem: guardam codigos sem descricao,
   datas com hora, valores em FLOAT, campos nulos e movimentos
   que nao sao venda.

   NADA aqui vem tratado. Traducao de codigo para descricao,
   derivacao de canal, flags, filtros de tipo e cancelamento e
   janela movel sao responsabilidade das views.

   Os dois arquivos do portal (portal_matriz.xlsx e
   portal_filial.xlsx) nao entram no banco: sao lidos direto
   pelo Power Query.

   Ajuste os caminhos do BULK INSERT antes de rodar.
   ============================================================ */

IF DB_ID('PortalB2B') IS NULL
    CREATE DATABASE PortalB2B;
GO

USE PortalB2B;
GO

DROP TABLE IF EXISTS dbo.MOVNFS;
DROP TABLE IF EXISTS dbo.VINEST;
DROP TABLE IF EXISTS dbo.CADCLI;
DROP TABLE IF EXISTS dbo.CADVEN;
DROP TABLE IF EXISTS dbo.CADSUP;
DROP TABLE IF EXISTS dbo.CADCID;
DROP TABLE IF EXISTS dbo.CADGRP;
GO

/* ------------------------------------------------------------
   CADCID - cidades
   Chave composta por codigo e estado. O mesmo COD_CIDADE se
   repete entre estados diferentes, entao o join precisa das
   duas colunas.
   ------------------------------------------------------------ */
CREATE TABLE dbo.CADCID (
    COD_CIDADE  INT          NOT NULL,
    COD_ESTADO  CHAR(2)      NOT NULL,
    DES_CIDADE  VARCHAR(100)  NOT NULL,
    CONSTRAINT pk_cadcid PRIMARY KEY (COD_CIDADE, COD_ESTADO)
);
GO

/* ------------------------------------------------------------
   CADGRP - grupos de cliente
   ------------------------------------------------------------ */
CREATE TABLE dbo.CADGRP (
    COD_GRPCLI  INT          NOT NULL,
    DES_GRPCLI  VARCHAR(100)  NOT NULL,
    CONSTRAINT pk_cadgrp PRIMARY KEY (COD_GRPCLI)
);
GO

/* ------------------------------------------------------------
   CADSUP - supervisores
   ------------------------------------------------------------ */
CREATE TABLE dbo.CADSUP (
    COD_SUPERVISOR  INT          NOT NULL,
    NOM_COMPLETO    VARCHAR(100)  NOT NULL,
    CONSTRAINT pk_cadsup PRIMARY KEY (COD_SUPERVISOR)
);
GO

/* ------------------------------------------------------------
   CADVEN - vendedores
   BLOQUEADO e codigo 0/1 sem descricao.
   COD_SUPERVISOR aceita nulo: nem todo vendedor tem supervisor.
   ------------------------------------------------------------ */
CREATE TABLE dbo.CADVEN (
    COD_VENDEDOR    INT          NOT NULL,
    NOM_GUERRA      VARCHAR(60)  NOT NULL,
    BLOQUEADO       TINYINT      NULL,
    COD_SUPERVISOR  INT          NULL,
    CONSTRAINT pk_cadven PRIMARY KEY (COD_VENDEDOR)
);
GO

/* ------------------------------------------------------------
   CADCLI - cadastro de clientes
   Guarda codigos, nao descricoes. BLOQUEADO pode ser nulo.
   COD_CIDADE pode apontar para cidade inexistente.
   DAT_CADASTRO e DATETIME, com hora.
   ------------------------------------------------------------ */
CREATE TABLE dbo.CADCLI (
    COD_CLI       INT           NOT NULL,
    CGC_CPF       VARCHAR(14)   NOT NULL,
    RAZ_SOCIAL    VARCHAR(120)  NOT NULL,
    NOM_FANTASIA  VARCHAR(100)   NULL,
    COD_CIDADE    INT           NULL,
    COD_ESTADO    CHAR(2)       NULL,
    BLOQUEADO     TINYINT       NULL,
    DAT_CADASTRO  DATETIME      NOT NULL,
    COD_GRPCLI    INT           NULL,
    CONSTRAINT pk_cadcli PRIMARY KEY (COD_CLI)
);
GO

/* ------------------------------------------------------------
   VINEST - vinculo cliente / estabelecimento / vendedor
   Nem todo cliente tem registro aqui.
   ------------------------------------------------------------ */
CREATE TABLE dbo.VINEST (
    COD_CLIENT    INT      NOT NULL,
    COD_ESTABE    TINYINT  NOT NULL,
    COD_VENDEDOR  INT      NOT NULL,
    CONSTRAINT pk_vinest PRIMARY KEY (COD_CLIENT, COD_ESTABE)
);
GO

/* ------------------------------------------------------------
   MOVNFS - movimento de notas fiscais
   Nao tem CNPJ: ele so existe em CADCLI, por isso a view de
   fato precisa do INNER JOIN.
   TIP_SAIDA: V venda, D devolucao, B bonificacao, T transferencia.
   DAT_EMISSAO pode ser nula. DAT_CANCELAMENTO preenchida indica
   nota cancelada. VLR_TOTALNOTA e FLOAT, nao DECIMAL.
   ------------------------------------------------------------ */
CREATE TABLE dbo.MOVNFS (
    NUM_NOTA          INT          NOT NULL,
    DAT_EMISSAO       DATETIME     NULL,
    COD_CLIENTE       INT          NOT NULL,
    COD_ESTABE        TINYINT      NOT NULL,
    DES_LAYOUTPDE     VARCHAR(100)  NULL,
    VLR_TOTALNOTA     FLOAT        NOT NULL,
    COD_VENDEDOR      INT          NOT NULL,
    TIP_SAIDA         CHAR(1)      NOT NULL,
    DAT_CANCELAMENTO  DATETIME     NULL,
    CONSTRAINT pk_movnfs PRIMARY KEY (NUM_NOTA)
);
GO

/* ============================================================
   CARGA
   Ajuste o caminho para a pasta data/ do repositorio.
   A ordem nao importa: nao ha chave estrangeira, de proposito,
   porque a origem de um ERP raramente as tem.
   ============================================================ */

BULK INSERT dbo.CADCID
FROM 'C:\Projetos_Portfolio\portal-b2b-analise-canal-digital\data\CADCID.csv'
WITH (FORMAT='CSV', FIRSTROW=2, CODEPAGE='65001',
      FIELDTERMINATOR=',', ROWTERMINATOR='0x0a', TABLOCK);
GO

BULK INSERT dbo.CADGRP
FROM 'C:\Projetos_Portfolio\portal-b2b-analise-canal-digital\data\CADGRP.csv'
WITH (FORMAT='CSV', FIRSTROW=2, CODEPAGE='65001',
      FIELDTERMINATOR=',', ROWTERMINATOR='0x0a', TABLOCK);
GO

BULK INSERT dbo.CADSUP
FROM 'C:\Projetos_Portfolio\portal-b2b-analise-canal-digital\data\CADSUP.csv'
WITH (FORMAT='CSV', FIRSTROW=2, CODEPAGE='65001',
      FIELDTERMINATOR=',', ROWTERMINATOR='0x0a', TABLOCK);
GO

BULK INSERT dbo.CADVEN
FROM 'C:\Projetos_Portfolio\portal-b2b-analise-canal-digital\data\CADVEN.csv'
WITH (FORMAT='CSV', FIRSTROW=2, CODEPAGE='65001',
      FIELDTERMINATOR=',', ROWTERMINATOR='0x0a', TABLOCK);
GO

BULK INSERT dbo.CADCLI
FROM 'C:\Projetos_Portfolio\portal-b2b-analise-canal-digital\data\CADCLI.csv'
WITH (FORMAT='CSV', FIRSTROW=2, CODEPAGE='65001',
      FIELDTERMINATOR=',', ROWTERMINATOR='0x0a', TABLOCK);
GO

BULK INSERT dbo.VINEST
FROM 'C:\Projetos_Portfolio\portal-b2b-analise-canal-digital\data\VINEST.csv'
WITH (FORMAT='CSV', FIRSTROW=2, CODEPAGE='65001',
      FIELDTERMINATOR=',', ROWTERMINATOR='0x0a', TABLOCK);
GO

BULK INSERT dbo.MOVNFS
FROM 'C:\Projetos_Portfolio\portal-b2b-analise-canal-digital\data\MOVNFS.csv'
WITH (FORMAT='CSV', FIRSTROW=2, CODEPAGE='65001',
      FIELDTERMINATOR=',', ROWTERMINATOR='0x0a', TABLOCK);
GO

/* ============================================================
   INDICES
   Um indice permite localizar linhas sem varrer a tabela toda.
   Criados depois da carga, que fica mais rapida assim.
   ============================================================ */
CREATE INDEX ix_movnfs_data     ON dbo.MOVNFS (DAT_EMISSAO);
CREATE INDEX ix_movnfs_cliente  ON dbo.MOVNFS (COD_CLIENTE, DAT_EMISSAO);
CREATE INDEX ix_cadcli_cgc      ON dbo.CADCLI (CGC_CPF);
GO

/* ============================================================
   CONFERENCIA
   Compare com o resumo impresso pelo gerador.
   ============================================================ */
SELECT 'CADCID' AS tabela, COUNT(*) AS linhas FROM dbo.CADCID
UNION ALL SELECT 'CADGRP', COUNT(*) FROM dbo.CADGRP
UNION ALL SELECT 'CADSUP', COUNT(*) FROM dbo.CADSUP
UNION ALL SELECT 'CADVEN', COUNT(*) FROM dbo.CADVEN
UNION ALL SELECT 'CADCLI', COUNT(*) FROM dbo.CADCLI
UNION ALL SELECT 'VINEST', COUNT(*) FROM dbo.VINEST
UNION ALL SELECT 'MOVNFS', COUNT(*) FROM dbo.MOVNFS;

/* Todos os CNPJ devem ter 14 caracteres. */
SELECT LEN(CGC_CPF) AS tamanho, COUNT(*) AS qtd
FROM dbo.CADCLI GROUP BY LEN(CGC_CPF);

/* O ruido que as views precisam tratar. */
SELECT
    COUNT(*)                                                      AS total_notas,
    SUM(CASE WHEN DAT_EMISSAO IS NULL THEN 1 ELSE 0 END)          AS sem_data,
    SUM(CASE WHEN DAT_CANCELAMENTO IS NOT NULL THEN 1 ELSE 0 END) AS canceladas,
    SUM(CASE WHEN TIP_SAIDA <> 'V' THEN 1 ELSE 0 END)             AS nao_venda,
    SUM(CASE WHEN DAT_EMISSAO IS NOT NULL
                  AND TIP_SAIDA = 'V'
                  AND DAT_CANCELAMENTO IS NULL
             THEN 1 ELSE 0 END)                                   AS validas
FROM dbo.MOVNFS;

SELECT TIP_SAIDA, COUNT(*) AS qtd FROM dbo.MOVNFS GROUP BY TIP_SAIDA;

/* Registros que dependem de LEFT JOIN para nao sumir do resultado. */
SELECT
    (SELECT COUNT(*) FROM dbo.CADCLI WHERE COD_GRPCLI IS NULL)  AS sem_grupo,
    (SELECT COUNT(*) FROM dbo.CADCLI WHERE BLOQUEADO IS NULL)   AS status_nulo,
    (SELECT COUNT(*) FROM dbo.CADCLI c
      WHERE NOT EXISTS (SELECT 1 FROM dbo.CADCID ci
                         WHERE ci.COD_CIDADE = c.COD_CIDADE
                           AND ci.COD_ESTADO = c.COD_ESTADO))   AS cidade_orfa,
    (SELECT COUNT(*) FROM dbo.CADCLI c
      WHERE NOT EXISTS (SELECT 1 FROM dbo.VINEST v
                         WHERE v.COD_CLIENT = c.COD_CLI))       AS sem_vinculo,
    (SELECT COUNT(*) FROM dbo.CADVEN WHERE COD_SUPERVISOR IS NULL) AS vend_sem_sup;
GO
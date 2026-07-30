CREATE OR ALTER VIEW vw_d_UltimaCompraCliente AS

WITH Ultima_Compra_Geral AS (
	SELECT
		nf.COD_CLIENTE AS [Codigo Cliente],
		nf.NUM_NOTA AS Nota,
		CAST(nf.DAT_EMISSAO AS DATE) AS [Data Emissao],
		nf.COD_ESTABE AS [Codigo Estabelecimento],

		ROW_NUMBER() OVER(
			PARTITION BY
				nf.COD_CLIENTE
			ORDER BY
				nf.DAT_EMISSAO DESC,
				nf.NUM_NOTA DESC
		) AS rn

	FROM
		MOVNFS nf
	WHERE
		nf.DAT_EMISSAO IS NOT NULL
		AND nf.DAT_CANCELAMENTO IS NULL
		AND nf.TIP_SAIDA = 'V'

	
),

Ultima_Compra_PORTALB2B AS (
	SELECT
		nf.COD_CLIENTE AS [Codigo Cliente],
		nf.NUM_NOTA AS Nota,
		CAST(nf.DAT_EMISSAO AS DATE) AS [Data Emissao],
		nf.COD_ESTABE AS [Codigo Estabelecimento],

		ROW_NUMBER() OVER(
			PARTITION BY
				nf.COD_CLIENTE
			ORDER BY
				nf.DAT_EMISSAO DESC,
				nf.NUM_NOTA DESC
		) AS rn

	FROM
		MOVNFS nf
	WHERE
		nf.DAT_EMISSAO IS NOT NULL
		AND nf.DAT_CANCELAMENTO IS NULL
		AND nf.TIP_SAIDA = 'V'
		AND nf.DES_LAYOUTPDE = 'PORTALB2B'


)

SELECT
	c.COD_CLI AS [Codigo Cliente],
	c.CGC_CPF AS CNPJ,
	ug.[Data Emissao] AS [Data Ultima Compra Geral],
	up.[Data Emissao] AS [Data Ultima Compra PORTALB2B],
	ug.Nota AS [Numero Ultima Nota Geral],
	up.Nota AS [Numero Ultima Nota PORTALB2B],
	ug.[Codigo Estabelecimento] AS [Codigo Estabelecimento Ultima Compra Geral],

	CASE
		WHEN ug.[Codigo Estabelecimento] = 1 THEN 'MATRIZ'
		WHEN ug.[Codigo Estabelecimento] = 2 THEN 'FILIAL'
		WHEN ug.[Codigo Estabelecimento] IS NULL THEN 'SEM COMPRA'
		ELSE 'Estabelecimento Não Identificado'
	END AS [Estabelecimento Ultima Compra Geral],

	up.[Codigo Estabelecimento] AS [Codigo Estabelecimento Ultima Compra PORTALB2B],

	CASE
		WHEN up.[Codigo Estabelecimento] = 1 THEN 'MATRIZ'
		WHEN up.[Codigo Estabelecimento] = 2 THEN 'FILIAL'
		WHEN up.[Codigo Estabelecimento] IS NULL THEN 'SEM COMPRA PORTALB2B'
		ELSE 'Estabelecimento Não Identificado'
	END AS [Estabelecimento Ultima Compra PORTALB2B],

	CASE
		WHEN ug.[Data Emissao] IS NOT NULL THEN 1
		ELSE 0
	END AS [Flag Comprou Geral],

	CASE
		WHEN up.[Data Emissao] IS NOT NULL THEN 1
		ELSE 0
	END AS [Flag Comprou PORTALB2B]

FROM
	CADCLI c
LEFT JOIN Ultima_Compra_Geral ug
	ON ug.[Codigo Cliente] = c.COD_CLI
	AND ug.rn = 1
LEFT JOIN Ultima_Compra_PORTALB2B up
	ON up.[Codigo Cliente] = c.COD_CLI
	AND up.rn = 1
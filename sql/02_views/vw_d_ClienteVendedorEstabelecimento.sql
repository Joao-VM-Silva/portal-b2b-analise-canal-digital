CREATE OR ALTER VIEW vw_d_ClienteVendedorEstabelecimento AS

SELECT
	c.COD_CLI AS [Codigo Cliente],
	c.CGC_CPF AS CNPJ,
	vn.COD_ESTABE AS [Codigo Estabelecimento],

	CASE
		WHEN vn.COD_ESTABE = 1 THEN 'MATRIZ'
		WHEN vn.COD_ESTABE = 2 THEN 'FILIAL'
		ELSE 'Sem estabelecimento vinculado'
	END AS Estabelecimento,
	
	vn.COD_VENDEDOR AS [Codigo Vendedor]

FROM
	CADCLI c
LEFT JOIN VINEST vn
	ON vn.COD_CLIENT = c.COD_CLI
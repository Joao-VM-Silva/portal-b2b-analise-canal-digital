CREATE OR ALTER VIEW vw_d_Clientes AS

SELECT
	cl.COD_CLI AS [Codigo Cliente],
	cl.CGC_CPF AS CNPJ,
	cl.RAZ_SOCIAL AS [Razao Social],
	cl.NOM_FANTASIA AS [Nome Fantasia],
	ISNULL(cp.DES_GRPCLI, 'SEM GRUPO') AS [Grupo Cliente],
	ISNULL(ci.DES_CIDADE, 'Não informado') AS Cidade,
	cl.COD_ESTADO AS UF,
	cl.BLOQUEADO AS [Flag Bloqueado],

	CASE
		WHEN cl.BLOQUEADO = 1 THEN 'Bloqueado'
		WHEN cl.BLOQUEADO = 0 THEN 'Ativo'
		ELSE 'Não Informado'
	END AS [Status Cliente],

	CAST(cl.DAT_CADASTRO AS DATE) AS [Data Cadastro]

FROM
	CADCLI cl
LEFT JOIN CADCID ci
	ON cl.COD_CIDADE = ci.COD_CIDADE
	AND cl.COD_ESTADO = ci.COD_ESTADO
LEFT JOIN CADGRP cp
	ON cl.COD_GRPCLI = cp.COD_GRPCLI
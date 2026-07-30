CREATE OR ALTER VIEW vw_d_Vendedores AS

SELECT
	cv.COD_VENDEDOR AS [Codigo Vendedor],
	cv.NOM_GUERRA AS [Nome Vendedor],
	cv.BLOQUEADO AS [Flag Bloqueado],

	CASE
		WHEN cv.BLOQUEADO = 1 THEN 'Bloqueado'
		WHEN cv.BLOQUEADO = 0 THEN 'Ativo'
		ELSE 'Não informado'
	END AS [Status Vendedor],

	sp.COD_SUPERVISOR AS [Codigo Supervisor],
	ISNULL(sp.NOM_COMPLETO, 'Sem Supervisor') AS [Nome Supervisor]

FROM
	CADVEN cv
LEFT JOIN CADSUP sp
	ON cv.COD_SUPERVISOR = sp.COD_SUPERVISOR
/* ------------------------------------------------------------
   vw_d_Vendedores
   Dimensão de vendedores. Grão: uma linha por vendedor.
 
   Achata a hierarquia comercial, trazendo o supervisor na mesma
   linha do vendedor para simplificar o modelo. Vendedores
   bloqueados permanecem na base: eles respondem por vendas
   históricas que ainda aparecem na view fato.
   ------------------------------------------------------------ */


CREATE OR ALTER VIEW vw_d_Vendedores AS

SELECT
	cv.COD_VENDEDOR AS [Codigo Vendedor],
	cv.NOM_GUERRA AS [Nome Vendedor],
	cv.BLOQUEADO AS [Flag Vendedor Bloqueado],

	CASE
		WHEN cv.BLOQUEADO = 1 THEN 'Bloqueado'
		WHEN cv.BLOQUEADO = 0 THEN 'Ativo'
		ELSE 'Não informado'
	END AS [Status Vendedor],

	cv.COD_SUPERVISOR AS [Codigo Supervisor],
	ISNULL(sp.NOM_COMPLETO, 'Sem supervisor') AS [Nome Supervisor]

FROM
	CADVEN cv

-- LEFT JOIN: parte dos vendedores não tem supervisor cadastrado.
-- Com INNER JOIN eles sumiriam, e as vendas atribuídas a eles
-- ficariam sem responsável na análise.
LEFT JOIN CADSUP sp
	ON cv.COD_SUPERVISOR = sp.COD_SUPERVISOR
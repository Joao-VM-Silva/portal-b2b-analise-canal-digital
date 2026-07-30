/* ------------------------------------------------------------
   vw_d_Clientes
   Dimensão de clientes. Grão: uma linha por cliente cadastrado.
 
   Traduz os códigos do cadastro de origem para descrições
   legíveis e mantém todos os clientes, inclusive bloqueados e
   sem classificação, para que o total reconcilie com o sistema
   de origem. Registros incompletos são rotulados, nunca
   descartados.
   ------------------------------------------------------------ */


CREATE OR ALTER VIEW vw_d_Clientes AS

SELECT
	cl.COD_CLI AS [Codigo Cliente],
	cl.CGC_CPF AS CNPJ,
	cl.RAZ_SOCIAL AS [Razao Social],
	cl.NOM_FANTASIA AS [Nome Fantasia],

	-- ausência de classificação é rotulada: o cliente existe e fatura,
	-- apenas não foi enquadrado em um grupo comercial
	ISNULL(cp.DES_GRPCLI, 'Sem grupo') AS [Grupo Cliente],
	ISNULL(ci.DES_CIDADE, 'Não informado') AS Cidade,
	cl.COD_ESTADO AS UF,
	cl.BLOQUEADO AS [Flag Bloqueado],

	-- o ELSE cobre o cadastro sem status preenchido, que existe
	-- na origem e não pode virar branco no modelo
	CASE
		WHEN cl.BLOQUEADO = 1 THEN 'Bloqueado'
		WHEN cl.BLOQUEADO = 0 THEN 'Ativo'
		ELSE 'Não informado'
	END AS [Status Cliente],

	CAST(cl.DAT_CADASTRO AS DATE) AS [Data Cadastro]

FROM
	CADCLI cl

-- LEFT JOIN nos dois casos: há cadastro apontando para cidade
-- inexistente e cadastro sem grupo. Com INNER JOIN esses clientes
-- desapareceriam da base sem aviso.
LEFT JOIN CADCID ci
	ON cl.COD_CIDADE = ci.COD_CIDADE
	AND cl.COD_ESTADO = ci.COD_ESTADO		-- chave composta: o código de cidade se repete entre estados
LEFT JOIN CADGRP cp
	ON cl.COD_GRPCLI = cp.COD_GRPCLI
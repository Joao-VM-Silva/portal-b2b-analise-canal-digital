/* ------------------------------------------------------------
   vw_d_UltimaCompraCliente
   Situação de compra do cliente. Grão: uma linha por cliente.
 
   POR QUE ELA EXISTE, SE JÁ HÁ UMA VIEW FATO
   A view fato expõe uma janela de 24 meses, adequada para
   análise temporal. Esta lê o histórico completo, sem filtro
   de data, e é o que permite separar três situações que a
   fato sozinha confunde:
 
     nunca comprou            -> prospecção
     comprou fora da janela   -> reativação
     comprou dentro da janela -> cliente ativo
 
   Sem essa distinção, um cliente antigo seria abordado como
   lead frio, e a ação comercial iria para a fila errada.
 
   FILTROS
   As duas CTEs aplicam os mesmos critérios de venda válida da
   view fato. Sem eles, uma devolução ou nota cancelada passaria
   a valer como "última compra", adiantando a data e mudando a
   classificação do cliente. O impacto foi medido e está no README.
 
   NULO É RESPOSTA
   Data de última compra nula não é dado faltante: significa que
   a compra nunca aconteceu. Por isso permanece nula, e a
   informação é exposta nas colunas de flag.
   ------------------------------------------------------------ */


CREATE OR ALTER VIEW vw_d_UltimaCompraCliente AS

/* Última venda válida do cliente em qualquer canal. */
WITH Ultima_Compra_Geral AS (
	SELECT
		nf.COD_CLIENTE AS [Codigo Cliente],
		nf.NUM_NOTA AS Nota,
		CAST(nf.DAT_EMISSAO AS DATE) AS [Data Emissao],
		nf.COD_ESTABE AS [Codigo Estabelecimento],

		-- ranqueia as notas de cada cliente da mais recente para a
		-- mais antiga; o número da nota desempata quando há mais de
		-- uma emissão na mesma data
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
		nf.DAT_EMISSAO IS NOT NULL			-- sem data não há como ordenar no tempo
		AND nf.DAT_CANCELAMENTO IS NULL		-- nota cancelada não representa compra	
		AND nf.TIP_SAIDA = 'V'				-- exclui devolução, bonificação e transferência

	
),

/* Mesma lógica, restrita ao canal digital. */
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
		AND nf.DES_LAYOUTPDE = 'PORTALB2B'		-- identifica a venda originada no canal


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
		WHEN ug.[Codigo Estabelecimento] = 1 THEN 'Matriz'
		WHEN ug.[Codigo Estabelecimento] = 2 THEN 'Filial'
		WHEN ug.[Codigo Estabelecimento] IS NULL THEN 'Sem compra'
		ELSE 'Estabelecimento não identificado'
	END AS [Estabelecimento Ultima Compra Geral],

	up.[Codigo Estabelecimento] AS [Codigo Estabelecimento Ultima Compra PORTALB2B],

	CASE
		WHEN up.[Codigo Estabelecimento] = 1 THEN 'Matriz'
		WHEN up.[Codigo Estabelecimento] = 2 THEN 'Filial'
		WHEN up.[Codigo Estabelecimento] IS NULL THEN 'Sem compra no portal'
		ELSE 'Estabelecimento não identificado'
	END AS [Estabelecimento Ultima Compra PORTALB2B],

	-- flags derivadas da presença da data: entregam a resposta pronta
	-- para o modelo, sem exigir tratamento de nulo no Power BI
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

-- LEFT JOIN com rn = 1: traz apenas a nota mais recente de cada
-- cliente e preserva quem nunca comprou, que é exatamente o
-- público-alvo da prospecção
LEFT JOIN Ultima_Compra_Geral ug
	ON ug.[Codigo Cliente] = c.COD_CLI
	AND ug.rn = 1
LEFT JOIN Ultima_Compra_PORTALB2B up
	ON up.[Codigo Cliente] = c.COD_CLI
	AND up.rn = 1
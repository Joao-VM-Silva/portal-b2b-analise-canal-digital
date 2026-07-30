/* ------------------------------------------------------------
   vw_f_Vendas
   Tabela fato de vendas. Grão: uma linha por nota fiscal.
 
   JANELA
   Expõe os últimos 24 meses, o que viabiliza a comparação de um
   ano contra o outro e a leitura da evolução do canal digital.
   A janela é ancorada na maior data da própria tabela, e não em
   GETDATE(): com uma base estática, GETDATE() faria a janela
   deslizar para fora dos dados e o dashboard esvaziaria sozinho
   com o passar do tempo.
 
   NOTAS DESCARTADAS
   Sai do resultado tudo o que não é venda efetiva: nota sem data
   de emissão, nota cancelada e movimento de tipo diferente de
   venda. É uma parcela relevante do movimento bruto, e o número
   está medido no README.
 
   CANAL DE VENDA
   A origem não tem uma coluna de canal. O canal é derivado aqui,
   a partir do layout de pedido, e exposto de três formas: o
   layout original, a descrição do canal e uma flag numérica que
   simplifica as medidas em DAX.
   ------------------------------------------------------------ */


CREATE OR ALTER VIEW vw_f_Vendas AS

SELECT
	nf.NUM_NOTA AS Nota,
	CAST(nf.DAT_EMISSAO AS DATE) AS [Data Emissao], -- remove a hora: a análise é diária
	nf.COD_CLIENTE AS [Codigo Cliente],
	c.CGC_CPF AS CNPJ,
	nf.COD_ESTABE AS [Codigo Estabelecimento],

	CASE
		WHEN nf.COD_ESTABE = 1 THEN 'Matriz'
		WHEN nf.COD_ESTABE = 2 THEN 'Filial'
		ELSE 'Sem estabelecimento vinculado'
	END AS Estabelecimento,

	ISNULL(nf.DES_LAYOUTPDE, 'Sem layout cadastrado') AS [Layout Pedido],

	-- canal derivado do layout: é o único vestígio, na origem, de
	-- que o pedido nasceu no portal
	CASE
		WHEN nf.DES_LAYOUTPDE = 'PORTALB2B' THEN 'Portal B2B'
		ELSE 'Outros'
	END AS [Canal de Venda],

	CASE
		WHEN nf.DES_LAYOUTPDE = 'PORTALB2B' THEN 1
		ELSE 0
	END AS [Flag Venda PORTALB2B],

	CAST(nf.VLR_TOTALNOTA AS DECIMAL(18,2)) AS [Valor Venda], -- origem é FLOAT, impróprio para valor monetário
	nf.COD_VENDEDOR AS [Codigo Vendedor]

FROM
	MOVNFS nf

-- INNER JOIN, e não LEFT: o CNPJ só existe no cadastro de
-- clientes, e nota sem cliente identificado não é analisável.
-- É a única junção do projeto em que a ausência invalida a linha.
INNER JOIN CADCLI c
	ON nf.COD_CLIENTE = c.COD_CLI
WHERE
	nf.DAT_EMISSAO IS NOT NULL				-- sem data não há como posicionar no tempo
	AND nf.TIP_SAIDA = 'V'					-- exclui devolução, bonificação e transferência
	AND nf.DAT_CANCELAMENTO IS NULL			-- nota cancelada não representa venda

	-- âncora móvel presa ao próprio dado, não à data de hoje
	AND nf.DAT_EMISSAO >= DATEADD(YEAR, -2,
        (SELECT MAX(DAT_EMISSAO) FROM MOVNFS))
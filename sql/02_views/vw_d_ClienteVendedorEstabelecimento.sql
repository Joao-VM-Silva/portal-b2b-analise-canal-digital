/* ------------------------------------------------------------
   vw_d_ClienteVendedorEstabelecimento
   Vínculo comercial entre cliente, estabelecimento e vendedor.
 
   ATENÇÃO AO GRÃO: esta view NÃO tem uma linha por cliente.
   Parte dos clientes é atendida pelos dois estabelecimentos e
   aparece duas vezes; clientes sem vínculo aparecem uma vez,
   com estabelecimento nulo.
 
   Por isso ela é uma tabela ponte, e não a dimensão de cliente.
   A dimensão é vw_d_Clientes. Ao contar clientes por
   estabelecimento, use DISTINCTCOUNT: o total geral fica
   correto, mas matriz e filial somadas ultrapassam o total,
   porque o cliente compartilhado é legítimo nas duas.
 
   A duplicidade foi mantida de propósito. Forçar um registro
   por cliente apagaria um vínculo comercial que existe.
   ------------------------------------------------------------ */


CREATE OR ALTER VIEW vw_d_ClienteVendedorEstabelecimento AS

SELECT
	c.COD_CLI AS [Codigo Cliente],
	c.CGC_CPF AS CNPJ,
	vn.COD_ESTABE AS [Codigo Estabelecimento],

	-- o ELSE atende o cliente sem registro de vínculo, que chega
	-- aqui com código nulo por causa do LEFT JOIN
	CASE
		WHEN vn.COD_ESTABE = 1 THEN 'Matriz'
		WHEN vn.COD_ESTABE = 2 THEN 'Filial'
		ELSE 'Sem estabelecimento vinculado'
	END AS Estabelecimento,
	
	vn.COD_VENDEDOR AS [Codigo Vendedor]

FROM
	CADCLI c

-- LEFT JOIN: cliente sem vínculo comercial continua na base.
-- São clientes reais, que precisam aparecer na análise de
-- carteira justamente por não terem atendimento definido.
LEFT JOIN VINEST vn
	ON vn.COD_CLIENT = c.COD_CLI
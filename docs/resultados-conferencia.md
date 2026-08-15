# Resultados da conferência

Números medidos sobre a base sintética, usados como referência no README
e na documentação técnica.

| | |
|---|---|
| Data da medição | 30/07/2026, reconferida em 14/08/2026 |
| Script | [`sql/03_conferencia.sql`](../sql/03_conferencia.sql) |
| Semente do gerador | `SEED = 42` |
| Reprodutibilidade | rodar `gerar_base.py` com a mesma semente reproduz estes números |

> Estes valores vêm de dados sintéticos. Servem para demonstrar o método e
> permitir a reprodução do cálculo, não para descrever nenhuma operação real.

---

## 1. Volumetria

| Tabela | Linhas |
|---|---:|
| CADCID — cidades | 30 |
| CADGRP — grupos de cliente | 5 |
| CADSUP — supervisores | 6 |
| CADVEN — vendedores | 44 |
| CADCLI — clientes | 1.200 |
| VINEST — vínculo comercial | 1.207 |
| MOVNFS — movimento de notas | 120.000 |
| **vw_f_Vendas** — fato exposto ao modelo | **43.900** |

A view fato expõe 43.900 das 120.000 linhas de origem: a diferença vem do
descarte de movimento inválido e da janela de 24 meses.

---

## 2. Movimento descartado pela view fato

De 120.000 notas na origem, **23.322 (19,4%)** não representam venda efetiva.

| Motivo | Notas |
|---|---:|
| Sem data de emissão | 3.589 |
| Canceladas | 6.930 |
| Tipo diferente de venda | 14.025 |
| **Vendas válidas** | **96.678** |

As causas se sobrepõem — uma nota pode ser cancelada *e* de tipo diferente de
venda — por isso a soma das três excede o total descartado.

### Composição por tipo de movimento

| Tipo | Descrição | Notas |
|---|---|---:|
| V | Venda | 105.975 |
| D | Devolução | 7.064 |
| B | Bonificação | 4.619 |
| T | Transferência | 2.342 |

---

## 3. Efeito do filtro de venda válida sobre a última compra

Comparação entre a última compra calculada apenas com data preenchida e a
calculada também com os filtros de tipo de saída e cancelamento.

| Medida | Valor |
|---|---:|
| Clientes com algum movimento | 1.015 |
| Clientes cuja última compra muda | **166** (16,4%) |
| Atraso médio da data sem filtro | 20 dias |
| Atraso máximo | 170 dias |
| Clientes sem nenhuma venda válida | 0 |

Sem os filtros, 166 clientes teriam como última compra uma devolução ou uma
nota cancelada. Como essa data separa reativação de prospecção, esses clientes
entrariam na fila errada do plano de ação.

---

## 4. Situação de compra da base

| Situação | Clientes | Ação correspondente |
|---|---:|---|
| Compraram dentro da janela de 24 meses | 966 | relacionamento ativo |
| Compraram apenas fora da janela | 49 | reativação |
| Nunca compraram | 185 | prospecção |
| **Total** | **1.200** | |
| Já compraram pelo canal digital | 77 | |

Os 49 clientes de reativação aparecem em `vw_d_UltimaCompraCliente` e não
aparecem em `vw_f_Vendas`. São eles que justificam a existência das duas views.

---

## 5. Faturamento e participação do canal

| | Ano anterior | Ano atual | Variação |
|---|---:|---:|---:|
| Notas | 21.950 | 21.950 | 0,0% |
| Faturamento total | R$ 98.149.383,71 | R$ 106.000.000,16 | +8,0% |
| Faturamento do canal | R$ 6.379.629,54 | R$ 10.069.999,99 | **+57,85%** |
| Participação do canal | 6,50% | 9,50% | +3,0 p.p. |
| Clientes comprando pelo canal | 73 | 70 | −3 |
| Receita por cliente do canal | R$ 87.392 | R$ 143.857 | +64,6% |

Duas leituras se destacam:

**O canal cresceu sete vezes mais rápido que a empresa**, mas sem expandir a
base. O número de clientes comprando pelo canal caiu de 73 para 70. Todo o
crescimento veio de quem já usava passando a usar mais.

**O crescimento total de 8% veio de ticket médio, não de volume.** O número de
notas ficou estável entre os dois períodos, e o valor médio por nota subiu de
R$ 4.471 para R$ 4.829.

---

## 6. Grão da tabela ponte

| Medida | Valor |
|---|---:|
| Linhas em `vw_d_ClienteVendedorEstabelecimento` | 1.256 |
| Clientes distintos | 1.200 |
| Excedente | 56 |
| Clientes sem vínculo comercial | 49 |

Os 56 excedentes são clientes atendidos pelos dois estabelecimentos. A
duplicidade é legítima e foi mantida — por isso a contagem de clientes por
estabelecimento no modelo usa `DISTINCTCOUNT`, e a soma das unidades supera o
total geral.

---

## 7. Registros incompletos preservados

Cada número justifica um `LEFT JOIN` ou um `ELSE` nas views. Nenhum destes
registros foi removido: todos aparecem rotulados.

| Situação | Registros |
|---|---:|
| Clientes sem grupo comercial | 47 |
| Clientes com código de cidade inexistente | 17 |
| Clientes sem status preenchido | 22 |
| Clientes bloqueados | 99 |
| Vendedores sem supervisor | 7 |
| Notas sem layout de pedido | 8.329 |

Manter e rotular preserva a reconciliação com o sistema de origem: o total da
dimensão continua sendo 1.200, igual ao cadastro.

---

## 8. Limitação conhecida da base sintética

| Status do cliente | Clientes | Já compraram |
|---|---:|---:|
| Ativo | 1.079 | 1.015 |
| Bloqueado | 99 | 0 |
| Não informado | 22 | 0 |

Nenhum cliente bloqueado possui histórico de compra. Na prática, o bloqueio
costuma ocorrer *depois* de um período comprando — inadimplência, encerramento
de atividade. Do jeito que a base foi gerada, "bloqueado" e "nunca comprou"
acabam coincidindo, o que reduz um pouco o realismo da análise de reativação.

A limitação foi documentada em vez de corrigida, por não afetar as conclusões
sobre o canal. Detalhes em [`base-sintetica.md`](base-sintetica.md).
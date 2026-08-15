# Decisões técnicas

Este documento reúne as decisões de modelagem e tratamento tomadas no projeto,
com o raciocínio por trás de cada uma. O registro cronológico está em
[`diario-de-decisoes.md`](diario-de-decisoes.md); os números citados aqui foram
medidos e estão em [`resultados-conferencia.md`](resultados-conferencia.md).

---

## Arquitetura

O projeto integra duas origens que não se conhecem: o ERP da distribuidora e a
plataforma de pedidos. Nenhuma delas responde sozinha à pergunta do negócio.

```
ERP (SQL Server)                      Plataforma (planilhas)
7 tabelas brutas                      2 arquivos, um por região
       │                                       │
       ▼                                       │
5 views SQL                                    │
regras de negócio, tradução                    │
de códigos, janela temporal                    │
       │                                       │
       └───────────► Power Query ◄─────────────┘
                     chave, mesclagens,
                     estados do funil
                            │
                            ▼
                     Modelo dimensional
                     2 fatos, 4 dimensões
                            │
                            ▼
                     Medidas e dashboard
```

A separação entre as camadas segue um princípio: **tratar o mais cedo possível,
na camada onde a regra é estável.** Regra de negócio que vale para qualquer
consumidor do dado fica no SQL. Limpeza específica de arquivo externo fica no
Power Query. Só o que depende de contexto de filtro fica em DAX.

---

## Camada SQL

### As cinco views

| View | Grão | Papel |
|---|---|---|
| `vw_d_Clientes` | cliente | Dimensão de clientes |
| `vw_d_Vendedores` | vendedor | Dimensão comercial, com supervisor |
| `vw_d_ClienteVendedorEstabelecimento` | cliente + estabelecimento | Vínculo comercial |
| `vw_d_UltimaCompraCliente` | cliente | Situação de compra, histórico completo |
| `vw_f_Vendas` | nota fiscal | Fato de vendas, janela de 24 meses |

As tabelas de origem seguem a convenção de um sistema legado: nomes abreviados,
códigos sem descrição, datas com hora, valores em ponto flutuante e ausência de
chaves estrangeiras. Traduzir isso para linguagem de negócio é o trabalho das
views, e é por isso que elas existem em vez de o Power BI consumir as tabelas
diretamente.

### Duas views para o mesmo assunto

`vw_f_Vendas` e `vw_d_UltimaCompraCliente` tratam de compra, mas cobrem janelas
diferentes de propósito.

A view fato expõe 24 meses, adequado para análise temporal e comparação entre
anos. A view de última compra lê o histórico inteiro, sem filtro de data. Essa
diferença é o que permite separar três situações que a fato sozinha confunde:

| Situação | Clientes | Ação correspondente |
|---|---:|---|
| Compraram dentro da janela | 966 | relacionamento ativo |
| Compraram apenas antes dela | 49 | reativação |
| Nunca compraram | 185 | prospecção |

Sem essa distinção, um cliente que comprava há dois anos e parou seria abordado
como lead frio. São situações comerciais opostas.

**Consequência assumida:** as duas views não reconciliam entre si. Contar
"clientes que já compraram" por uma e por outra devolve números diferentes, e
isso está correto.

### O que a view fato descarta

De 120.000 movimentos na origem, 23.322 (19,4%) não representam venda efetiva:

| Motivo | Notas |
|---|---:|
| Sem data de emissão | 3.589 |
| Canceladas | 6.930 |
| Tipo diferente de venda | 14.025 |
| **Vendas válidas** | **96.678** |

As causas se sobrepõem, então a soma das três excede o total descartado. Depois
do recorte de 24 meses, a view expõe 43.900 linhas.

Devolução, bonificação e transferência circulam pela mesma tabela de notas
fiscais que a venda. Sem o filtro de tipo, o faturamento incluiria movimento
que não é receita.

### O filtro de venda válida na view de última compra

A primeira versão aplicava os filtros de tipo e cancelamento apenas na view
fato. A de última compra lia todo o movimento.

O efeito foi medido: **166 clientes (16,4%)** teriam como última compra uma
devolução ou uma nota cancelada, com atraso médio de 20 dias e máximo de 170.
Como essa data separa reativação de prospecção, seriam 166 clientes na fila
errada do plano de ação.

A decisão foi alinhar os critérios nas duas views. A alternativa — definir
última compra como último relacionamento comercial, incluindo devolução — seria
defensável, mas quebraria a coerência entre elas.

### Janela ancorada no dado

O caso original usava a data corrente para manter uma janela móvel, o que
funcionava porque a base recebia dados novos diariamente. Com uma base estática,
isso faria a janela deslizar para fora dos dados: em algum momento o dashboard
abriria vazio, sem erro e sem aviso.

```sql
AND nf.DAT_EMISSAO >= DATEADD(YEAR, -2,
        (SELECT MAX(DAT_EMISSAO) FROM MOVNFS))
```

A lógica continua dinâmica, mas presa ao próprio dado. Regerar a base move a
janela junto.

### Nulo se rotula, não se remove

Três tipos de nulo receberam tratamento diferente:

| Tipo | Exemplo | Tratamento |
|---|---|---|
| Invalida o registro | nota sem data de emissão | filtrado na view |
| Ausência de atributo | cliente sem grupo comercial | mantido e rotulado |
| É a própria resposta | nunca comprou pelo canal | mantido nulo, exposto em flag |

Registros incompletos preservados:

| Situação | Registros | O que justifica |
|---|---:|---|
| Cliente sem grupo comercial | 47 | `LEFT JOIN` com grupos |
| Cliente com código de cidade inexistente | 17 | `LEFT JOIN` com cidades |
| Cliente sem status preenchido | 22 | `ELSE` no `CASE` de status |
| Cliente sem vínculo comercial | 49 | `LEFT JOIN` com vínculos |
| Vendedor sem supervisor | 7 | `LEFT JOIN` com supervisores |
| Nota sem layout de pedido | 8.329 | `ISNULL` com rótulo |

Remover os incompletos quebraria a reconciliação com o sistema de origem: o
total da dimensão deixaria de bater com o cadastro, e ninguém conseguiria
explicar a diferença. Manter e rotular também transforma o problema em
informação — 47 clientes sem classificação comercial é um achado de qualidade
cadastral que pode virar ação.

**Regra adotada:** `INNER JOIN` apenas quando a ausência invalida a linha. No
projeto isso acontece uma única vez, na view fato, porque nota sem cliente
identificado não é analisável.

### A tabela ponte

`vw_d_ClienteVendedorEstabelecimento` devolve 1.256 linhas para 1.200 clientes.
O excedente são 56 clientes atendidos pelos dois estabelecimentos; outros 49 não
têm vínculo nenhum.

A duplicidade foi mantida. Forçar um registro por cliente apagaria um vínculo
comercial que existe.

**Consequência:** a view não é dimensão de cliente, é tabela ponte. A dimensão é
`vw_d_Clientes`. A contagem de clientes por estabelecimento usa `DISTINCTCOUNT`,
e a soma das unidades supera o total geral — o que está correto e precisa
aparecer declarado.

---

## Camada de transformação

### A chave de cruzamento

O identificador chega com máscara nas planilhas da plataforma e sem máscara no
banco. Sem padronização, o cruzamento entre as duas fontes não acontece — e
falha em silêncio, apenas devolvendo menos correspondências do que deveria.

A normalização é feita no Power Query, em etapa única: extrair apenas os dígitos
e completar com zeros à esquerda até 14 posições.

```powerquery
let Digitos = Text.Select(Text.From([CNPJ]), {"0".."9"})
in  if Text.Length(Digitos) = 0 then null
    else Text.PadStart(Digitos, 14, "0")
```

O tratamento ficou na camada de transformação porque o problema pertence ao
arquivo externo: as tabelas internas já armazenam o campo padronizado.

### Estabelecimento derivado da região

A tabela ponte tem grão de cliente e estabelecimento. Cruzar apenas pelo código
do cliente duplicaria linhas no funil para quem é atendido pelas duas unidades.

A chave de mesclagem compõe cliente e estabelecimento, derivando o
estabelecimento da região informada pela plataforma. A premissa assumida é que o
cliente é atendido pela unidade da própria região.

### Os estados do funil

Derivados por encadeamento de condições, em ordem que importa:

| Estado | Condição | Ação recomendada |
|---|---|---|
| Sem cadastro interno | não existe no ERP | avaliar cadastro |
| Não integrado | tem cadastro, sem integração | solicitar integração |
| Integrado sem compra | integrado, nunca comprou pelo canal | ativar uso |
| Integrado com compra | integrado e comprando | acompanhar |

A regra de bloqueio é avaliada **antes** de todas as outras na coluna de ação
recomendada. Invertida, um cliente bloqueado receberia ação comercial em vez de
validação cadastral.

A prioridade acompanha o estado: alta para quem está a um passo da compra —
integrado sem compra, e não integrado com cadastro pronto —, média para quem
exige cadastro novo, e monitoramento para quem já compra.

### Tabela de oportunidades denormalizada

`f_OportunidadesPortal` incorpora, por mesclagem, atributos que também existem
nas dimensões: razão social, grupo comercial, cidade, região, status do cliente
e dados do vendedor responsável.

A tabela não serve apenas à contagem do funil — ela é a base do plano de ação,
que precisa ser lido, filtrado e exportado linha a linha, com o contexto
completo de cada cliente. Uma tabela enxuta cumpriria o primeiro papel e não o
segundo.

**Consequência assumida:** o mesmo atributo existe em dois lugares, com
comportamento de filtro diferente. Ao montar cada visual, é preciso decidir
conscientemente de qual origem parte a segmentação.

### Clientes sem cadastro na segmentação

Os 95 clientes que usam a plataforma e não existem no ERP não possuem código de
cliente. Ao segmentar por qualquer atributo vindo da dimensão de clientes, eles
desaparecem do resultado.

O comportamento foi aceito em vez de contornado com um membro desconhecido:
quem não tem cadastro interno não tem grupo comercial nem carteira atribuída, e
não deveria aparecer numa quebra por esses atributos. Para as análises em que
esse público precisa aparecer, a segmentação parte das colunas da própria
plataforma, que a tabela de oportunidades carrega.

### Consultas de apoio sem carga

As views de vínculo comercial e de última compra entram no projeto apenas como
origem de mesclagem, com carga desabilitada.

A primeira não tem grão de cliente e, carregada como dimensão, permitiria
contagens duplicadas sem aviso. A segunda tem seus atributos já incorporados à
tabela de oportunidades, e carregá-la criaria um segundo caminho para a mesma
informação.

---

## Modelo de dados

Modelo em estrela com dois fatos e quatro dimensões. As dimensões filtram os
dois fatos, que não se relacionam entre si.

### Dimensão de calendário

Gerada a partir da tabela fato e expandida para anos completos, o que
inteligência temporal exige. Como a janela do fato é de 24 meses e não coincide
com o ano civil, isso deixa meses vazios nas duas pontas — removidos dos visuais
por uma coluna de vigência que delimita o intervalo com movimento.

O calendário **não** é relacionado às datas de última compra: elas alcançam até
48 meses atrás, fora do intervalo, e não são eixo de análise temporal. Funcionam
como atributo de classificação do cliente.

### Ciclo anual customizado

A janela de dados vai de julho a junho. Um ano civil partiria os dois períodos
ao meio e inviabilizaria a comparação.

O calendário recebeu quatro colunas de ciclo: `Ano Ciclo Inicio`, que identifica
o ano de abertura do período; `Ano Ciclo`, no formato 2025/26, usado como rótulo
nos visuais; e `Mes Ciclo Ordem` com `Mes Ciclo`, que posicionam e nomeiam o mês
dentro do ciclo — julho é o mês 1 e junho o mês 12. As medidas de variação e
acumulado operam sobre essas colunas, não sobre o ano civil.

Duas colunas de recorte complementam o calendário: `Data Vigente?`, que delimita
o intervalo em que existe movimento e remove os meses vazios das pontas, e
`Flag ultimos 12 Meses`, usada como filtro de página onde a análise precisa se
restringir ao período mais recente.

### Dimensão de estabelecimento

Criada como dimensão própria para que um único segmentador filtre os dois fatos
ao mesmo tempo. Sem ela, seriam necessários dois segmentadores independentes,
com risco de ficarem dessincronizados na tela.

### Tabelas de apoio

Uma tabela dedicada às medidas, que as mantém agrupadas em vez de espalhadas
pelas tabelas de origem, e uma tabela de data de atualização, que registra o
momento da última carga e aparece na capa.

---

## Medidas

### Bases de cálculo do funil

As contagens partem de bases diferentes conforme a pergunta: o total de usuários
da plataforma, quando o interesse é alcance; a base com cadastro interno, quando
o interesse é conversão.

Cada percentual foi padronizado sobre a base que corresponde à sua pergunta.
Misturar as duas produz número correto para uma pergunta que ninguém fez.

### Vendas restritas à base da plataforma

Os dois fatos não se relacionam. Para medir o faturamento apenas dos clientes da
plataforma, o vínculo é feito em tempo de cálculo, tratando o par cliente e
estabelecimento da tabela de oportunidades como filtro sobre a tabela de vendas.

O par, e não apenas o cliente: quem aparece na exportação de uma unidade não
deve trazer para o cálculo as vendas feitas pela outra.

### Tratamento de contexto vazio

Divisões que representam participação retornam zero quando não há dado, porque
zero é leitura legítima. Divisões que representam variação entre períodos
retornam vazio, para que o primeiro período do histórico — que não tem
comparação — não desenhe uma linha em zero no gráfico.

---

## Uma decisão revista

A medida que restringe o faturamento aos clientes da plataforma iterava linha a
linha aplicando o filtro dentro de cada iteração. Como os argumentos de filtro do
`CALCULATE` são avaliados **antes** da transição de contexto, cada iteração
recebia o conjunto inteiro de clientes em vez de um só.

O resultado ficava correto na linha e multiplicado no total, por um fator
próximo ao número de grupos percorridos pela iteração. É o tipo de erro que
passa despercebido em conferência linha a linha, porque o percentual derivado
continuava plausível: numerador e denominador foram inflados pelo mesmo fator.

A correção aplica o par cliente e estabelecimento como filtro único, em uma
avaliação, no lugar da iteração.

O episódio vale como registro de método: o total foi conferido contra o
faturamento conhecido do canal, e não apenas contra a soma visível na tela.

---

## Limitações conhecidas

Sobre a base sintética — geração, imperfeições deliberadas e limitações — o
detalhamento está em [`base-sintetica.md`](base-sintetica.md).

Sobre o modelo, duas observações:

**O filtro de bloqueio na base elegível é inerte.** Nenhum cliente bloqueado
está na base da plataforma, então o filtro nunca remove ninguém. É defensivo, e
passaria a valer em dado real.

**A premissa da região não é validada.** Se a região informada pela plataforma
divergir do cadastro interno para algum cliente, a mesclagem não encontra par e o
vendedor responsável volta vazio, sem indício de que algo deu errado. Em produção,
valeria uma coluna expondo esse caso.
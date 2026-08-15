# Diário de decisões

Registro das decisões técnicas tomadas durante o projeto, na ordem em que
aconteceram. Não é documentação final — é o material de onde a documentação
sai depois.

Cada entrada responde a três perguntas: qual era a alternativa, o que foi
decidido e por quê.

---

## 25/07 — Reconstruir com base sintética, e não mascarar o original

O projeto nasceu de um caso corporativo real, já apresentado à diretoria. Para
publicá-lo, era preciso resolver a confidencialidade dos dados.

**Alternativas:** substituir apenas nomes e identificadores no material
original; refazer a análise sobre uma base pública; gerar uma base sintética
com a mesma estrutura.

**Decisão:** gerar base sintética do zero, com script próprio.

Substituir nomes não bastaria — valores, volumes e composição de carteira também
são informação sensível. E partir dos arquivos originais traria resíduo junto:
o código do Power Query carrega nome de servidor, caminho de arquivo e nome de
tabela mesmo quando nada disso aparece na tela.

Consequência: nada do material original é reaproveitado. Metodologia, estrutura
e regras de negócio são reais; os dados, não.

---

## 25/07 — Preservar a estrutura, não os valores

Definido o que a base sintética precisa reproduzir para o caso continuar
fazendo sentido:

- esquema e chaves das tabelas de origem
- proporções do funil de clientes
- concentração de compras em poucos clientes (distribuição de cauda longa)
- distribuição do ticket médio
- sazonalidade e curva de evolução

E o que não deve ser preservado: valores absolutos, nomes, identificadores,
localidades e ordem de grandeza do faturamento real.

---

## 26/07 — O gerador produz tabelas brutas, não a saída das views

Primeira versão do gerador produzia tabelas já tratadas, espelhando o resultado
das views.

**Problema:** com os dados chegando prontos, as views virariam praticamente um
`SELECT *`, e todo o trabalho de tradução do sistema de origem desapareceria do
projeto.

**Decisão:** o gerador produz sete tabelas no formato bruto de um ERP —
códigos sem descrição, datas com hora, valores em `FLOAT`, campos nulos e
movimentos que não são venda. Todo o tratamento acontece nas views.

As imperfeições foram injetadas de propósito, cada uma correspondendo a um
trecho específico das views: tipos de saída além de venda, notas canceladas,
notas sem data, cadastro sem grupo, cidade inexistente, cliente sem vínculo
comercial e vendedor sem supervisor. Sem elas, os filtros seriam decorativos.

---

## 26/07 — Histórico de 48 meses na origem, janela de 24 na view fato

**Decisão:** a tabela de movimento cobre 48 meses; a view fato expõe 24.

A diferença não é arbitrária. É ela que cria clientes cuja última compra é
anterior à janela do fato — e são esses clientes que dão razão de existir à
view de última compra. Com as duas cobrindo o mesmo período, "comprou há muito
tempo" e "nunca comprou" ficariam indistinguíveis, e o plano de ação trataria
cliente antigo como lead frio.

A janela de 24 meses, em vez dos 12 do projeto original, permite comparar um
ano contra o outro.

---

## 27/07 — CNPJ como texto padronizado

**Alternativas:** guardar o CNPJ como número, reproduzindo o defeito comum de
perda do zero à esquerda, ou guardar já padronizado como texto.

**Decisão:** texto de 14 dígitos, com os zeros preservados, em todas as tabelas
do banco.

CNPJ é identificador, não número: não entra em cálculo e tem zero à esquerda
que só existe como texto. O tratamento de limpeza fica concentrado nas
planilhas do portal, que trazem o campo com máscara, e acontece no Power Query.

---

## 27/07 — As planilhas do portal não entram no banco

**Decisão:** os dois arquivos exportados pela plataforma são lidos direto pelo
Power Query, sem passar pelo banco de dados.

Reproduz a arquitetura do caso original, em que a análise cruzava uma fonte
interna com uma exportação externa. Manter as duas fontes separadas preserva a
integração multi-fonte, que é parte do que o projeto demonstra.

---

## 28/07 — Nulo se rotula, não se remove

**Decisão:** registros incompletos permanecem na base, com rótulo explícito.

Três tipos de nulo receberam tratamento diferente:

| Tipo | Exemplo | Tratamento |
|---|---|---|
| Invalida o registro | nota sem data de emissão | filtrado na view |
| Ausência de atributo | cliente sem grupo comercial | mantido e rotulado |
| É a própria resposta | cliente que nunca comprou pelo canal | mantido como nulo, exposto em flag |

Remover os incompletos quebraria a reconciliação com o sistema de origem: o
total da dimensão deixaria de bater com o total do cadastro, e ninguém
conseguiria explicar a diferença. Manter e rotular também transforma o problema
em informação — 47 clientes sem classificação comercial é um achado de
qualidade cadastral.

Regra geral adotada: `INNER JOIN` apenas quando a ausência invalida a linha.
No projeto, isso acontece uma única vez, na view fato, porque nota sem cliente
identificado não é analisável.

---

## 28/07 — Janela ancorada no dado, não na data de hoje

O projeto original usava `GETDATE()` para manter uma janela móvel de 12 meses,
o que funcionava porque a base recebia dados novos diariamente.

**Problema:** com uma base estática, `GETDATE()` faz a janela deslizar para fora
dos dados. Em algum momento o dashboard abriria vazio, sem erro e sem aviso.

**Decisão:** ancorar em `MAX(DAT_EMISSAO)` da própria tabela.

A lógica continua dinâmica — regerar a base move a janela junto — mas ela nunca
sai de cima dos dados.

---

## 28/07 — Filtro de venda válida também na view de última compra

O projeto original aplicava os filtros de tipo de saída e cancelamento apenas
na view fato. A view de última compra lia todo o movimento.

**Consequência medida:** 166 clientes teriam como última compra uma devolução ou
uma nota cancelada, com atraso médio de 20 dias e máximo de 170. Como essa data
separa reativação de prospecção, seriam 166 clientes na fila errada do plano de
ação.

**Decisão:** aplicar os mesmos critérios de venda válida nas duas views.

A alternativa — definir última compra como último relacionamento comercial,
incluindo devoluções — seria defensável, mas quebraria a coerência entre as duas
views.

Números em [`resultados-conferencia.md`](resultados-conferencia.md).

---

## 28/07 — A tabela ponte mantém a duplicidade

A view de vínculo comercial devolve 1.256 linhas para 1.200 clientes: 56
clientes são atendidos pelos dois estabelecimentos.

**Alternativas:** aplicar uma regra de estabelecimento principal para forçar um
registro por cliente, ou manter todos os vínculos.

**Decisão:** manter. Forçar registro único apagaria um vínculo comercial que
existe de fato.

Consequência para o modelo: a view não é dimensão de cliente, é tabela ponte.
A dimensão é `vw_d_Clientes`. A contagem de clientes por estabelecimento usa
`DISTINCTCOUNT`, e a soma das unidades supera o total geral — o que está
correto e precisa aparecer declarado no dashboard.

---

## 29/07 — Documentação em duas camadas

**Decisão:** cabeçalho em toda view, explicando o que ela faz, qual o grão e
qual decisão alguém questionaria. Comentário de linha apenas onde o código
provoca a pergunta "por que assim?".

Comentário que explica sintaxe SQL foi evitado.

Números não entram nos comentários das views: se a base for regerada com outra
semente, comentário com número passa a mentir silenciosamente. As medições
ficam na documentação, com data.

---

## 29/07 — Rótulos de exibição padronizados

Os textos das views vão direto para segmentadores e eixos do dashboard.
Conviviam três convenções de capitalização.

**Decisão:** capitalização de sentença em todos os rótulos.

Separado também o valor de origem do rótulo de exibição: a comparação continua
sendo feita contra o código armazenado, e apenas o texto apresentado ao usuário
é formatado para leitura.

---

## 30/07 — Interpretação do volume estável entre os dois anos

A conferência mostrou exatamente 21.950 notas em cada um dos dois anos da
janela. É coincidência do sorteio, com probabilidade em torno de 0,4%.

**Alternativas:** regerar a base com outra semente, ou adotar a leitura.

**Decisão:** adotar. O crescimento de 8% no faturamento veio de ticket médio,
com volume de notas estável. É um cenário de negócio possível, e a igualdade só
aparece no agregado anual.

---

## 30/07 — Limitação dos clientes bloqueados

A conferência revelou que nenhum dos 99 clientes bloqueados possui histórico de
compra. Na prática, o bloqueio costuma vir depois de um período comprando.

**Decisão:** documentar em vez de corrigir. A limitação não afeta as conclusões
sobre o canal, e regerar exigiria refazer a carga e a conferência.

---

## 30/07 — Sequência de trabalho

**Decisão:** desenvolver primeiro, documentar depois — com este diário
registrando as decisões enquanto acontecem.

Documentar antes de o projeto existir produz texto sobre intenção. Mas confiar
só na memória perde o que não se reconstitui depois: medição feita antes de uma
mudança e print de um estado de tela que não existe mais.

---

## 31/07 — Flags de bloqueio expostas nas dimensões

As duas views já retornavam uma flag numérica para identificar registros bloqueados.
No entanto, em ambas, a coluna possuía o mesmo nome: Flag Bloqueado.
**Decisão:** renomear as colunas para deixar explícita a entidade representada por cada flag:

Flag Cliente Bloqueado na d_Clientes;
Flag Vendedor Bloqueado na d_Vendedores.

A alteração não modificou a regra nem o conteúdo das colunas. O objetivo foi apenas melhorar a
clareza, evitar ambiguidades durante a modelagem e facilitar a identificação dos campos na
criação de medidas e análises.

---

## 01/08 — Tratamento da chave de cruzamento no Power Query

O identificador chega com máscara nas planilhas do portal e sem máscara no
banco. Sem padronização, o cruzamento entre as duas fontes simplesmente não
acontece — e falha em silêncio, sem erro, apenas devolvendo menos
correspondências do que deveria.

**Alternativas:** tratar no banco, criando uma coluna normalizada; tratar na
camada de transformação.

**Decisão:** normalizar no Power Query, em etapa única — extrair apenas os
dígitos e completar com zeros à esquerda até 14 posições. A coluna tratada
substitui a original.

O tratamento ficou na camada de transformação porque o problema pertence ao
arquivo externo: as tabelas internas já armazenam o campo padronizado como
texto. Corrigir no banco seria resolver no lugar errado.

---

## 01/08 — Estabelecimento responsável derivado da UF

A tabela de vínculo comercial tem grão de cliente e estabelecimento, não de
cliente. Cruzar apenas pelo código do cliente duplicaria linhas no funil para
quem é atendido pelas duas unidades.

**Decisão:** compor a chave de mesclagem com cliente e estabelecimento,
derivando o estabelecimento a partir da UF informada pela plataforma.

A regra assumida é que o cliente é atendido pela unidade do próprio estado.
Ela resolve a duplicidade sem descartar vínculo, mas é uma premissa: se a UF
do portal divergir do cadastro interno para algum cliente, a mesclagem não
encontra par e o vendedor volta nulo.

---

## 01/08 — Consultas de apoio sem carga no modelo

`d_ClienteVendedorEstabelecimento` e `d_UltimaCompraCliente` entram no projeto
apenas como origem de mesclagem.

**Decisão:** manter as duas com carga desabilitada.

A primeira não tem grão de cliente e, carregada como dimensão, permitiria
contagens duplicadas sem aviso. A segunda tem seus atributos já incorporados à
tabela de oportunidades, e carregá-la criaria um segundo caminho para a mesma
informação.

---

## 01/08 — Tabela de oportunidades mantida denormalizada

`f_OportunidadesPortal` incorpora, por mesclagem, atributos que também existem
nas dimensões: razão social, grupo comercial, cidade, UF, status do cliente e
dados do vendedor responsável.

**Alternativas:** manter a tabela enxuta, apenas com chaves e colunas próprias,
buscando o restante pelas dimensões; ou incorporar os atributos.

**Decisão:** incorporar.

A tabela não serve apenas à contagem do funil — ela é também a base do plano de
ação, que precisa ser lido, exportado e distribuído linha a linha, com o
contexto completo de cada cliente. Uma tabela enxuta cumpriria o primeiro papel
e não o segundo.

Consequência assumida: o mesmo atributo existe em dois lugares, com
comportamento de filtro diferente. Ao montar cada visual, é preciso decidir
conscientemente de qual origem parte a segmentação.

---

## 01/08 — Clientes sem cadastro interno na segmentação

Os clientes que usam a plataforma e não existem no cadastro interno — o público
de prospecção — não possuem código de cliente. Ao segmentar por qualquer
atributo vindo da dimensão de clientes, eles desaparecem do resultado.

**Alternativas:** criar um membro desconhecido na dimensão, com chave sentinela,
para que nenhum registro saia da segmentação; ou aceitar o comportamento.

**Decisão:** aceitar.

O comportamento é coerente: quem não tem cadastro interno não tem grupo
comercial nem carteira atribuída, e não deveria aparecer numa quebra por esses
atributos. Para as análises em que esse público precisa aparecer, a segmentação
parte das colunas do próprio portal, que a tabela de oportunidades carrega.

---

## 01/08 — Dimensão de calendário

**Decisão:** gerar o calendário a partir da tabela fato de vendas, expandido
para anos completos, e controlar a exibição por uma coluna de vigência.

A expansão para anos completos é necessária para que inteligência temporal
funcione — cálculos acumulados no ano exigem janeiro a dezembro presentes. Como
a janela do fato é de 24 meses e não coincide com o ano civil, isso deixa meses
vazios nas duas pontas.

A coluna de vigência delimita o intervalo em que existe movimento, comparando
cada data com a menor e a maior data da tabela fato. Aplicada como filtro, ela
remove os períodos vazios dos visuais sem quebrar os cálculos acumulados.

O calendário não foi relacionado às datas de última compra: elas alcançam até
48 meses atrás, fora do intervalo do calendário, e não são eixo de análise
temporal — funcionam como atributo de classificação do cliente.

---

## 01/08 — Dimensão de estabelecimento

Matriz e filial eram identificadas por código em cada tabela fato, com a
descrição resolvida separadamente em cada uma.

**Decisão:** criar uma dimensão própria de estabelecimento.

Um único segmentador passa a filtrar as duas tabelas fato ao mesmo tempo — as
vendas e o funil de oportunidades. Sem a dimensão, seriam necessários dois
segmentadores independentes, com risco de ficarem dessincronizados na tela.

---

## 01/08 — Tabelas de apoio ao modelo

**Decisão:** criar uma tabela dedicada às medidas e uma tabela de data de
atualização.

A tabela de medidas mantém os cálculos agrupados em um só lugar do painel de
campos, em vez de espalhados pelas tabelas de origem. A data de atualização
registra o momento da última carga e fica visível no rodapé do relatório, para
que ninguém interprete um dado antigo como atual.


## 02/08 — Medidas de comparação entre períodos

O projeto original expunha apenas valores absolutos do período corrente,
porque a janela era de 12 meses e não havia base de comparação.

**Decisão:** com a janela ampliada para 24 meses, incluir medidas de
variação anual e acumulado no ano.

A comparação com o mesmo período do ano anterior é o que transforma a
participação do canal de um número isolado em uma trajetória. Sem ela,
não é possível dizer se o canal está ganhando ou perdendo espaço.

## 02/08 — Base de cálculo das medidas do funil

As contagens do funil partem de bases diferentes conforme a pergunta:
o total de usuários da plataforma, quando o interesse é o alcance; e a
base elegível — com cadastro interno e sem bloqueio — quando o interesse
é a conversão.

**Decisão:** padronizar cada percentual sobre a base que corresponde à
pergunta que ele responde, e deixar o denominador explícito no nome da
medida.

Misturar as duas bases num mesmo percentual produz número correto para
uma pergunta que ninguém fez.

## 02/08 — Vendas restritas à base do portal

As duas tabelas fato não estão relacionadas entre si. Para medir o
faturamento apenas dos clientes que usam a plataforma, o vínculo é feito
em tempo de cálculo, tratando o par cliente e estabelecimento da tabela
de oportunidades como filtro sobre a tabela de vendas.

**Decisão:** usar o par, e não apenas o cliente. Um cliente que aparece
na exportação de uma unidade não deve trazer para o cálculo as vendas
feitas pela outra.

## 02/08 — Tratamento de contexto vazio nas medidas

Divisões que representam participação retornam zero quando não há dado,
porque zero é leitura legítima. Divisões que representam variação entre
períodos retornam vazio, para que o primeiro período do histórico — que
não tem comparação — não desenhe uma linha em zero no gráfico.


## 07/08 — Data de referência fixada no gerador

O gerador usava a data corrente do sistema como âncora do histórico.
Rodar o script em dias diferentes produzia bases diferentes, e os números
da conferência deixavam de corresponder ao que estava documentado.

**Decisão:** transformar a data de referência em parâmetro fixo.

A reprodutibilidade era premissa do projeto — qualquer pessoa deveria
chegar aos mesmos números rodando o script. Com a data do sistema como
âncora, isso só valia dentro do mesmo mês.

## 07/08 — Nome de guerra único por vendedor

Os nomes eram sorteados de uma lista menor que o número de vendedores,
o que produzia homônimos. Nos visuais agrupados por nome, dois vendedores
diferentes se fundiam em um único ponto.

**Decisão:** acrescentar o sobrenome aos nomes repetidos, mantendo o
código do vendedor como chave.

A correção usa um gerador aleatório isolado, para alterar apenas essa
coluna sem deslocar as demais tabelas da base.


## 08/08 — Planilhas do portal em diretório próprio

O Power Query lê as exportações da plataforma com Folder.Files, que carrega
todos os arquivos do diretório. Misturadas aos CSVs da base, a consulta
tentaria abrir cada um deles como planilha.

**Decisão:** o gerador grava as duas planilhas em pasta separada, criada
por ele quando não existe.

Antes a separação era feita manualmente, o que quebrava a reprodutibilidade:
quem clonasse o repositório e rodasse o script teria a consulta apontando
para uma pasta vazia.

## 09/08 — Correção do cálculo de vendas restritas à base do portal

A medida que restringe o faturamento aos clientes da plataforma iterava
linha a linha aplicando o filtro dentro de cada iteração. Como os
argumentos de filtro são avaliados antes da transição de contexto, cada
iteração recebia o conjunto inteiro de clientes em vez de um só.

O resultado ficava correto no detalhe e multiplicado no total — o tipo de
erro que não aparece na conferência linha a linha.

**Decisão:** aplicar o par cliente e estabelecimento como filtro único,
em uma avaliação, no lugar da iteração.

## 13/08 — Compressão das imagens de fundo

As imagens de plano de fundo levaram o arquivo do Power BI a mais de
30 MB. Como o Git guarda cópia inteira de binário a cada commit, o
repositório cresceria rápido e sem possibilidade de enxugar depois.

**Decisão:** comprimir as imagens antes de aplicá-las ao relatório.
Imagem de fundo para tela não exige a resolução original, e a diferença
não é perceptível na apresentação.
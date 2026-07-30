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

<!--
Modelo para as próximas entradas:

## DD/MM — Título curto da decisão

**Alternativas:** o que estava em jogo.

**Decisão:** o que foi escolhido.

Por quê, e o que muda em consequência. Se houver número medido, registrar
aqui com a data.
-->
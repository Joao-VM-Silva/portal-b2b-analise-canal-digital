# A base sintética

Todos os dados deste projeto são gerados por script. Nenhum registro
corresponde a empresa, pessoa ou operação existente.

Este documento explica como a base foi construída, o que ela reproduz do caso
original e onde ela deixa a desejar.

---

## Por que os dados não são reais

O projeto reconstrói um caso corporativo real, desenvolvido e apresentado
internamente em uma distribuidora. Faturamento, composição de carteira e
identificação de clientes são informação confidencial e não podem ser
publicados.

Havia três caminhos:

| Caminho | Por que foi descartado |
|---|---|
| Mascarar os dados originais | Substituir nomes não resolve: valores, volumes e composição de carteira também são sensíveis |
| Refazer com base pública | Perderia a estrutura do problema, que é o que dá valor ao caso |
| **Gerar base sintética** | **Adotado** |

Um detalhe pesou na escolha: partir dos arquivos originais traria resíduo
junto. O código de transformação carrega nome de servidor, caminho de arquivo e
nome de tabela mesmo quando nada disso aparece na tela. A base foi gerada do
zero, e nenhum artefato do material original foi reaproveitado.

**Metodologia, estrutura e regras de negócio são reais. Os dados, não.**

---

## O que a base reproduz

Para o caso continuar fazendo sentido, a base preserva:

- o esquema e as chaves das tabelas de origem
- as proporções do funil de clientes
- a concentração de compras em poucos clientes, com cauda longa
- a distribuição do ticket médio
- a sazonalidade e a curva de evolução do canal
- a proporção de registros incompletos no cadastro

## O que ela não reproduz

- valores absolutos de faturamento
- nomes, identificadores e localidades
- ordem de grandeza da operação real

---

## Importante: os resultados não são descobertas

Os números que aparecem no dashboard e na documentação vêm desta base. Alguns
deles são **parâmetros de entrada**, não conclusões da análise.

A participação do canal no faturamento, o crescimento entre os dois anos e a
distribuição do funil estão definidos em `data-generator/parametros.py`. Foram
calibrados para reproduzir a *forma* do achado original, e não para serem
descobertos por ela.

O que esta base demonstra é o **método**: como as fontes foram cruzadas, como a
chave foi tratada, como os estados do cliente foram derivados e como a análise
chega de um movimento bruto a um plano de ação. Os números permitem que
qualquer pessoa reproduza o cálculo — não são evidência sobre o mundo.

As conclusões do caso original estão descritas no README em linguagem
qualitativa, sem valores.

---

## As tabelas geradas

O gerador produz sete tabelas no formato bruto de um ERP, mais duas planilhas
que simulam a exportação da plataforma externa.

| Arquivo | Pasta | Conteúdo |
|---|---|---|
| `CADCLI.csv` | `data/` | Cadastro de clientes |
| `CADCID.csv` | `data/` | Cidades, com chave composta por código e estado |
| `CADGRP.csv` | `data/` | Grupos comerciais |
| `CADVEN.csv` | `data/` | Vendedores |
| `CADSUP.csv` | `data/` | Supervisores |
| `VINEST.csv` | `data/` | Vínculo entre cliente, estabelecimento e vendedor |
| `MOVNFS.csv` | `data/` | Movimento de notas fiscais, 48 meses |
| `portal_matriz.xlsx` | `data-portal/` | Exportação da plataforma, região da matriz |
| `portal_filial.xlsx` | `data-portal/` | Exportação da plataforma, região da filial |

As tabelas seguem a convenção de um sistema legado: nomes abreviados, códigos
sem descrição, datas com hora, valores em ponto flutuante e ausência de chaves
estrangeiras. Nada chega tratado — a tradução para linguagem de negócio é
trabalho das views.

As duas planilhas não entram no banco. São lidas direto pela camada de
transformação, reproduzindo a integração multi-fonte do caso original. O CNPJ
vem com máscara nelas e sem máscara no banco, o que exige tratamento da chave
antes do cruzamento.

Elas ficam em diretório separado porque a camada de transformação lê a pasta
inteira: um CSV da base ali dentro seria interpretado como planilha e quebraria
a consulta.

---

## Imperfeições deliberadas

A base não é limpa de propósito. Cada defeito existe para dar trabalho a um
trecho específico das views — sem eles, os filtros e tratamentos seriam
decorativos, e removê-los não mudaria resultado nenhum.

| Imperfeição | O que ela justifica |
|---|---|
| Movimento de tipo diferente de venda | Filtro de tipo de saída |
| Notas canceladas | Filtro de data de cancelamento |
| Notas sem data de emissão | Filtro de data preenchida |
| Cliente sem status cadastrado | Cláusula `ELSE` no `CASE` de status |
| Cliente sem grupo comercial | `LEFT JOIN` com a tabela de grupos |
| Código de cidade inexistente | `LEFT JOIN` com a tabela de cidades |
| Cliente sem vínculo comercial | `LEFT JOIN` com a tabela de vínculos |
| Vendedor sem supervisor | `LEFT JOIN` com a tabela de supervisores |
| Datas com hora e valores em `FLOAT` | Conversões de tipo nas views |
| CNPJ com e sem máscara entre as fontes | Tratamento da chave de cruzamento |

Cerca de um quinto do movimento gerado não representa venda efetiva. A medição
está em [`resultados-conferencia.md`](resultados-conferencia.md).

---

## Como reproduzir

```powershell
cd data-generator
python -m venv .venv
.venv\Scripts\Activate.ps1         # Windows PowerShell
# .venv/Scripts/activate           # Git Bash
# source .venv/bin/activate        # Linux e macOS
pip install -r requirements.txt
python gerar_base.py
```

Os CSVs são escritos em `data/` e as duas planilhas do portal em
`data-portal/`, ambas criadas pelo próprio script quando não existem. Em
seguida, `sql/01_ddl_e_carga.sql` cria as tabelas e faz a carga; ajuste os
caminhos antes de executar.

Dois parâmetros garantem que o resultado seja sempre o mesmo: a semente
aleatória (`SEED`) e a data de referência (`DATA_REFERENCIA`), que ancora todo
o histórico. Com a data do sistema no lugar dela, o resultado mudaria a cada
execução em dia diferente, e os números da conferência deixariam de bater.

Os parâmetros de porte, funil, faturamento e proporção de registros incompletos
ficam em `parametros.py` e podem ser alterados. Mudar qualquer um deles
invalida os números registrados na conferência.

---

## Limitações conhecidas

### Clientes bloqueados não possuem histórico de compra

Dos 1.200 clientes gerados, 99 estão bloqueados e 22 estão sem status
preenchido. Nenhum deles tem nota fiscal associada.

Na prática, o bloqueio costuma ocorrer *depois* de um período comprando —
inadimplência, encerramento de atividade, mudança de titularidade. Do jeito que
a base foi construída, "bloqueado" e "nunca comprou" acabam coincidindo, o que
empobrece a análise de reativação: não existe o caso do cliente que comprava
bem e foi bloqueado.

A limitação foi mantida por não afetar as conclusões sobre o canal digital, que
é o objeto do estudo.

### Volume de notas idêntico entre os dois anos

A janela de 24 meses contém exatamente 21.950 notas em cada um dos dois anos.
É coincidência do sorteio aleatório, com probabilidade em torno de 0,4%.

O efeito é que o crescimento de 8% no faturamento vem inteiramente de ticket
médio, com volume estável. É um cenário de negócio possível, mas a igualdade
perfeita não ocorreria em dado real. A leitura foi adotada como está.

### A cauda longa é sintética

A concentração de compras em poucos clientes segue uma distribuição de Pareto
com parâmetro fixo. Reproduz o formato observado em distribuição, mas não a
dinâmica real — não há entrada e saída de clientes ao longo do tempo, nem
mudança de comportamento de compra.
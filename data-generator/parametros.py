"""
Parametros de geracao da base sintetica do projeto Portal B2B.

As tabelas geradas imitam a origem de um ERP: nomes abreviados, codigos
sem descricao, datas com hora, campos nulos e movimentos que nao sao venda.
Todo o tratamento acontece nas views SQL, nao aqui.

Nenhum valor corresponde a dado real de qualquer empresa.
"""

"""
Parametros de geracao (...)
"""

from datetime import date
from pathlib import Path

SEED = 42

# Data de referencia da base. Fixada de proposito: com date.today() o
# resultado mudaria a cada execucao em dia diferente, e os numeros da
# conferencia deixariam de bater. Alterar aqui desloca toda a base no tempo.

DATA_REFERENCIA = date(2026, 7, 1)

# ---------------------------------------------------------------- porte
N_CLIENTES = 1200
N_CLIENTES_PLATAFORMA = 380
N_VENDEDORES_POR_REGIAO = 22
N_SUPERVISORES_POR_REGIAO = 3

# ---------------------------------------------------------------- tempo
# MESES_HISTORICO precisa ser MAIOR que MESES_FATO. E essa diferenca que
# cria clientes cuja ultima compra e anterior a janela do fato, sem os
# quais a view de ultima compra perde a razao de existir.
MESES_HISTORICO = 48
MESES_FATO = 24

# ---------------------------------------------------------------- valores
# Calibrado sobre as notas validas apenas: venda, nao cancelada, com data.
FATURAMENTO_ANO_ATUAL = 106_000_000.0
CRESCIMENTO_ANUAL = 1.08

PARTICIPACAO_CANAL_ANO_ATUAL = 0.095
PARTICIPACAO_CANAL_ANO_ANTERIOR = 0.065

N_NOTAS_POR_ANO = 30_000       # inclui movimentos que a view vai descartar

TICKET_MU = 7.9
TICKET_SIGMA = 0.85

# ---------------------------------------------------------------- funil
FUNIL = {
    "ativo": 0.22,
    "ativacao": 0.18,
    "integracao": 0.35,
    "prospeccao": 0.25,
}

PROP_CLIENTES_SEM_COMPRA_RECENTE = 0.12
PROP_CLIENTES_SEM_COMPRA_NENHUMA = 0.06

# ---------------------------------------------------------------- estrutura
REGIOES = {
    1: {"sigla": "MG", "nome": "MATRIZ", "peso": 0.62},
    2: {"sigla": "GO", "nome": "FILIAL", "peso": 0.38},
}

PROP_CLIENTE_EM_DOIS_ESTAB = 0.05

GRUPOS_CLIENTE = [
    (10, "REDE REGIONAL A", 0.11),
    (20, "REDE REGIONAL B", 0.08),
    (30, "ASSOCIATIVISMO", 0.20),
    (40, "FARMACIA INDEPENDENTE", 0.47),
    (50, "CLINICA E HOSPITAL", 0.14),
]

# DES_LAYOUTPDE. O primeiro identifica o canal digital.
LAYOUT_CANAL = "PORTALB2B"
LAYOUTS_OUTROS = ["EDI_A1", "EDI_B2", "EDI_C3", "TELEVENDA", None]

ADOCAO_INICIAL = 0.18
ADOCAO_FINAL = 0.55

PROP_CNPJ_COM_ZERO_INICIAL = 0.12

# ---------------------------------------------------------------- imperfeicoes
# Cada uma existe para dar trabalho a um trecho especifico das views.
# Zerar qualquer uma torna o filtro correspondente decorativo.

TIPOS_SAIDA = [("V", 0.88), ("D", 0.06), ("B", 0.04), ("T", 0.02)]
PROP_NOTA_CANCELADA = 0.06
PROP_NOTA_SEM_DATA = 0.03

PROP_CLIENTE_BLOQUEADO = 0.09
PROP_CLIENTE_STATUS_NULO = 0.02
PROP_CLIENTE_SEM_GRUPO = 0.05
PROP_CLIENTE_CIDADE_ORFA = 0.01
PROP_CLIENTE_SEM_VINCULO = 0.04

PROP_VENDEDOR_BLOQUEADO = 0.12
PROP_VENDEDOR_SEM_SUPERVISOR = 0.15

DIR_SAIDA = str(Path(__file__).resolve().parent.parent / "data")
DIR_PORTAL = str(Path(__file__).resolve().parent.parent / "data-portal")
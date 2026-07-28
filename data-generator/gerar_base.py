"""
Gerador da base sintetica do projeto Portal B2B.

Produz sete tabelas no formato bruto de um ERP. Nada aqui vem tratado:
os codigos nao tem descricao, as datas tem hora, ha campos nulos e ha
movimentos que nao sao venda. Todo o tratamento acontece nas views SQL.

Saida:
    CADCLI.csv   cadastro de clientes
    CADCID.csv   cidades
    CADGRP.csv   grupos de cliente
    VINEST.csv   vinculo cliente / estabelecimento / vendedor
    MOVNFS.csv   movimento de notas fiscais
    CADVEN.csv   vendedores
    CADSUP.csv   supervisores
    portal_matriz.xlsx / portal_filial.xlsx   exportacoes da plataforma

Nenhum dado real e utilizado. Os CNPJ tem digito verificador valido mas
sao gerados aleatoriamente e nao correspondem a empresas existentes.

Uso:
    python gerar_base.py
"""

import os
import random
from datetime import date, datetime, timedelta

import numpy as np
import pandas as pd

import parametros as p

rng = np.random.default_rng(p.SEED)
random.seed(p.SEED)


# --------------------------------------------------------------- utilidades
def _dv_cnpj(base12: str) -> str:
    def digito(nums, pesos):
        s = sum(int(n) * peso for n, peso in zip(nums, pesos))
        resto = s % 11
        return "0" if resto < 2 else str(11 - resto)

    p1 = [5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2]
    d1 = digito(base12, p1)
    return d1 + digito(base12 + d1, [6] + p1)


def gerar_cnpj() -> str:
    primeiro = "0" if rng.random() < p.PROP_CNPJ_COM_ZERO_INICIAL else str(rng.integers(1, 10))
    base12 = primeiro + "".join(str(rng.integers(0, 10)) for _ in range(7)) + "0001"
    return base12 + _dv_cnpj(base12)


def formatar_cnpj(c: str) -> str:
    return f"{c[:2]}.{c[2:5]}.{c[5:8]}/{c[8:12]}-{c[12:]}"


PREFIXOS = ["DROGARIA", "FARMACIA", "DROGA", "FARMA", "REDE", "COMERCIAL"]
NUCLEOS = ["SAO PEDRO", "CENTRAL", "POPULAR", "VIDA", "SAUDE", "BOM PRECO",
           "UNIAO", "ESPERANCA", "SANTA CLARA", "NOVA ERA", "PRIME", "IDEAL",
           "MODELO", "REAL", "ESTRELA", "HORIZONTE", "AURORA", "PLANALTO"]
SUFIXOS = ["LTDA", "ME", "EIRELI", "COMERCIO LTDA"]

NOMES = ["Ana", "Bruno", "Carla", "Diego", "Elisa", "Fabio", "Gabriela",
         "Heitor", "Ines", "Joao", "Karina", "Lucas", "Marina", "Nelson",
         "Olivia", "Paulo", "Renata", "Sergio", "Tatiana", "Vitor"]
SOBRENOMES = ["Almeida", "Barbosa", "Cardoso", "Duarte", "Ferreira", "Gomes",
              "Henrique", "Junqueira", "Lopes", "Machado", "Nogueira",
              "Oliveira", "Prado", "Queiroz", "Ribeiro", "Teixeira"]


def nome_empresa(i: int) -> str:
    return (f"{random.choice(PREFIXOS)} {random.choice(NUCLEOS)} "
            f"{random.choice(SUFIXOS)} {i:04d}")


def nome_pessoa() -> str:
    return f"{random.choice(NOMES)} {random.choice(SOBRENOMES)}"


def escolher(opcoes):
    """Sorteia de uma lista de (valor, peso)."""
    vals = [v for v, _ in opcoes]
    pesos = np.array([w for _, w in opcoes], dtype=float)
    return vals[int(rng.choice(len(vals), p=pesos / pesos.sum()))]


# --------------------------------------------------------------- CADCID
def gerar_cidades() -> pd.DataFrame:
    """Cidades. Chave composta por codigo e estado, como no ERP original."""
    linhas = []
    for cod_reg, reg in p.REGIOES.items():
        for i in range(1, 19 if cod_reg == 1 else 13):
            linhas.append({
                "COD_CIDADE": i,
                "COD_ESTADO": reg["sigla"],
                "DES_CIDADE": f"Cidade {reg['sigla']}{i:02d}",
            })
    return pd.DataFrame(linhas)


# --------------------------------------------------------------- CADGRP
def gerar_grupos() -> pd.DataFrame:
    return pd.DataFrame([{"COD_GRPCLI": c, "DES_GRPCLI": d}
                         for c, d, _ in p.GRUPOS_CLIENTE])


# --------------------------------------------------------------- CADSUP / CADVEN
def gerar_supervisores() -> pd.DataFrame:
    linhas = []
    cod = 9000
    for cod_reg in p.REGIOES:
        for _ in range(p.N_SUPERVISORES_POR_REGIAO):
            linhas.append({"COD_SUPERVISOR": cod,
                           "NOM_COMPLETO": nome_pessoa(),
                           "_regiao": cod_reg})
            cod += 1
    return pd.DataFrame(linhas)


def gerar_vendedores(supervisores: pd.DataFrame) -> pd.DataFrame:
    """
    BLOQUEADO vem como codigo 0/1, sem descricao: a traducao e trabalho
    da view. Parte dos vendedores nao tem supervisor, o que da razao ao
    LEFT JOIN.
    """
    linhas = []
    cod = 1000
    for cod_reg in p.REGIOES:
        sups = supervisores.loc[supervisores["_regiao"] == cod_reg,
                                "COD_SUPERVISOR"].tolist()
        for _ in range(p.N_VENDEDORES_POR_REGIAO):
            sem_sup = rng.random() < p.PROP_VENDEDOR_SEM_SUPERVISOR
            linhas.append({
                "COD_VENDEDOR": cod,
                "NOM_GUERRA": nome_pessoa().split()[0].upper(),
                "BLOQUEADO": 1 if rng.random() < p.PROP_VENDEDOR_BLOQUEADO else 0,
                "COD_SUPERVISOR": np.nan if sem_sup else random.choice(sups),
                "_regiao": cod_reg,
            })
            cod += 1
    return pd.DataFrame(linhas)


# --------------------------------------------------------------- CADCLI
def gerar_clientes(cidades: pd.DataFrame) -> pd.DataFrame:
    """
    Cadastro bruto. Guarda codigos, nao descricoes: a cidade vem por
    codigo, o grupo por codigo, o status por 0/1. Nulos presentes de
    proposito para exercitar os LEFT JOIN e o ELSE dos CASE.
    """
    cods_reg = list(p.REGIOES.keys())
    p_reg = np.array([p.REGIOES[c]["peso"] for c in cods_reg], dtype=float)
    p_reg /= p_reg.sum()

    grupos = [(c, w) for c, _, w in p.GRUPOS_CLIENTE]
    hoje = date.today()
    inicio = hoje - timedelta(days=365 * 12)

    cid_por_uf = {r["sigla"]: cidades.loc[cidades["COD_ESTADO"] == r["sigla"],
                                          "COD_CIDADE"].tolist()
                  for r in p.REGIOES.values()}

    linhas = []
    for i in range(p.N_CLIENTES):
        reg = int(rng.choice(cods_reg, p=p_reg))
        uf = p.REGIOES[reg]["sigla"]

        # cidade orfa: codigo que nao existe em CADCID
        if rng.random() < p.PROP_CLIENTE_CIDADE_ORFA:
            cod_cidade = 999
        else:
            cod_cidade = random.choice(cid_por_uf[uf])

        if rng.random() < p.PROP_CLIENTE_STATUS_NULO:
            bloqueado = np.nan
        else:
            bloqueado = 1 if rng.random() < p.PROP_CLIENTE_BLOQUEADO else 0

        grupo = (np.nan if rng.random() < p.PROP_CLIENTE_SEM_GRUPO
                 else escolher(grupos))

        razao = nome_empresa(i)
        cadastro = datetime.combine(
            inicio + timedelta(days=int(rng.integers(0, 365 * 12))),
            datetime.min.time()) + timedelta(
                seconds=int(rng.integers(0, 86400)))

        linhas.append({
            "COD_CLI": 10000 + i,
            "CGC_CPF": gerar_cnpj(),
            "RAZ_SOCIAL": razao,
            "NOM_FANTASIA": " ".join(razao.split()[:2]),
            "COD_CIDADE": cod_cidade,
            "COD_ESTADO": uf,
            "BLOQUEADO": bloqueado,
            "DAT_CADASTRO": cadastro,
            "COD_GRPCLI": grupo,
            "_regiao": reg,
        })
    return pd.DataFrame(linhas)


# --------------------------------------------------------------- VINEST
def gerar_vinculos(clientes: pd.DataFrame, vendedores: pd.DataFrame) -> pd.DataFrame:
    """
    Vinculo comercial. Parte dos clientes nao tem registro aqui, o que
    obriga a view a usar LEFT JOIN e tratar o caso sem vinculo.
    """
    vend_reg = {r: vendedores.loc[(vendedores["_regiao"] == r)
                                  & (vendedores["BLOQUEADO"] == 0),
                                  "COD_VENDEDOR"].tolist()
                for r in p.REGIOES}
    linhas = []
    for _, c in clientes.iterrows():
        if rng.random() < p.PROP_CLIENTE_SEM_VINCULO:
            continue
        reg = int(c["_regiao"])
        linhas.append({
            "COD_CLIENT": c["COD_CLI"],
            "COD_ESTABE": reg,
            "COD_VENDEDOR": random.choice(vend_reg[reg]),
        })
        if rng.random() < p.PROP_CLIENTE_EM_DOIS_ESTAB:
            outra = 2 if reg == 1 else 1
            linhas.append({
                "COD_CLIENT": c["COD_CLI"],
                "COD_ESTABE": outra,
                "COD_VENDEDOR": random.choice(vend_reg[outra]),
            })
    return pd.DataFrame(linhas)


# --------------------------------------------------------------- funil
def definir_funil(clientes: pd.DataFrame) -> pd.DataFrame:
    n_plat = p.N_CLIENTES_PLATAFORMA
    n_prosp = int(n_plat * p.FUNIL["prospeccao"])
    n_cad = n_plat - n_prosp

    elegiveis = clientes[clientes["BLOQUEADO"] == 0]
    escolhidos = elegiveis.sample(n=n_cad, random_state=p.SEED)

    props = np.array([p.FUNIL["ativo"], p.FUNIL["ativacao"], p.FUNIL["integracao"]])
    props /= props.sum()
    n_ativo = int(n_cad * props[0])
    n_ativacao = int(n_cad * props[1])
    estados = (["ativo"] * n_ativo + ["ativacao"] * n_ativacao
               + ["integracao"] * (n_cad - n_ativo - n_ativacao))
    rng.shuffle(estados)

    plat = escolhidos[["COD_CLI", "CGC_CPF", "RAZ_SOCIAL", "COD_ESTADO"]].copy()
    plat["estado_funil"] = estados

    cods_reg = list(p.REGIOES.keys())
    p_reg = np.array([p.REGIOES[c]["peso"] for c in cods_reg], dtype=float)
    p_reg /= p_reg.sum()

    prosp = []
    for i in range(n_prosp):
        reg = int(rng.choice(cods_reg, p=p_reg))
        prosp.append({
            "COD_CLI": np.nan,
            "CGC_CPF": gerar_cnpj(),
            "RAZ_SOCIAL": nome_empresa(90000 + i),
            "COD_ESTADO": p.REGIOES[reg]["sigla"],
            "estado_funil": "prospeccao",
        })
    return pd.concat([plat, pd.DataFrame(prosp)], ignore_index=True)


def gerar_export_plataforma(plataforma: pd.DataFrame, cidades: pd.DataFrame):
    """Exportacao da plataforma: CNPJ com mascara, uma planilha por regiao."""
    df = plataforma.copy()
    df["Integração"] = np.where(
        df["estado_funil"].isin(["ativo", "ativacao"]), "Sim", "Não")
    df["Portal B2B"] = "Sim"
    df["CNPJ"] = df["CGC_CPF"].apply(formatar_cnpj)
    df["Município"] = [random.choice(
        cidades.loc[cidades["COD_ESTADO"] == uf, "DES_CIDADE"].tolist())
        for uf in df["COD_ESTADO"]]
    df = df.rename(columns={"RAZ_SOCIAL": "Nome", "COD_ESTADO": "UF"})
    cols = ["CNPJ", "Nome", "Município", "UF", "Portal B2B", "Integração"]
    return (df[df["UF"] == p.REGIOES[1]["sigla"]][cols],
            df[df["UF"] == p.REGIOES[2]["sigla"]][cols])


# --------------------------------------------------------------- MOVNFS
def gerar_notas(clientes: pd.DataFrame, vinculos: pd.DataFrame,
                plataforma: pd.DataFrame) -> pd.DataFrame:
    """
    Movimento bruto de notas. Inclui devolucao, bonificacao, transferencia,
    notas canceladas e notas sem data. A view de fato descarta tudo isso;
    a de ultima compra, no script original, nao descartava.
    """
    hoje = date.today().replace(day=1)
    inicio = hoje - timedelta(days=30 * p.MESES_HISTORICO)
    dias_hist = (hoje - inicio).days
    dias_fora = dias_hist - 30 * p.MESES_FATO

    ativos_canal = set(plataforma.loc[plataforma["estado_funil"] == "ativo", "CGC_CPF"])
    base = clientes[clientes["BLOQUEADO"] == 0].reset_index(drop=True)

    n = len(base)
    ordem = rng.permutation(n)
    n_nunca = int(n * p.PROP_CLIENTES_SEM_COMPRA_NENHUMA)
    n_dorm = int(n * p.PROP_CLIENTES_SEM_COMPRA_RECENTE)
    nunca = set(ordem[:n_nunca].tolist())
    dormentes = set(ordem[n_nunca:n_nunca + n_dorm].tolist())

    peso = rng.pareto(1.6, size=n) + 1
    peso[list(nunca)] = 0.0
    peso /= peso.sum()

    n_total = int(p.N_NOTAS_POR_ANO * p.MESES_HISTORICO / 12)
    idx = rng.choice(n, size=n_total, p=peso)
    offsets = rng.integers(0, dias_hist, size=n_total)
    offsets = np.where([j in dormentes for j in idx],
                       rng.integers(0, max(dias_fora, 1), size=n_total), offsets)
    valores = rng.lognormal(p.TICKET_MU, p.TICKET_SIGMA, size=n_total)
    sorteio = rng.random(n_total)

    vinc = vinculos.groupby("COD_CLIENT").first()
    cnpjs = base["CGC_CPF"].to_numpy()
    cods = base["COD_CLI"].to_numpy()
    regs = base["_regiao"].to_numpy()

    linhas = []
    for i in range(n_total):
        j = idx[i]
        d = inicio + timedelta(days=int(offsets[i]))
        emissao = datetime.combine(d, datetime.min.time()) + timedelta(
            seconds=int(rng.integers(28800, 72000)))

        chance = p.ADOCAO_INICIAL + (p.ADOCAO_FINAL - p.ADOCAO_INICIAL) * (
            offsets[i] / dias_hist)
        via_canal = (cnpjs[j] in ativos_canal) and (sorteio[i] < chance)

        cod_cli = int(cods[j])
        try:
            est = int(vinc.loc[cod_cli, "COD_ESTABE"])
            vend = int(vinc.loc[cod_cli, "COD_VENDEDOR"])
        except KeyError:
            est, vend = int(regs[j]), 1000

        tipo = "V" if via_canal else escolher(p.TIPOS_SAIDA)
        cancelada = rng.random() < p.PROP_NOTA_CANCELADA
        sem_data = rng.random() < p.PROP_NOTA_SEM_DATA

        linhas.append({
            "NUM_NOTA": 500000 + i,
            "DAT_EMISSAO": pd.NaT if sem_data else emissao,
            "COD_CLIENTE": cod_cli,
            "COD_ESTABE": est,
            "DES_LAYOUTPDE": (p.LAYOUT_CANAL if via_canal
                              else random.choice(p.LAYOUTS_OUTROS)),
            "VLR_TOTALNOTA": float(valores[i]),
            "COD_VENDEDOR": vend,
            "TIP_SAIDA": tipo,
            "DAT_CANCELAMENTO": (emissao + timedelta(days=int(rng.integers(1, 30)))
                                 if cancelada and not sem_data else pd.NaT),
        })

    notas = pd.DataFrame(linhas)
    _calibrar(notas, hoje)
    return notas.sort_values("NUM_NOTA").reset_index(drop=True)


def _calibrar(notas: pd.DataFrame, hoje: date) -> None:
    """
    Ajusta os valores para que o faturamento e a participacao do canal
    batam CONSIDERANDO SO AS NOTAS VALIDAS, que sao as que a view expoe.
    """
    valida = (notas["DAT_EMISSAO"].notna()
              & (notas["TIP_SAIDA"] == "V")
              & notas["DAT_CANCELAMENTO"].isna())
    canal = notas["DES_LAYOUTPDE"] == p.LAYOUT_CANAL

    c1 = pd.Timestamp(hoje - timedelta(days=365))
    c2 = pd.Timestamp(hoje - timedelta(days=730))
    aa = valida & (notas["DAT_EMISSAO"] >= c1)
    an = valida & (notas["DAT_EMISSAO"] >= c2) & (notas["DAT_EMISSAO"] < c1)

    fat_ant = p.FATURAMENTO_ANO_ATUAL / p.CRESCIMENTO_ANUAL
    for mask, alvo, part in [
            (aa, p.FATURAMENTO_ANO_ATUAL, p.PARTICIPACAO_CANAL_ANO_ATUAL),
            (an, fat_ant, p.PARTICIPACAO_CANAL_ANO_ANTERIOR)]:
        for grupo, destino in [(mask & canal, alvo * part),
                               (mask & ~canal, alvo * (1 - part))]:
            atual = notas.loc[grupo, "VLR_TOTALNOTA"].sum()
            if atual > 0:
                notas.loc[grupo, "VLR_TOTALNOTA"] *= destino / atual

    # demais notas: escala pelo fator medio, so para manter a ordem de grandeza
    resto = ~(aa | an)
    ref = notas.loc[an, "VLR_TOTALNOTA"].mean()
    atual = notas.loc[resto, "VLR_TOTALNOTA"].mean()
    if ref and atual:
        notas.loc[resto, "VLR_TOTALNOTA"] *= ref / atual


# --------------------------------------------------------------- saida
def escrever(df: pd.DataFrame, nome: str):
    """
    CSV com quebra de linha \\n fixa. Colunas inteiras que contem nulo sao
    convertidas para Int64 antes de gravar: sem isso o pandas as escreve
    como float e o BULK INSERT falha ao carregar em coluna INT.
    """
    os.makedirs(p.DIR_SAIDA, exist_ok=True)
    out = df[[c for c in df.columns if not c.startswith("_")]].copy()
    for col in out.columns:
        s = out[col]
        if s.dtype.kind == "f":
            validos = s.dropna()
            if len(validos) and (validos % 1 == 0).all():
                out[col] = s.astype("Int64")
    if "VLR_TOTALNOTA" in out.columns:
        out["VLR_TOTALNOTA"] = out["VLR_TOTALNOTA"].round(4)
    out.to_csv(os.path.join(p.DIR_SAIDA, nome), index=False,
               encoding="utf-8", lineterminator="\n")
    print(f"  {nome:24} {len(out):>8,} linhas")


def main():
    print("Gerando base bruta do ERP ficticio\n")

    cidades = gerar_cidades()
    grupos = gerar_grupos()
    supervisores = gerar_supervisores()
    vendedores = gerar_vendedores(supervisores)
    clientes = gerar_clientes(cidades)
    vinculos = gerar_vinculos(clientes, vendedores)
    plataforma = definir_funil(clientes)
    notas = gerar_notas(clientes, vinculos, plataforma)
    exp_m, exp_f = gerar_export_plataforma(plataforma, cidades)

    escrever(cidades, "CADCID.csv")
    escrever(grupos, "CADGRP.csv")
    escrever(supervisores, "CADSUP.csv")
    escrever(vendedores, "CADVEN.csv")
    escrever(clientes, "CADCLI.csv")
    escrever(vinculos, "VINEST.csv")
    escrever(notas, "MOVNFS.csv")
    for df, nome in [(exp_m, "portal_matriz.xlsx"), (exp_f, "portal_filial.xlsx")]:
        df.to_excel(os.path.join(p.DIR_SAIDA, nome), index=False,
                    sheet_name="Relatorio")
        print(f"  {nome:24} {len(df):>8,} linhas")

    # ---------------------------------------------------------- conferencia
    hoje = date.today().replace(day=1)
    valida = (notas["DAT_EMISSAO"].notna() & (notas["TIP_SAIDA"] == "V")
              & notas["DAT_CANCELAMENTO"].isna())
    canal = notas["DES_LAYOUTPDE"] == p.LAYOUT_CANAL
    c1 = pd.Timestamp(hoje - timedelta(days=365))
    c2 = pd.Timestamp(hoje - timedelta(days=730))

    print("\nFaturamento (so notas validas)")
    for rot, m in [("ano atual   ", valida & (notas.DAT_EMISSAO >= c1)),
                   ("ano anterior", valida & (notas.DAT_EMISSAO >= c2)
                    & (notas.DAT_EMISSAO < c1))]:
        t = notas.loc[m, "VLR_TOTALNOTA"].sum()
        c = notas.loc[m & canal, "VLR_TOTALNOTA"].sum()
        print(f"  {rot}  R$ {t:>14,.2f}   canal {c/t:>6.2%}")

    print("\nRuido que as views precisam tratar")
    print(f"  notas no total                {len(notas):>7,}")
    print(f"  notas validas                 {int(valida.sum()):>7,}"
          f"   ({valida.mean():.1%})")
    print(f"  sem data de emissao           {int(notas.DAT_EMISSAO.isna().sum()):>7,}")
    print(f"  canceladas                    {int(notas.DAT_CANCELAMENTO.notna().sum()):>7,}")
    print(f"  tipo diferente de venda       {int((notas.TIP_SAIDA != 'V').sum()):>7,}")
    print(f"  clientes sem grupo            {int(clientes.COD_GRPCLI.isna().sum()):>7,}")
    print(f"  clientes com status nulo      {int(clientes.BLOQUEADO.isna().sum()):>7,}")
    print(f"  clientes com cidade orfa      {int((clientes.COD_CIDADE == 999).sum()):>7,}")
    sem_vinc = p.N_CLIENTES - vinculos.COD_CLIENT.nunique()
    print(f"  clientes sem vinculo          {sem_vinc:>7,}")
    print(f"  vendedores sem supervisor     {int(vendedores.COD_SUPERVISOR.isna().sum()):>7,}")

    # impacto da inconsistencia do script original
    ult_todas = notas.dropna(subset=["DAT_EMISSAO"]).groupby(
        "COD_CLIENTE")["DAT_EMISSAO"].max()
    ult_validas = notas[valida].groupby("COD_CLIENTE")["DAT_EMISSAO"].max()
    juntos = pd.concat([ult_todas.rename("todas"),
                        ult_validas.rename("validas")], axis=1)
    difere = (juntos["todas"] != juntos["validas"]).sum()
    print(f"\n  clientes cuja ultima compra muda se o filtro de")
    print(f"  tipo e cancelamento for aplicado: {difere:,}")


if __name__ == "__main__":
    main()

from __future__ import annotations

from dataclasses import dataclass


AVISO = (
    "Leitura automática com a Selic do Banco Central e cotações públicas. "
    "Não entra no banco nem na corretora, não envia ordem e não promete que uma data de venda evita perda."
)


@dataclass
class Quote:
    ticker: str
    preco: float | None
    variacao_dia_percent: float | None
    dividend_yield_anual: float | None
    desconto_maxima_52s: float | None
    erro: str | None = None

    def as_dict(self) -> dict:
        return {
            "ticker": self.ticker,
            "preco": self.preco,
            "variacao_dia_percent": self.variacao_dia_percent,
            "dividend_yield_anual": self.dividend_yield_anual,
            "desconto_maxima_52s": self.desconto_maxima_52s,
            "erro": self.erro,
        }


@dataclass
class Caminho:
    nome: str
    tipo: str
    percentual: int
    hoje: float
    saldo: float
    meta: float
    data_alvo: str | None = None

    def as_dict(self) -> dict:
        return {
            "nome": self.nome,
            "tipo": self.tipo,
            "percentual": self.percentual,
            "hoje": self.hoje,
            "saldo": self.saldo,
            "meta": self.meta,
            "data_alvo": self.data_alvo,
        }


@dataclass
class Reading:
    selic_meta_anual: float | None
    selic_data: str | None
    aporte: float | None
    registrado: bool
    negocio: str
    cofre: str
    tipo_cofre: str
    falta_meta: float | None
    investidor: str
    caminhos: list[Caminho]
    sugestao_ticker: str | None
    sugestao_valor: float | None
    motivo: str
    aviso: str
    cotacoes: list[Quote]

    def as_dict(self) -> dict:
        return {
            "selic_meta_anual": self.selic_meta_anual,
            "selic_data": self.selic_data,
            "aporte": self.aporte,
            "registrado": self.registrado,
            "negocio": self.negocio,
            "cofre": self.cofre,
            "tipo_cofre": self.tipo_cofre,
            "falta_meta": self.falta_meta,
            "investidor": self.investidor,
            "caminhos": [caminho.as_dict() for caminho in self.caminhos],
            "sugestao_ticker": self.sugestao_ticker,
            "sugestao_valor": self.sugestao_valor,
            "motivo": self.motivo,
            "aviso": self.aviso,
            "cotacoes": [quote.as_dict() for quote in self.cotacoes],
        }


def build_reading(
    *,
    selic_meta_anual: float | None,
    selic_data: str | None,
    quotes: list[Quote],
    aporte: float | None = None,
    registrado: bool = False,
    negocio: str = "",
    cofre: str = "",
    tipo_cofre: str = "",
    falta_meta: float | None = None,
    investidor: str = "",
    caminhos: list[Caminho] | None = None,
) -> Reading:
    caminhos = caminhos or []
    usable = [quote for quote in quotes if quote.erro is None and quote.preco is not None]
    chosen = _pick(usable, selic_meta_anual)
    reserva_aberta = tipo_cofre == "emergency" and (falta_meta or 0) > 0
    valor = None if aporte is None else max(aporte, 0)

    if valor == 0 and registrado:
        ticker = None
        sugerido = 0.0
    elif reserva_aberta:
        ticker = None
        sugerido = None
    else:
        ticker = chosen.ticker if chosen else None
        sugerido = valor if ticker else None

    motivo = _motivo(
        selic=selic_meta_anual,
        selic_data=selic_data,
        chosen=chosen,
        aporte=valor,
        registrado=registrado,
        negocio=negocio,
        cofre=cofre,
        reserva_aberta=reserva_aberta,
        falta_meta=falta_meta,
        vazio=not usable,
        investidor=investidor.strip(),
        caminhos=caminhos,
        cotacoes=quotes,
    )
    return Reading(
        selic_meta_anual=selic_meta_anual,
        selic_data=selic_data,
        aporte=valor,
        registrado=registrado,
        negocio=negocio,
        cofre=cofre,
        tipo_cofre=tipo_cofre,
        falta_meta=falta_meta,
        investidor=investidor.strip(),
        caminhos=caminhos,
        sugestao_ticker=ticker,
        sugestao_valor=sugerido,
        motivo=motivo,
        aviso=AVISO,
        cotacoes=quotes,
    )


def telegram_text(reading: Reading) -> str:
    lines = ["EconoZar"]
    if reading.negocio:
        lines.append(reading.negocio)
    lines.append("")
    lines.append(reading.motivo)
    listed = [quote for quote in reading.cotacoes if quote.preco is not None][:6]
    if listed and not reading.caminhos:
        lines.append("")
        lines.append("Cesta:")
        for quote in listed:
            bits = [f"{_rotulo(quote.ticker)} {_brl(quote.preco)}"]
            if quote.variacao_dia_percent is not None:
                bits.append(f"{_pct(quote.variacao_dia_percent)} no dia")
            if quote.dividend_yield_anual is not None:
                bits.append(f"DY {_nivel(quote.dividend_yield_anual)}")
            lines.append(" · ".join(bits))
    lines.append("")
    lines.append(reading.aviso)
    return "\n".join(lines)


def _pick(quotes: list[Quote], selic: float | None) -> Quote | None:
    if not quotes:
        return None

    def score(quote: Quote) -> float:
        desconto = (quote.desconto_maxima_52s or 0) * 0.15
        dy = quote.dividend_yield_anual
        if dy is None or selic is None:
            return desconto - 100
        return (dy - selic) + desconto

    return max(quotes, key=score)


def _motivo_plano(
    *,
    selic: float | None,
    selic_data: str | None,
    chosen: Quote | None,
    registrado: bool,
    investidor: str,
    caminhos: list[Caminho],
    vazio: bool,
    cotacoes: list[Quote],
) -> str:
    nome = investidor.strip() or "Você"
    partes = [f"{nome}, isto é o que eu consigo ver do seu plano."]
    if selic is not None:
        quando = f" em {selic_data}" if selic_data else ""
        partes.append(
            f"A Selic meta está em {_nivel(selic)} ao ano{quando}. "
            "CDB de liquidez diária costuma pagar um percentual do CDI, e o CDI acompanha essa Selic. "
            "Eu não entro na conta do Banco Inter, então não vejo a taxa que o app do banco está mostrando."
        )
    else:
        partes.append("A Selic não respondeu agora, então não comparo a cesta com a taxa básica.")

    total = sum(max(caminho.hoje, 0) for caminho in caminhos)
    if registrado:
        partes.append(f"Hoje você separou {_brl(total)}.")
    else:
        partes.append(f"O plano de hoje soma {_brl(total)}. O check-in ainda não foi feito.")

    for caminho in caminhos:
        partes.append(_bloco_caminho(caminho, selic=selic, chosen=chosen, vazio=vazio, cotacoes=cotacoes))

    partes.append(
        "Eu não marco dia para vender achando que isso evita perda. "
        "A data que existe é a que você colocou na meta. "
        "No pregão eu só aviso se um papel da cesta andar bastante."
    )
    return "\n\n".join(partes)


def _bloco_caminho(
    caminho: Caminho,
    *,
    selic: float | None,
    chosen: Quote | None,
    vazio: bool,
    cotacoes: list[Quote],
) -> str:
    nome = caminho.nome or "Cofre"
    falta = max(caminho.meta - caminho.saldo, 0)
    cabeca = f"{nome} · {caminho.percentual}% · {_brl(caminho.hoje)} neste aporte"
    linhas = [cabeca, f"Saldo {_brl(caminho.saldo)}"]
    if caminho.meta > 0:
        linhas.append(f"Meta {_brl(caminho.meta)}. Falta {_brl(falta)}.")
    data = _data_br(caminho.data_alvo)
    if data:
        linhas.append(f"Data da meta: {data}.")

    if caminho.tipo == "furniture":
        linhas.append("Esse caminho fica guardado até a data. Não entra na cesta de ações.")
    elif caminho.tipo == "emergency":
        if caminho.meta > 0 and falta <= 0:
            linhas.append(
                "A reserva chegou na meta. No app, você pode reduzir o percentual dela "
                "e passar essa fatia para os móveis ou para investimentos."
            )
        else:
            linhas.append(
                "Enquanto a reserva não fecha, essa parte continua nela, em liquidez diária. "
                "A cesta de ações não usa esse dinheiro."
            )
    else:
        vivos = [quote for quote in cotacoes if quote.preco is not None]
        if vivos:
            precos = []
            for quote in vivos[:6]:
                dia = f" {_pct(quote.variacao_dia_percent)}" if quote.variacao_dia_percent is not None else ""
                precos.append(f"{_rotulo(quote.ticker)} {_brl(quote.preco)}{dia}")
            linhas.append("Sua cesta: " + " · ".join(precos) + ".")
        if caminho.hoje <= 0 and not tickers:
            linhas.append("Hoje não há valor neste caminho para apontar um papel.")
        elif vazio or chosen is None:
            linhas.append("Nenhuma cotação da cesta respondeu, então não aponto um papel.")
        else:
            linhas.append(_detalhe_escolha(chosen, selic))
            if caminho.hoje > 0:
                linhas.append(
                    f"Se for aplicar essa fatia, o valor é {_brl(caminho.hoje)} em {_rotulo(chosen.ticker)}. "
                    "A compra é na corretora. Eu não compro."
                )
    return "\n".join(linhas)


def _detalhe_escolha(chosen: Quote, selic: float | None) -> str:
    detalhe = [f"{_rotulo(chosen.ticker)} a {_brl(chosen.preco)}"]
    if chosen.variacao_dia_percent is not None:
        detalhe.append(f"{_pct(chosen.variacao_dia_percent)} no dia")
    if chosen.dividend_yield_anual is not None and selic is not None:
        detalhe.append(
            f"dividendos de 12 meses em {_nivel(chosen.dividend_yield_anual)}, contra Selic de {_nivel(selic)}"
        )
    elif chosen.dividend_yield_anual is not None:
        detalhe.append(f"dividendos de 12 meses em {_nivel(chosen.dividend_yield_anual)}")
    if chosen.desconto_maxima_52s is not None:
        detalhe.append(f"{_nivel(chosen.desconto_maxima_52s)} abaixo da máxima de 52 semanas")
    return (
        "Na cesta, a regra mecânica (dividendo frente à Selic e distância da máxima) aponta "
        + ", ".join(detalhe)
        + "."
    )


def _data_br(iso: str | None) -> str | None:
    if not iso:
        return None
    partes = iso[:10].split("-")
    if len(partes) != 3:
        return iso
    ano, mes, dia = partes
    if len(ano) != 4 or len(mes) != 2 or len(dia) != 2:
        return iso
    return f"{dia}/{mes}/{ano}"


def _motivo(
    *,
    selic: float | None,
    selic_data: str | None,
    chosen: Quote | None,
    aporte: float | None,
    registrado: bool,
    negocio: str,
    cofre: str,
    reserva_aberta: bool,
    falta_meta: float | None,
    vazio: bool,
    investidor: str,
    caminhos: list[Caminho],
    cotacoes: list[Quote] | None = None,
) -> str:
    if caminhos:
        return _motivo_plano(
            selic=selic,
            selic_data=selic_data,
            chosen=chosen,
            registrado=registrado,
            investidor=investidor,
            caminhos=caminhos,
            vazio=vazio,
            cotacoes=cotacoes or [],
        )

    partes: list[str] = []
    if selic is not None:
        quando = f" em {selic_data}" if selic_data else ""
        partes.append(f"A Selic meta está em {_nivel(selic)} ao ano{quando}.")
    else:
        partes.append("A Selic não respondeu agora.")

    if aporte is not None and cofre:
        estado = "registrado" if registrado else "ainda é o plano, sem check-in"
        partes.append(
            f"O aporte de {_brl(aporte)} ({estado}) fica no cofre {cofre}."
        )
    elif negocio:
        partes.append(f"Negócio: {negocio}.")

    if reserva_aberta:
        falta = _brl(falta_meta or 0)
        partes.append(
            f"A reserva de emergência ainda tem {falta} em aberto. "
            "Esse valor permanece na reserva. A cesta abaixo é só contexto."
        )
        return " ".join(partes)

    if aporte == 0 and registrado:
        partes.append("Dia zero: a sequência segue, e não há valor para apontar um ativo.")
        return " ".join(partes)

    if vazio or chosen is None:
        partes.append("Nenhuma cotação da cesta respondeu, então não há ativo apontado.")
        return " ".join(partes)

    detalhe = [f"{_rotulo(chosen.ticker)} a {_brl(chosen.preco)}"]
    if chosen.variacao_dia_percent is not None:
        detalhe.append(f"{_pct(chosen.variacao_dia_percent)} no dia")
    if chosen.dividend_yield_anual is not None and selic is not None:
        detalhe.append(
            f"dividendos de 12 meses em {_nivel(chosen.dividend_yield_anual)}, "
            f"contra Selic de {_nivel(selic)}"
        )
    elif chosen.dividend_yield_anual is not None:
        detalhe.append(f"dividendos de 12 meses em {_nivel(chosen.dividend_yield_anual)}")
    if chosen.desconto_maxima_52s is not None:
        detalhe.append(f"{_nivel(chosen.desconto_maxima_52s)} abaixo da máxima de 52 semanas")

    partes.append(
        "Na sua cesta, a regra mecânica (yield frente à Selic e distância da máxima) aponta "
        + ", ".join(detalhe)
        + "."
    )
    if aporte and aporte > 0:
        partes.append(
            f"Se for alocar esse aporte no mercado, o valor correspondente é {_brl(aporte)} em {_rotulo(chosen.ticker)}."
        )
    return " ".join(partes)


def _rotulo(ticker: str) -> str:
    return ticker.removesuffix(".SA")


def _brl(value: float | None) -> str:
    if value is None:
        return "R$ —"
    formatted = f"{value:,.2f}"
    formatted = formatted.replace(",", "X").replace(".", ",").replace("X", ".")
    return f"R$ {formatted}"


def _nivel(value: float) -> str:
    return f"{value:.2f}%".replace(".", ",")


def _pct(value: float) -> str:
    sign = "+" if value > 0 else ""
    return f"{sign}{value:.2f}%".replace(".", ",")

import asyncio
import time

from market_agent.analyze import Caminho, Quote, Reading, build_reading, telegram_text
from market_agent.counsel import counsel, montar_fatos, responder_chat
from market_agent.crypto import fetch_crypto
from market_agent.quotes import fetch_quotes, fetch_selic
from market_agent.session import pregao_aberto
from market_agent.settings import Settings
from market_agent.telegram import send_message


class MarketService:
    def __init__(self, settings: Settings):
        self.settings = settings
        self._quotes_at = 0.0
        self._selic_at = 0.0
        self._selic: tuple[float | None, str | None] = (None, None)
        self._quotes: list[Quote] = []
        self._alert_price: dict[str, float] = {}
        self._context: dict | None = None
        self._lock = asyncio.Lock()

    async def reading(
        self,
        *,
        aporte: float | None = None,
        registrado: bool = False,
        negocio: str = "",
        cofre: str = "",
        tipo_cofre: str = "",
        falta_meta: float | None = None,
        investidor: str = "",
        caminhos: list[Caminho] | None = None,
        entradas_mes: float = 0,
        saidas_mes: float = 0,
        gastos: list[dict] | None = None,
        dividas: list[dict] | None = None,
        conselheiro: bool = False,
        notificar: bool = False,
        force_quotes: bool = False,
    ) -> tuple[Reading, bool]:
        gastos = gastos or []
        dividas = dividas or []
        if caminhos:
            self._context = {
                "aporte": aporte,
                "registrado": registrado,
                "negocio": negocio,
                "cofre": cofre,
                "tipo_cofre": tipo_cofre,
                "falta_meta": falta_meta,
                "investidor": investidor,
                "caminhos": caminhos,
                "entradas_mes": entradas_mes,
                "saidas_mes": saidas_mes,
                "gastos": gastos,
                "dividas": dividas,
            }
        elif self._context is not None and aporte is None and not cofre:
            ctx = self._context
            aporte = ctx["aporte"]
            registrado = ctx["registrado"]
            negocio = ctx["negocio"]
            cofre = ctx["cofre"]
            tipo_cofre = ctx["tipo_cofre"]
            falta_meta = ctx["falta_meta"]
            investidor = ctx["investidor"]
            caminhos = ctx["caminhos"]
            entradas_mes = ctx["entradas_mes"]
            saidas_mes = ctx["saidas_mes"]
            gastos = ctx["gastos"]
            dividas = ctx["dividas"]

        selic, selic_data, quotes = await self._snapshot(force_quotes=force_quotes)
        reading = build_reading(
            selic_meta_anual=selic,
            selic_data=selic_data,
            quotes=quotes,
            aporte=aporte,
            registrado=registrado,
            negocio=negocio,
            cofre=cofre,
            tipo_cofre=tipo_cofre,
            falta_meta=falta_meta,
            investidor=investidor,
            caminhos=caminhos,
        )
        cripto = await asyncio.to_thread(fetch_crypto, self.settings.crypto_list())
        if conselheiro or notificar:
            texto = counsel(
                montar_fatos(
                    investidor=investidor,
                    negocio=negocio,
                    selic=reading.selic_meta_anual,
                    plano=reading.motivo,
                    entradas=entradas_mes,
                    saidas=saidas_mes,
                    gastos=gastos,
                    dividas=dividas,
                    cripto=cripto,
                    cesta=_cesta(reading),
                ),
                self.settings,
            )
            if texto:
                reading.motivo = texto
            else:
                reading.motivo = _com_cripto(reading.motivo, cripto)
        else:
            reading.motivo = _com_cripto(reading.motivo, cripto)
        sent = False
        if notificar:
            sent = await send_message(telegram_text(reading), self.settings)
        return reading, sent

    async def chat(
        self,
        *,
        mensagem: str,
        historico: list[dict],
        investidor: str,
        negocio: str,
        caminhos: list[Caminho],
        entradas_mes: float,
        saidas_mes: float,
        gastos: list[dict],
        dividas: list[dict],
    ) -> dict:
        aporte = sum(max(item.hoje, 0) for item in caminhos if item.tipo == "free")
        reading, _ = await self.reading(
            aporte=aporte,
            registrado=True,
            negocio=negocio,
            cofre=", ".join(item.nome for item in caminhos if item.tipo == "free") or "Projetos Futuros",
            tipo_cofre="free" if aporte > 0 else "furniture",
            investidor=investidor,
            caminhos=caminhos,
            entradas_mes=entradas_mes,
            saidas_mes=saidas_mes,
            gastos=gastos,
            dividas=dividas,
            conselheiro=False,
            notificar=False,
        )
        cripto = await asyncio.to_thread(fetch_crypto, self.settings.crypto_list())
        return responder_chat(
            mensagem=mensagem,
            historico=historico,
            investidor=investidor,
            negocio=negocio,
            selic=reading.selic_meta_anual,
            plano=reading.motivo,
            entradas=entradas_mes,
            saidas=saidas_mes,
            gastos=gastos,
            dividas=dividas,
            cripto=cripto,
            cesta=_cesta(reading),
            reading=reading,
            caminhos=caminhos,
            settings=self.settings,
        )

    async def watch_session(self) -> int:
        """Busca cotações no pregão e avisa só quando o preço anda além do limite."""
        if not pregao_aberto():
            return 0
        _, _, quotes = await self._snapshot(force_quotes=True)
        movimentos = self._movimentos(quotes)
        if not movimentos:
            return 0
        nome = ""
        if self._context:
            nome = str(self._context.get("investidor") or "")
        await send_message(_texto_pregao(movimentos, nome), self.settings)
        return len(movimentos)

    def _movimentos(self, quotes: list[Quote]) -> list[str]:
        limite = self.settings.alert_move_percent
        linhas: list[str] = []
        for quote in quotes:
            if quote.preco is None:
                continue
            anterior = self._alert_price.get(quote.ticker)
            if anterior in (None, 0):
                self._alert_price[quote.ticker] = quote.preco
                continue
            delta = (quote.preco - anterior) / anterior * 100
            if abs(delta) < limite:
                continue
            self._alert_price[quote.ticker] = quote.preco
            dia = ""
            if quote.variacao_dia_percent is not None:
                dia = f" · {_pct(quote.variacao_dia_percent)} no dia"
            linhas.append(
                f"{quote.ticker.removesuffix('.SA')} {_brl(quote.preco)}{dia} · {_pct(delta)} desde o último aviso"
            )
        return linhas

    async def _snapshot(self, *, force_quotes: bool = False):
        async with self._lock:
            now = time.time()
            need_selic = self._selic[0] is None or now - self._selic_at >= self.settings.cache_seconds
            need_quotes = force_quotes or not self._quotes or now - self._quotes_at >= self.settings.cache_seconds
            if need_selic or need_quotes:
                tasks = []
                if need_selic:
                    tasks.append(asyncio.to_thread(fetch_selic))
                if need_quotes:
                    tasks.append(asyncio.to_thread(fetch_quotes, self.settings.ticker_list()))
                results = await asyncio.gather(*tasks)
                cursor = 0
                if need_selic:
                    self._selic = results[cursor]
                    self._selic_at = now
                    cursor += 1
                if need_quotes:
                    self._quotes = results[cursor]
                    self._quotes_at = now
            return self._selic[0], self._selic[1], self._quotes


def _cesta(reading: Reading) -> str:
    vivos = [quote for quote in reading.cotacoes if quote.preco is not None][:6]
    if not vivos:
        return "Cesta sem cotação agora."
    partes = []
    for quote in vivos:
        rotulo = quote.ticker.removesuffix(".SA")
        partes.append(f"{rotulo} {_brl(quote.preco)}")
    if reading.sugestao_ticker:
        partes.append(f"Regra da cesta aponta {reading.sugestao_ticker.removesuffix('.SA')}.")
    return " · ".join(partes)


def _com_cripto(motivo: str, cripto: list[dict]) -> str:
    vivos = [item for item in cripto if item.get("preco") is not None]
    if not vivos:
        return motivo
    linhas = ["Mercado Bitcoin, cotação pública:"]
    for item in vivos:
        linhas.append(f"{item['par']} {_brl(item['preco'])}")
    linhas.append("Bitcoin e Ethereum só cabem na fatia de investimentos. Móveis e reserva seguem no CDB DI.")
    return motivo + "\n\n" + "\n".join(linhas)


def _texto_pregao(linhas: list[str], nome: str) -> str:
    corpo = "\n".join(linhas)
    cabeca = f"{nome}, movimento na sua cesta." if nome else "EconoZar · movimento na cesta"
    return (
        f"{cabeca}\n"
        f"{corpo}\n\n"
        "Cotação pública durante o pregão. Pode atrasar em relação à B3. "
        "Não é ordem de compra nem de venda."
    )


def _brl(value: float) -> str:
    formatted = f"{value:,.2f}".replace(",", "X").replace(".", ",").replace("X", ".")
    return f"R$ {formatted}"


def _pct(value: float) -> str:
    sign = "+" if value > 0 else ""
    return f"{sign}{value:.2f}%".replace(".", ",")


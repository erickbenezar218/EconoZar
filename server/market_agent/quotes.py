import logging
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta

import httpx
import yfinance as yf

from market_agent.analyze import Quote

log = logging.getLogger("econozar.market")
BCB_SELIC_META = "https://api.bcb.gov.br/dados/serie/bcdata.sgs.432/dados/ultimos/1?formato=json"


def fetch_selic() -> tuple[float | None, str | None]:
    try:
        with httpx.Client(timeout=20, headers={"User-Agent": "EconoZarMarketAgent/1.0"}) as client:
            response = client.get(BCB_SELIC_META)
            response.raise_for_status()
            payload = response.json()
        if not payload:
            return None, None
        row = payload[-1]
        valor = float(str(row["valor"]).replace(",", "."))
        return valor, str(row.get("data") or "")
    except Exception:
        log.exception("Falha ao consultar a Selic")
        return None, None


def fetch_quotes(tickers: list[str]) -> list[Quote]:
    if not tickers:
        return []
    workers = min(4, len(tickers))
    with ThreadPoolExecutor(max_workers=workers) as pool:
        return list(pool.map(_one, tickers))


def _one(ticker: str) -> Quote:
    try:
        instrument = yf.Ticker(ticker)
        fast = instrument.fast_info
        price = _float(getattr(fast, "last_price", None))
        previous = _float(getattr(fast, "previous_close", None))
        high = _float(getattr(fast, "year_high", None))
        change = None
        if price is not None and previous not in (None, 0):
            change = (price - previous) / previous * 100
        discount = None
        if price is not None and high not in (None, 0) and high >= price:
            discount = (high - price) / high * 100
        try:
            dividend_yield = _trailing_yield(instrument, price)
        except Exception:
            log.exception("Falha no dividend yield de %s", ticker)
            dividend_yield = None
        if price is None:
            return Quote(ticker, None, None, None, None, "sem preço")
        return Quote(ticker, price, change, dividend_yield, discount, None)
    except Exception as error:
        log.exception("Falha na cotação de %s", ticker)
        return Quote(ticker, None, None, None, None, str(error))


def _trailing_yield(instrument, price: float | None) -> float | None:
    if price is None or price <= 0:
        return None
    dividends = instrument.dividends
    if dividends is None or len(dividends) == 0:
        return None
    index = dividends.index
    if getattr(index, "tz", None) is not None:
        dividends = dividends.copy()
        dividends.index = index.tz_convert(None)
    cutoff = datetime.now() - timedelta(days=365)
    recent = dividends[dividends.index >= cutoff]
    total = float(recent.sum()) if len(recent) else 0.0
    if total <= 0:
        return None
    return total / price * 100


def _float(value) -> float | None:
    if value is None:
        return None
    try:
        number = float(value)
    except (TypeError, ValueError):
        return None
    if number != number:
        return None
    return number

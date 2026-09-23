import asyncio
import time

from market_agent.analyze import Reading, build_reading, telegram_text
from market_agent.quotes import fetch_quotes, fetch_selic
from market_agent.settings import Settings
from market_agent.telegram import send_message


class MarketService:
    def __init__(self, settings: Settings):
        self.settings = settings
        self._saved_at = 0.0
        self._selic: tuple[float | None, str | None] = (None, None)
        self._quotes = []
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
        notificar: bool = False,
    ) -> tuple[Reading, bool]:
        selic, selic_data, quotes = await self._snapshot()
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
        )
        sent = False
        if notificar:
            sent = await send_message(telegram_text(reading), self.settings)
        return reading, sent

    async def _snapshot(self):
        async with self._lock:
            fresh = time.time() - self._saved_at < self.settings.cache_seconds
            if fresh and (self._quotes or self._selic[0] is not None):
                return self._selic[0], self._selic[1], self._quotes
            tickers = self.settings.ticker_list()
            selic, quotes = await asyncio.gather(
                asyncio.to_thread(fetch_selic),
                asyncio.to_thread(fetch_quotes, tickers),
            )
            self._selic = selic
            self._quotes = quotes
            self._saved_at = time.time()
            return selic[0], selic[1], quotes

import logging
from contextlib import asynccontextmanager

from apscheduler.schedulers.asyncio import AsyncIOScheduler
from apscheduler.triggers.cron import CronTrigger
from fastapi import Depends, FastAPI, Header, HTTPException
from pydantic import BaseModel

from market_agent.service import MarketService
from market_agent.settings import Settings

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s %(message)s")
log = logging.getLogger("econozar.api")

settings = Settings()
service = MarketService(settings)
scheduler = AsyncIOScheduler(timezone="America/Sao_Paulo")


class LeituraIn(BaseModel):
    aporte: float = 0
    registrado: bool = False
    negocio: str = ""
    cofre: str = ""
    tipo_cofre: str = ""
    falta_meta: float = 0
    notificar: bool = False


def require_key(x_api_key: str = Header(default="")) -> None:
    expected = settings.api_key.strip()
    if not expected or x_api_key != expected:
        raise HTTPException(status_code=401, detail="Chave da API inválida.")


@asynccontextmanager
async def lifespan(_: FastAPI):
    scheduler.add_job(
        _digest,
        CronTrigger(hour=settings.digest_hour, minute=settings.digest_minute),
        id="digest",
        replace_existing=True,
    )
    scheduler.start()
    log.info(
        "Resumo diário às %02d:%02d (America/Sao_Paulo), %d tickers.",
        settings.digest_hour,
        settings.digest_minute,
        len(settings.ticker_list()),
    )
    yield
    scheduler.shutdown(wait=False)


app = FastAPI(title="EconoZar Market", version="1.0.0", lifespan=lifespan)


@app.get("/health")
def health() -> dict:
    return {"status": "ok"}


@app.get("/v1/market", dependencies=[Depends(require_key)])
async def market() -> dict:
    reading, _ = await service.reading()
    payload = reading.as_dict()
    payload["telegram_enviado"] = False
    payload["gerado_em"] = _now()
    return payload


@app.post("/v1/leitura", dependencies=[Depends(require_key)])
async def leitura(body: LeituraIn) -> dict:
    reading, sent = await service.reading(
        aporte=body.aporte,
        registrado=body.registrado,
        negocio=body.negocio.strip(),
        cofre=body.cofre.strip(),
        tipo_cofre=body.tipo_cofre.strip(),
        falta_meta=body.falta_meta,
        notificar=body.notificar,
    )
    payload = reading.as_dict()
    payload["telegram_enviado"] = sent
    payload["gerado_em"] = _now()
    return payload


async def _digest() -> None:
    reading, sent = await service.reading(notificar=True)
    log.info("Resumo diário enviado=%s ticker=%s", sent, reading.sugestao_ticker)


def _now() -> str:
    from datetime import datetime
    from zoneinfo import ZoneInfo

    return datetime.now(ZoneInfo("America/Sao_Paulo")).isoformat(timespec="seconds")

import logging
from contextlib import asynccontextmanager

from apscheduler.schedulers.asyncio import AsyncIOScheduler
from apscheduler.triggers.cron import CronTrigger
from fastapi import Depends, FastAPI, Header, HTTPException
from pydantic import BaseModel

from market_agent.analyze import Caminho
from market_agent.service import MarketService
from market_agent.session import pregao_aberto
from market_agent.settings import Settings

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s %(message)s")
log = logging.getLogger("econozar.api")

settings = Settings()
service = MarketService(settings)
scheduler = AsyncIOScheduler(timezone="America/Sao_Paulo")


class CaminhoIn(BaseModel):
    nome: str = ""
    tipo: str = ""
    percentual: int = 0
    hoje: float = 0
    saldo: float = 0
    meta: float = 0
    data_alvo: str | None = None


class GastoIn(BaseModel):
    nome: str = ""
    valor: float = 0


class DividaIn(BaseModel):
    nome: str = ""
    saldo: float = 0
    parcela: float = 0
    dia: int = 1


class HistoricoIn(BaseModel):
    papel: str = "user"
    texto: str = ""


class ChatIn(BaseModel):
    mensagem: str = ""
    historico: list[HistoricoIn] = []
    investidor: str = ""
    negocio: str = ""
    caminhos: list[CaminhoIn] = []
    entradas_mes: float = 0
    saidas_mes: float = 0
    gastos: list[GastoIn] = []
    dividas: list[DividaIn] = []


class LeituraIn(BaseModel):
    aporte: float = 0
    registrado: bool = False
    negocio: str = ""
    cofre: str = ""
    tipo_cofre: str = ""
    falta_meta: float = 0
    investidor: str = ""
    caminhos: list[CaminhoIn] = []
    entradas_mes: float = 0
    saidas_mes: float = 0
    gastos: list[GastoIn] = []
    dividas: list[DividaIn] = []
    conselheiro: bool = False
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
    scheduler.add_job(
        _pregao,
        "interval",
        seconds=max(settings.session_poll_seconds, 30),
        id="pregao",
        replace_existing=True,
        max_instances=1,
        coalesce=True,
    )
    scheduler.start()
    log.info(
        "Resumo diário às %02d:%02d. Pregão a cada %ss, alerta a partir de %s%%.",
        settings.digest_hour,
        settings.digest_minute,
        max(settings.session_poll_seconds, 30),
        settings.alert_move_percent,
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
    payload["pregao_aberto"] = pregao_aberto()
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
        investidor=body.investidor.strip(),
        caminhos=[Caminho(**item.model_dump()) for item in body.caminhos],
        entradas_mes=body.entradas_mes,
        saidas_mes=body.saidas_mes,
        gastos=[item.model_dump() for item in body.gastos],
        dividas=[item.model_dump() for item in body.dividas],
        conselheiro=body.conselheiro,
        notificar=body.notificar,
    )
    payload = reading.as_dict()
    payload["telegram_enviado"] = sent
    payload["pregao_aberto"] = pregao_aberto()
    payload["gerado_em"] = _now()
    return payload


@app.post("/v1/chat", dependencies=[Depends(require_key)])
async def chat(body: ChatIn) -> dict:
    return await service.chat(
        mensagem=body.mensagem.strip(),
        historico=[item.model_dump() for item in body.historico],
        investidor=body.investidor.strip(),
        negocio=body.negocio.strip(),
        caminhos=[Caminho(**item.model_dump()) for item in body.caminhos],
        entradas_mes=body.entradas_mes,
        saidas_mes=body.saidas_mes,
        gastos=[item.model_dump() for item in body.gastos],
        dividas=[item.model_dump() for item in body.dividas],
    )


async def _digest() -> None:
    reading, sent = await service.reading(notificar=True)
    log.info("Resumo diário enviado=%s ticker=%s", sent, reading.sugestao_ticker)


async def _pregao() -> None:
    avisos = await service.watch_session()
    if avisos:
        log.info("Pregão: %s aviso(s) enviado(s).", avisos)


def _now() -> str:
    from datetime import datetime
    from zoneinfo import ZoneInfo

    return datetime.now(ZoneInfo("America/Sao_Paulo")).isoformat(timespec="seconds")

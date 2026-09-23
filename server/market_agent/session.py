from __future__ import annotations

from datetime import datetime, time
from zoneinfo import ZoneInfo

BRASILIA = ZoneInfo("America/Sao_Paulo")


def agora() -> datetime:
    return datetime.now(BRASILIA)


def pregao_aberto(
    momento: datetime | None = None,
    inicio: time = time(10, 0),
    fim: time = time(17, 0),
) -> bool:
    """Pregão à vista da B3: dias úteis, 10h até o call de fechamento (17h)."""
    momento = momento or agora()
    if momento.weekday() >= 5:
        return False
    atual = momento.timetz().replace(tzinfo=None)
    return inicio <= atual < fim

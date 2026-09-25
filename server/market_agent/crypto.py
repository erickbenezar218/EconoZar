from __future__ import annotations

import logging

import httpx

log = logging.getLogger("econozar.crypto")
TICKERS_URL = "https://api.mercadobitcoin.net/api/v4/tickers"


def fetch_crypto(symbols: list[str]) -> list[dict]:
    clean = [item.strip().upper() for item in symbols if item.strip()]
    if not clean:
        return []
    try:
        with httpx.Client(timeout=20, headers={"User-Agent": "EconoZarMarketAgent/1.0"}) as client:
            response = client.get(TICKERS_URL, params={"symbols": ",".join(clean)})
            response.raise_for_status()
            payload = response.json()
    except Exception:
        log.exception("Falha ao consultar o Mercado Bitcoin")
        return []

    if isinstance(payload, list):
        rows = payload
    elif isinstance(payload, dict):
        rows = payload.get("tickers") or payload.get("data") or []
    else:
        rows = []
    saida: list[dict] = []
    for row in rows:
        if not isinstance(row, dict):
            continue
        last = _numero(row.get("last"))
        aberto = _numero(row.get("open"))
        variacao = None
        if last is not None and aberto not in (None, 0):
            variacao = (last - aberto) / aberto * 100
        saida.append(
            {
                "par": str(row.get("pair") or ""),
                "preco": last,
                "variacao_percent": variacao,
            }
        )
    return saida


def _numero(value) -> float | None:
    if value in (None, ""):
        return None
    try:
        return float(str(value).replace(",", "."))
    except ValueError:
        return None

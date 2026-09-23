from __future__ import annotations

import logging

import httpx

from market_agent.settings import Settings

log = logging.getLogger("econozar.counsel")

SISTEMA = """Você é o conselheiro do EconoZar. Fale em português, direto, pelo nome da pessoa.
Use somente os fatos recebidos. Não invente taxa, preço, data, saldo ou gasto.
Regras fixas:
- Móveis e reserva ficam em CDB DI de 100% do CDI, liquidez diária, no banco. Esse dinheiro não vai para ação nem para cripto.
- Só a fatia do cofre de investimentos pode ir para a cesta de ações ou para Bitcoin e Ethereum.
- Cripto vem da cotação pública do Mercado Bitcoin. Diga o preço. Não diga que uma moeda vai deixar a pessoa rica. Diga que o preço sobe e desce, e que a compra é feita pela própria pessoa na corretora.
- Se as saídas do mês passarem das entradas, cite os maiores gastos e diga para cortar esses antes de aumentar o aporte.
- Se houver dívida, cite saldo e parcela. A parcela vem antes de aumentar a fatia de investimentos.
- Feche com um único passo para hoje.
- Não prometa lucro. Não envie ordem de compra nem de venda.
- No máximo 900 caracteres."""


def montar_fatos(
    *,
    investidor: str,
    negocio: str,
    selic: float | None,
    plano: str,
    entradas: float,
    saidas: float,
    gastos: list[dict],
    dividas: list[dict],
    cripto: list[dict],
    cesta: str,
) -> str:
    linhas = [
        f"Nome: {investidor or 'Erick'}",
        f"Negócio: {negocio or 'não informado'}",
        f"Selic meta anual: {selic if selic is not None else 'indisponível'}",
        f"Entradas do mês: {entradas:.2f}",
        f"Saídas do mês: {saidas:.2f}",
        "Maiores gastos: " + (", ".join(f"{item.get('nome')} {item.get('valor')}" for item in gastos) or "nenhum"),
        "Dívidas: " + (
            ", ".join(
                f"{item.get('nome')} saldo {item.get('saldo')} parcela {item.get('parcela')} dia {item.get('dia')}"
                for item in dividas
            )
            or "nenhuma"
        ),
        "Cripto Mercado Bitcoin: " + (
            ", ".join(
                f"{item.get('par')} {item.get('preco')}"
                for item in cripto
                if item.get("preco") is not None
            )
            or "cotação indisponível"
        ),
        "Plano e cesta:",
        plano,
        cesta,
    ]
    return "\n".join(linhas)


def counsel(facts: str, settings: Settings) -> str | None:
    key = settings.gemini_api_key.strip()
    if not key or not facts.strip():
        return None
    url = (
        "https://generativelanguage.googleapis.com/v1beta/models/"
        f"{settings.gemini_model.strip() or 'gemini-2.5-flash'}:generateContent"
    )
    body = {
        "systemInstruction": {"parts": [{"text": SISTEMA}]},
        "contents": [{"role": "user", "parts": [{"text": facts}]}],
        "generationConfig": {"temperature": 0.3, "maxOutputTokens": 700},
    }
    try:
        with httpx.Client(timeout=40) as client:
            response = client.post(url, headers={"x-goog-api-key": key}, json=body)
            response.raise_for_status()
            payload = response.json()
        parts = payload["candidates"][0]["content"]["parts"]
        text = "\n".join(part.get("text", "") for part in parts).strip()
        return text or None
    except Exception:
        log.exception("Falha ao consultar o Gemini")
        return None

from __future__ import annotations

import json
import logging
from pathlib import Path

import httpx

from market_agent.analyze import Reading
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


CHAT_SISTEMA = """Você é o consultor de investimentos do EconoZar. Fale em português, pelo nome, em tom de conversa.
Use somente os fatos e a memória recebidos. Não invente taxa, preço ou saldo.
Responda a pergunta atual primeiro.
Regras:
- Se perguntarem quanto está guardado, liste cada cofre com saldo e meta, e feche com o total. Use o bloco Cofres.
- Reserva de Emergência e Móveis Planejados não se mexem. Nunca sugira tirar dinheiro desses cofres.
- Só a fatia de Projetos Futuros, tipo free, pode ser comparada com um ativo.
- O card de sugestão já foi calculado pelo sistema. Se houver sugestão validada, explique esse ativo e pergunte "O que acha?".
- Se não houver sugestão validada, diga que o cofrinho segue melhor e não invente outra compra.
- O usuário precisa aprovar. Você não compra e não envia ordem.
- Não prometa lucro.
- No máximo 700 caracteres."""

MEMORIA_PATH = Path("/app/data/consultor-memoria.json")


def responder_chat(
    *,
    mensagem: str,
    historico: list[dict],
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
    reading: Reading,
    caminhos: list,
    settings: Settings,
) -> dict:
    livres = [item for item in caminhos if getattr(item, "tipo", "") == "free"]
    saldo = sum(max(getattr(item, "saldo", 0) or 0, 0) for item in livres)
    nome_cofre = livres[0].nome if livres and livres[0].nome else "Projetos Futuros"
    sugestao = _proposta(reading, saldo, nome_cofre)
    fatos = montar_fatos(
        investidor=investidor,
        negocio=negocio,
        selic=selic,
        plano=plano,
        entradas=entradas,
        saidas=saidas,
        gastos=gastos,
        dividas=dividas,
        cripto=cripto,
        cesta=cesta,
    )
    bloco = (
        f"{fatos}\n\nCofres:\n{_linhas_cofres(caminhos)}\n\nSugestão validada pelo sistema: "
        f"{json.dumps(sugestao, ensure_ascii=False) if sugestao else 'nenhuma'}\n\n"
        f"Memória recente:\n{_memoria_texto()}\n\nPergunta atual: {mensagem.strip() or 'Olhe meu plano e diga o passo de hoje.'}"
    )
    if _pergunta_saldo(mensagem):
        texto = _texto_local(investidor or "Erick", saldo, nome_cofre, None, selic, caminhos, mensagem)
        sugestao = None
    else:
        texto = _gerar_chat(bloco, historico, settings) or _texto_local(
            investidor or "Erick", saldo, nome_cofre, sugestao, selic, caminhos, mensagem
        )
    _gravar_memoria(mensagem, texto)
    return {"texto": texto, "sugestao": sugestao}


def _proposta(reading: Reading, saldo: float, nome_cofre: str) -> dict | None:
    selic = reading.selic_meta_anual
    if saldo <= 0 or selic is None:
        return None
    candidatos = [
        quote
        for quote in reading.cotacoes
        if quote.preco is not None
        and quote.dividend_yield_anual is not None
        and quote.dividend_yield_anual > selic
    ]
    if not candidatos:
        return None
    escolhido = max(candidatos, key=lambda quote: quote.dividend_yield_anual or 0)
    dy = escolhido.dividend_yield_anual or 0
    ativo = escolhido.ticker.removesuffix(".SA")
    return {
        "valor": round(saldo, 2),
        "ativo": ativo,
        "cofre": nome_cofre,
        "rendimento_cofre": f"Cofrinho em liquidez diária, perto de 100% do CDI. Selic meta {_nivel(selic)} a.a.",
        "estimativa_ativo": (
            f"{ativo} a {_brl(escolhido.preco)}, dividendos de 12 meses em {_nivel(dy)}, acima da Selic."
        ),
    }


def _linhas_cofres(caminhos: list) -> str:
    if not caminhos:
        return "nenhum cofre informado"
    linhas = []
    total = 0.0
    for item in caminhos:
        saldo = float(getattr(item, "saldo", 0) or 0)
        meta = float(getattr(item, "meta", 0) or 0)
        nome = getattr(item, "nome", "") or "Cofre"
        total += saldo
        linhas.append(f"{nome}: saldo {_brl(saldo)}, meta {_brl(meta)}")
    linhas.append(f"Total guardado: {_brl(total)}")
    return "\n".join(linhas)


def _texto_local(
    nome: str,
    saldo: float,
    cofre: str,
    sugestao: dict | None,
    selic: float | None,
    caminhos: list,
    mensagem: str = "",
) -> str:
    guardado = _linhas_cofres(caminhos).replace("\n", ". ")
    if _pergunta_saldo(mensagem):
        return f"{nome}, você tem isto guardado. {guardado}."
    if sugestao:
        return (
            f"{nome}, você tem isto guardado. {guardado}. "
            f"Na fatia de {cofre} há {_brl(saldo)}. {sugestao['estimativa_ativo']} "
            f"Sugiro tirar {_brl(sugestao['valor'])} só desse cofre e registrar a compra de {sugestao['ativo']}. "
            "O que acha?"
        )
    selic_txt = _nivel(selic) if selic is not None else "indisponível"
    return (
        f"{nome}, você tem isto guardado. {guardado}. "
        f"Nenhum papel da cesta mostra dividendo de 12 meses acima da Selic de {selic_txt}. "
        f"A fatia de {cofre} segue no cofrinho. Reserva e móveis permanecem nos cofres deles."
    )


def _pergunta_saldo(mensagem: str) -> bool:
    texto = mensagem.lower()
    chaves = ("quanto", "guardado", "saldo", "tenho", "reserva", "móvel", "movel", "móveis", "moveis", "cofre")
    return any(chave in texto for chave in chaves)


def _gerar_chat(facts: str, historico: list[dict], settings: Settings) -> str | None:
    key = settings.gemini_api_key.strip()
    if not key:
        return None
    contents = []
    for item in historico[-8:]:
        papel = "model" if item.get("papel") == "assistant" else "user"
        texto = str(item.get("texto") or "").strip()
        if texto:
            contents.append({"role": papel, "parts": [{"text": texto}]})
    contents.append({"role": "user", "parts": [{"text": facts}]})
    url = (
        "https://generativelanguage.googleapis.com/v1beta/models/"
        f"{settings.gemini_model.strip() or 'gemini-2.5-flash'}:generateContent"
    )
    body = {
        "systemInstruction": {"parts": [{"text": CHAT_SISTEMA}]},
        "contents": _alternar_papeis(contents),
        "generationConfig": {
            "temperature": 0.4,
            "maxOutputTokens": 1024,
            "thinkingConfig": {"thinkingBudget": 0},
        },
    }
    try:
        with httpx.Client(timeout=40) as client:
            response = client.post(url, headers={"x-goog-api-key": key}, json=body)
            response.raise_for_status()
            payload = response.json()
        return _extrair_texto(payload)
    except Exception:
        log.exception("Falha no chat do Gemini")
        return None


def _alternar_papeis(contents: list[dict]) -> list[dict]:
    saida: list[dict] = []
    for item in contents:
        if saida and saida[-1]["role"] == item["role"]:
            anterior = saida[-1]["parts"][0]["text"]
            atual = item["parts"][0]["text"]
            saida[-1]["parts"][0]["text"] = f"{anterior}\n\n{atual}"
            continue
        saida.append(item)
    return saida


def _extrair_texto(payload: dict) -> str | None:
    candidates = payload.get("candidates") or []
    if not candidates:
        log.warning("Gemini sem candidatos: %s", payload.get("promptFeedback"))
        return None
    content = candidates[0].get("content") or {}
    partes = []
    for part in content.get("parts") or []:
        if part.get("thought"):
            continue
        texto = str(part.get("text") or "").strip()
        if texto:
            partes.append(texto)
    if not partes:
        log.warning("Gemini sem texto visível. finish=%s", candidates[0].get("finishReason"))
        return None
    return "\n".join(partes).strip()


def _memoria_texto() -> str:
    itens = _ler_memoria()
    if not itens:
        return "nenhuma"
    return "\n".join(f"- {item.get('pergunta', '')} → {item.get('resposta', '')}" for item in itens[-8:])


def _ler_memoria() -> list[dict]:
    try:
        if not MEMORIA_PATH.exists():
            return []
        data = json.loads(MEMORIA_PATH.read_text(encoding="utf-8"))
        return data if isinstance(data, list) else []
    except Exception:
        log.exception("Falha ao ler a memória do consultor")
        return []


def _gravar_memoria(pergunta: str, resposta: str) -> None:
    itens = _ler_memoria()
    itens.append({"pergunta": pergunta.strip()[:400], "resposta": resposta.strip()[:700]})
    try:
        MEMORIA_PATH.parent.mkdir(parents=True, exist_ok=True)
        MEMORIA_PATH.write_text(json.dumps(itens[-12:], ensure_ascii=False), encoding="utf-8")
    except Exception:
        log.exception("Falha ao gravar a memória do consultor")


def _brl(value: float | None) -> str:
    if value is None:
        return "R$ —"
    formatted = f"{value:,.2f}".replace(",", "X").replace(".", ",").replace("X", ".")
    return f"R$ {formatted}"


def _nivel(value: float) -> str:
    return f"{value:.2f}%".replace(".", ",")

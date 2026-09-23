import logging

import httpx

from market_agent.settings import Settings

log = logging.getLogger("econozar.telegram")


async def send_message(text: str, settings: Settings) -> bool:
    token = settings.telegram_bot_token.strip()
    chat_id = settings.telegram_chat_id.strip()
    if not token or not chat_id:
        return False
    url = f"https://api.telegram.org/bot{token}/sendMessage"
    try:
        async with httpx.AsyncClient(timeout=20) as client:
            response = await client.post(url, json={"chat_id": chat_id, "text": text})
            response.raise_for_status()
        return True
    except Exception:
        log.exception("Falha ao enviar mensagem no Telegram")
        return False

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    api_key: str = ""
    tickers: str = "HGLG11.SA,MXRF11.SA,KNCR11.SA,PETR4.SA,VALE3.SA,ITUB4.SA"
    telegram_bot_token: str = ""
    telegram_chat_id: str = ""
    digest_hour: int = 18
    digest_minute: int = 0
    cache_seconds: int = 900
    session_poll_seconds: int = 60
    alert_move_percent: float = 1.5
    gemini_api_key: str = ""
    gemini_model: str = "gemini-2.5-flash"
    crypto_symbols: str = "BTC-BRL,ETH-BRL"

    def ticker_list(self) -> list[str]:
        seen: list[str] = []
        for raw in self.tickers.split(","):
            ticker = raw.strip().upper()
            if ticker and ticker not in seen:
                seen.append(ticker)
        return seen

    def crypto_list(self) -> list[str]:
        seen: list[str] = []
        for raw in self.crypto_symbols.split(","):
            symbol = raw.strip().upper()
            if symbol and symbol not in seen:
                seen.append(symbol)
        return seen

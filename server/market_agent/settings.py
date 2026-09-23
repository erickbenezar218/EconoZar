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

    def ticker_list(self) -> list[str]:
        seen: list[str] = []
        for raw in self.tickers.split(","):
            ticker = raw.strip().upper()
            if ticker and ticker not in seen:
                seen.append(ticker)
        return seen

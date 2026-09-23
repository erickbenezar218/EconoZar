FROM python:3.12-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY market_agent ./market_agent

ENV PYTHONUNBUFFERED=1
EXPOSE 8060

HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8060/health')"

CMD ["uvicorn", "market_agent.main:app", "--host", "0.0.0.0", "--port", "8060"]

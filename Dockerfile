FROM ghcr.io/astral-sh/uv:python3.12-bookworm-slim

WORKDIR /app

ENV UV_COMPILE_BYTECODE=1
ENV UV_LINK_MODE=copy

# Install dependencies (cached layer — only re-runs when lockfile changes)
COPY pyproject.toml uv.lock ./
RUN uv sync --frozen --no-dev

COPY scraper/ ./scraper/
COPY db/ ./db/
COPY migrations/ ./migrations/

CMD ["uv", "run", "python", "scraper/scraper.py"]

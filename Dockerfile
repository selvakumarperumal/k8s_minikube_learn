# Use a Python image with uv pre-installed
FROM ghcr.io/astral-sh/uv:python3.14-bookworm-slim

# Set working directory
WORKDIR /app

COPY ./app.py /app/app.py
COPY ./pyproject.toml /app/pyproject.toml
COPY ./uv.lock /app/uv.lock

RUN uv sync --frozen --no-cache

EXPOSE 80

CMD ["/app/.venv/bin/fastapi", "run", "app.py", "--port", "80", "--host", "0.0.0.0"]

FROM python:3.12-slim
# ffmpeg is only used on the Instagram GraphQL fallback path (DASH -c copy mux).
RUN apt-get update && apt-get install -y --no-install-recommends ffmpeg ca-certificates \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /srv
COPY pyproject.toml ./
RUN pip install --no-cache-dir uv && uv pip install --system --no-cache .
COPY app ./app
ENV DB_PATH=/data/hoard.db PORT=8080
EXPOSE 8080
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8080", "--workers", "1"]

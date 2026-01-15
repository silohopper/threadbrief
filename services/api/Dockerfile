FROM python:3.11-slim

WORKDIR /app

# System deps
RUN apt-get update \
    && apt-get install -y --no-install-recommends ffmpeg nodejs \
    && rm -rf /var/lib/apt/lists/*
RUN pip install --no-cache-dir --upgrade pip

COPY requirements.txt /app/requirements.txt
RUN pip install --no-cache-dir -r requirements.txt
COPY requirements-whisper.txt /app/requirements-whisper.txt
RUN pip install --no-cache-dir -r requirements-whisper.txt
ARG WHISPER_MODEL=base
ENV WHISPER_MODEL=${WHISPER_MODEL}
RUN python - <<'PY'
import os
import whisper

model = os.getenv("WHISPER_MODEL", "base")
whisper.load_model(model)
print(f"Whisper model cached: {model}")
PY

COPY app /app/app

EXPOSE 8080
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8080"]

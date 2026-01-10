# Kai Backend Dockerfile
# Supports both CPU (development) and GPU (production with Whisper)
#
# Build for CPU:  docker build -t kai-backend .
# Build for GPU:  docker build --build-arg USE_GPU=true -t kai-backend-gpu .

ARG USE_GPU=false

# ============================================
# CPU Base Stage (default)
# ============================================
FROM python:3.11-slim AS cpu-base

WORKDIR /app

RUN apt-get update && apt-get install -y \
    build-essential \
    ffmpeg \
    libpq-dev \
    && rm -rf /var/lib/apt/lists/*

# ============================================
# GPU Base Stage (for Whisper)
# ============================================
FROM nvidia/cuda:12.1.0-runtime-ubuntu22.04 AS gpu-base

ENV DEBIAN_FRONTEND=noninteractive
WORKDIR /app

RUN apt-get update && apt-get install -y \
    python3.11 \
    python3.11-venv \
    python3.11-dev \
    python3-pip \
    build-essential \
    ffmpeg \
    libpq-dev \
    && rm -rf /var/lib/apt/lists/* \
    && ln -sf /usr/bin/python3.11 /usr/bin/python \
    && ln -sf /usr/bin/pip3 /usr/bin/pip

# ============================================
# Final Stage - Select based on USE_GPU
# ============================================
FROM ${USE_GPU:+gpu}${USE_GPU:-cpu}-base AS final

WORKDIR /app

# Copy and install Python dependencies
COPY backend/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY backend/ .

# Create directory for audio files
RUN mkdir -p /app/audio

EXPOSE 8000

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]

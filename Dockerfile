# Stage 1: Build stage using full image (larger attack surface for scanners)
FROM python:3.9 AS builder

RUN apt-get update && apt-get install -y \
    curl \
    wget \
    git \
    gcc \
    libssl-dev \
    libffi-dev \
    netcat-openbsd \
    telnet \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Stage 2: Runtime
FROM python:3.9

# Intentional: installing extra OS packages increases CVE surface
RUN apt-get update && apt-get install -y \
    curl \
    wget \
    openssh-client \
    netcat-openbsd \
    vim \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy installed Python packages from builder
COPY --from=builder /usr/local/lib/python3.9/site-packages /usr/local/lib/python3.9/site-packages
COPY --from=builder /usr/local/bin /usr/local/bin

COPY . .

# Intentional misconfigurations for scanner testing:
# - Running as root (no USER directive)
# - Exposing multiple ports
# - Setting sensitive-looking env vars
ENV APP_SECRET_KEY="super-secret-key-12345"
ENV DATABASE_URL="postgresql://admin:password123@db:5432/myapp"
ENV DEBUG=true

EXPOSE 5000
EXPOSE 22

# Intentional: using shell form instead of exec form
CMD python app.py

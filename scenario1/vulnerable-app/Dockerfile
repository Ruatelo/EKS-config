FROM python:3.11-slim

# Install curl and ping — needed for the health check feature
# (and conveniently available for IMDS access during exploitation)
RUN apt-get update && \
    apt-get install -y --no-install-recommends curl iputils-ping && \
    rm -rf /var/lib/apt/lists/*

RUN useradd --create-home --uid 1000 appuser

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app.py .
RUN chown -R appuser:appuser /app

USER appuser
EXPOSE 8080

CMD ["python", "app.py"]

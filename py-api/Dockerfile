FROM python:3.12-slim

WORKDIR /app

# Install dependencies
COPY pyproject.toml ./
RUN pip install --no-cache-dir -e .

# Copy application
COPY app/ ./app/

# Expose port
EXPOSE 8081

# Run with uvicorn
CMD ["sh", "-c", "uvicorn app.main:app --host 0.0.0.0 --port ${SERVER_PORT:-8081} --workers ${UVICORN_WORKERS:-1} --log-level warning"]

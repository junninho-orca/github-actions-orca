# Intentionally outdated base image to surface vulns in the image scan demo.
# Do NOT use in production.
FROM python:3.9.7-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY src/ ./src/

# Running as root is a Dockerfile misconfig the scan will flag.
EXPOSE 5000
CMD ["python", "src/app.py"]

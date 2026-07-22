FROM public.ecr.aws/docker/library/python:3.11-slim

WORKDIR /app

# Install system deps if needed
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Copy data files
COPY data/ /app/data/

# Ensure /app is writable and has structure
RUN mkdir -p /app && chmod -R 755 /app

# No pip installs at runtime - tests will pip install pytest

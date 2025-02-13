# Use an official Python runtime as a parent image
FROM python:3.11-slim

# Set the working directory in the container
WORKDIR /app

# Install dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt litellm

# Copy application code
COPY . .

# Create LiteLLM client code
COPY litellm_client.py .

# Expose ports for both services
EXPOSE 7860

CMD ["python", "app.py"]
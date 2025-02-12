# Use an official Python runtime as a parent image
FROM python:3.11-slim

# Set the working directory in the container
WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    git \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements and install dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt \
    litellm \
    vllm \
    fastapi \
    uvicorn

# Copy the current directory contents into the container
COPY . .

# Create config file for LiteLLM
RUN echo '{\
    "model_list": [\
        {\
            "model_name": "deepseek-ai/DeepSeek-R1-Distill-Llama-8B",\
            "litellm_params": {\
                "model_name": "deepseek-ai/DeepSeek-R1-Distill-Llama-8B",\
                "api_base": "http://localhost:8000/v1",\
                "custom_llm_provider": "vllm"\
            }\
        }\
    ]\
}' > config.json

# Expose ports for both services
EXPOSE 7860 8000 8080

# Start services based on environment variable
CMD if [ "$USE_COMBINED" = "true" ]; then \
        sh -c "vllm serve deepseek-ai/DeepSeek-R1-Distill-Llama-8B --port 8000 & litellm --config config.json --port 8080 & python app.py"; \
    else \
        python app.py; \
    fi
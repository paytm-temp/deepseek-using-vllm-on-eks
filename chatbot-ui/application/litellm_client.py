from litellm import completion
import os
from litellm.utils import completion_cost, get_litellm_params
from litellm.integrations.prometheus import PrometheusCallback

# Initialize Prometheus monitoring
prometheus_callback = PrometheusCallback()

def get_completion(prompt):
    messages = [{"content": prompt, "role": "user"}]
    try:
        # Log the incoming prompt
        print(f"\n=== New Request ===")
        print(f"Prompt: {prompt}")
        
        # Add logging and monitoring
        response = completion(
            model="deepseek-ai/DeepSeek-R1-Distill-Qwen-32B",
            messages=messages,
            api_base="http://localhost:8000/v1",  # vLLM server endpoint
            custom_llm_provider="vllm",
            callbacks=[prometheus_callback]  # Add monitoring callback
        )
        
        # Log metrics
        print(f"=== Metrics ===")
        print(f"Request ID: {response.id}")
        print(f"Latency: {response.response_ms}ms")
        print(f"Token Count: {len(response.choices[0].message.content.split())}")
        print(f"=== End Request ===\n")
        
        return response.choices[0].message.content
    except Exception as e:
        return f"Error: {str(e)}" 
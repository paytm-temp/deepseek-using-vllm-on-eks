from litellm import completion
import os

def get_completion(prompt):
    messages = [{"content": prompt, "role": "user"}]
    try:
        response = completion(
            model="deepseek-ai/DeepSeek-R1-Distill-Llama-8B",
            messages=messages,
            api_base="http://localhost:8000/v1",  # vLLM server endpoint
            custom_llm_provider="vllm"
        )
        return response.choices[0].message.content
    except Exception as e:
        return f"Error: {str(e)}" 
resource "helm_release" "deepseek_gpu" {
  count            = local.enable_deep_seek_gpu ? 1 : 0
  name             = "deepseek-gpu"
  chart            = "./vllm-chart"
  create_namespace = true
  namespace        = "deepseek"

  values = [
    <<-EOT
    nodeSelector:
      owner: "data-engineer"
    tolerations:
      - key: "nvidia.com/gpu"
        operator: "Exists"
        effect: "NoSchedule"
    resources:
      limits:
        cpu: "32"
        memory: 100G
        nvidia.com/gpu: "1"
      requests:
        cpu: "16"
        memory: 30G
        nvidia.com/gpu: "1"
    command: "vllm serve deepseek-ai/DeepSeek-R1-Distill-Llama-8B --max_model 2048"
    EOT
  ]
}

resource "helm_release" "deepseek_neuron" {
  count            = local.enable_deep_seek_neuron ? 1 : 0
  name             = "deepseek-neuron"
  chart            = "./vllm-chart"
  create_namespace = true
  wait             = false
  namespace        = "deepseek"

  values = [
    <<-EOT
    image:
      repository: 936068047509.dkr.ecr.us-east-1.amazonaws.com/neuron-image-vllm
      tag: latest
      pullPolicy: IfNotPresent

    nodeSelector:
      owner: "data-engineer-neuron"

    tolerations:
      - key: "aws.amazon.com/neuron"
        operator: "Exists"
        effect: "NoSchedule"

    command: "vllm serve deepseek-ai/DeepSeek-R1-Distill-Llama-8B --device neuron --tensor-parallel-size 2 --max-num-seqs 4 --block-size 8 --use-v2-block-manager --max-model-len 4096"

    env:
      - name: NEURON_RT_NUM_CORES
        value: "2"
      - name: NEURON_RT_VISIBLE_CORES
        value: "0,1"
      - name: VLLM_LOGGING_LEVEL
        value: "DEBUG"

    resources:
      limits:
        cpu: "30"
        memory: 64G
        aws.amazon.com/neuron: "1"
      requests:
        cpu: "30"
        memory: 64G
        aws.amazon.com/neuron: "1"

    livenessProbe:
      httpGet:
        path: /health
        port: 8000
      initialDelaySeconds: 1800
      periodSeconds: 10

    readinessProbe:
      httpGet:
        path: /health
        port: 8000
      initialDelaySeconds: 1800
      periodSeconds: 5
    EOT
  ]
}
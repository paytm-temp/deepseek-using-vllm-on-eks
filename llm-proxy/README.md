# LiteLLM Proxy Kubernetes Setup

This repository contains Kubernetes configurations for deploying LiteLLM proxy with API key authentication and management.

## Components

1. **LiteLLM Master Key** (`litellm-secret.yaml`)
   - Contains the master key for admin operations
   - Used for API key generation and management

2. **PostgreSQL Database** (`litellm-db.yaml`)
   - Stores API keys and usage data
   - Includes persistent storage
   - Runs as a single replica

3. **Database Connection** (`litellm-db-connection.yaml`)
   - Contains database connection credentials
   - Used by LiteLLM proxy to connect to database

4. **LiteLLM Configuration** (`litellm-config.yaml`)
   - Contains LiteLLM settings
   - Model configurations
   - Authentication settings

5. **LiteLLM Proxy** (`litellm-proxy.yaml`)
   - Handles API requests and authentication
   - Runs with 2 replicas for high availability
   - Includes health checks and resource limits
   - Exposed via LoadBalancer and Ingress

## Prerequisites

- Kubernetes cluster
- kubectl configured
- Ingress controller (e.g., nginx-ingress)
- Domain name for the service

## Deployment Order

### 1. Create LiteLLM Master Key Secret
```bash
kubectl apply -f litellm-secret.yaml
```

### 2. Create Database Secrets and Setup
```bash
kubectl apply -f litellm-db.yaml
```

### 3. Create Database Connection Secret
```bash
kubectl apply -f litellm-db-connection.yaml
```

### 4. Create LiteLLM Configuration
```bash
kubectl apply -f litellm-config.yaml
```

### 5. Deploy LiteLLM Proxy
```bash
kubectl apply -f litellm-proxy.yaml
```

### Complete One-liner Deployment
```bash
# Apply secrets first
kubectl apply -f litellm-secret.yaml && \
kubectl apply -f litellm-db.yaml && \
echo "Waiting for database PVC to be bound..." && \
kubectl wait --for=condition=bound pvc litellm-db-pvc --timeout=60s && \

# Apply database connection secret
kubectl apply -f litellm-db-connection.yaml && \

# Apply config
kubectl apply -f litellm-config.yaml && \

# Wait for database to be ready before deploying proxy
echo "Waiting for database to be ready..." && \
kubectl wait --for=condition=ready pod -l app=litellm-db --timeout=120s && \

# Deploy proxy
kubectl apply -f litellm-proxy.yaml && \
echo "Waiting for proxy pods to be ready..." && \
kubectl wait --for=condition=ready pod -l app=litellm-proxy --timeout=120s && \
echo "Deployment complete!"
```

## Verification Steps

### Check Secrets
```bash
# List all LiteLLM secrets
kubectl get secrets | grep litellm

# Check individual secrets
kubectl describe secret litellm-secret
kubectl describe secret litellm-db-secret
kubectl describe secret litellm-db-connection
```

### Check Database Status
```bash
# Check database pods
kubectl get pods -l app=litellm-db

# Check database logs
kubectl logs -l app=litellm-db
```

### Check Proxy Status
```bash
# Check proxy pods
kubectl get pods -l app=litellm-proxy

# Check proxy logs
kubectl logs -l app=litellm-proxy
```

### Check Services and Ingress
```bash
# Check services
kubectl get services | grep litellm

# Check ingress
kubectl get ingress litellm-proxy-ingress
```

## Troubleshooting

### Check Events
```bash
# View all events sorted by timestamp
kubectl get events --sort-by='.lastTimestamp'
```

### Check Specific Component Logs
```bash
# Follow proxy logs
kubectl logs -f deployment/litellm-proxy

# Follow database logs
kubectl logs -f deployment/litellm-db
```

### Common Issues
1. PVC not binding
   - Check storage class availability
   - Check PVC status: `kubectl describe pvc litellm-db-pvc`

2. Database not starting
   - Check PVC is bound
   - Check secrets are properly created
   - Check pod events: `kubectl describe pod -l app=litellm-db`

3. Proxy not starting
   - Check all secrets are available
   - Check database is running
   - Check config is properly mounted

## API Key Management

### Generate a new API key
```bash
curl -X POST "https://your-domain/key/generate" \
  -H "Authorization: Bearer YOUR_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{"duration": "24h"}'
```

### List API keys
```bash
curl "https://your-domain/key/info" \
  -H "Authorization: Bearer YOUR_MASTER_KEY"
```

### Delete an API key
```bash
curl -X DELETE "https://your-domain/key/delete" \
  -H "Authorization: Bearer YOUR_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{"key": "key-to-delete"}'
```

## Usage

After deployment, you can use the proxy like this:

```bash
curl "https://your-domain/v1/chat/completions" \
  -H "Authorization: Bearer YOUR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gpt-3.5-turbo",
    "messages": [{"role": "user", "content": "Hello!"}]
  }'
```

## Security Considerations

1. Store sensitive values in Kubernetes secrets
2. Use proper SSL/TLS termination
3. Implement network policies
4. Regularly rotate API keys
5. Monitor usage and implement rate limiting
6. Use strong passwords in production
7. Consider using a secrets management solution like HashiCorp Vault
8. Enable database SSL/TLS connections in production

## Monitoring

The deployment includes:
- Readiness probe at `/health`
- Liveness probe at `/health`
- Resource limits and requests
- Multiple replicas for high availability

## Configuration Updates

### Update Database Credentials
1. Update `litellm-db.yaml` with new credentials
2. Update `litellm-db-connection.yaml` with matching credentials
3. Restart both database and proxy pods

### Update Master Key
1. Update `litellm-secret.yaml` with new master key
2. Restart proxy pods

### Update Model Configuration
1. Update `litellm-config.yaml` with new model settings
2. Restart proxy pods 
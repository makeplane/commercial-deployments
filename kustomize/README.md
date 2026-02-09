# Plane Commercial - Kustomize Deployment

Kubernetes deployment for Plane Commercial using Kustomize.

## Table of Contents

- [Overview](#overview)
- [Quick Reference](#quick-reference)
- [Architecture](#architecture)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Component Decision Matrix](#component-decision-matrix)
- [Component Details](#component-details)
- [Deployment Scenarios](#deployment-scenarios)
- [Configuration](#configuration)
- [Production Considerations](#production-considerations)
- [Security Best Practices](#security-best-practices)
- [Common Customization Examples](#common-customization-examples)
- [Support and Contributing](#support-and-contributing)
- [License](#license)

## Overview

This repository provides a flexible, production-ready Kustomize configuration for deploying Plane Commercial on Kubernetes. It uses Kustomize's component architecture and replacement system to enable modular deployment where infrastructure services can be deployed locally or provided externally.

**Key Features:**
- **Component-based Architecture**: Mix and match infrastructure components
- **Kustomize Replacements**: Centralized configuration management via `vars.yaml` and `secrets-vars.yaml`
- **Production Ready**: Default configurations with sensible resource limits and health checks
- **Version Management**: Helper script for easy version updates across all overlays

## Quick Reference

**Current Version**: `v2.3.3` (iframely: `v1.2.0`)

**Core Services Deployed** (from `base/`):
- 10 Deployments: api, web, space, admin, live, worker, beat-worker, iframely, outbox-poller, automation-consumer
- 1 StatefulSet: monitor
- 1 Job: migrator (database migrations)
- 1 Ingress: path-based routing for all services

**Infrastructure Components** (optional, in `components/`):
- `postgres`, `redis`, `rabbitmq`, `minio`, `opensearch` - Deploy locally OR use external services
- `silo`, `email-service` - Optional features

**How Configuration Works**:
```
1. Copy overlays/example/ to your environment (e.g., overlays/production/)
2. Edit vars.yaml (domain, version, etc.)
3. Edit secrets-vars.yaml (DATABASE_URL, secrets, etc.)
4. Choose components (local infrastructure) or configure external URLs
5. kubectl apply -k overlays/production/
```

**File You'll Edit**:
- `overlays/my-env/vars.yaml` - Domain, version, ingress class
- `overlays/my-env/secrets-vars.yaml` - Credentials and connection strings
- `overlays/my-env/kustomization.yaml` - Components and image versions

**Files You Won't Edit**:
- `base/` - Core application manifests (edit via overlays/patches)
- `components/` - Infrastructure component definitions (include or don't)

## Architecture

### Base (Always Deployed)

Core Plane application services and required components defined in `base/`:

**Deployments:**
- `api` - Main API server (backend-commercial image)
- `web` - Web application frontend
- `space` - Public space frontend  
- `admin` - Admin panel (god-mode)
- `live` - Real-time collaboration service
- `worker` - Background job worker (Celery)
- `beat-worker` - Scheduled task worker (Celery Beat)
- `iframely` - URL preview service (v1.2.0)
- `outbox-poller` - Outbox pattern poller
- `automation-consumer` - Automation task consumer

**StatefulSets:**
- `monitor` - Monitoring and metrics service

**Jobs:**
- `migrator` - Database migration job (runs on deployment)

**Ingress:**
- Single ingress with path-based routing for all services
- Paths: `/` (web), `/spaces/` (space), `/god-mode/` (admin), `/api/`, `/auth/`, `/live/`

**Services:**
- Service definitions for api, web, space, admin, live, monitor, iframely

**ConfigMaps & Secrets:**
- Application configuration, Live config, OpenSearch config, Monitor config, Silo config
- Database, Redis, RabbitMQ connection strings (populated by components or overlays)

### Components - Infrastructure (Required: Local OR External)

Choose to deploy these locally OR provide external managed services. Each component is a Kustomize component in `components/` that adds resources and configuration patches:

**postgres** (PostgreSQL database)
- Adds: StatefulSet, Service, Secret
- Patches: `plane-app-secrets` with `DATABASE_URL: postgresql://plane:plane@plane-postgres/plane`
- Alternative: AWS RDS, Google Cloud SQL, Azure Database

**redis** (Redis cache)
- Adds: StatefulSet, Service
- Patches: `plane-app-secrets` and `plane-live-secrets` with Redis URLs
- Alternative: AWS ElastiCache, Redis Cloud, Azure Cache

**rabbitmq** (RabbitMQ message broker)
- Adds: StatefulSet, Service, Secret
- Patches: `plane-app-secrets` with `AMQP_URL`
- Alternative: AWS MQ, CloudAMQP, RabbitMQ Cloud

**minio** (S3-compatible object storage)
- Adds: StatefulSet, Service, Job (bucket creation)
- Patches: `plane-doc-store-secrets` with MinIO credentials and endpoint
- Alternative: AWS S3, Google Cloud Storage, Azure Blob Storage

**opensearch** (Full-text search and analytics)
- Adds: StatefulSet, Service, ConfigMap
- Patches: `plane-opensearch-secrets` with OpenSearch URL and credentials
- Alternative: AWS OpenSearch Service, Elastic Cloud

**Important**: Infrastructure components are **required**. If not included as components, you MUST provide external URLs via `secrets-vars.yaml` in your overlay.

### Components - Optional Services

Additional features that can be enabled:

**email-service** (Email delivery)
- Adds: Deployment, Service, ConfigMap
- Provides email sending capabilities

**silo** (Silo integration)  
- Adds: Deployment, Service, ConfigMap
- Patches: Ingress to add `/silo/` path
- Enables silo functionality

## Prerequisites

### Required

- **Kubernetes cluster** (v1.31+)
  - Minimum 4 CPU cores, 8GB RAM for development
  - Recommended 16+ CPU cores, 32GB+ RAM for production
  
- **kubectl** with Kustomize support (v1.14+) or standalone Kustomize (v5.0+)
  ```bash
  kubectl version --client
  kubectl kustomize --help
  ```

- **Storage class** configured for PersistentVolumeClaims (if using local infrastructure components)
  ```bash
  kubectl get storageclass
  # Should show at least one storage class, preferably marked as (default)
  ```

### Optional but Recommended

- **Ingress Controller** (nginx, traefik, etc.)
  ```bash
  # Install nginx ingress controller
  kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.8.1/deploy/static/provider/cloud/deploy.yaml
  ```

- **Cert-Manager** for automatic TLS certificates
  ```bash
  kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.0/cert-manager.yaml
  ```

- **External Secrets Operator** for production secrets management
  ```bash
  helm repo add external-secrets https://charts.external-secrets.io
  helm install external-secrets external-secrets/external-secrets -n external-secrets-system --create-namespace
  ```

- **Metrics Server** for resource monitoring and HPA
  ```bash
  kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
  ```

### Image Registry Access

All Plane images are hosted at `artifacts.plane.so`. These are the images used:

- `artifacts.plane.so/makeplane/backend-commercial:v2.3.3` - Backend API & Workers
- `artifacts.plane.so/makeplane/web-commercial:v2.3.3` - Web frontend
- `artifacts.plane.so/makeplane/space-commercial:v2.3.3` - Space frontend
- `artifacts.plane.so/makeplane/admin-commercial:v2.3.3` - Admin panel
- `artifacts.plane.so/makeplane/live-commercial:v2.3.3` - Live collaboration
- `artifacts.plane.so/makeplane/monitor-commercial:v2.3.3` - Monitor service
- `artifacts.plane.so/makeplane/silo-commercial:v2.3.3` - Silo service (optional)
- `artifacts.plane.so/makeplane/email-commercial:v2.3.3` - Email service (optional)
- `artifacts.plane.so/makeplane/iframely:v1.2.0` - URL preview service

**Note**: You need valid Plane Commercial credentials to pull these images. Configure image pull secrets if required:

```bash
kubectl create secret docker-registry plane-registry-secret \
  --docker-server=artifacts.plane.so \
  --docker-username=<your-username> \
  --docker-password=<your-password> \
  -n plane-production
```

Then add to service account or deployments:
```yaml
spec:
  imagePullSecrets:
    - name: plane-registry-secret
```

## Quick Start

### Getting Started

1. **Copy the example overlay:**
   ```bash
   cd overlays/
   cp -r example my-deployment
   cd my-deployment
   ```

2. **Configure your deployment:**
   ```bash
   # Copy and edit configuration files
   cp vars.yaml.example vars.yaml
   cp secrets-vars.yaml.example secrets-vars.yaml
   
   # Edit vars.yaml (non-sensitive configuration)
   nano vars.yaml
   
   # Edit secrets-vars.yaml (sensitive credentials - DO NOT COMMIT!)
   nano secrets-vars.yaml
   ```

3. **Choose your infrastructure approach:**

   **Option A: Local Infrastructure** (development/self-hosted)
   ```yaml
   # In kustomization.yaml, uncomment infrastructure components:
   components:
     - ../../components/postgres
     - ../../components/redis
     - ../../components/rabbitmq
     - ../../components/minio
     - ../../components/opensearch
   ```

   **Option B: Managed Services** (production/cloud)
   ```yaml
   # In kustomization.yaml, keep infrastructure components commented
   # Configure external URLs in secrets-vars.yaml instead
   ```

4. **Deploy to Kubernetes:**
   ```bash
   # Preview what will be deployed
   kubectl kustomize overlays/my-deployment/
   
   # Apply the configuration
   kubectl apply -k overlays/my-deployment/
   
   # Check deployment status
   kubectl get pods -n plane-ns
   
   # Watch rollout
   kubectl rollout status -n plane-ns deployment/plane-api-wl
   ```

5. **Access Plane:**
   ```bash
   # Using port-forward for testing:
   kubectl port-forward -n plane-ns svc/plane-web 3000:3000
   
   # Or configure your domain in ingress (see Configuration section)
   ```

## Component Decision Matrix

| Component | Include When | Don't Include When |
|-----------|-------------|-------------------|
| **postgres** | Use local PostgreSQL | Using AWS RDS, Cloud SQL, etc. |
| **redis** | Use local Redis | Using AWS ElastiCache, Redis Cloud |
| **rabbitmq** | Use local RabbitMQ | Using AWS MQ, CloudAMQP |
| **minio** | Use local S3 storage | Using AWS S3, Google Cloud Storage |
| **opensearch** | Use local OpenSearch | Using AWS OpenSearch Service |
| **email-service** | Need email delivery | Using external email service |
| **silo** | Need silo functionality | Not needed |

**Important**: Infrastructure components (postgres, redis, rabbitmq, minio, opensearch) are **required**. If not included as components, you MUST provide external URLs in secrets.

## Component Details

### How Components Work

Kustomize components are reusable building blocks that can be included in overlays. When you include a component, it:
1. Adds new resources (StatefulSets, Services, etc.)
2. Applies patches to existing base resources (like updating connection URLs)

Example in `overlays/my-env/kustomization.yaml`:
```yaml
components:
  - ../../components/postgres  # Adds Postgres StatefulSet and patches DATABASE_URL
  - ../../components/redis     # Adds Redis StatefulSet and patches REDIS_URL
```

### Infrastructure Component Details

#### PostgreSQL Component

**What it adds:**
- `StatefulSet` with 1 replica running PostgreSQL 15
- `Service` exposing port 5432 (`plane-postgres`)
- `Secret` with default credentials (`plane:plane`)
- `PersistentVolumeClaim` for data (10Gi default)

**What it patches:**
- Updates `plane-app-secrets.DATABASE_URL` to `postgresql://plane:plane@plane-postgres/plane`

**Default configuration:**
- Image: `postgres:15`
- Resources: 50Mi memory, 50m CPU (requests)
- Storage: 10Gi (can be increased via patches)

#### Redis Component

**What it adds:**
- `StatefulSet` with 1 replica running Redis 7
- `Service` exposing port 6379 (`plane-redis`)
- `PersistentVolumeClaim` for data (1Gi default)

**What it patches:**
- Updates `plane-app-secrets.REDIS_URL` to `redis://plane-redis:6379/`
- Updates `plane-live-secrets.REDIS_URL` to `redis://plane-redis:6379/`

**Default configuration:**
- Image: `redis:7`
- Resources: 50Mi memory, 50m CPU
- Storage: 1Gi

#### RabbitMQ Component

**What it adds:**
- `StatefulSet` with 1 replica running RabbitMQ 3.13
- `Service` exposing ports 5672 (AMQP) and 15672 (Management UI)
- `Secret` with default credentials
- `PersistentVolumeClaim` for data (1Gi default)

**What it patches:**
- Updates `plane-app-secrets.AMQP_URL` with RabbitMQ connection string

**Default configuration:**
- Image: `rabbitmq:3.13-management`
- Resources: 50Mi memory, 50m CPU
- Storage: 1Gi
- Management UI available at: `http://plane-rabbitmq:15672` (guest/guest)

#### MinIO Component

**What it adds:**
- `StatefulSet` with 1 replica running MinIO
- `Service` exposing ports 9000 (API) and 9001 (Console)
- `Job` to create the `uploads` bucket automatically
- `PersistentVolumeClaim` for data (10Gi default)

**What it patches:**
- Updates `plane-doc-store-secrets` with MinIO credentials:
  - `AWS_ACCESS_KEY_ID`: `minioadmin`
  - `AWS_SECRET_ACCESS_KEY`: `minioadmin`
  - `AWS_S3_ENDPOINT_URL`: `http://plane-minio:9000`
  - `AWS_S3_BUCKET_NAME`: `uploads`

**Default configuration:**
- Image: `minio/minio:latest`
- Resources: 50Mi memory, 50m CPU
- Storage: 10Gi
- Console available at: `http://plane-minio:9001`

#### OpenSearch Component

**What it adds:**
- `StatefulSet` with 1 replica running OpenSearch 2
- `Service` exposing ports 9200 (HTTP) and 9300 (Transport)
- `ConfigMap` with OpenSearch configuration
- `PersistentVolumeClaim` for data (10Gi default)

**What it patches:**
- Updates `plane-opensearch-secrets`:
  - `OPENSEARCH_ENABLED`: `1`
  - `OPENSEARCH_URL`: `http://plane-opensearch:9200`
  - `OPENSEARCH_USERNAME`: `admin`
  - `OPENSEARCH_PASSWORD`: `admin`

**Default configuration:**
- Image: `opensearchproject/opensearch:2`
- Resources: 512Mi memory, 500m CPU (OpenSearch needs more resources)
- Storage: 10Gi
- Security plugin disabled for simplicity (enable for production!)
- Single-node discovery mode

### Optional Service Components

#### Email Service Component

**What it adds:**
- `Deployment` for email service
- `Service` exposing email API
- `ConfigMap` with email configuration

**Use when:** You need integrated email sending capabilities

**Configuration:** Set email provider credentials via environment variables

#### Silo Component

**What it adds:**
- `Deployment` for silo service
- `Service` exposing silo API
- `ConfigMap` with silo configuration
- `Patch` to add `/silo/` path to main ingress

**Use when:** You need silo integration functionality

**Configuration:** Configure via `plane-silo-vars` ConfigMap and `plane-silo-secrets`

## Deployment Scenarios

### Scenario 1: Local Development with Local Infrastructure

**Use Case**: Development, testing, demos, self-hosted environments

**Configuration**:
```yaml
# overlays/dev/kustomization.yaml
namespace: plane-dev

resources:
  - ../../base
  - vars.yaml
  - secrets-vars.yaml

components:
  - ../../components/postgres      # Local PostgreSQL
  - ../../components/redis         # Local Redis
  - ../../components/rabbitmq      # Local RabbitMQ
  - ../../components/minio         # Local MinIO
  - ../../components/opensearch    # Local OpenSearch
  - ../../components/silo          # Optional
  - ../../components/email-service # Optional
```

**Resources**: Minimal by default (50Mi RAM, 50m CPU per service)

**Deploy**: 
```bash
kubectl apply -k overlays/dev/
```

### Scenario 2: Production with Managed Cloud Services

**Use Case**: Cloud-native production (AWS, GCP, Azure)

**Configuration**:
```yaml
# overlays/production/kustomization.yaml
namespace: plane-production

resources:
  - ../../base
  - vars.yaml
  - secrets-vars.yaml

# NO infrastructure components - use external services
components:
  - ../../components/silo          # Optional: if needed
  - ../../components/email-service # Optional: if needed

# Configure external services in secrets-vars.yaml:
# - DATABASE_URL: postgresql://user:pass@rds-endpoint:5432/plane
# - REDIS_URL: redis://elasticache-endpoint:6379/
# - AMQP_URL: amqps://user:pass@mq-endpoint:5671/
# - AWS_S3_ENDPOINT_URL: https://s3.amazonaws.com
# - OPENSEARCH_URL: https://opensearch-endpoint:443
```

**Benefits**:
- Managed backups and updates
- High availability built-in
- Auto-scaling capabilities
- Reduced operational overhead
- No stateful workloads in Kubernetes

**Deploy**: 
```bash
kubectl apply -k overlays/production/
```

### Scenario 3: Hybrid Deployment

**Use Case**: Mix local and external services based on your needs

Create a custom overlay mixing local and external services:

```yaml
# overlays/hybrid/kustomization.yaml
namespace: plane-hybrid

resources:
  - ../../base
  - vars.yaml
  - secrets-vars.yaml

components:
  - ../../components/postgres    # Local (for data sovereignty)
  - ../../components/redis       # Local (low latency needs)
  # RabbitMQ: External (AWS MQ) - set AMQP_URL in secrets-vars.yaml
  # MinIO: External (AWS S3) - set AWS_* vars in secrets-vars.yaml
  # OpenSearch: External (managed) - set OPENSEARCH_* vars in secrets-vars.yaml

# Additional patches for production scaling (see Configuration section)
patches:
  - path: patches/replicas.yaml
  - path: patches/resources.yaml
```

**Deploy**: 
```bash
kubectl apply -k overlays/hybrid/
```

## Configuration

### Configuration System

This deployment uses **Kustomize Replacements** for centralized configuration management. All customization is done through two files in your overlay:

1. **`vars.yaml`** - Non-sensitive configuration (safe to commit)
2. **`secrets-vars.yaml`** - Sensitive credentials (NEVER commit - in `.gitignore`)

These files are marked with `config.kubernetes.io/local-config: "true"` so they're not deployed to the cluster. Instead, their values are automatically replaced throughout the manifests.

### Setting Up Your Configuration

1. **Copy the example overlay:**
   ```bash
   cd overlays/
   cp -r example my-environment
   cd my-environment
   ```

2. **Configure non-sensitive values** in `vars.yaml`:
   ```yaml
   apiVersion: v1
   kind: ConfigMap
   metadata:
     name: overlay-vars
     annotations:
       config.kubernetes.io/local-config: "true"
   data:
     # Application version (keep in sync with image tags below)
     APP_VERSION: "v2.3.3"
     
     # Domain configuration (without protocol)
     APP_DOMAIN: "plane.yourcompany.com"
     
     # Web URL (with protocol - http for dev, https for production)
     WEB_URL: "https://plane.yourcompany.com"
     
     # CORS allowed origins (comma-separated)
     CORS_ALLOWED_ORIGINS: "https://plane.yourcompany.com"
     
     # Ingress class (nginx, traefik, alb, etc.)
     INGRESS_CLASS: "nginx"
     
     # Air-gapped deployment flag
     IS_AIRGAPPED: "0"  # Set to "1" for air-gapped environments
   ```

3. **Configure sensitive values** in `secrets-vars.yaml`:
   ```yaml
   apiVersion: v1
   kind: Secret
   metadata:
     name: overlay-secret-vars
     annotations:
       config.kubernetes.io/local-config: "true"
   type: Opaque
   stringData:
     # ====== INFRASTRUCTURE CONNECTION STRINGS ======
     # If using components, these will be overridden by component patches
     # If using external services, configure them here:
     
     DATABASE_URL: "postgresql://user:pass@your-rds.amazonaws.com:5432/plane"
     REDIS_URL: "redis://your-elasticache.amazonaws.com:6379/"
     REDIS_URL_LIVE: "redis://your-elasticache.amazonaws.com:6379/"
     AMQP_URL: "amqps://user:pass@your-mq.amazonaws.com:5671/"
     
     # ====== OPENSEARCH CONFIGURATION ======
     OPENSEARCH_ENABLED: "1"
     OPENSEARCH_URL: "https://your-opensearch.amazonaws.com:443"
     OPENSEARCH_USERNAME: "admin"
     OPENSEARCH_PASSWORD: "YourSecurePassword123!"
     
     # ====== MINIO / S3 CONFIGURATION ======
     AWS_ACCESS_KEY_ID: "AKIAXXXXXXXXXXXXXXXX"
     AWS_SECRET_ACCESS_KEY: "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
     AWS_S3_ENDPOINT_URL: "https://s3.us-east-1.amazonaws.com"
     AWS_S3_BUCKET_NAME: "plane-uploads-prod"
     AWS_REGION: "us-east-1"
     
     # ====== APPLICATION SECRETS ======
     # CRITICAL: Generate new random values! Never use defaults in production!
     # Generate with: openssl rand -hex 32
     SECRET_KEY: "GENERATE-A-RANDOM-50-CHARACTER-STRING"
     AES_SECRET_KEY: "GENERATE-A-RANDOM-32-CHARACTER-STRING"  
     LIVE_SERVER_SECRET_KEY: "GENERATE-A-RANDOM-42-CHARACTER-STRING"
   ```

### Environment Variables Reference

**Configured via vars.yaml (non-sensitive):**
- `APP_VERSION` - Application version (must match image tags)
- `APP_DOMAIN` - Domain name without protocol
- `WEB_URL` - Full web URL with protocol
- `CORS_ALLOWED_ORIGINS` - Comma-separated allowed origins
- `INGRESS_CLASS` - Ingress controller class
- `IS_AIRGAPPED` - Air-gapped deployment flag (0 or 1)

**Configured via secrets-vars.yaml (sensitive):**
- `DATABASE_URL` - PostgreSQL connection string
- `REDIS_URL` - Redis connection string (main)
- `REDIS_URL_LIVE` - Redis connection string for Live service
- `AMQP_URL` - RabbitMQ connection string
- `OPENSEARCH_*` - OpenSearch configuration
- `AWS_*` - S3/MinIO configuration
- `SECRET_KEY`, `AES_SECRET_KEY`, `LIVE_SERVER_SECRET_KEY` - Application secrets

**Additional variables in base configs:**
- `PRIME_HOST` - License server URL (in `plane-app-vars`)
- `ENABLE_EMAIL_PASSWORD` - Email/password auth (in `plane-app-vars`)
- `ENABLE_MAGIC_LINK_LOGIN` - Magic link auth (in `plane-app-vars`)

## Production Considerations

### Resource Planning

**Minimum Production Requirements:**

| Component | CPU (requests) | Memory (requests) | Replicas | Notes |
|-----------|---------------|-------------------|----------|-------|
| API | 500m | 512Mi | 2-3 | Scale based on user count |
| Worker | 300m | 512Mi | 2-5 | Scale based on background job volume |
| Beat Worker | 100m | 256Mi | 1 | Only 1 replica needed |
| Web | 100m | 256Mi | 2 | Can scale for high traffic |
| Space | 100m | 256Mi | 1-2 | Public space access |
| Admin | 100m | 256Mi | 1 | Low traffic typically |
| Live | 200m | 256Mi | 1-2 | WebSocket connections |
| Monitor | 100m | 256Mi | 1 | StatefulSet, single replica |
| Iframely | 100m | 256Mi | 1 | URL preview service |

**Infrastructure (if using local components):**

| Component | CPU | Memory | Storage | Notes |
|-----------|-----|--------|---------|-------|
| PostgreSQL | 1000m | 2Gi | 50-200Gi | Critical - allocate generously |
| Redis | 500m | 1Gi | 10Gi | Cache and session storage |
| RabbitMQ | 500m | 1Gi | 10Gi | Message broker |
| MinIO | 500m | 1Gi | 100Gi+ | Object storage grows with uploads |
| OpenSearch | 1000m | 2Gi | 50Gi | Search and analytics |

### High Availability Setup

For production, configure HA for critical components:

1. **Application Layer HA:**
   ```yaml
   # Multiple replicas with pod anti-affinity
   spec:
     replicas: 3
     template:
       spec:
         affinity:
           podAntiAffinity:
             preferredDuringSchedulingIgnoredDuringExecution:
               - weight: 100
                 podAffinityTerm:
                   labelSelector:
                     matchLabels:
                       app.kubernetes.io/component: api
                   topologyKey: kubernetes.io/hostname
   ```

2. **Use Managed Services:** For true HA, use cloud-managed services:
   - AWS RDS Multi-AZ for PostgreSQL
   - AWS ElastiCache with Redis replication
   - AWS MQ with active/standby brokers
   - S3 with versioning and cross-region replication
   - AWS OpenSearch with 3+ nodes across AZs

3. **LoadBalancer Service Type:** For production ingress
   ```yaml
   # Use cloud load balancer with health checks
   spec:
     type: LoadBalancer
   ```

### Persistence and Data Protection

1. **StorageClass Selection:**
   ```yaml
   # Use production-grade storage class
   volumeClaimTemplates:
     - metadata:
         name: postgres-data
       spec:
         storageClassName: gp3  # AWS gp3, or equivalent
         accessModes: ["ReadWriteOnce"]
         resources:
           requests:
             storage: 100Gi
   ```

2. **Backup Strategy:**
   - Automated daily backups for PostgreSQL
   - Point-in-time recovery capability
   - Backup retention: 30 days minimum
   - Test restore procedures regularly

3. **Volume Snapshots:**
   ```bash
   # Use VolumeSnapshot API for PVC backups
   kubectl apply -f volume-snapshot.yaml
   ```

## Security Best Practices

### Secrets Management

1. **Never Commit Secrets to Git**
   - `secrets-vars.yaml` is in `.gitignore` - keep it there
   - Use External Secrets Operator for production
   - Rotate secrets regularly (every 90 days minimum)

2. **Generate Strong Secrets**
   ```bash
   # Generate random secrets
   openssl rand -hex 32  # For SECRET_KEY (64 chars)
   openssl rand -hex 16  # For AES_SECRET_KEY (32 chars)
   openssl rand -hex 21  # For LIVE_SERVER_SECRET_KEY (42 chars)
   ```

3. **Kubernetes Secrets Encryption at Rest**
   ```bash
   # Enable encryption provider in Kubernetes
   # Add to kube-apiserver configuration
   --encryption-provider-config=/etc/kubernetes/encryption-config.yaml
   ```

4. **Secret Access Control**
   ```yaml
   # Restrict secret access via RBAC
   apiVersion: rbac.authorization.k8s.io/v1
   kind: Role
   metadata:
     name: plane-secrets-reader
     namespace: plane-production
   rules:
     - apiGroups: [""]
       resources: ["secrets"]
       resourceNames: ["plane-app-secrets"]
       verbs: ["get"]
   ```

### Database Security

1. **PostgreSQL Security**
   ```yaml
   # Use strong passwords
   # Enable SSL connections
   # Restrict network access
   # Regular security updates
   ```

2. **Connection String Security**
   ```bash
   # Use PostgreSQL connection pooler (PgBouncer)
   # Limit max connections
   # Use SSL mode: sslmode=require in DATABASE_URL
   DATABASE_URL: "postgresql://user:pass@host:5432/plane?sslmode=require"
   ```

## Common Customization Examples

### Example 1: Production with AWS Managed Services

```yaml
# overlays/aws-production/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: plane-production

resources:
  - ../../base
  - vars.yaml
  - secrets-vars.yaml

# NO infrastructure components - using AWS managed services
components:
  - ../../components/silo  # Optional

images:
  - name: artifacts.plane.so/makeplane/backend-commercial
    newTag: v2.3.3
  # ... other images

patches:
  - path: patches/replicas.yaml
  - path: patches/resources.yaml
  - path: patches/ingress-alb.yaml

replacements:
  # ... same as example overlay
```

```yaml
# overlays/aws-production/secrets-vars.yaml
stringData:
  DATABASE_URL: "postgresql://planeuser:XXXXX@plane-db.xxx.us-east-1.rds.amazonaws.com:5432/plane?sslmode=require"
  REDIS_URL: "rediss://plane-cache.xxx.cache.amazonaws.com:6379?ssl_cert_reqs=required"
  REDIS_URL_LIVE: "rediss://plane-cache.xxx.cache.amazonaws.com:6379?ssl_cert_reqs=required"
  AMQP_URL: "amqps://planeuser:XXXXX@b-xxx.mq.us-east-1.amazonaws.com:5671"
  OPENSEARCH_URL: "https://search-plane-xxx.us-east-1.es.amazonaws.com"
  OPENSEARCH_USERNAME: "admin"
  OPENSEARCH_PASSWORD: "XXXXX"
  AWS_S3_ENDPOINT_URL: "https://s3.us-east-1.amazonaws.com"
  AWS_S3_BUCKET_NAME: "plane-uploads-prod"
  AWS_REGION: "us-east-1"
  AWS_ACCESS_KEY_ID: "AKIAXXXXXXXXXXXXX"
  AWS_SECRET_ACCESS_KEY: "XXXXXXXXXXXXXXXXXXXXXXXXXXXXX"
  SECRET_KEY: "xxxx-generated-secret-xxxx"
  AES_SECRET_KEY: "xxxx-generated-secret-xxxx"
  LIVE_SERVER_SECRET_KEY: "xxxx-generated-secret-xxxx"
```

### Example 2: Multi-Environment Setup

```bash
# Directory structure
overlays/
├── dev/
│   ├── kustomization.yaml
│   ├── vars.yaml
│   └── secrets-vars.yaml
├── staging/
│   ├── kustomization.yaml
│   ├── vars.yaml
│   └── secrets-vars.yaml
└── production/
    ├── kustomization.yaml
    ├── vars.yaml
    ├── secrets-vars.yaml
    └── patches/
        ├── replicas.yaml
        ├── resources.yaml
        └── hpa.yaml
```

```yaml
# overlays/dev/kustomization.yaml - All local, minimal resources
namespace: plane-dev
components:
  - ../../components/postgres
  - ../../components/redis
  - ../../components/rabbitmq
  - ../../components/minio
  - ../../components/opensearch
```

```yaml
# overlays/staging/kustomization.yaml - Mixed: local DB, managed cache/queue
namespace: plane-staging
components:
  - ../../components/postgres  # Local for cost savings
  # Redis, RabbitMQ from AWS
patches:
  - path: patches/resources-medium.yaml
```

```yaml
# overlays/production/kustomization.yaml - All managed, scaled
namespace: plane-production
# No infrastructure components - all managed
patches:
  - path: patches/replicas.yaml       # Scale to multiple replicas
  - path: patches/resources.yaml      # Production resource limits
  - path: patches/hpa.yaml            # Horizontal autoscaling
  - path: patches/pdb.yaml            # Pod disruption budgets
  - path: patches/ingress-tls.yaml    # TLS configuration
```

### Example 3: Air-Gapped Deployment

```yaml
# overlays/airgapped/kustomization.yaml
namespace: plane-airgapped

resources:
  - ../../base
  - vars.yaml
  - secrets-vars.yaml

# All infrastructure must be local in air-gapped
components:
  - ../../components/postgres
  - ../../components/redis
  - ../../components/rabbitmq
  - ../../components/minio
  - ../../components/opensearch

# Use private registry for images
images:
  - name: artifacts.plane.so/makeplane/backend-commercial
    newName: my-registry.internal/plane/backend
    newTag: v2.3.3
  - name: artifacts.plane.so/makeplane/web-commercial
    newName: my-registry.internal/plane/web
    newTag: v2.3.3
  # ... other images
```

```yaml
# overlays/airgapped/vars.yaml
data:
  IS_AIRGAPPED: "1"  # Critical for air-gapped mode
  APP_DOMAIN: "plane.internal"
  WEB_URL: "https://plane.internal"
```

### Example 4: Custom Storage Class and Sizes

```yaml
# overlays/production/patches/storage.yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: plane-postgres
spec:
  volumeClaimTemplates:
    - metadata:
        name: postgres-data
      spec:
        storageClassName: fast-ssd  # Custom storage class
        resources:
          requests:
            storage: 200Gi  # Increased from 10Gi
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: plane-minio
spec:
  volumeClaimTemplates:
    - metadata:
        name: minio-data
      spec:
        storageClassName: standard  # Cheaper storage for objects
        resources:
          requests:
            storage: 500Gi  # Large storage for uploads
```

### Example 5: Custom Environment Variables

```yaml
# overlays/production/patches/custom-env.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: plane-api-wl
spec:
  template:
    spec:
      containers:
        - name: api
          env:
            # Add custom environment variables
            - name: DEBUG
              value: "0"
            - name: DJANGO_SETTINGS_MODULE
              value: "plane.settings.production"
            - name: SENTRY_DSN
              value: "https://xxx@sentry.io/xxx"
            - name: LOG_LEVEL
              value: "INFO"
```

## Support and Contributing

- **Documentation**: Full Plane docs at [https://docs.plane.so](https://docs.plane.so)
- **Issues**: Report issues in the main Plane repository
- **Community**: Join the [Plane Discord](https://discord.com/invite/A92xrEGCge)

## License

This project follows the Plane Commercial license terms.

# Fly.io Migration Plan for Proof Pad

## Executive Summary

This document outlines a migration path for Proof Pad from Google Cloud Platform (GKE/Cloud Run + GCS) to Fly.io. The migration involves both backend (Go WebSocket server + ACL2 runtime) and frontend (React static files) components.

---

## Current Architecture

### Backend
- **Language**: Go 1.21
- **Server**: HTTP + WebSocket (`gorilla/websocket`)
- **Process**: Spawns ACL2 subprocess per WebSocket connection
- **Logging**: Google Cloud Logging SDK (`cloud.google.com/go/logging`)
- **Deployment**: Google Cloud Run (`acl2-jbhe53iwqa-uc.a.run.app`)
- **Container**: Debian Sid with ACL2 8.5 built from source

### Frontend
- **Framework**: React 17 + TypeScript
- **Bundler**: Parcel
- **Deployment**: Google Cloud Storage (static hosting)
- **WebSocket Client**: Connects to `wss://acl2-jbhe53iwqa-uc.a.run.app/acl2`

---

## Migration Steps

### Phase 1: Remove Google Cloud Dependencies

**1.1 Replace Google Cloud Logging**

The Go backend uses `cloud.google.com/go/logging` which will fail without GCP credentials. Replace with standard library logging or a Fly.io-compatible alternative.

**Current code (`main.go` lines 239-255):**
```go
client, err := logging.NewClient(context.Background(), "proof-pad")
if err != nil {
    log.Fatalf("Can't create logging client: %v", err)
}
defer client.Close()
logger = client.Logger("acl2-service")
```

**Proposed changes:**
```go
// Option A: Standard library logging (simplest)
ilog = func(l string, args ...interface{}) {
    log.Printf("[INFO] "+l, args...)
}
elog = func(l string, args ...interface{}) {
    log.Printf("[ERROR] "+l, args...)
}

// Option B: Structured JSON logging for Fly.io log aggregation
// Use zerolog or zap for JSON output
```

**1.2 Remove Cloud Logging from HTTP handler**

Remove the `logging.HTTPRequest` usage in the `acl2()` handler (line 92-95).

**1.3 Update `go.mod`**

Remove these dependencies:
- `cloud.google.com/go/logging`
- All transitive Google dependencies

---

### Phase 2: Create Fly.io Configuration

**2.1 Create `fly.toml`**

```toml
app = "proof-pad-acl2"
primary_region = "ord"  # Chicago, or choose your preferred region

[build]
  dockerfile = "Dockerfile"

[env]
  PORT = "8080"

[http_service]
  internal_port = 8080
  force_https = true
  auto_stop_machines = false  # Keep running for WebSocket connections
  auto_start_machines = true
  min_machines_running = 1

  [http_service.concurrency]
    type = "connections"
    hard_limit = 25
    soft_limit = 20

[[services]]
  protocol = "tcp"
  internal_port = 8080
  
  [[services.ports]]
    port = 80
    handlers = ["http"]
    
  [[services.ports]]
    port = 443
    handlers = ["tls", "http"]

  [[services.tcp_checks]]
    port = 8080
    interval = "15s"
    timeout = "2s"
    grace_period = "60s"

[[vm]]
  memory = "2gb"  # ACL2 may need significant memory
  cpu_kind = "shared"
  cpus = 2
```

**2.2 Create `.dockerignore`**

```
node_modules/
dist/
.git/
*.md
.eslintrc.json
.eslintignore
package*.json
src/
style.css
index.html
tsconfig.json
grammar/
```

---

### Phase 3: Optimize Docker Build

The current Dockerfile takes 30+ minutes due to ACL2 compilation. Consider these optimizations:

**3.1 Multi-stage build with caching**

```dockerfile
# Stage 1: Build Go binary
FROM golang:1.21-bookworm AS go-builder
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY main.go ./
RUN CGO_ENABLED=0 go build -o /acl2-server

# Stage 2: Build ACL2 (cache this layer)
FROM debian:bookworm AS acl2-builder
RUN apt-get update && apt-get install -y wget make perl build-essential sbcl
RUN wget https://github.com/acl2-devel/acl2-devel/releases/download/8.5/acl2-8.5.tar.gz && \
    tar xfz acl2-8.5.tar.gz && \
    rm acl2-8.5.tar.gz && \
    cd acl2-8.5 && \
    make LISP=sbcl && \
    cd books && \
    make ACL2=/app/acl2-8.5/saved_acl2 basic

# Stage 3: Final runtime image
FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y sbcl ca-certificates && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY --from=go-builder /acl2-server /acl2-server
COPY --from=acl2-builder /acl2-8.5 ./acl2-8.5
COPY dracula dracula
ENV PORT=8080
CMD ["/acl2-server"]
```

**3.2 Pre-built ACL2 image option**

Consider publishing a Docker image with pre-built ACL2 to a registry:
```bash
# Build once and push
fly deploy --build-only --push
# Or use Docker Hub / GitHub Container Registry
```

---

### Phase 4: Update Frontend Configuration

**4.1 Update WebSocket URL**

In `src/acl2_driver.ts` (line 23):

```typescript
// Current
const ws = new WebSocket(`wss://acl2-jbhe53iwqa-uc.a.run.app/acl2`);

// Updated for Fly.io
const ws = new WebSocket(`wss://proof-pad-acl2.fly.dev/acl2`);

// Or make it configurable via environment variable
const ACL2_URL = process.env.ACL2_BACKEND_URL || 'wss://proof-pad-acl2.fly.dev/acl2';
const ws = new WebSocket(ACL2_URL);
```

**4.2 Frontend hosting options**

**Option A**: Host on Fly.io (recommended for simplicity)
- Add static file serving to the Go backend
- Or create a separate Fly.io app with a static file server

**Option B**: Keep on external static hosting
- Cloudflare Pages
- Vercel
- Netlify
- GitHub Pages (with custom domain)

---

### Phase 5: Deployment

**5.1 Initial deployment**

```bash
# Install flyctl
curl -L https://fly.io/install.sh | sh

# Authenticate
fly auth login

# Create the app
fly apps create proof-pad-acl2

# Deploy (first deploy will take 30+ min for ACL2 build)
fly deploy --build-arg PORT=8080

# Check status
fly status
fly logs
```

**5.2 Set up custom domain (optional)**

```bash
fly certs create acl2.proofpad.org
```

**5.3 Scale as needed**

```bash
# Add machines in other regions for latency
fly scale count 2 --region ord,iad

# Adjust memory if needed
fly scale memory 4096
```

---

## Cost Estimation

| Resource | Fly.io | Notes |
|----------|--------|-------|
| Machines | ~$5-15/mo | 1-2 shared-cpu-2x with 2GB RAM |
| Bandwidth | ~$0-5/mo | First 100GB free |
| IPv4 | $2/mo | Per dedicated IP |
| **Total** | **~$7-22/mo** | Depending on usage |

---

## Risks and Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| Long build time (30+ min) | Slow deploys | Use remote builder, cache ACL2 layer |
| Memory pressure from ACL2 | OOM kills | Monitor and scale memory |
| WebSocket disconnections | User session loss | Implement reconnection logic |
| Cold starts | Slow first request | Keep min 1 machine running |
| Regional latency | Slow for distant users | Deploy to multiple regions |

---

## Implementation Checklist

- [x] **Phase 1**: Remove Google Cloud dependencies
  - [x] Replace `cloud.google.com/go/logging` with standard logging
  - [x] Remove HTTP request logging
  - [x] Update `go.mod` and `go.sum`
  - [ ] Test locally

- [x] **Phase 2**: Create Fly.io configuration
  - [x] Create `fly.toml`
  - [x] Create `.dockerignore`
  - [ ] Test Dockerfile locally

- [x] **Phase 3**: Optimize Docker build
  - [x] Convert to multi-stage build
  - [ ] Test build time improvement

- [x] **Phase 4**: Update frontend
  - [x] Make backend URL configurable (same-origin)
  - [x] Choose frontend hosting strategy (Fly.io via Go backend)
  - [ ] Test WebSocket connectivity

- [ ] **Phase 5**: Deploy
  - [ ] Create Fly.io account and app
  - [ ] Initial deployment
  - [ ] Configure DNS/SSL
  - [ ] Monitor and scale

---

## Quick Start Commands

```bash
# 1. Apply Go code changes (remove GCP logging)
# 2. Create fly.toml (see Phase 2)
# 3. Deploy

fly auth login
fly launch --name proof-pad-acl2 --region ord --no-deploy
fly deploy

# Monitor
fly logs -f
fly status
```

---

## References

- [Fly.io Documentation](https://fly.io/docs/)
- [Fly.io WebSocket Support](https://fly.io/docs/reference/websockets/)
- [Fly.io Dockerfile Deployment](https://fly.io/docs/reference/builders/#dockerfile)
- [ACL2 Documentation](https://www.cs.utexas.edu/users/moore/acl2/)

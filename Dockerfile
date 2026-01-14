# Stage 1: Build Go binary
FROM golang:1.21-bookworm AS go-builder
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY main.go ./
RUN CGO_ENABLED=0 go build -o /acl2-server

# Stage 2: Build ACL2 (cache this layer - takes 30+ min)
FROM debian:bookworm AS acl2-builder
RUN apt-get update && apt-get install -y --no-install-recommends \
    wget make perl build-essential sbcl ca-certificates \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /app
RUN wget https://github.com/acl2-devel/acl2-devel/releases/download/8.5/acl2-8.5.tar.gz && \
    tar xfz acl2-8.5.tar.gz && \
    rm acl2-8.5.tar.gz && \
    cd acl2-8.5 && \
    make LISP=sbcl && \
    cd books && \
    make ACL2=/app/acl2-8.5/saved_acl2 basic

# Stage 3: Build frontend
FROM node:20-bookworm-slim AS frontend-builder
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci
COPY tsconfig.json ./
COPY src/ src/
COPY index.html style.css ./
RUN npm run build

# Stage 4: Final runtime image
FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends \
    sbcl ca-certificates \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY --from=go-builder /acl2-server /acl2-server
COPY --from=acl2-builder /app/acl2-8.5 ./acl2-8.5
COPY --from=frontend-builder /app/dist ./static
COPY dracula dracula
ENV PORT=8080
EXPOSE 8080
CMD ["/acl2-server"]
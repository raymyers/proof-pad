# Stage 1: Build Go binary
FROM golang:1.23-bookworm AS go-builder
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY main.go ./
RUN CGO_ENABLED=0 go build -o /acl2-server

# Stage 2: Build frontend
FROM node:20-bookworm-slim AS frontend-builder
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci
COPY tsconfig.json ./
COPY src/ src/
COPY index.html style.css ./
RUN mkdir -p grammar && npm run build

# Stage 3: Final runtime image based on pre-built ACL2
FROM ghcr.io/jimwhite/acl2-jupyter:8.6
USER root
WORKDIR /app
COPY --from=go-builder /acl2-server /acl2-server
COPY --from=frontend-builder /app/dist ./static
COPY dracula dracula
ENV PORT=8080
EXPOSE 8080
CMD ["/acl2-server"]

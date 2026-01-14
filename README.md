# Proof Pad

Proof Pad is a web based IDE for
[ACL2](https://www.cs.utexas.edu/users/moore/acl2/), using [Fly.io](https://fly.io)
to run ACL2 itself on the backend. Users can write and verify functions
and theorems using a modern editor or a REPL interface. It's the evolution of
the [original Proof Pad project](https://github.com/calebegg/proof-pad-classic).

This is not an official Google product.

## Deploying to Fly.io

The application is deployed as a single Fly.io app that serves both the frontend
static files and the backend WebSocket API.

### First-time setup

```shell
# Install flyctl
curl -L https://fly.io/install.sh | sh

# Authenticate
fly auth login

# Create the app (first time only)
fly apps create proof-pad-acl2
```

### Deploy

```shell
fly deploy
```

Note: The first deploy takes 30+ minutes due to ACL2 compilation. Subsequent
deploys with cached layers are much faster.

### Monitor

```shell
fly status
fly logs -f
```

### Local development

To build the frontend locally:
```shell
npm install
npm run build
```

To run the Go backend locally (requires ACL2 installed):
```shell
go run main.go
```

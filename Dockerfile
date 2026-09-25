# Stage 1: Build the frontend (email-builder and Vue frontend)
FROM node:20-alpine AS frontend-builder
WORKDIR /app

# 1. Build email-builder
WORKDIR /app/frontend/email-builder
COPY frontend/email-builder/package.json frontend/email-builder/yarn.lock ./
RUN yarn install --frozen-lockfile || yarn install
COPY frontend/email-builder/ ./
RUN yarn build

# 2. Build Vue frontend
WORKDIR /app/frontend
COPY frontend/package.json frontend/yarn.lock ./
RUN mkdir -p /app/static/public/static
COPY static/ /app/static/
RUN yarn install --frozen-lockfile || yarn install
COPY frontend/ ./
# Copy built email-builder into frontend static assets
RUN mkdir -p public/static/email-builder && \
    cp -r /app/frontend/email-builder/dist/* public/static/email-builder/
RUN touch .gitignore && yarn build

# Stage 2: Build the Go backend and pack all assets with stuffbin
FROM golang:latest AS builder
WORKDIR /build

# Copy go mod files
COPY go.mod go.sum ./
RUN go mod download

# Copy source code
COPY . .

# Copy compiled frontend and static assets from frontend-builder
COPY --from=frontend-builder /app/frontend/dist ./frontend/dist
COPY --from=frontend-builder /app/static/public/static/altcha.umd.js ./static/public/static/altcha.umd.js

# Install stuffbin, compile binary, and pack assets into the standalone binary
RUN go install github.com/knadh/stuffbin/... && \
    CGO_ENABLED=0 GOOS=linux go build -o listmonk ./cmd && \
    $(go env GOPATH)/bin/stuffbin -a stuff -in listmonk -out listmonk \
      config.toml.sample \
      schema.sql queries:/queries permissions.json \
      static/public:/public \
      static/email-templates \
      frontend/dist:/admin \
      i18n:/i18n

# Stage 3: Minimal runtime container
FROM alpine:latest
RUN apk --no-cache add ca-certificates tzdata shadow su-exec
WORKDIR /listmonk

# Copy the compiled standalone binary and default config
COPY --from=builder /build/listmonk .
COPY config.toml.sample config.toml

# Copy entrypoint script
COPY docker-entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

EXPOSE 9000
ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["./listmonk"]
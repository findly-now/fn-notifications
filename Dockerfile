# Multi-stage Dockerfile for FN-Notifications
# Unified build for all environments: dev, qa, staging, prod
ARG MIX_ENV=prod

# Stage 1: Dependencies and compilation
FROM hexpm/elixir:1.16.3-erlang-26.2.5-alpine-3.19.1 as builder

# Install build dependencies
RUN apk add --no-cache \
    build-base \
    git \
    curl \
    cmake \
    make \
    postgresql-client

WORKDIR /app

# Set build environment
ARG MIX_ENV
ENV MIX_ENV=${MIX_ENV}

# Install hex and rebar
RUN mix local.hex --force && \
    mix local.rebar --force

# Copy mix files for dependency resolution
COPY mix.exs mix.lock ./

# Install dependencies based on environment
RUN if [ "$MIX_ENV" = "prod" ]; then \
        mix deps.get --only prod; \
    else \
        mix deps.get; \
    fi && \
    mix deps.compile

# Copy application source
COPY . ./

# Compile application
RUN mix compile

# Build release for production environments
RUN if [ "$MIX_ENV" = "prod" ] || [ "$MIX_ENV" = "staging" ]; then \
        mix assets.deploy 2>/dev/null || echo "No assets to deploy" && \
        mix release fn_notifications; \
    fi

# Stage 2: Runtime
FROM alpine:3.19.1 as runtime

# Install runtime dependencies
RUN apk add --no-cache \
    bash \
    openssl \
    ncurses-libs \
    curl \
    ca-certificates \
    tini

# Development environments need additional tools
ARG MIX_ENV
RUN if [ "$MIX_ENV" = "dev" ] || [ "$MIX_ENV" = "qa" ]; then \
        apk add --no-cache \
            inotify-tools \
            postgresql-client \
            elixir \
            erlang \
            git \
            build-base; \
    fi

# Create app user for security
RUN addgroup -g 1000 -S phoenix && \
    adduser -S phoenix -G phoenix -u 1000

# Create app directory
WORKDIR /app
RUN chown -R phoenix:phoenix /app

# Switch to non-root user
USER phoenix

# Set environment variables
ARG MIX_ENV
ENV MIX_ENV=${MIX_ENV}
ENV PHX_HOST=0.0.0.0
ENV PORT=4000
ENV PHX_SERVER=true

# Setup development environment
RUN if [ "$MIX_ENV" = "dev" ] || [ "$MIX_ENV" = "qa" ]; then \
        mix local.hex --force && \
        mix local.rebar --force; \
    fi

# Copy build artifacts
COPY --from=builder --chown=phoenix:phoenix /app /app

# Expose application port
EXPOSE 4000

# Health check for cloud readiness
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -f http://localhost:4000/api/health || exit 1

# Use tini for proper signal handling in cloud environments
ENTRYPOINT ["/sbin/tini", "--"]

# Environment-specific startup command
CMD if [ "$MIX_ENV" = "prod" ] || [ "$MIX_ENV" = "staging" ]; then \
        exec ./bin/fn_notifications start; \
    else \
        exec mix phx.server; \
    fi
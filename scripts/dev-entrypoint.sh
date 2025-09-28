#!/bin/bash
set -e

# Verify cloud service configuration
echo "Checking cloud service configuration..."

if [ -z "$DATABASE_URL" ]; then
  echo "❌ ERROR: DATABASE_URL environment variable not set"
  echo "Please configure cloud PostgreSQL connection"
  exit 1
fi

if [ -z "$KAFKA_BROKERS" ]; then
  echo "❌ ERROR: KAFKA_BROKERS environment variable not set"
  echo "Please configure Confluent Cloud connection"
  exit 1
fi

echo "✅ Cloud service configuration verified"

# Install dependencies
echo "Installing dependencies..."
mix deps.get

# Compile application
echo "Compiling application..."
mix compile

# Cloud database setup (schema should already be deployed)
echo "Note: Using cloud database - ensure schema is deployed with 'make deploy-schema-postgres'"

# Start server
echo "Starting Phoenix server..."
exec mix phx.server
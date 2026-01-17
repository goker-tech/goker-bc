# goker-bc Dockerfile
# Foundry for Solidity development

FROM ghcr.io/foundry-rs/foundry:latest AS builder

WORKDIR /app

# Copy project files
COPY . .

# Build contracts
RUN forge build

# Production stage for running tests/scripts
FROM ghcr.io/foundry-rs/foundry:latest

WORKDIR /app

# Copy built artifacts
COPY --from=builder /app /app

# Default command runs tests
CMD ["forge", "test"]

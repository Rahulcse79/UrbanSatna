# Multi-stage build: compile with the Rust toolchain, ship a slim runtime.
FROM rust:1-slim AS builder
WORKDIR /app
COPY . .
# Migrations are embedded at compile time (sqlx::migrate!), so the final
# image needs only the binary.
RUN cargo build --release

FROM debian:bookworm-slim
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates \
    && rm -rf /var/lib/apt/lists/*
COPY --from=builder /app/target/release/urbansatna-api /usr/local/bin/urbansatna-api
ENV LOG_FORMAT=json
EXPOSE 8080
CMD ["urbansatna-api"]

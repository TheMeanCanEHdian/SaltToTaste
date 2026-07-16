# SaltToTaste v2 — single-container image. Build from the repo root:
#
#   docker build -t salttotaste .
#
# Multi-arch release build:
#
#   docker buildx build \
#     --platform linux/amd64,linux/arm64 -t <registry>/salttotaste --push .
#
# Run:
#
#   docker run -d -p 8080:8080 -v salt-data:/data \
#     -v "/path/to/corpus:/data/import:ro" salttotaste
#
# /data MUST be a local filesystem (SQLite WAL is unsafe on NFS/SMB).

# ---- Stage 1: Flutter web build --------------------------------------
# Latest cirruslabs tag on the 3.44 line (3.44.3 exists only upstream).
FROM ghcr.io/cirruslabs/flutter:3.44.0 AS web
WORKDIR /src
# Pubspecs (+ lockfile) first, so `pub get` caches until a dependency
# actually changes — editing source no longer re-resolves everything.
COPY pubspec.yaml pubspec.lock analysis_options.yaml ./
COPY packages/salt_shared/pubspec.yaml packages/salt_shared/
COPY apps/app/pubspec.yaml apps/app/
COPY apps/server/pubspec.yaml apps/server/
RUN flutter pub get --enforce-lockfile
COPY packages/ packages/
COPY apps/app/ apps/app/
WORKDIR /src/apps/app
# --no-web-resources-cdn: CanvasKit + fonts come from the app itself, so
# the same-origin CSP holds and the container runs fully offline.
RUN flutter build web --release --no-web-resources-cdn

# ---- Stage 2: Dart Frog AOT compile ----------------------------------
FROM dart:3.12.2 AS server
WORKDIR /src
COPY pubspec.yaml pubspec.lock analysis_options.yaml ./
COPY packages/salt_shared/pubspec.yaml packages/salt_shared/
COPY apps/app/pubspec.yaml apps/app/
COPY apps/server/pubspec.yaml apps/server/
# The workspace lists apps/app, whose Flutter deps the pure-Dart SDK can't
# fetch — drop it from the member list for the server-only resolve.
RUN sed -i 's|^  - apps/app$||' pubspec.yaml && dart pub get
COPY packages/ packages/
COPY apps/server/ apps/server/
WORKDIR /src/apps/server
# dart_frog only wires its static-file handler when public/ exists at
# build time; the real web build is copied into the runtime stage. Pin the
# CLI so a future major bump can't silently change the generated entry.
RUN mkdir -p public && \
    dart pub global activate dart_frog_cli 1.2.14 && \
    dart pub global run dart_frog_cli:dart_frog build && \
    mkdir -p /out && \
    dart compile exe build/bin/server.dart -o /out/server && \
    dart compile exe bin/healthcheck.dart -o /out/healthcheck

# ---- Stage 3: slim runtime -------------------------------------------
FROM debian:bookworm-slim
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      libsqlite3-0 ca-certificates tzdata && \
    rm -rf /var/lib/apt/lists/* && \
    # package:sqlite3 dlopens the unversioned name, which only -dev ships.
    ln -s "$(find /usr/lib -name libsqlite3.so.0 | head -1)" \
      /usr/local/lib/libsqlite3.so && ldconfig && \
    useradd --system --uid 1000 --create-home salt && \
    mkdir -p /data && chown salt:salt /data
WORKDIR /app
COPY --from=server /out/server /out/healthcheck /app/
COPY --from=web /src/apps/app/build/web/ /app/public/
ENV DATA_DIR=/data PORT=8080
EXPOSE 8080
VOLUME /data
USER salt
# start-period covers the synchronous library scan at boot (a large
# library on slow storage takes a while); retries add headroom.
HEALTHCHECK --interval=30s --timeout=5s --start-period=120s --retries=5 \
  CMD ["/app/healthcheck"]
CMD ["/app/server"]

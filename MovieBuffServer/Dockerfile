# syntax=docker/dockerfile:1

# ================================
# Build image
# ================================
FROM swift:6.0-jammy AS build

# Install jemalloc dev headers (needed by the `-ljemalloc` linker flag below).
RUN export DEBIAN_FRONTEND=noninteractive DEBCONF_NONINTERACTIVE_SEEN=true && \
    apt-get -q update && \
    apt-get -q dist-upgrade -y && \
    apt-get -q install -y libjemalloc-dev && \
    rm -r /var/lib/apt/lists/*

WORKDIR /build

# Resolve dependencies first so this layer is cached until Package.* changes.
# BuildKit cache mounts persist /build/.build and ~/.swiftpm across deploys, so
# unchanged packages (BoringSSL, NIO, etc.) skip recompilation on subsequent builds.
COPY ./Package.* ./
RUN --mount=type=cache,target=/build/.build \
    --mount=type=cache,target=/root/.swiftpm \
    swift package resolve $([ -f ./Package.resolved ] && echo "--force-resolved-versions" || true)

# Copy the rest of the sources.
COPY . .

# Build AND stage artifacts in a single RUN so the cache mount is live for both
# the build and the cp steps that follow (BuildKit tears down cache mounts
# between RUNs). Dropping --static-swift-stdlib halves the linker's peak RAM;
# instead we ship the swift runtime via the swift:*-slim image below.
# --disable-index-store skips index-store generation (~10% faster, only useful
# for IDEs which don't apply on Render).
RUN --mount=type=cache,target=/build/.build \
    --mount=type=cache,target=/root/.swiftpm \
    swift build -c release -j 1 -Xlinker -ljemalloc --disable-index-store && \
    mkdir -p /staging && \
    BIN_PATH="$(swift build --package-path /build -c release --show-bin-path)" && \
    cp "$BIN_PATH/App" /staging/ && \
    cp /usr/libexec/swift/linux/swift-backtrace-static /staging/ && \
    find -L "$BIN_PATH/" -regex '.*\.resources$' -exec cp -Ra {} /staging/ \; && \
    { [ -d /build/Public ]    && { cp -R /build/Public    /staging/Public;    chmod -R a-w /staging/Public;    } || true; } && \
    { [ -d /build/Resources ] && { cp -R /build/Resources /staging/Resources; chmod -R a-w /staging/Resources; } || true; }

# ================================
# Run image
# ================================
FROM swift:6.0-jammy-slim

# Install runtime dependencies + drop root privileges.
RUN export DEBIAN_FRONTEND=noninteractive DEBCONF_NONINTERACTIVE_SEEN=true && \
    apt-get -q update && \
    apt-get -q dist-upgrade -y && \
    apt-get -q install -y \
      libjemalloc2 \
      ca-certificates \
      tzdata \
      libcurl4 \
      libxml2 \
    && rm -r /var/lib/apt/lists/*

RUN useradd --user-group --create-home --system --skel /dev/null --home-dir /app vapor
WORKDIR /app
COPY --from=build --chown=vapor:vapor /staging /app

ENV SWIFT_BACKTRACE=enable=yes,sanitize=yes,threads=all,images=all,interactive=no,swift-backtrace=./swift-backtrace-static

USER vapor:vapor
EXPOSE 8080
ENTRYPOINT ["./App"]
CMD ["serve", "--env", "production", "--hostname", "0.0.0.0", "--port", "8080"]

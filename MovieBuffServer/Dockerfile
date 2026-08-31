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
COPY ./Package.* ./
RUN swift package resolve $([ -f ./Package.resolved ] && echo "--force-resolved-versions" || true)

# Copy the rest of the sources.
COPY . .

# Serial release build. Dropping --static-swift-stdlib halves the linker's peak RAM;
# instead we ship the swift runtime via the swift:*-slim image below.
RUN swift build -c release -j 1 -Xlinker -ljemalloc

# Stage the artifacts we actually need to run.
WORKDIR /staging
RUN cp "$(swift build --package-path /build -c release --show-bin-path)/App" ./
RUN cp "/usr/libexec/swift/linux/swift-backtrace-static" ./
RUN find -L "$(swift build --package-path /build -c release --show-bin-path)/" -regex '.*\.resources$' -exec cp -Ra {} ./ \;
RUN [ -d /build/Public ] && { mv /build/Public ./Public && chmod -R a-w ./Public; } || true
RUN [ -d /build/Resources ] && { mv /build/Resources ./Resources && chmod -R a-w ./Resources; } || true

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

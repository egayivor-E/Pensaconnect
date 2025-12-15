# Use the correct Flutter Docker image
FROM ghcr.io/cirruslabs/flutter:stable AS build

WORKDIR /app

# Install web dependencies and Chrome for testing
RUN apt-get update && apt-get install -y \
    curl \
    unzip \
    libglu1-mesa \
    && rm -rf /var/lib/apt/lists/*

# Best Practice: Run build steps as a non-root user
RUN useradd -m --shell /bin/bash nonroot

# Add Flutter to PATH for nonroot user
RUN echo 'export PATH="$PATH:/flutter/bin"' >> /home/nonroot/.bashrc

# Check where Flutter is actually installed in this image
RUN FLUTTER_PATH=$(find / -type d -name "flutter" 2>/dev/null | head -1) && \
    if [ -n "$FLUTTER_PATH" ]; then \
        echo "Flutter found at: $FLUTTER_PATH" && \
        chown -R nonroot:nonroot "$FLUTTER_PATH" && \
        echo "export PATH=\"\$PATH:$FLUTTER_PATH/bin\"" >> /home/nonroot/.bashrc; \
    else \
        echo "Warning: Flutter directory not found." && \
        echo "export PATH=\"\$PATH:/flutter/bin\"" >> /home/nonroot/.bashrc; \
    fi

RUN chown -R nonroot:nonroot /app
ENV HOME /home/nonroot
ENV PATH="$PATH:/flutter/bin"
USER nonroot

# Ensure Flutter is available
RUN which flutter && flutter --version

# Copy pubspec files first for better layer caching
COPY --chown=nonroot:nonroot pubspec.yaml pubspec.lock ./

# Keep the suppress flag for robustness
RUN flutter pub get --suppress-analytics

# Copy the rest of the code
COPY --chown=nonroot:nonroot . .

# Enable web support and get dependencies
RUN flutter config --enable-web

# Build for web with optimizations
RUN flutter build web --release \
    --web-renderer canvaskit \
    --dart-define=BACKEND_URL="${BACKEND_URL:-https://pensaconnect.onrender.com}" \
    --pwa-strategy offline-first \
    --source-maps

# ----------------------------------------------------
# Production Stage (NGINX)
# ----------------------------------------------------
FROM nginx:alpine
COPY --from=build /app/build/web /usr/share/nginx/html
COPY nginx.conf /etc/nginx/nginx.conf

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD wget --no-verbose --tries=1 --spider http://localhost:80/ || exit 1

EXPOSE 80
# Use the correct Flutter Docker image
FROM ghcr.io/cirruslabs/flutter:stable AS build

WORKDIR /app

# Install web dependencies
RUN apt-get update && apt-get install -y \
    curl \
    unzip \
    libglu1-mesa \
    && rm -rf /var/lib/apt/lists/*

# Best Practice: Run build steps as a non-root user
RUN useradd -m --shell /bin/bash nonroot

# First, fix the Flutter Git safety issue
# Flutter is located at /sdks/flutter in this image
RUN FLUTTER_PATH="/sdks/flutter" && \
    if [ -d "$FLUTTER_PATH" ]; then \
        echo "Flutter found at: $FLUTTER_PATH" && \
        # Fix Git safety directory issue for all users
        git config --global --add safe.directory "$FLUTTER_PATH" && \
        # Set proper ownership for nonroot user
        chown -R nonroot:nonroot "$FLUTTER_PATH" || true; \
    else \
        echo "Warning: Flutter directory not found at /sdks/flutter"; \
    fi

# Add Flutter to PATH for all users
ENV PATH="$PATH:/sdks/flutter/bin"

RUN chown -R nonroot:nonroot /app
ENV HOME /home/nonroot
USER nonroot

# Copy pubspec files first for better layer caching
COPY --chown=nonroot:nonroot pubspec.yaml pubspec.lock ./

# Keep the suppress flag for robustness
RUN flutter pub get --suppress-analytics

# Copy the rest of the code
COPY --chown=nonroot:nonroot . .

# Enable web support if not already enabled
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
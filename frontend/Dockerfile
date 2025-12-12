# Multi-stage build
FROM cirrusci/flutter:stable AS build

WORKDIR /app

# Copy pubspec files first for better layer caching
COPY pubspec.yaml pubspec.lock ./
RUN flutter pub get

# Copy the rest of the code
COPY . .

# Build for web with optimizations
RUN flutter build web --release \
    --web-renderer canvaskit \
    --dart-define=BACKEND_URL=${BACKEND_URL:-https://pensaconnect.onrender.com} \
    --pwa-strategy offline-first \
    --source-maps

# Production stage
FROM nginx:alpine

# Copy built web files
COPY --from=build /app/build/web /usr/share/nginx/html

# Add nginx configuration for SPA routing
COPY nginx.conf /etc/nginx/nginx.conf

# Health check (optional but recommended)
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://localhost:80/ || exit 1

EXPOSE 80
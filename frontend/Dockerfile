FROM cirrusci/flutter:latest AS build 

# ... (Previous WORKDIR /app and useradd steps)
WORKDIR /app

# Best Practice: Run build steps as a non-root user
RUN useradd --no-create-home --shell /bin/false nonroot

# FIX: Change ownership of the Flutter SDK to the nonroot user.
# This prevents "Permission denied" on cache/version files and "dubious ownership" from Git.
RUN chown -R nonroot:nonroot /sdks/flutter

# Change ownership of the app directory
RUN chown -R nonroot:nonroot /app

# Switch to the non-root user
USER nonroot

# Copy pubspec files first for better layer caching
COPY pubspec.yaml pubspec.lock ./

# FIX: Suppress analytics to bypass tool initialization failure (Exit Code 255)
RUN flutter pub get --suppress-analytics

# Copy the rest of the code
COPY . /app

# Run the build
RUN flutter build web --release

# ... (Rest of the Dockerfile)

# Copy the rest of the code
COPY . .

# Build for web with optimizations
RUN flutter build web --release \
    --web-renderer canvaskit \
    --dart-define=BACKEND_URL=${BACKEND_URL:-https://pensaconnect.onrender.com} \
    --pwa-strategy offline-first \
    --source-maps

# ----------------------------------------------------
# Production Stage (NGINX)
# ----------------------------------------------------
# Nginx is a great choice for serving static Flutter web builds.
FROM nginx:alpine

# Copy built web files from the 'build' stage
# NGINX runs as a non-root user (nginx) in the alpine image, so no further user change is needed here.
COPY --from=build /app/build/web /usr/share/nginx/html

# Add custom nginx configuration for SPA routing
COPY nginx.conf /etc/nginx/nginx.conf

# Health check (optional but recommended)
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD wget --no-verbose --tries=1 --spider http://localhost:80/ || exit 1

EXPOSE 80
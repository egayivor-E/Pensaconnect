FROM cirrusci/flutter:latest AS build 

# ... (Lines before WORKDIR /app)

WORKDIR /app

# Best Practice: Run build steps as a non-root user

# 1. Create the user with a real home directory (e.g., /home/nonroot)
RUN useradd -m --shell /bin/bash nonroot

# 2. FIX: Change ownership of the Flutter SDK to the nonroot user.
RUN chown -R nonroot:nonroot /sdks/flutter

# 3. Change ownership of the app directory
RUN chown -R nonroot:nonroot /app

# 4. EXPLICIT FIX: Set the HOME variable for Flutter
# The default HOME is /home/nonroot, but setting it explicitly helps in CI.
ENV HOME /home/nonroot

# 5. Switch to the non-root user
USER nonroot

# Copy pubspec files first for better layer caching
COPY pubspec.yaml pubspec.lock ./

# Keep the suppress flag for robustness
RUN flutter pub get --suppress-analytics

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
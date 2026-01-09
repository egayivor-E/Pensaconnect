# Use a specific version if possible for stability (e.g., 3.27.0)
FROM ghcr.io/cirruslabs/flutter:stable AS build

WORKDIR /app

# 1. Copy pubspec files
COPY pubspec.yaml pubspec.lock ./

# 2. Get dependencies
RUN flutter pub get --suppress-analytics

# 3. Copy the rest of the code
COPY . .

# 4. Fix assets and .env
# Ensure the assets directory exists and create the .env file safely
RUN mkdir -p assets && \
    echo "BACKEND_URL=https://pensaconnect-pjz9.onrender.com/" > assets/.env

# 5. Generate code (Using 'dart run' which is the modern standard)
RUN dart run build_runner build --delete-conflicting-outputs

# 6. Build Web 
ARG BACKEND_URL=https://pensaconnect-pjz9.onrender.com
# Explicitly using canvaskit to avoid Wasm issues if your environment isn't ready for it
RUN flutter build web --release \
    --web-renderer canvaskit \
    --dart-define=BACKEND_URL=$BACKEND_URL \
    --no-tree-shake-icons \
    --verbose

# ----------------------------------------------------
# Production Stage
# ----------------------------------------------------
FROM nginx:alpine
# Ensure we copy from the correct Flutter web build path
COPY --from=build /app/build/web /usr/share/nginx/html
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
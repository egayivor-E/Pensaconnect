# Use Flutter Docker image
FROM ghcr.io/cirruslabs/flutter:stable AS build

WORKDIR /app

# 1. Copy pubspec files first
COPY pubspec.yaml pubspec.lock ./

# 2. Get dependencies
RUN flutter pub get --suppress-analytics

# 3. Copy the rest of the code
COPY . .

# 4. Fix the .env file pathing
# Ensure the assets directory exists where your pubspec expects it
RUN mkdir -p assets && \
    cp assets/.env assets/.env || echo "BACKEND_URL=https://pensaconnect-pjz9.onrender.com/" > assets/.env

# 5. Generate code for freezed/json_serializable
RUN flutter pub run build_runner build --delete-conflicting-outputs

# 6. Single Build Command
# Removed the duplicate RUN command and fixed the variable syntax
# Single Build Command (removed --no-wasm)
ARG BACKEND_URL=https://pensaconnect-pjz9.onrender.com
RUN flutter build web --release \
    --dart-define=BACKEND_URL=$BACKEND_URL \
    --no-tree-shake-icons \
    --verbose

# ----------------------------------------------------
# Production Stage (NGINX)
# ----------------------------------------------------
FROM nginx:alpine

# Copy built web files
COPY --from=build /app/build/web /usr/share/nginx/html

# EXPOSE is fine, but ensure your nginx.conf handles SPA routing
EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
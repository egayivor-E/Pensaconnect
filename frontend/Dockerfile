FROM cirrusci/flutter:stable AS build
WORKDIR /app
COPY frontend /app
RUN flutter pub get && flutter build web
FROM nginx:alpine
COPY --from=build /app/build/web /usr/share/nginx/html
EXPOSE 80

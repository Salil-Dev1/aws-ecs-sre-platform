FROM node:20-alpine AS build
WORKDIR /src
COPY app/frontend/package*.json ./
RUN npm install
COPY app/frontend/ ./
RUN npm run build

FROM nginxinc/nginx-unprivileged:alpine
COPY app/frontend/nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /src/dist /usr/share/nginx/html
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD wget -qO- http://127.0.0.1:8080/ >/dev/null || exit 1

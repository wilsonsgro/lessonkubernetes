# Build di produzione del frontend per Kubernetes: Dockerfile.prod di src/ non passa VITE_API_BASE_URL e cerca certificati che nel pod non ci sono.
FROM node:25-alpine3.23 AS builder
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci
COPY . .
ARG VITE_API_BASE_URL
ENV VITE_API_BASE_URL=${VITE_API_BASE_URL}
RUN npm run build

FROM nginx:1.27-alpine
COPY --from=builder /app/dist /usr/share/nginx/html
COPY nginx-k8s.conf /etc/nginx/conf.d/default.conf
EXPOSE 8080

FROM node:20-bookworm-slim AS build
WORKDIR /app

ARG VITE_API_BASE_URL
ARG VITE_SOCKET_URL
ENV VITE_API_BASE_URL=$VITE_API_BASE_URL
ENV VITE_SOCKET_URL=$VITE_SOCKET_URL

COPY package.json package-lock.json ./
RUN npm ci --no-audit --no-fund

COPY . .
RUN npm run build

FROM node:20-bookworm-slim AS runtime
ENV NODE_ENV=production
WORKDIR /app

RUN npm i -g serve@14.2.6

COPY --from=build /app/dist ./dist

EXPOSE 8080
CMD ["serve","-s","dist","-l","8080"]

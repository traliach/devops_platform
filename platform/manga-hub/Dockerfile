# ── Stage 1: Build ───────────────────────────────────────────────────────────
# Use Node 20 LTS alpine — small image, enough to run Vite build
FROM node:20-alpine AS build

WORKDIR /app

# Copy package files first — layer cache means npm ci only re-runs when deps change
COPY package*.json ./
RUN npm ci

# Copy source and build
COPY . .
RUN npm run build
# Output: /app/dist

# ── Stage 2: Serve ───────────────────────────────────────────────────────────
# nginx:alpine — ~25MB, serves the static dist/ output
FROM nginx:alpine

# Custom nginx config — handles React Router (client-side routing)
COPY nginx.conf /etc/nginx/conf.d/default.conf

# Copy built assets from Stage 1
COPY --from=build /app/dist /usr/share/nginx/html

EXPOSE 80

HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
  CMD wget -qO- http://localhost/health || exit 1

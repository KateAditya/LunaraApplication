# Stage 1: Build the Admin Panel (React)
FROM node:20-alpine AS admin-build
WORKDIR /app/admin-panel
COPY admin-panel/package*.json ./
RUN npm ci
COPY admin-panel/ ./
RUN npm run build

# Stage 2: Build the Server (Node.js)
FROM node:20-alpine AS server-build
WORKDIR /app/server
COPY server/package*.json ./
RUN npm ci
COPY server/ ./
RUN npm run build

# Stage 3: Production Environment
FROM node:20-alpine
WORKDIR /app
# We run the server from the /app/server directory
WORKDIR /app/server
COPY --from=server-build /app/server/package*.json ./
RUN npm ci --only=production

# Copy built server code
COPY --from=server-build /app/server/dist ./dist

# Copy built admin panel so the server can serve it statically
COPY --from=admin-build /app/admin-panel/dist /app/admin-panel/dist

# Expose the API port
EXPOSE 5000

# Start the Node server
CMD ["node", "dist/server.js"]

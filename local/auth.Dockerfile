# Dockerfile simple para desarrollo local (hot-reload)
FROM node:20-alpine

WORKDIR /app

COPY auth-service/package*.json ./

RUN npm install

COPY auth-service .

EXPOSE 4000

CMD ["npm", "run", "start:dev"]

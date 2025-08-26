# Dockerfile específico para storage-service en entorno local
FROM node:20-alpine

WORKDIR /app

RUN apk add --no-cache curl

COPY storage-service/package*.json ./
COPY storage-service/tsconfig*.json ./
COPY storage-service/nest-cli.json ./

RUN npm install

COPY storage-service/src ./src

EXPOSE 4001

CMD ["npm", "run", "start:dev"]

FROM node:20-alpine
WORKDIR /app
COPY src/app/package.json .
RUN npm ci --omit=dev || npm install --omit=dev
COPY src/app/ ./
EXPOSE 8080
ENV PORT=8080
CMD ["npm","start"]

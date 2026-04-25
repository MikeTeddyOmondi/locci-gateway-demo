FROM node:22-alpine
RUN addgroup -S locci && adduser -S locci -G locci
WORKDIR /app
COPY index.mjs ./
USER locci
EXPOSE 3002
CMD ["node", "index.mjs"]

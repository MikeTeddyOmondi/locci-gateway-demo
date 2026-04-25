FROM node:22-alpine
RUN addgroup -S locci && adduser -S locci -G locci
WORKDIR /app
COPY index.mjs ./
USER locci
EXPOSE 3003
CMD ["node", "index.mjs"]

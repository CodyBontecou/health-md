# Deployments must supply a reviewed immutable image digest.
ARG NODE_IMAGE
FROM ${NODE_IMAGE}
WORKDIR /app
COPY --chown=node:node package.json package-lock.json ./
COPY --chown=node:node src ./src
USER node
ENV NODE_ENV=production
EXPOSE 8792 8793
CMD ["node","src/server.mjs"]

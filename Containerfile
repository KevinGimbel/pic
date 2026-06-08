FROM node:24-bookworm-slim

ENV PI_VERSION="0.79.0"

RUN apt-get update && apt-get install -y --no-install-recommends \
    bash \
    ca-certificates \
    curl \
    git \
    ripgrep \
  && rm -rf /var/lib/apt/lists/*

RUN npm install -g @earendil-works/pi-coding-agent@${PI_VERSION}

RUN mkdir -p /home/node/.pi/agent && chown -R node:node /home/node/.pi

USER node
WORKDIR /workspace
ENV HOME=/home/node

# Add local `bin` directories to PATH
ENV PATH="$PATH:./bin"

ENTRYPOINT ["pi"]

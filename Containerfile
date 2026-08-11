FROM node:26-trixie-slim

ENV PI_VERSION="0.84.1"

RUN apt-get update && apt-get install -y --no-install-recommends \
    bash \
    ca-certificates \
    curl \
    git \
    ripgrep \
  && rm -rf /var/lib/apt/lists/*

RUN npm install -g @earendil-works/pi-coding-agent@${PI_VERSION}

USER node
WORKDIR /workspace
ENV HOME=/home/node

# Add local `bin` directories to PATH
ENV PATH="$PATH:./bin"

ENTRYPOINT ["pi"]

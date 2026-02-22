# The build image could be golang, but it currently does not support riscv64. Only debian:sid does, at the time of writing.
FROM debian:sid-slim AS build

ARG version
ARG BRIDGE_REPO=https://github.com/bolausson/proton-bridge.git
ARG BRIDGE_REF=master
ARG GLUON_REPO=https://github.com/bolausson/gluon.git
ARG GLUON_REF=dev

# Install dependencies
RUN apt-get update && apt-get install -y golang build-essential libsecret-1-dev libfido2-dev libcbor-dev git

# Clone both repositories as siblings so go.mod replace directive (../gluon) works
RUN git clone --depth 1 --branch ${GLUON_REF} ${GLUON_REPO} /build/gluon
RUN git clone --depth 1 --branch ${BRIDGE_REF} ${BRIDGE_REPO} /build/proton-bridge

# Build
WORKDIR /build/proton-bridge/
RUN make build-nogui vault-editor

FROM debian:sid-slim
LABEL maintainer="Simon Felding <sife@adm.ku.dk>"

EXPOSE 25/tcp
EXPOSE 143/tcp

# Install dependencies and protonmail bridge
RUN apt-get update \
    && apt-get install -y --no-install-recommends socat pass libsecret-1-0 ca-certificates libfido2-1 procps tmux \
    && rm -rf /var/lib/apt/lists/*

# Copy bash scripts
COPY gpgparams entrypoint.sh /protonmail/

# Copy protonmail
COPY --from=build /build/proton-bridge/bridge /protonmail/
COPY --from=build /build/proton-bridge/proton-bridge /protonmail/
COPY --from=build /build/proton-bridge/vault-editor /protonmail/

ENTRYPOINT ["bash", "/protonmail/entrypoint.sh"]

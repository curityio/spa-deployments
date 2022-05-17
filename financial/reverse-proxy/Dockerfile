FROM kong:2.6.0-alpine

# Fetch from luarocks, and set git options if required
USER root
RUN git config --global url."https://".insteadOf git:// && \
    git config --global advice.detachedHead false &&
    luarocks install kong-oauth-proxy && \
    luarocks install kong-phantom-token

USER kong
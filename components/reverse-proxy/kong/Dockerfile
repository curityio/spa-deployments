FROM kong:2.6.0-alpine

# Fetch from luarocks, and set git options if required
USER root
RUN git config --global url."https://".insteadOf git:// && \
    git config --global advice.detachedHead false && \
    luarocks install kong-oauth-proxy   1.2.0 && \
    luarocks install kong-phantom-token 1.1.1

USER kong
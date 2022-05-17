FROM kong:2.6.0-alpine

USER root
RUN git config --global url."https://".insteadOf git:// && \
    luarocks install kong-oauth-proxy && \
    luarocks install kong-phantom-token
USER kong
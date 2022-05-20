FROM openresty/openresty:1.19.9.1-2-bionic

# Fetch from luarocks, and set git options if required
RUN apt-get update && apt-get install git -y
RUN git config --global url."https://".insteadOf git:// && \
    git config --global advice.detachedHead false && \
    luarocks install kong-oauth-proxy && \
    luarocks install kong-phantom-token

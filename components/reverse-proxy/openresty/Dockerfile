FROM openresty/openresty:1.19.9.1-2-bionic

# Fetch from luarocks, and set git options if required
RUN apt-get update && apt-get install git -y
RUN git config --global url."https://".insteadOf git:// && \
    git config --global advice.detachedHead false && \
    luarocks install lua-resty-oauth-proxy   1.2.0 && \
    luarocks install lua-resty-phantom-token 1.1.1

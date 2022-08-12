FROM nginx:1.21.6-alpine

# Download the built modules from Curity GitHub repo
RUN curl -s -L 'https://github.com/curityio/nginx_phantom_token_module/releases/download/1.3.0/alpine.ngx_curity_http_phantom_token_module_1.21.6.so' > /usr/lib/nginx/modules/ngx_curity_http_phantom_token_module.so
RUN curl -s -L 'https://github.com/curityio/nginx_oauth_proxy_module/releases/download/1.1.0/alpine.ngx_curity_http_oauth_proxy_module_1.21.6.so'     > /usr/lib/nginx/modules/ngx_curity_http_oauth_proxy_module.so

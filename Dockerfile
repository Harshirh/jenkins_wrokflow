FROM nginx:alpine

COPY *.html /usr/share/nginx/html/
COPY style.css /usr/share/nginx/html/style.css
COPY images/ /usr/share/nginx/html/images/

EXPOSE 80

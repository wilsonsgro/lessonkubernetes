# Il sito: una pagina statica servita da nginx; la versione entra nell'immagine al build.
FROM nginx:1.29-alpine
ARG VERSIONE=v1
COPY index.html /usr/share/nginx/html/index.html
RUN sed -i "s/__VERSIONE__/${VERSIONE}/g" /usr/share/nginx/html/index.html

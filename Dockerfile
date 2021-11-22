#####################################################################################
#  Build Application Image - Run below command
#
#     docker build . -t yourname/example-service:1.0.0 -f ./Dockerfile
#
######################################################################################
FROM suvera/winter-boot:latest

USER root
LABEL maintainer="yourname@example.com"

RUN useradd -ms /bin/bash app && mkdir -p /home/app/lib && mkdir -p /home/app/config

COPY ./target/phar/example-service-*.phar /home/app/lib/example-service.phar
COPY ./config/* /home/app/config/

RUN chown -R app /home/app

USER app
WORKDIR /home/app

ENTRYPOINT ["php", "/home/app/lib/example-service.phar", "-c", "/home/app/config"]

EXPOSE 8080
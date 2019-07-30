#!/bin/bash
#docker pull docker-registry.intr/webservices/php73:master
docker run --rm  \
           --read-only \
           --name apache-73-test-8075 \
           --net=host \
           --mount type=tmpfs,destination=/run \
           --mount type=tmpfs,destination=/tmp,tmpfs-mode=1777 \
            -e "HTTPD_PORT=8075" \
            -e "HTTPD_SERVERNAME=web344" \
            -v /etc/passwd:/etc/passwd:ro \
            -v /etc/group:/etc/group:ro \
            -v /home/u168138:/home/u168138:rw \
            -v /opcache:/opcache:rw \
            -v $(pwd)/spool-postfix:/var/spool/postfix:rw \
            -v $(pwd)/lib-postfix:/var/lib/postfix:rw \
            -v $(pwd)/phpsec/defaultsec.ini:/etc/php.d/defaultsec.ini:ro \
            -v $(pwd)/sites-enabled:/read/sites-enabled:ro \
            docker-registry.intr/webservices/php73:master


#-v $(pwd)/postfix-conf-test:/etc/postfix:ro \

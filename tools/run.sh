#!/bin/bash
docker run --rm --net=host \
           --name php72 \
           --mount type=tmpfs,destination=/run \
            -e "HTTPD_PORT=8075" \
            -e "HTTPD_SERVERNAME=web99" \
            -v /etc/passwd:/etc/passwd:ro \
            -v /etc/group:/etc/group:ro \
            -v /home/u168138:/home/u168138:rw \
            -v /opcache:/opcache:rw \
            -v /var/spool/postfix:/var/spool/postfix:rw \
            -v $(pwd)/phpsec/defaultsec.ini:/etc/php.d/defaultsec.ini:ro \
            -v $(pwd)/sites-enabled:/read/sites-enabled:ro \
            docker-registry.intr/webservices/php72:master --read-only

# --read-only
#            -v /var/lib/postfix:/var/lib/postfix:rw \


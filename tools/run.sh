#!/bin/bash
docker run --rm --net=host \
           --mount type=tmpfs,destination=/run \
            -v /etc/passwd:/etc/passwd:ro \
            -v /etc/group:/etc/group:ro \
            -v /home/u168138:/home/u168138:rw \
            -v /opcache:/opcache:rw \
            -v $(pwd)/sites-enabled:/read/sites-enabled:ro \
            docker-registry.intr/webservices/php72:master --read-only


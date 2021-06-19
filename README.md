# Apache PHP 7.3

Docker container with Apache PHP 7.3 build by [Nix package manager](https://nixos.org/).

## Prerequisites

Before you begin, ensure you have met the following requirements:

* You have a `<Linux/Mac>` machine.
* You have installed the latest version of [Nix package manager](https://nixos.org/) and [Docker daemon](https://www.docker.com).

## Building Apache PHP 7.3

To build Apache PHP 7.3, follow these steps:

Linux and macOS:
``` shell
nix-build .#container-master
docker load --input ./result
```

Hint: If you failed to build with your current nixpkgs version, try to
build with a tested [nixpkgs](https://github.com/NixOS/nixpkgs "Nix
Packages collection") version.

[![Build Status](https://jenkins.majordomo.ru/job/webservices/job/apache2-php73/job/master/lastBuild/badge/icon?config=webservices-apache2-php73)](https://jenkins.majordomo.ru/job/webservices/job/apache2-php73/job/master/lastBuild/badge/icon?config=webservices-apache2-php73)

## Using Apache PHP 7.3

To use Apache PHP 7.3, call:

``` shell
docker inspect docker-registry.intr/webservices/apache2-php73 | grep cmd
```

which will produce flags for `docker run` command as a hint.

For example:

``` shell
docker run --read-only --network=host \
        --mount readonly,source=/etc/ssl,target=/etc/ssl,type=bind \
        --mount readonly,source=$SITES_CONF_PATH,target=/read/sites-enabled,type=bind \
        --mount readonly,source=/opt/etc,target=/opt/etc,type=bind \
        --mount source=/opt/postfix/spool/maildrop,target=/var/spool/postfix/maildrop,type=bind \
        --mount source=/opt/postfix/spool/public,target=/var/spool/postfix/public,type=bind \
        --mount source=/opt/postfix/lib,target=/var/lib/postfix,type=bind \
        --mount source=/opcache,target=/opcache,type=bind \
        --mount target=/run,type=tmpfs \
        --mount source=/home,target=/home,type=bind \
        --tmpfs /tmp:mode=1777 \
        --tmpfs /run/bin:exec,suid \
        -e HTTPD_PORT=$SOCKET_HTTP_PORT \
        -e PHP_INI_SCAN_DIR=:/etc/phpsec/$SECURITY_LEVEL \
        -e PHP_SECURITY=/etc/phpsec/$SECURITY_LEVEL \
        --ulimit stack=-1:-1 \
        --cap-add SYS_ADMIN \
        --security-opt apparmor:unconfined docker-registry.intr/webservices/apache2-php73:latest
```
before running the command you need to provide all variables:

* `$SITES_CONF_PATH` should point to a directory with Apache's configuration files for vhosts.
* `$SECURITY_LEVEL` should be one of: `default`, `unsafe`, `hardened`, `hardened-nochmod`.
* `$SOCKET_HTTP_PORT` any free port on your computer, e.g. `8080`.

## Contributing to Apache PHP 7.3

To contribute to Apache PHP 7.3, follow these steps:

1. Fork this repository.
2. Create a branch: `git checkout -b <branch_name>`.
3. Make your changes and commit them: `git commit -m '<commit_message>'`
4. Push to the original branch: `git push origin <project_name>/<location>`
5. Create the pull request.

## Contact

If you want to contact me you can reach us at <support@majordomo.ru>.

## License

This project uses the following license: [GPL3+](https://www.gnu.org/licenses/gpl-3.0.en.html).

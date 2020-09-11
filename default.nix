{ nixpkgs ? (import ./common.nix).nixpkgs }:

with nixpkgs;

let
  inherit (builtins) concatMap getEnv toJSON;
  inherit (dockerTools) buildLayeredImage;
  inherit (lib)
    concatMapStringsSep firstNChars flattenSet dockerRunCmd mkRootfs;
  inherit (lib.attrsets) collect isDerivation;
  inherit (stdenv) mkDerivation;

  php73DockerArgHints = lib.phpDockerArgHints { php = php73; };

  shell = sh;

  xdebug = buildPhp73Package {
    version = "2.8.1";
    name = "xdebug";
    sha256 = "080mwr7m72rf0jsig5074dgq2n86hhs7rdbfg6yvnm959sby72w3";
    doCheck = true;
    checkTarget = "test";
  };

  xdebugWithConfig = pkgs.stdenv.mkDerivation rec {
    name = "xdebugWithConfig";
    src = ./debug;
    buildInputs = [ xdebug ];
    phases = [ "buildPhase" "installPhase" ];
    buildPhase = ''
    cp ${src}/etc/php73.d/opcache.ini .
    substituteInPlace opcache.ini \
      --replace @xdebug@ ${xdebug}/lib/php/extensions/xdebug.so
  '';
    installPhase = ''
    install -D opcache.ini $out/etc/php73.d/opcache.ini
  '';
  };

  rootfs = mkRootfs {
    name = "apache2-rootfs-php73";
    src = ./rootfs;
    inherit zlib curl coreutils findutils apacheHttpdmpmITK apacheHttpd
      mjHttpErrorPages s6 execline php73 logger;
    postfix = sendmail;
    mjperl5Packages = mjperl5lib;
    ioncube = ioncube.v73;
    s6PortableUtils = s6-portable-utils;
    s6LinuxUtils = s6-linux-utils;
    mimeTypes = mime-types;
    libstdcxx = gcc-unwrapped.lib;
  };

in pkgs.dockerTools.buildLayeredImage rec {
  name = "docker-registry.intr/webservices/apache2-php73";
  tag = "latest";
  contents = [
    rootfs
    tzdata
    apacheHttpd
    locale
    sendmail
    shell
    coreutils
    libjpeg_turbo
    jpegoptim
    (optipng.override { inherit libpng; })
    imagemagickBig
    ghostscript
    gifsicle
    nss-certs.unbundled
    zip
    gcc-unwrapped.lib
    glibc
    zlib
    mariadbConnectorC
    logger
    perl520
  ] ++ collect isDerivation mjperl5Packages
    ++ collect isDerivation php73Packages;

  config = {
    Entrypoint = [ "${rootfs}/init" ];
    Env = [
      "TZ=Europe/Moscow"
      "TZDIR=${tzdata}/share/zoneinfo"
      "LOCALE_ARCHIVE_2_27=${locale}/lib/locale/locale-archive"
      "LOCALE_ARCHIVE=${locale}/lib/locale/locale-archive"
      "LC_ALL=en_US.UTF-8"
    ];
    Labels = flattenSet rec {
      ru.majordomo.docker.arg-hints-json = builtins.toJSON php73DockerArgHints;
      ru.majordomo.docker.cmd =
        dockerRunCmd php73DockerArgHints "${name}:${tag}";
      ru.majordomo.docker.exec.reload-cmd =
        "${apacheHttpd}/bin/httpd -d ${rootfs}/etc/httpd -k graceful";
    };
  };
  extraCommands = ''
    set -xe

    mkdir {opt,root,tmp}
    chmod 1777 tmp
    chmod 0700 root

    mkdir -p usr/local

    ln -s ${php73} opt/php73
    ln -s /bin usr/bin
    ln -s /bin usr/sbin
    ln -s /bin usr/local/bin
  '';
}

{ nixpkgs, tag ? "latest" }:

with nixpkgs;

let
  inherit (builtins) concatMap getEnv toJSON;
  inherit (dockerTools) buildLayeredImage;
  inherit (lib) concatMapStringsSep firstNChars flattenSet dockerRunCmd mkRootfs optional;
  inherit (lib.attrsets) collect isDerivation;
  inherit (stdenv) mkDerivation;

  php73DockerArgHints = lib.phpDockerArgHints { php = php73; };

  shell = sh;

  rootfs = mkRootfs {
    name = "apache2-rootfs-php73";
    src = ./rootfs;
    inherit zlib curl coreutils findutils apacheHttpdmpmITK apacheHttpd
      s6 execline php73 logger;
    mjHttpErrorPages = mj-http-error-pages;
    # TODO: Fix "error: undefined variable 'xdebug'" in apps/moodle
    postfix = sendmail;
    mjperl5Packages = mjperl5lib;
    ioncube = ioncube.v73;
    s6PortableUtils = s6-portable-utils;
    s6LinuxUtils = s6-linux-utils;
    mimeTypes = mime-types;
    libstdcxx = gcc-unwrapped.lib;
  };

in
pkgs.dockerTools.buildLayeredImage rec {
  inherit tag;
  name = "docker-registry.intr/webservices/apache2-php73";
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
    gifsicle
    ghostscript
    nodePackages.svgo
  ] ++ collect isDerivation mjperl5Packages
  ++ collect isDerivation php73Packages;

  # TODO: Fix "error: undefined variable 'xdebug'" in apps/moodle
  # ++ optional (tag == "debug") xdebug;

  config = {
    Entrypoint = [ "${rootfs}/init" ];
    Env = [
      "TZ=Europe/Moscow"
      "TZDIR=${tzdata}/share/zoneinfo"
      "LOCALE_ARCHIVE_2_27=${locale}/lib/locale/locale-archive"
      "LOCALE_ARCHIVE=${locale}/lib/locale/locale-archive"
      "LC_ALL=en_US.UTF-8"
      "LD_PRELOAD=${jemalloc}/lib/libjemalloc.so"
      "PERL5LIB=${mjPerlPackages.PERL5LIB}"
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

    mkdir -p {opt,root,tmp,bin}
    chmod 1777 tmp
    chmod 0700 root
    chmod 755 bin
    mkdir -p usr/local

    ln -s ${nodePackages.svgo}/bin/svgo bin/svgo
    ln -s ${php73} opt/php73
    ln -s /bin usr/bin
    ln -s /bin usr/sbin
    ln -s /bin usr/local/bin
  '';
}

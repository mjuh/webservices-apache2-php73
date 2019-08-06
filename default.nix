with import <nixpkgs> {
#add_postfix_test
  overlays = [
    (import (builtins.fetchGit { url = "git@gitlab.intr:_ci/nixpkgs.git"; ref = "master"; }))
  ];
};


let

inherit (builtins) concatMap getEnv toJSON;
inherit (dockerTools) buildLayeredImage;
inherit (lib) concatMapStringsSep firstNChars flattenSet dockerRunCmd buildPhpPackage mkRootfs;
inherit (lib.attrsets) collect isDerivation;
inherit (stdenv) mkDerivation;


  locale = glibcLocales.override {
      allLocales = false;
      locales = ["en_US.UTF-8/UTF-8"];
  };

sh = dash.overrideAttrs (_: rec {
  postInstall = ''
    ln -s dash "$out/bin/sh"
  '';
});

buildPhp73Package = args: buildPhpPackage ({ php = php73; } // args);

php73Packages = {
  redis = buildPhp73Package {
      name = "redis";
      version = "4.2.0";
      sha256 = "7655d88addda89814ad2131e093662e1d88a8c010a34d83ece5b9ff45d16b380";
  };

  timezonedb = buildPhp73Package {
      name = "timezonedb";
      version ="2019.1";
      sha256 = "0rrxfs5izdmimww1w9khzs9vcmgi1l90wni9ypqdyk773cxsn725";
  };

  rrd = buildPhp73Package {
      name = "rrd";
      version = "2.0.1";
      sha256 = "39f5ae515de003d8dad6bfd77db60f5bd5b4a9f6caa41479b1b24b0d6592715d";
      inputs = [ pkgconfig rrdtool ];
  };

  memcached = buildPhp73Package {
      name = "memcached";
      version = "3.1.3";
      sha256 = "20786213ff92cd7ebdb0d0ac10dde1e9580a2f84296618b666654fd76ea307d4";
      inputs = [ pkgconfig zlib.dev libmemcached ];
      configureFlags = [
        "--with-zlib-dir=${zlib.dev}"
        "--with-libmemcached-dir=${libmemcached}"
      ];
  };

  imagick = buildPhp73Package {
      name = "imagick";
      version = "3.4.3";
      sha256 = "1f3c5b5eeaa02800ad22f506cd100e8889a66b2ec937e192eaaa30d74562567c";
      inputs = [ pkgconfig imagemagick.dev pcre pcre.dev pcre2.dev ];
      CXXFLAGS = "-I${pcre.dev} -I${pcre2.dev}";
      configureFlags = [ "--with-imagick=${imagemagick.dev}" ];
  };

};

  rootfs = mkRootfs {
      name = "apache2-php73-rootfs";
      src = ./rootfs;
      inherit curl coreutils findutils apacheHttpdmpmITK apacheHttpd mjHttpErrorPages php73 postfix s6 execline mjperl5Packages;
      ioncube = ioncube.v73;
      s6PortableUtils = s6-portable-utils;
      s6LinuxUtils = s6-linux-utils;
      mimeTypes = mime-types;
      libstdcxx = gcc-unwrapped.lib;
  };

dockerArgHints = {
    init = false;
    read_only = true;
    network = "host";
    environment = { HTTPD_PORT = "$SOCKET_HTTP_PORT"; PHP_INI_SCAN_DIR = ":${rootfs}/etc/phpsec/$SECURITY_LEVEL"; };
    tmpfs = [
      "/tmp:mode=1777"
      "/run/bin:exec,suid"
    ];
    ulimits = [
      { name = "stack"; hard = -1; soft = -1; }
    ];
    security_opt = [ "apparmor:unconfined" ];
    cap_add = [ "SYS_ADMIN" ];
    volumes = [
      ({ type = "bind"; source =  "$SITES_CONF_PATH" ; target = "/read/sites-enabled"; read_only = true; })
      ({ type = "bind"; source =  "/etc/passwd" ; target = "/etc/passwd"; read_only = true; })
      ({ type = "bind"; source =  "/etc/group" ; target = "/etc/group"; read_only = true; })
      ({ type = "bind"; source = "/opcache"; target = "/opcache"; })
      ({ type = "bind"; source = "/home"; target = "/home"; })
      ({ type = "bind"; source = "/opt/postfix/spool/maildrop"; target = "/var/spool/postfix/maildrop"; })
      ({ type = "bind"; source = "/opt/postfix/spool/public"; target = "/var/spool/postfix/public"; })
      ({ type = "bind"; source = "/opt/postfix/lib"; target = "/var/lib/postfix"; })
      ({ type = "tmpfs"; target = "/run"; })
    ];
  };

gitAbbrev = firstNChars 8 (getEnv "GIT_COMMIT");

in 

pkgs.dockerTools.buildLayeredImage rec {
  maxLayers = 124;
  name = "docker-registry.intr/webservices/apache2-php73";
  tag = if gitAbbrev != "" then gitAbbrev else "latest";
  contents = [
    rootfs
    tzdata
    locale
    postfix
    sh
    coreutils
    perl
         perlPackages.TextTruncate
         perlPackages.TimeLocal
         perlPackages.PerlMagick
         perlPackages.commonsense
         perlPackages.Mojolicious
         perlPackages.base
         perlPackages.libxml_perl
         perlPackages.libnet
         perlPackages.libintl_perl
         perlPackages.LWP
         perlPackages.ListMoreUtilsXS
         perlPackages.LWPProtocolHttps
         perlPackages.DBI
         perlPackages.DBDmysql
         perlPackages.CGI
         perlPackages.FilePath
         perlPackages.DigestPerlMD5
         perlPackages.DigestSHA1
         perlPackages.FileBOM
         perlPackages.GD
         perlPackages.LocaleGettext
         perlPackages.HashDiff
         perlPackages.JSONXS
         perlPackages.POSIXstrftimeCompiler
         perlPackages.perl
  ] ++ collect isDerivation php73Packages;
  config = {
    Entrypoint = [ "${rootfs}/init" ];
    Env = [
      "TZ=Europe/Moscow"
      "TZDIR=${tzdata}/share/zoneinfo"
      "LOCALE_ARCHIVE_2_27=${locale}/lib/locale/locale-archive"
      "LC_ALL=en_US.UTF-8"
    ];
    Labels = flattenSet rec {
      ru.majordomo.docker.arg-hints-json = builtins.toJSON dockerArgHints;
      ru.majordomo.docker.cmd = dockerRunCmd dockerArgHints "${name}:${tag}";
      ru.majordomo.docker.exec.reload-cmd = "${apacheHttpd}/bin/httpd -d ${rootfs}/etc/httpd -k graceful";
    };
  };
}

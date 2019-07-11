with import <nixpkgs> {
#add_postfix_test
  overlays = [
    (import (builtins.fetchGit { url = "git@gitlab.intr:_ci/nixpkgs.git"; ref = "master"; }))
  ];
};

with lib;

let

inherit (builtins) concatMap getEnv toJSON;
inherit (dockerTools) buildLayeredImage;
inherit (lib) concatMapStringsSep firstNChars flattenSet dockerRunCmd;
inherit (stdenv) mkDerivation;

  locale = glibcLocales.override {
      allLocales = false;
      locales = ["en_US.UTF-8/UTF-8"];
  };

  phpioncubepack = stdenv.mkDerivation rec {
      name = "phpioncubepack";
      src =  fetchurl {
          url = "https://downloads.ioncube.com/loader_downloads/ioncube_loaders_lin_x86-64.tar.gz";
          sha256 = "08bq06yr29zns53m603yv5h11ija8vzkq174qhcj4hz7ya05zb4a";
      };
      installPhase = ''
                  mkdir -p  $out/
                  tar zxvf  ${src} -C $out/ ioncube/ioncube_loader_lin_7.2.so
      '';
  };

  php72 = stdenv.mkDerivation rec {
      name = "php-7.2.18";
      sha256 = "0wjb9j5slqjx1fn00ljwgy4vlxvz9a6s9677h5z20wqi5nqjf6ps";
      enableParallelBuilding = true;
      nativeBuildInputs = [ pkgconfig autoconf ];

      buildInputs = [
         autoconf
         automake
         pkgconfig
         curl
         apacheHttpd
         bison
         bzip2
         flex
         freetype
         gettext
         gmp
         icu
         libzip
         libjpeg
         libmcrypt
         libmhash
         libpng
         libxml2
         libsodium
         icu.dev
         xorg.libXpm.dev
         libxslt
         mariadb
         pam
         pcre
         postgresql
         readline
         sqlite
         uwimap
         zlib
         libiconv
         t1lib
         libtidy
         kerberos
         openssl.dev
         glibcLocales
      ];

      CXXFLAGS = "-std=c++11";

      configureFlags = ''
       --disable-cgi
       --disable-pthreads
       --without-pthreads
       --disable-phpdbg
       --disable-maintainer-zts
       --disable-debug
       --disable-memcached-sasl
       --disable-fpm
       --enable-pdo
       --enable-dom
       --enable-libxml
       --enable-inline-optimization
       --enable-dba
       --enable-bcmath
       --enable-soap
       --enable-sockets
       --enable-zip
       --enable-intl
       --enable-exif
       --enable-ftp
       --enable-mbstring
       --enable-calendar
       --enable-timezonedb
       --enable-gd-native-ttf 
       --enable-sysvsem
       --enable-sysvshm
       --enable-opcache
       --enable-magic-quotes
       --with-config-file-scan-dir=/etc/php.d
       --with-pcre-regex=${pcre.dev} PCRE_LIBDIR=${pcre}
       --with-imap=${uwimap}
       --with-imap-ssl
       --with-mhash
       --with-libzip
       --with-curl=${curl.dev}
       --with-curlwrappers
       --with-zlib=${zlib.dev}
       --with-libxml-dir=${libxml2.dev}
       --with-xmlrpc
       --with-readline=${readline.dev}
       --with-pdo-sqlite=${sqlite.dev}
       --with-pgsql=${postgresql}
       --with-pdo-pgsql=${postgresql}
       --with-pdo-mysql=mysqlnd
       --with-mysql=mysqlnd
       --with-mysqli=mysqlnd
       --with-gd
       --with-freetype-dir=${freetype.dev}
       --with-png-dir=${libpng.dev}
       --with-jpeg-dir=${libjpeg.dev}
       --with-gmp=${gmp.dev}
       --with-openssl
       --with-gettext=${gettext}
       --with-xsl=${libxslt.dev}
       --with-mcrypt=${libmcrypt}
       --with-bz2=${bzip2.dev}
       --with-sodium=${libsodium.dev}
       --with-tidy=${html-tidy}
       --with-password-argon2=${libargon2}
       --with-apxs2=${apacheHttpd.dev}/bin/apxs
       '';

      hardeningDisable = [ "bindnow" ];

      preConfigure = ''
        # Don't record the configure flags since this causes unnecessary
        # runtime dependencies
        for i in main/build-defs.h.in scripts/php-config.in; do
          substituteInPlace $i \
            --replace '@CONFIGURE_COMMAND@' '(omitted)' \
            --replace '@CONFIGURE_OPTIONS@' "" \
            --replace '@PHP_LDFLAGS@' ""
        done

        [[ -z "$libxml2" ]] || addToSearchPath PATH $libxml2/bin

        export EXTENSION_DIR=$out/lib/php/extensions

        configureFlags+=(--with-config-file-path=$out/etc \
          --includedir=$dev/include)

        ./buildconf --force
      '';

      postFixup = ''
             mkdir -p $dev/bin $dev/share/man/man1
             mv $out/bin/phpize $out/bin/php-config $dev/bin/
             mv $out/share/man/man1/phpize.1.gz \
             $out/share/man/man1/php-config.1.gz \
             $dev/share/man/man1/
      '';

      src = fetchurl {
             url = "http://www.php.net/distributions/php-7.2.18.tar.bz2";
             inherit sha256;
      };

      patches = [ ./patch/php7/fix-paths-php7.patch ];
      stripDebugList = "bin sbin lib modules";
      outputs = [ "out" "dev" ];
      doCheck = false;
      checkTarget = "test"; 
  };

  php72Packages.redis = stdenv.mkDerivation rec {
      name = "redis-4.2.0";
      src = fetchurl {
          url = "http://pecl.php.net/get/${name}.tgz";
          sha256 = "7655d88addda89814ad2131e093662e1d88a8c010a34d83ece5b9ff45d16b380";
      };  
      nativeBuildInputs = [ autoreconfHook ] ;
      buildInputs = [ php72 ];
      makeFlags = [ "EXTENSION_DIR=$(out)/lib/php/extensions" ];
      autoreconfPhase = "phpize";  
      postInstall = ''
          mkdir -p  $out/etc/php.d
          echo "extension = $out/lib/php/extensions/redis.so" >> $out/etc/php.d/redis.ini
      '';
  };

  php72Packages.timezonedb = stdenv.mkDerivation rec {
      name = "timezonedb-2019.1";
      src = fetchurl {
          url = "http://pecl.php.net/get/${name}.tgz";
          sha256 = "0rrxfs5izdmimww1w9khzs9vcmgi1l90wni9ypqdyk773cxsn725";
      };
      nativeBuildInputs = [ autoreconfHook ] ;
      buildInputs = [ php72 ];
      makeFlags = [ "EXTENSION_DIR=$(out)/lib/php/extensions" ];
      autoreconfPhase = "phpize";
      postInstall = ''
          mkdir -p  $out/etc/php.d
          echo "extension = $out/lib/php/extensions/timezonedb.so" >> $out/etc/php.d/timezonedb.ini
      '';
  };

  php72Packages.rrd = stdenv.mkDerivation rec {
      name = "rrd-2.0.1";
      src = fetchurl {
          url = "http://pecl.php.net/get/${name}.tgz";
          sha256 = "39f5ae515de003d8dad6bfd77db60f5bd5b4a9f6caa41479b1b24b0d6592715d";
      };
      nativeBuildInputs = [ autoreconfHook pkgconfig ] ;
      buildInputs = [ php72 rrdtool ];
      makeFlags = [ "EXTENSION_DIR=$(out)/lib/php/extensions" ];
      autoreconfPhase = "phpize";
      postInstall = ''
          mkdir -p  $out/etc/php.d
          echo "extension = $out/lib/php/extensions/rrd.so" >> $out/etc/php.d/rrd.ini
      '';
  };


  php72Packages.memcached = stdenv.mkDerivation rec {
      name = "memcached-3.1.3";
      src = fetchurl {
          url = "http://pecl.php.net/get/${name}.tgz";
          sha256 = "20786213ff92cd7ebdb0d0ac10dde1e9580a2f84296618b666654fd76ea307d4";
      };
      nativeBuildInputs = [ autoreconfHook ] ;
      buildInputs = [ php72 pkg-config zlib libmemcached ];
      makeFlags = [ "EXTENSION_DIR=$(out)/lib/php/extensions" ];
      configureFlags = ''
          --with-zlib-dir=${zlib.dev}
          --with-libmemcached-dir=${libmemcached}
      '';
      autoreconfPhase = "phpize";
      postInstall = ''
          mkdir -p  $out/etc/php.d
          echo "extension = $out/lib/php/extensions/memcached.so" >> $out/etc/php.d/memcached.ini
      '';
  };

  php72Packages.imagick = stdenv.mkDerivation rec {
      name = "imagick-3.4.3";
      src = fetchurl {
          url = "http://pecl.php.net/get/${name}.tgz";
          sha256 = "1f3c5b5eeaa02800ad22f506cd100e8889a66b2ec937e192eaaa30d74562567c";
      };
      nativeBuildInputs = [ autoreconfHook pkgconfig ] ;
      buildInputs = [ php72 imagemagick pcre ];
      makeFlags = [ "EXTENSION_DIR=$(out)/lib/php/extensions" ];
      configureFlags = [ "--with-imagick=${pkgs.imagemagick.dev}" ];
      autoreconfPhase = "phpize";
      postInstall = ''
          mkdir -p  $out/etc/php.d
          echo "extension = $out/lib/php/extensions/imagick.so" >> $out/etc/php.d/imagick.ini
      '';
  };

  rootfs = stdenv.mkDerivation rec {
      nativeBuildInputs = [ 
         mjHttpErrorPages
         phpioncubepack
         php72
         php72Packages.rrd
         php72Packages.redis
         php72Packages.timezonedb
         php72Packages.memcached
         php72Packages.imagick
         bash
         apacheHttpd
         apacheHttpdmpmITK
         execline
         s6
         s6-portable-utils
         coreutils
         findutils
         postfix
         perl
         gnugrep
         curl
      ];
      name = "rootfs";
      src = ./rootfs;
      buildPhase = ''
         echo $nativeBuildInputs
         export coreutils="${coreutils}"
         export bash="${bash}"
         export curl="${curl}"
         export findutils="${findutils}"
         export rootfs="$out"
         export apacheHttpdmpmITK="${apacheHttpdmpmITK}"
         export apacheHttpd="${apacheHttpd}"
         export s6portableutils="${s6-portable-utils}"
         export phpioncubepack="${phpioncubepack}"
         export php72="${php72}"
         export mjerrors="${mjHttpErrorPages}"
         export postfix="${postfix}"
         export libstdcxx="${gcc-unwrapped.lib}"
         echo ${apacheHttpd}
         for file in $(find $src/ -type f)
         do
           echo $file
           substituteAllInPlace $file
         done
      '';
      installPhase = ''
         cp -pr ${src} $out/
      '';
  };

dockerArgHints = {
    init = false;
    read_only = true;
    network = "host";
    environment = { HTTPD_PORT = "\$socket_http_port"; PHP_SEC = "\$security_level"; PHP_INI_SCAN_DIR = ":/etc/phpsec/$security_level";} ;

##TO DO:
##? -v $(pwd)/postfix-conf-test:/etc/postfix:ro ?
#? ({ type = "bind"; source = "/etc/passwd"; destination = "/etc/passwd"; readonly = true; })
#? ({ type = "bind"; source = "/etc/group"; destination = "/etc/group"; readonly = true; })
    tmpfs = [ "/tmp:mode=1777" ];
    volumes = [
      ({ type = "bind"; source =  "\$sites_conf_path" ; target = "/read/sites-enabled"; read_only = true; })
      ({ type = "bind"; source = "/opcache"; target = "/opcache"; read_only = false; })
      ({ type = "bind"; source = "/home"; target = "/home"; read_only = false; })
      ({ type = "bind"; source = "/var/spool/postfix"; target = "/var/spool/postfix"; read_only = false; })
      ({ type = "bind"; source = "/var/lib/postfix"; target = "/var/lib/postfix"; read_only = false; })
      ({ type = "tmpfs"; target = "/run"; })
    ];
  };

gitAbbrev = firstNChars 8 (getEnv "GIT_COMMIT");

in 

pkgs.dockerTools.buildLayeredImage rec {
    maxLayers = 220;
    name = "docker-registry.intr/webservices/apache2-php72";
    tag = if gitAbbrev != "" then gitAbbrev else "latest";
    contents = [ php72 
                 perl
                 php72Packages.rrd
                 php72Packages.redis
                 php72Packages.timezonedb
                 php72Packages.memcached
                 php72Packages.imagick
                 phpioncubepack
                 curl
                 bash
                 coreutils
                 findutils
                 apacheHttpd
                 apacheHttpdmpmITK
                 rootfs
                 execline
                 tzdata
                 mime-types
                 postfix
                 locale
                 perl528Packages.Mojolicious
                 perl528Packages.base
                 perl528Packages.libxml_perl
                 perl528Packages.libnet
                 perl528Packages.libintl_perl
                 perl528Packages.LWP 
                 perl528Packages.ListMoreUtilsXS
                 perl528Packages.LWPProtocolHttps
                 mjHttpErrorPages
                 glibc
                 gcc-unwrapped.lib
                 s6
                 s6-portable-utils
    ];
      extraCommands = ''
          chmod 555 ${postfix}/bin/postdrop
      '';
   config = {
#       Entrypoint = [ "${apacheHttpd}/bin/httpd" "-D" "FOREGROUND" "-d" "${rootfs}/etc/httpd" ];
       Entrypoint = [ "/init" ];
       Env = [
          "TZ=Europe/Moscow"
          "TZDIR=/share/zoneinfo"
          "LOCALE_ARCHIVE_2_27=${locale}/lib/locale/locale-archive"
          "LC_ALL=en_US.UTF-8"
          "HTTPD_PORT=8074"
       ];
       Labels = flattenSet rec {
          "ru.majordomo.docker.arg-hints-json" = builtins.toJSON dockerArgHints;
          "ru.majordomo.docker.cmd" = dockerRunCmd dockerArgHints "${name}:${tag}";
          "ru.majordomo.docker.exec.reload-cmd" = "${apacheHttpd}/bin/httpd -d ${rootfs}/etc/httpd -k graceful";
       };
    };
}


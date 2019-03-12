with import <nixpkgs> {};

with lib;

let

  locale = glibcLocales.override {
      allLocales = false;
      locales = ["en_US.UTF-8/UTF-8"];
  };

  postfix = stdenv.mkDerivation rec {

      name = "postfix-${version}";
      version = "3.3.2";
      srcs = [
         ( fetchurl {
            url = "ftp://ftp.cs.uu.nl/mirror/postfix/postfix-release/official/${name}.tar.gz";
            sha256 = "0nxkszdgs6fs86j6w1lf3vhxvjh1hw2jmrii5icqx9a9xqgg74rw";
          })
       ./patch/postfix/mj/lib
      ];

      nativeBuildInputs = [ makeWrapper m4 ];
      buildInputs = [ db openssl cyrus_sasl icu libnsl pcre ];
      sourceRoot = "postfix-3.3.2";
      hardeningDisable = [ "format" ];
      hardeningEnable = [ "pie" ];

      patches = [
       ./patch/postfix/nix/postfix-script-shell.patch
       ./patch/postfix/nix/postfix-3.0-no-warnings.patch
       ./patch/postfix/nix/post-install-script.patch
       ./patch/postfix/nix/relative-symlinks.patch
       ./patch/postfix/mj/sendmail.patch
       ./patch/postfix/mj/postdrop.patch
       ./patch/postfix/mj/globalmake.patch
      ];

       ccargs = lib.concatStringsSep " " ([
          "-DUSE_TLS" "-DUSE_SASL_AUTH" "-DUSE_CYRUS_SASL" "-I${cyrus_sasl.dev}/include/sasl"
          "-DHAS_DB_BYPASS_MAKEDEFS_CHECK"
       ]);

       auxlibs = lib.concatStringsSep " " ([
          "-ldb" "-lnsl" "-lresolv" "-lsasl2" "-lcrypto" "-lssl"
       ]);

      preBuild = ''
          cp -pr ../lib/* src/global
          sed -e '/^PATH=/d' -i postfix-install
          sed -e "s|@PACKAGE@|$out|" -i conf/post-install

          # post-install need skip permissions check/set on all symlinks following to /nix/store
          sed -e "s|@NIX_STORE@|$NIX_STORE|" -i conf/post-install

          export command_directory=$out/sbin
          export config_directory=/etc/postfix
          export meta_directory=$out/etc/postfix
          export daemon_directory=$out/libexec/postfix
          export data_directory=/var/lib/postfix
          export html_directory=$out/share/postfix/doc/html
          export mailq_path=$out/bin/mailq
          export manpage_directory=$out/share/man
          export newaliases_path=$out/bin/newaliases
          export queue_directory=/var/spool/postfix
          export readme_directory=$out/share/postfix/doc
          export sendmail_path=$out/bin/sendmail
          make makefiles CCARGS='${ccargs}' AUXLIBS='${auxlibs}'
      '';

      installTargets = [ "non-interactive-package" ];
      installFlags = [ "install_root=installdir" ];

      postInstall = ''
          mkdir -p $out
          mv -v installdir/$out/* $out/
          cp -rv installdir/etc $out
          sed -e '/^PATH=/d' -i $out/libexec/postfix/post-install
          wrapProgram $out/libexec/postfix/post-install \
            --prefix PATH ":" ${lib.makeBinPath [ coreutils findutils gnugrep ]}
          wrapProgram $out/libexec/postfix/postfix-script \
            --prefix PATH ":" ${lib.makeBinPath [ coreutils findutils gnugrep gawk gnused ]}
      '';
  };

  apacheHttpd = stdenv.mkDerivation rec {
      version = "2.4.35";
      name = "apache-httpd-${version}";
      src = fetchurl {
          url = "mirror://apache/httpd/httpd-${version}.tar.bz2";
          sha256 = "0mlvwsm7hmpc7db6lfc2nx3v4cll3qljjxhjhgsw6aniskywc1r6";
      };
      outputs = [ "out" "dev" ];
      setOutputFlags = false; # it would move $out/modules, etc.
      buildInputs = [ perl zlib nss_ldap nss_pam_ldapd openldap];
      prePatch = ''
          sed -i config.layout -e "s|installbuilddir:.*|installbuilddir: $dev/share/build|"
      '';

      preConfigure = ''
          configureFlags="$configureFlags --includedir=$dev/include"
      '';

      configureFlags = [
          "--with-apr=${apr.dev}"
          "--with-apr-util=${aprutil.dev}"
          "--with-z=${zlib.dev}"
          "--with-pcre=${pcre.dev}"
          "--disable-maintainer-mode"
          "--disable-debugger-mode"
          "--enable-mods-shared=all"
          "--enable-mpms-shared=all"
          "--enable-cern-meta"
          "--enable-imagemap"
          "--enable-cgi"
          "--disable-ldap"
          "--with-mpm=prefork"
      ];

      enableParallelBuilding = true;
      stripDebugList = "lib modules bin";
      postInstall = ''
          #mkdir -p $doc/share/doc/httpd
          #mv $out/manual $doc/share/doc/httpd
          mkdir -p $dev/bin
          mv $out/bin/apxs $dev/bin/apxs
      '';

      passthru = {
          inherit apr aprutil ;
      };
  };

  phpioncubepack = stdenv.mkDerivation rec {
      name = "phpioncubepack";
      src =  fetchurl {
          url = "https://downloads.ioncube.com/loader_downloads/ioncube_loaders_lin_x86-64.tar.gz";
          sha256 = "50dc6011199e08eb4762732a146196fed727ef6543fc0a06fa1396309726aebe";
      };
      installPhase = ''
                  mkdir -p  $out/
                  tar zxvf  ${src} -C $out/ ioncube/ioncube_loader_lin_7.2.so
      '';
  };

  php72 = stdenv.mkDerivation rec {
      name = "php-7.2.16";
      sha256 = "2c0ad10053d58694cd14323248ecd6d9ba71d2733d160973c356ad01d09e7f38";
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
             url = "http://www.php.net/distributions/php-7.2.16.tar.bz2";
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
      name = "timezonedb-2018.9";
      src = fetchurl {
          url = "http://pecl.php.net/get/${name}.tgz";
          sha256 = "661364836f91ec8b5904da4c928b5b2df8cb3af853994f8f4d68b57bc3c32ec8";
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

#http://mpm-itk.sesse.net/
  apacheHttpdmpmITK = stdenv.mkDerivation rec {
      name = "apacheHttpdmpmITK";
      buildInputs =[ apacheHttpd ];
      src = fetchurl {
          url = "http://mpm-itk.sesse.net/mpm-itk-2.4.7-04.tar.gz";
          sha256 = "609f83e8995416c5491348e07139f26046a579db20cf8488ebf75d314668efcf";
      };
      configureFlags = [ "--with-apxs2=${apacheHttpd}/bin/apxs" ];
      patches = [ ./patch/httpd/itk.patch ];
      postInstall = ''
          mkdir -p $out/modules
          cp -pr /tmp/out/mpm_itk.so $out/modules
      '';
      outputs = [ "out" ];
      enableParallelBuilding = true;
      stripDebugList = "lib modules bin";
  };

  mjerrors = stdenv.mkDerivation rec {
      name = "mjerrors";
      buildInputs = [ gettext ];
      src = fetchGit {
              url = "git@gitlab.intr:shared/http_errors.git";
              ref = "master";
              rev = "f83136c7e6027cb28804172ff3582f635a8d2af7";
            };
      outputs = [ "out" ];
      postInstall = ''
             mkdir -p $out/tmp $out/mjstuff/mj_http_errors
             cp -pr /tmp/mj_http_errors/* $out/mjstuff/mj_http_errors/
      '';
  };

  rootfs = stdenv.mkDerivation rec {
      nativeBuildInputs = [ 
         mjerrors
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
#         lib
      ];
      name = "rootfs";
      src = ./rootfs;
      buildPhase = ''
         echo $nativeBuildInputs
         export bash="${bash}"
         export apacheHttpdmpmITK="${apacheHttpdmpmITK}"
         export apacheHttpd="${apacheHttpd}"
         export s6portableutils="${s6-portable-utils}"
         export phpioncubepack="${phpioncubepack}"
         export php72="${php72}"
         export mjerrors="${mjerrors}"
         export postfix="${postfix}"
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

in 

pkgs.dockerTools.buildLayeredImage rec {
    name = "docker-registry.intr/webservices/php72";
    tag = "master";
#    maxLayers = 124;
    contents = [ php72 
                 perl
                 php72Packages.rrd
                 php72Packages.redis
                 php72Packages.timezonedb
                 php72Packages.memcached
                 php72Packages.imagick
                 phpioncubepack
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
                 s6-portable-utils
                 s6
                 perl528Packages.Mojolicious
                 perl528Packages.base
                 perl528Packages.libxml_perl
                 perl528Packages.libnet
                 perl528Packages.libintl_perl
                 perl528Packages.LWP 
                 perl528Packages.ListMoreUtilsXS
                 perl528Packages.LWPProtocolHttps
                 mjerrors
    ];
   config = {
       Entrypoint = [ "/init" ];
       Env = [ "TZ=Europe/Moscow" "TZDIR=/share/zoneinfo" "LOCALE_ARCHIVE_2_27=${locale}/lib/locale/locale-archive" "LC_ALL=en_US.UTF-8" "HTTPD_PORT=8074" "HTTPD_SERVERNAME=web15" ];
    };
}


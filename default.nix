{}:

with import <nixpkgs> {
  overlays = [
    (import (builtins.fetchGit { url = "git@gitlab.intr:_ci/nixpkgs.git"; ref = (if builtins ? getEnv then builtins.getEnv "GIT_BRANCH" else "master"); }))
  ];
};

let
  inherit (builtins) concatMap getEnv replaceStrings toJSON;
  inherit (dockerTools) buildLayeredImage;
  inherit (lib) concatMapStringsSep firstNChars flattenSet dockerRunCmd mkRootfs;
  inherit (lib.attrsets) collect isDerivation;
  inherit (stdenv) mkDerivation;

  php73DockerArgHints = lib.phpDockerArgHints php73;

  rootfs = mkRootfs {
    name = "apache2-rootfs-php73";
    src = ./rootfs;
    inherit zlib curl coreutils findutils apacheHttpdmpmITK apacheHttpd
      mjHttpErrorPages s6 execline php73;
    postfix = sendmail;
    mjperl5Packages = mjperl5lib;
    ioncube = ioncube.v73;
    s6PortableUtils = s6-portable-utils;
    s6LinuxUtils = s6-linux-utils;
    mimeTypes = mime-types;
    libstdcxx = gcc-unwrapped.lib;
  };

gitAbbrev = firstNChars 8 (getEnv "GIT_COMMIT");
gitCommit = (getEnv "GIT_COMMIT");
jenkinsBuildUrl = (getEnv "BUILD_URL");
jenkinsJobName = (getEnv "JOB_NAME");
jenkinsBranchName = (getEnv "BRANCH_NAME");
gitlabCommitUrl = "https://gitlab.intr/" + (replaceStrings [jenkinsBranchName ""] ["" ""] jenkinsJobName) + "/commit/" + gitCommit;

in

pkgs.dockerTools.buildLayeredImage rec {
  maxLayers = 124;
  name = "docker-registry.intr/webservices/apache2-php73";
  tag = "latest";
  contents = [
    rootfs
    tzdata apacheHttpd
    locale
    sendmail
    sh
    coreutils
    libjpeg_turbo
    jpegoptim
    (optipng.override{ inherit libpng ;})
    gifsicle nss-certs.unbundled zip
    gcc-unwrapped.lib
    glibc
    zlib
    mariadbConnectorC
    perl520
  ]
  ++ collect isDerivation mjperl5Packages
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
      ru.majordomo.docker.cmd = dockerRunCmd php73DockerArgHints "${name}:${tag}";
      ru.majordomo.docker.exec.reload-cmd = "${apacheHttpd}/bin/httpd -d ${rootfs}/etc/httpd -k graceful";
      ru.majordomo.ci.jenkins.build.url = if jenkinsBuildUrl != "" then jenkinsBuildUrl + "console" else "none";
      ru.majordomo.ci.gitlab.commit.url = if gitlabCommitUrl != "" then gitlabCommitUrl else "none";
    };
  };
    extraCommands = ''
      set -xe
      ls
      mkdir -p etc
      mkdir -p bin
      mkdir -p usr/local
      mkdir -p opt
      ln -s ${php73} opt/php73
      ln -s /bin usr/bin
      ln -s /bin usr/sbin
      ln -s /bin usr/local/bin
    '';
}

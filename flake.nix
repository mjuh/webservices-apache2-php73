{
  description = "Docker container with Apache and PHP builded by Nix";

  inputs = {
    deploy-rs.url = "github:serokell/deploy-rs";
    flake-compat = { url = "github:edolstra/flake-compat"; flake = false; };
    flake-utils.url = "github:numtide/flake-utils";
    majordomo.url = "git+https://gitlab.intr/_ci/nixpkgs";
  };

  outputs = { self, flake-utils, nixpkgs, majordomo, deploy-rs, ... } @ inputs:
    flake-utils.lib.eachDefaultSystem (system: {
      packages = rec {
        rootfs =
          with nixpkgs.legacyPackages.${system};
          with majordomo.outputs.nixpkgs;
          lib.mkRootfs {
            name = "apache2-rootfs-php73";
            src = ./rootfs;
            inherit zlib curl coreutils findutils apacheHttpdmpmITK apacheHttpd
              mjHttpErrorPages s6 execline php73 logger;
            # TODO: Fix "error: undefined variable 'xdebug'" in apps/moodle
            postfix = sendmail;
            mjperl5Packages = mjperl5lib;
            ioncube = ioncube.v73;
            s6PortableUtils = s6-portable-utils;
            s6LinuxUtils = s6-linux-utils;
            mimeTypes = mime-types;
            libstdcxx = gcc-unwrapped.lib;
          };
        service-apache = with nixpkgs.legacyPackages.${system};
          callPackage ({ stdenv, writeScriptBin, apacheHttpd, runtimeShell, rootfs }: stdenv.mkDerivation rec {
            pname = "service-apache";
            version = "0.0.1";
            src = writeScriptBin "httpd" ''
              #!${runtimeShell}
              set -euo pipefail
              exec -a apache2-php73 ${apacheHttpd}/bin/httpd -D FOREGROUND -d ${rootfs}/etc/httpd "$@"
            '';
            dontUnpack = true;
            buildPhase = ''
              cp -a "$src/bin" .
            '';
            installPhase = ''
              mkdir -p "$out"/bin
              install bin/httpd "$out"/bin/httpd
            '';
          }) { inherit (majordomo.packages.${system}) apacheHttpd; inherit rootfs; };
        container-latest = import ./default.nix {
          inherit rootfs;
          nixpkgs = majordomo.outputs.nixpkgs;
          tag = "latest";
        };
        container-master = import ./default.nix {
          inherit rootfs;
          nixpkgs = majordomo.outputs.nixpkgs;
          tag = "master";
        };
        container-debug = import ./default.nix {
          inherit rootfs;
          nixpkgs = majordomo.outputs.nixpkgs;
          tag = "debug";
        };
      };
      checks.container =
        import ./test.nix {
          nixpkgs = majordomo.outputs.nixpkgs;
          image = self.packages.${system}.container-master;
        };
      defaultPackage = self.packages.${system}.container-master;
      devShell = with nixpkgs.legacyPackages.${system}; mkShell {
        buildInputs = [
          nixUnstable
          deploy-rs.outputs.packages.${system}.deploy-rs
        ];
        shellHook = ''
          . ${nixUnstable}/share/bash-completion/completions/nix
          export LANG=C
        '';
   };
    }) // (
      let
        system = "x86_64-linux";
        node = {
          sshUser = "jenkins";
          autoRollback = false;
          magicRollback = false;
        };
      in
        with nixpkgs.legacyPackages.${system}; {
          deploy.nodes = {
            apache2-php73 = node // {
              hostname = "jenkins.intr";
              profiles = {
                apache2-php73 = {
                  path = deploy-rs.lib.${system}.activate.custom
                    (symlinkJoin {
                      name = "profile";
                      paths = [];
                    })
                    ((with self.packages.${system}.container-latest; ''
                      #!${runtimeShell} -e
                      echo ${docker}/bin/docker load --input ${out}
                      echo ${docker}/bin/docker push ${imageName}:${imageTag}
                    '')
                    + (with self.packages.${system}.container-master; ''
                      echo ${docker}/bin/docker load --input ${out}
                      echo ${docker}/bin/docker push ${imageName}:${imageTag}
                    ''));
                };
                apache2-php73-debug = node // {
                  path = deploy-rs.lib.${system}.activate.custom
                    (symlinkJoin {
                      name = "profile";
                      paths = [];
                    })
                    (with self.packages.${system}.container-debug; ''
                      #!${runtimeShell} -e
                      echo ${docker}/bin/docker load --input ${out}
                      echo ${docker}/bin/docker push ${imageName}:${imageTag}
                    '');
                };
              };
            };
          };
        }
    );
}

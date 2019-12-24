{ ref ? "master", debug ? false }:

with import <nixpkgs> {
  overlays = [
    (import (builtins.fetchGit {
      url = "git@gitlab.intr:_ci/nixpkgs.git";
      inherit ref;
    }))
  ];
};

let
  domain = "php73.ru";
  phpVersion = "php" + lib.versions.major php73.version
    + lib.versions.minor php73.version;
  containerStructureTestConfig = ./tests/container-structure-test.yaml;
  image = callPackage ./default.nix { inherit ref; };

in maketestPhp {
  inherit image;
  inherit debug;
  php = php73;
  inherit containerStructureTestConfig;
  rootfs = ./rootfs;
  defaultTestSuite = false;
  testSuite = [
    (dockerNodeTest {
      description = "Copy phpinfo.";
      action = "execute";
      command = "cp -v ${phpinfo} /home/u12/${domain}/www/phpinfo.php";
    })
    (dockerNodeTest {
      description = "Fetch phpinfo.";
      action = "succeed";
      command = runCurl "http://${domain}/phpinfo.php"
        "/tmp/xchg/coverage-data/phpinfo.html";
    })
    (dockerNodeTest {
      description = "Fetch server-status.";
      action = "succeed";
      command = runCurl "http://127.0.0.1/server-status"
        "/tmp/xchg/coverage-data/server-status.html";
    })
    (dockerNodeTest {
      description = "Copy phpinfo-json.php.";
      action = "succeed";
      command =
        "cp -v ${./tests/phpinfo-json.php} /home/u12/${domain}/www/phpinfo-json.php";
    })
    (dockerNodeTest {
      description = "Fetch phpinfo-json.php.";
      action = "succeed";
      command = runCurl "http://${domain}/phpinfo-json.php"
        "/tmp/xchg/coverage-data/phpinfo.json";
    })
    (dockerNodeTest {
      description = "Run deepdiff against PHP on Upstart.";
      action = "succeed";
      command = testDiffPy {
        inherit pkgs;
        sampleJson = (./tests/. + "/${phpVersion}.json");
        output = "/tmp/xchg/coverage-data/deepdiff.html";
      };
    })
    (dockerNodeTest {
      description = "Run deepdiff against PHP on Upstart with excludes.";
      action = "succeed";
      command = testDiffPy {
        inherit pkgs;
        sampleJson = (./tests/. + "/${phpVersion}.json");
        output = "/tmp/xchg/coverage-data/deepdiff-with-excludes.html";
        excludes = import ./tests/diff-to-skip.nix;
      };
    })
    (dockerNodeTest {
      description = "Run deepdiff against PHP on Nix.";
      action = "succeed";
      command = testDiffPy {
        inherit pkgs;
        sampleJson = (./tests/. + "/web34/${phpVersion}.json");
        output = "/tmp/xchg/coverage-data/deepdiff-web34.html";
      };
    })
    (dockerNodeTest {
      description = "Run deepdiff against PHP on Nix with excludes.";
      action = "succeed";
      command = testDiffPy {
        inherit pkgs;
        sampleJson = (./tests/. + "/web34/${phpVersion}.json");
        output = "/tmp/xchg/coverage-data/deepdiff-web34-with-excludes.html";
        excludes = import ./tests/diff-to-skip.nix;
      };
    })
    (dockerNodeTest {
      description = "Copy bitrix_server_test.php.";
      action = "succeed";
      command = "cp -v ${
          ./tests/bitrix_server_test.php
        } /home/u12/${domain}/www/bitrix_server_test.php";
    })
    (dockerNodeTest {
      description = "Run Bitrix test.";
      action = "succeed";
      command = runCurl "http://${domain}/bitrix_server_test.php"
        "/tmp/xchg/coverage-data/bitrix_server_test.html";
    })
    (dockerNodeTest {
      description = "Run container structure test.";
      action = "succeed";
      command = containerStructureTest {
        inherit pkgs;
        config = containerStructureTestConfig;
        image = image.imageName;
      };
    })
    (dockerNodeTest {
      description = "Run mariadb connector test.";
      action = "succeed";
      command = testPhpMariadbConnector { inherit pkgs; };
    })
    (dockerNodeTest {
      description = "Run WordPress test.";
      action = "succeed";
      command = wordpressScript {
        inherit pkgs;
        inherit domain;
      };
    })
    (dockerNodeTest {
      description = "Take WordPress screenshot";
      action = "succeed";
      command = builtins.concatStringsSep " " [
        "${firefox}/bin/firefox"
        "--headless"
        "--screenshot=/tmp/xchg/coverage-data/wordpress.png"
        "http://${domain}/"
      ];
    })
    (dockerNodeTest {
      description = "Copy parser3.cgi";
      action = "succeed";
      command = "cp -v ${parser3}/parser3.cgi /home/u12/${domain}/www/parser3.cgi";
    })
    (dockerNodeTest {
      description = "help parser3.cgi";
      action = "succeed";
      command = ''#!{bash}/bin/bash
          docker exec `docker ps --format '{{ .Names }}' ` /home/u12/${domain}/www/parser3.cgi -h | grep Parser
      '';
    })
    (dockerNodeTest {
      description = "Perl version";
      action = "succeed";
      command = ''#!{bash}/bin/bash
          docker exec `docker ps --format '{{ .Names }}' ` perl -v | grep 'v5.20'
      '';
    })
  ];
} { }

{ nixpkgs ? import <nixpkgs> {
  overlays = [
    (import (builtins.fetchGit {
      url = "git@gitlab.intr:_ci/nixpkgs.git";
      ref = "master";
    }))
  ];
} }:

with nixpkgs;

let
  domain = "php73.ru";
  phpVersion = "php" + lib.versions.major php73.version
    + lib.versions.minor php73.version;
  containerStructureTestConfig = ./tests/container-structure-test.yaml;
  image = callPackage ./default.nix { inherit overlayUrl overlayRef; inherit debug; };

in maketestPhp {
  inherit image;
  php = php73;
  inherit containerStructureTestConfig;
  rootfs = ./rootfs;
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
      description = "Copy example pdf.";
      action = "execute";
      command = "cp -v ${./tests/example.pdf} /home/u12/${domain}/www/example.pdf";
    })
    (dockerNodeTest {
      description = "Test imageMagick convert pdf";
      action = "succeed";
      command = ''#!{bash}/bin/bash
          docker exec `docker ps --format '{{ .Names }}' ` convert -density 100 -colorspace rgb /home/u12/${domain}/www/example.pdf -scale 200x200 /home/u12/${domain}/www/example.jpg && cp /home/u12/${domain}/www/example.jpg /tmp/xchg/coverage-data/pdf2jpg.jpg
      '';
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
      command = "cp -v ${
          ./tests/phpinfo-json.php
        } /home/u12/${domain}/www/phpinfo-json.php";
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
        output = "/tmp/xchg/coverage-data/deepdiff.json";
      };
    })
    (dockerNodeTest {
      description = "Run deepdiff against PHP on Upstart with excludes.";
      action = "succeed";
      command = testDiffPy {
        inherit pkgs;
        sampleJson = (./tests/. + "/${phpVersion}.json");
        output = "/tmp/xchg/coverage-data/deepdiff-with-excludes.json";
        excludes = import ./tests/diff-to-skip.nix;
      };
    })
    (dockerNodeTest {
      description = "Run deepdiff against PHP on Nix.";
      action = "succeed";
      command = testDiffPy {
        inherit pkgs;
        sampleJson = (./tests/. + "/web34/${phpVersion}.json");
        output = "/tmp/xchg/coverage-data/deepdiff-web34.json";
      };
    })
    (dockerNodeTest {
      description = "Run deepdiff against PHP on Nix with excludes.";
      action = "succeed";
      command = testDiffPy {
        inherit pkgs;
        sampleJson = (./tests/. + "/web34/${phpVersion}.json");
        output = "/tmp/xchg/coverage-data/deepdiff-web34-with-excludes.json";
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
      command =
        "cp -v ${parser3}/parser3.cgi /home/u12/${domain}/www/parser3.cgi";
    })
    (dockerNodeTest {
      description = "help parser3.cgi";
      action = "succeed";
      command = ''
        #!{bash}/bin/bash
                  docker exec `docker ps --format '{{ .Names }}' ` /home/u12/${domain}/www/parser3.cgi -h | grep Parser
              '';
    })
    (dockerNodeTest {
      description = "Perl version";
      action = "succeed";
      command = ''
        #!{bash}/bin/bash
                  docker exec `docker ps --format '{{ .Names }}' ` perl -v | grep 'v5.20'
              '';
    })
    (dockerNodeTest {
      description = "Spiner test";
      action = "succeed";
      command = runCurlGrep "127.0.0.1" "refresh";
    })
    (dockerNodeTest {
      description = "404 test";
      action = "succeed";
      command = runCurlGrep "127.0.0.1/non-existent" "' 404'";
    })
    (dockerNodeTest {
      description = "404 mj-error test";
      action = "succeed";
      command = runCurlGrep "127.0.0.1/non-existent" "majordomo";
    })
    # TODO: Add MySQL tests.
    #    (dockerNodeTest {
    #      description = "Copy mysqlconnect.php";
    #      action = "succeed";
    #      command = "cp -v ${./tests/mysqlconnect.php} /home/u12/${domain}/www/mysqlconnect.php";
    #    })
    #    (dockerNodeTest {
    #      description = "Test mysqlconnect with old password hash";
    #      action = "succeed";
    #      command = "curl http://${domain}/mysqlconnect.php | grep success";
    #    })
    #    (dockerNodeTest {
    #      description = "Copy mysqliconnect.php";
    #      action = "succeed";
    #      command = "cp -v ${./tests/mysqliconnect.php} /home/u12/${domain}/www/mysqliconnect.php";
    #    })
    #    (dockerNodeTest {
    #      description = "Test mysqlIconnect with old password hash";
    #      action = "succeed";
    #      command = "curl http://${domain}/mysqliconnect.php | grep success";
    #    })
    #    (dockerNodeTest {
    #      description = "Copy mysqlpdoconnect.php";
    #      action = "succeed";
    #      command = "cp -v ${./tests/mysqlpdoconnect.php} /home/u12/${domain}/www/mysqlpdoconnect.php";
    #    })
    #    (dockerNodeTest {
    #      description = "Test mysqlPDOconnect with old password hash";
    #      action = "succeed";
    #      command = "curl http://${domain}/mysqlpdoconnect.php | grep success";
    #    })
    (dockerNodeTest {
      description = "deepdiff iterable_item_removed";
      action = "succeed";
      command =
        "jq .iterable_item_removed /tmp/xchg/coverage-data/deepdiff-with-excludes.json ; jq .iterable_item_removed /tmp/xchg/coverage-data/deepdiff-with-excludes.json | grep null ";
    })
  ];
} { }

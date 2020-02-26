#! /usr/bin/env nix-shell
#! nix-shell -i python -p "with import <nixpkgs> {overlays = [(import (builtins.fetchGit { url = \"git@gitlab.intr:_ci/nixpkgs.git\"; ref = \"master\"; }))];}; python37mj.withPackages (ps: with ps; [ junit-xml ])"

import os
import json
from junit_xml import TestSuite, TestCase

vulnix_json = os.environ.get("JUNIT_OUTPUT_JSON")
output = os.environ.get("JUNIT_OUTPUT_XML")

with open(vulnix_json, "r") as input_file: vulnix = json.load(input_file)

with open(output, 'w') as output_file:
    TestSuite.to_file(output_file,
                      [TestSuite("my test suite",
                                 [val for sublist in list(map((lambda cve: list(map(lambda affected: TestCase(affected,
                                                                                                    classname=cve["name"],
                                                                                                    stdout='name: {}\nderivation: {}\nurl: <a href="{}">{}</a>'.format(cve["name"],
                                                                                                                                                      cve["derivation"],
                                                                                                                                                      "https://nvd.nist.gov/vuln/detail/" + cve["name"],
                                                                                                                                                      "https://nvd.nist.gov/vuln/detail/" + cve["name"])),
                                                                               cve["affected_by"]))),
                                                              vulnix))
                                  for val in sublist])],
                      prettyprint=False);

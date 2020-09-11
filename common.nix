rec {
  nixpkgs = import <nixpkgs> {
    overlays = [
      (import (builtins.fetchGit {
        url = "git@gitlab.intr:_ci/nixpkgs.git";
        ref = "master";
      }))
    ];
  };
}

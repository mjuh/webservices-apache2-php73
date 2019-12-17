with import <nixpkgs> {
  overlays = [
    (import (builtins.fetchGit { url = "git@gitlab.intr:_ci/nixpkgs.git"; ref = (if builtins ? getEnv then builtins.getEnv "GIT_BRANCH" else "master"); }))
  ];
};

maketestPhp {
  php = php73;
  image = callPackage ./default.nix {};
  rootfs = ./rootfs;
}

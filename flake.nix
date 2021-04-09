{
  description = "Docker container with Apache and PHP builded by Nix";

  inputs.majordomo.url = "git+https://gitlab.intr/_ci/nixpkgs?ref=xdebug";

  outputs = { self, nixpkgs, majordomo }: {

    packages.x86_64-linux.container =
      import ./default.nix { nixpkgs = majordomo.outputs.nixpkgs; };

    checks.x86_64-linux.container =
      import ./test.nix { nixpkgs = majordomo.outputs.nixpkgs; };

    defaultPackage.x86_64-linux = self.packages.x86_64-linux.container;

    packages.x86_64-linux.deploy = majordomo.outputs.deploy { tag = "webservices/apache2-php73"; impure = true; };

  };
}

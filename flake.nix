{
  description = "elm-server-components flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      pkgs = import nixpkgs { system = "aarch64-darwin"; };

      lamdera = pkgs.stdenv.mkDerivation {
        pname = "lamdera";
        version = "0.0.1";
        src = pkgs.fetchurl {
          # nix-prefetch-url this URL to find the hash value
          url = "https://static.lamdera.com/bin/osx/lamdera";
          sha256 = "08qgqj36n9fjgjvvybznnkbm2gxxj4llgxc80rr0m86ahcb1v6b2";
        };

        dontUnpack = true;

        phases = [ "installPhase" ];
        installPhase = ''
          install -m755 -D $src $out/bin/lamdera
        '';
      };

    in {
      devShell.aarch64-darwin = pkgs.mkShell {
        buildInputs = [
          lamdera
          pkgs.elmPackages.elm
          pkgs.elmPackages.elm-format
        ];
      };
    };
}

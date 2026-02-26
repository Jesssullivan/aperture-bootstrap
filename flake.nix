{
  description = "aperture-bootstrap — Tailscale Aperture config management via tsnet";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
      in
      {
        packages.default = pkgs.buildGoModule {
          pname = "aperture-bootstrap";
          version = "0.1.0";
          src = ./.;
          vendorHash = null; # Update after first `go mod tidy`

          meta = {
            description = "Bootstrap Tailscale Aperture config from tagged devices";
            homepage = "https://github.com/Jesssullivan/aperture-bootstrap";
            mainProgram = "aperture-bootstrap";
          };
        };

        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            go
            just
            dhall
            dhall-json
            jq
            curl
          ];
        };
      }
    );
}

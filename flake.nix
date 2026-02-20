{
  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
    in {
      devShells = forAllSystems (system:
        let
          pkgs = import nixpkgs { inherit system; };
          busted-nlua = pkgs.lua5_1.pkgs.busted.overrideAttrs (oa: {
            propagatedBuildInputs = oa.propagatedBuildInputs ++ [ pkgs.lua5_1.pkgs.nlua ];
            nativeBuildInputs = oa.nativeBuildInputs ++ [ pkgs.makeWrapper ];
            postInstall = (oa.postInstall or "") + ''
              wrapProgram $out/bin/busted --add-flags "--lua=nlua"
            '';
          });
        in {
          default = pkgs.mkShell {
            buildInputs = [ pkgs.neovim-unwrapped busted-nlua pkgs.lua5_1.pkgs.nlua pkgs.lua5_1.pkgs.luacov pkgs.lua5_1.pkgs.luacheck ];
          };
        }
      );
    };
}

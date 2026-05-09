{
  description = "DeepSeek V4 Flash native inference engine";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  };

  outputs =
    { self, nixpkgs }:
    let
      systems = [
        "aarch64-darwin"
        "x86_64-darwin"
      ];

      forAllSystems = nixpkgs.lib.genAttrs systems;

      metalSources = [
        [ "DS4_METAL_FLASH_ATTN_SOURCE" "flash_attn.metal" ]
        [ "DS4_METAL_DENSE_SOURCE" "dense.metal" ]
        [ "DS4_METAL_MOE_SOURCE" "moe.metal" ]
        [ "DS4_METAL_DSV4_HC_SOURCE" "dsv4_hc.metal" ]
        [ "DS4_METAL_UNARY_SOURCE" "unary.metal" ]
        [ "DS4_METAL_DSV4_KV_SOURCE" "dsv4_kv.metal" ]
        [ "DS4_METAL_DSV4_ROPE_SOURCE" "dsv4_rope.metal" ]
        [ "DS4_METAL_DSV4_MISC_SOURCE" "dsv4_misc.metal" ]
        [ "DS4_METAL_ARGSORT_SOURCE" "argsort.metal" ]
        [ "DS4_METAL_CPY_SOURCE" "cpy.metal" ]
        [ "DS4_METAL_CONCAT_SOURCE" "concat.metal" ]
        [ "DS4_METAL_GET_ROWS_SOURCE" "get_rows.metal" ]
        [ "DS4_METAL_SUM_ROWS_SOURCE" "sum_rows.metal" ]
        [ "DS4_METAL_SOFTMAX_SOURCE" "softmax.metal" ]
        [ "DS4_METAL_REPEAT_SOURCE" "repeat.metal" ]
        [ "DS4_METAL_GLU_SOURCE" "glu.metal" ]
        [ "DS4_METAL_NORM_SOURCE" "norm.metal" ]
        [ "DS4_METAL_BIN_SOURCE" "bin.metal" ]
        [ "DS4_METAL_SET_ROWS_SOURCE" "set_rows.metal" ]
      ];

      makeFlags = [
        "CFLAGS=-O3 -ffast-math -Wall -Wextra -std=c99"
        "OBJCFLAGS=-O3 -ffast-math -Wall -Wextra -fobjc-arc"
      ];
    in
    {
      packages = forAllSystems (
        system:
        let
          pkgs = import nixpkgs { inherit system; };
          inherit (pkgs) lib stdenv;
          ds4 = stdenv.mkDerivation {
            pname = "ds4";
            version = (builtins.fromJSON (builtins.readFile ./package.json)).version;

            src = lib.cleanSourceWith {
              src = ./.;
              filter =
                path: type:
                let
                  name = baseNameOf path;
                in
                !(
                  name == ".git"
                  || name == "gguf"
                  || name == "misc"
                  || name == "ds4flash.gguf"
                  || name == "ds4"
                  || name == "ds4-server"
                  || name == "ds4_native"
                  || name == "ds4_server_test"
                  || name == "ds4_test"
                  || lib.hasSuffix ".o" name
                  || lib.hasSuffix ".dSYM" name
                  || lib.hasSuffix ".swp" name
                );
            };

            strictDeps = true;
            nativeBuildInputs = [
              pkgs.gnumake
              pkgs.makeWrapper
            ];
            buildInputs = [
              pkgs.apple-sdk_15
            ];

            dontConfigure = true;

            buildPhase = ''
              runHook preBuild
              make all ${nixpkgs.lib.escapeShellArgs makeFlags}
              runHook postBuild
            '';

            doCheck = true;
            checkPhase = ''
              runHook preCheck
              make ds4_test ${nixpkgs.lib.escapeShellArgs makeFlags}
              ./ds4_test --server
              runHook postCheck
            '';

            installPhase = ''
              runHook preInstall

              install -Dm755 ds4 "$out/bin/ds4"
              install -Dm755 ds4-server "$out/bin/ds4-server"
              install -Dm755 download_model.sh "$out/bin/ds4-download-model"
              install -Dm755 ds4-watchdog.sh "$out/bin/ds4-watchdog"

              install -Dm644 README.md "$out/share/doc/ds4/README.md"
              install -Dm644 LICENSE "$out/share/doc/ds4/LICENSE"
              mkdir -p "$out/share/ds4"
              cp -R metal "$out/share/ds4/metal"

              runHook postInstall
            '';

            postFixup = ''
              wrapProgram "$out/bin/ds4" \
                ${lib.concatMapStringsSep " \\\n                " (
                  spec:
                  let
                    env = builtins.elemAt spec 0;
                    file = builtins.elemAt spec 1;
                  in
                  ''--set-default ${env} "$out/share/ds4/metal/${file}"''
                ) metalSources}

              wrapProgram "$out/bin/ds4-server" \
                ${lib.concatMapStringsSep " \\\n                " (
                  spec:
                  let
                    env = builtins.elemAt spec 0;
                    file = builtins.elemAt spec 1;
                  in
                  ''--set-default ${env} "$out/share/ds4/metal/${file}"''
                ) metalSources}
            '';

            meta = {
              description = "Small native Metal inference engine for DeepSeek V4 Flash";
              homepage = "https://github.com/mitsuhiko/ds4";
              license = lib.licenses.mit;
              mainProgram = "ds4";
              platforms = lib.platforms.darwin;
            };
          };
        in
        {
          default = ds4;
          ds4 = ds4;
        }
      );

      apps = forAllSystems (
        system:
        let
          pkg = self.packages.${system}.default;
        in
        {
          default = {
            type = "app";
            program = "${pkg}/bin/ds4";
          };
          ds4-server = {
            type = "app";
            program = "${pkg}/bin/ds4-server";
          };
        }
      );

      checks = forAllSystems (system: {
        build = self.packages.${system}.default;
      });

      devShells = forAllSystems (
        system:
        let
          pkgs = import nixpkgs { inherit system; };
        in
        {
          default = pkgs.mkShell {
            packages = [
              pkgs.gnumake
            ];
            buildInputs = [
              pkgs.apple-sdk_15
            ];
          };
        }
      );
    };
}

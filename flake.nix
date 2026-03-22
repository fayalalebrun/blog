
{
  description = "Org-mode blog built with Emacs";

  inputs = {
    nixpkgs.url = "flake:nixpkgs";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};

        # Emacs with htmlize package for syntax highlighting
        emacsWithPackages = pkgs.emacs-nox.pkgs.withPackages (epkgs: [
          epkgs.htmlize
        ]);

        # The built site as a derivation
        blog = pkgs.stdenv.mkDerivation {
          name = "blog";
          src = ./.;
          buildInputs = [ emacsWithPackages ];
          buildPhase = ''
            # Set HOME to a writable directory for org-mode cache
            export HOME=$(mktemp -d)
            export TERM=''${TERM:-xterm-256color}
            ${emacsWithPackages}/bin/emacs --batch -Q -l build-site.el
          '';
          installPhase = ''
            cp -r public $out
          '';
        };

      in {
        packages = {
          default = blog;
          blog = blog;
        };

        apps = {
          # nix run .#build - Build the site (run from blog directory)
          build = {
            type = "app";
            program = toString (pkgs.writeShellScript "build" ''
              set -e
              if [ ! -f "flake.nix" ]; then
                echo "Error: Run this from the blog directory (where flake.nix is)"
                exit 1
              fi
              export TERM="''${TERM:-xterm-256color}"
              echo "Building site..."
              ${emacsWithPackages}/bin/emacs --batch -Q -l build-site.el
              echo ""
              echo "Site built in ./public"
            '');
          };

          # nix run .#preview - Build and serve with live preview
          preview = {
            type = "app";
            program = toString (pkgs.writeShellScript "preview" ''
              set -e
              if [ ! -f "flake.nix" ]; then
                echo "Error: Run this from the blog directory (where flake.nix is)"
                exit 1
              fi
              export TERM="''${TERM:-xterm-256color}"

              build_site() {
                echo "Building site..."
                ${emacsWithPackages}/bin/emacs --batch -Q -l build-site.el
                echo "Build complete"
                echo ""
              }

              build_site

              echo "Serving at http://localhost:4613"
              echo "Watching content/, build-site.el, preamble.html, and header.html"
              echo "Press Ctrl+C to stop"
              echo ""

              ${pkgs.python3}/bin/python -m http.server 4613 --directory public &
              server_pid=$!

              cleanup() {
                kill "$server_pid" 2>/dev/null || true
              }

              trap cleanup EXIT INT TERM

              ${pkgs.watchexec}/bin/watchexec \
                --watch content \
                --watch build-site.el \
                --watch preamble.html \
                --watch header.html \
                -- ${pkgs.bash}/bin/bash -lc 'export TERM="''${TERM:-xterm-256color}"; ${emacsWithPackages}/bin/emacs --batch -Q -l build-site.el'
            '');
          };

          # nix run .#serve - Just serve existing build
          serve = {
            type = "app";
            program = toString (pkgs.writeShellScript "serve" ''
              set -e
              if [ ! -d "public" ] || [ ! -f "public/index.html" ]; then
                echo "No build found. Run 'nix run .#build' first."
                exit 1
              fi

              echo "Serving at http://localhost:4613"
              echo "Press Ctrl+C to stop"
              cd public
              ${pkgs.python3}/bin/python -m http.server 4613
            '');
          };
        };

        # nix develop - Shell with all tools available
        devShells.default = pkgs.mkShell {
          buildInputs = [
            emacsWithPackages
            pkgs.python3  # for local preview server
            pkgs.watchexec
          ];

          shellHook = ''
            echo "Blog development shell"
            echo ""
            echo "Commands:"
            echo "  nix run .#build    - Build the site to ./public"
            echo "  nix run .#preview  - Build and serve at localhost:4613"
            echo "  nix run .#serve    - Serve existing build"
            echo "  nix build          - Build site as Nix derivation"
            echo ""
          '';
        };
      }
    );
}

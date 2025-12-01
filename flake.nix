{
  description = "Thanatos - Zoi server with GTK WebKit display";
  
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
        devShells.default = pkgs.mkShell {
          packages = with pkgs; [
            # Build tools
            zig
            pkg-config
            
            # GTK and WebKit
            gtk3
            webkitgtk_4_1
            
            # Graphics libraries (for EGL/OpenGL)
            libGL
            mesa
            libglvnd
            
            # Additional dependencies
            sqlite
            glib
            cairo
            pango
            gdk-pixbuf
            libsoup_3
            
            # X11 libraries
            xorg.libX11
            xorg.libXcomposite
            xorg.libXdamage
            xorg.libXext
            
            # Utility
            fortune
          ];
          
          shellHook = ''
            echo "==================================="
            echo "Thanatos development environment"
            echo "==================================="
            echo "Available commands:"
            echo "  zig build        - Build the project"
            echo "  zig build run    - Build and run"
            echo ""
            export PKG_CONFIG_PATH="${pkgs.webkitgtk_4_1}/lib/pkgconfig:${pkgs.gtk3}/lib/pkgconfig:$PKG_CONFIG_PATH"
            export LD_LIBRARY_PATH="${pkgs.webkitgtk_4_1}/lib:${pkgs.gtk3}/lib:${pkgs.libGL}/lib:${pkgs.mesa}/lib:$LD_LIBRARY_PATH"
            
            # Use software rendering if hardware acceleration fails
            export LIBGL_ALWAYS_SOFTWARE=1
          '';
        };
      }
    );
}


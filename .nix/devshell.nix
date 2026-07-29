{ pkgs, agentCheck }:
pkgs.mkShell {
  packages = [
    agentCheck
  ]
  ++ (with pkgs; [
    actionlint
    cargo
    clippy
    dart
    beam28Packages.erlang
    git
    gleam
    jq
    nixfmt
    nodejs_22
    openssl
    pkg-config
    python312
    beam28Packages.rebar3
    ripgrep
    rust-analyzer
    rustc
    rustfmt
    shellcheck
    shfmt
  ]);

  LANG = if pkgs.stdenv.hostPlatform.isDarwin then "en_US.UTF-8" else "C.UTF-8";
  LC_ALL = if pkgs.stdenv.hostPlatform.isDarwin then "en_US.UTF-8" else "C.UTF-8";

  shellHook = ''
    export FTNL_DEV_SHELL="clients"
    export XDG_CACHE_HOME="''${XDG_CACHE_HOME:-$PWD/.cache/nix-agent}"
  '';
}

# To learn more about how to use Nix to configure your environment
# see: https://firebase.google.com/docs/studio/customize-workspace
{ pkgs, ... }: {
  # Which nixpkgs channel to use.
  channel = "stable-24.05"; # or "unstable"

  # Use https://search.nixos.org/packages to find packages
  packages = [
    pkgs.flutter
    pkgs.python311
    pkgs.nss_latest
    pkgs.fontconfig
    pkgs.freetype
    pkgs.libGL
    pkgs.android-sdk
    (pkgs.android-sdk.packages.build-tools.override { version = "35.0.0"; })
    pkgs.jdk
  ];

  # Sets environment variables in the workspace
  env = {};
  idx = {
    # Search for the extensions you want on https://open-vsx.org/ and use "publisher.id"
    extensions = [
      "dart-code.flutter"
    ];

    # Enable previews
    previews = {
      enable = true;
      previews = {
        web = {
          command = ["bash", "-c", "cd flutter_app/build/web && python3 -m http.server $PORT"];
          manager = "web";
        };
      };
    };

    # Workspace lifecycle hooks
    workspace = {
      # Runs when a workspace is first created
      onCreate = {
        # Build the flutter web app
        flutter-build = "cd flutter_app && flutter build web";
      };
      # Runs when the workspace is (re)started
      onStart = {};
    };
  };
}

{ lib, stdenv, fetchurl, pkgconfig, gtk2, pango, perl, python2, python3, nodejs
, libIDL, libjpeg, zlib, dbus, dbus-glib, bzip2, xorg
, freetype, fontconfig, file, nspr, nss, libnotify
, yasm, libGLU_combined, sqlite, zip, unzip
, libevent, libstartup_notification
, icu, libpng, jemalloc
, autoconf213, which, m4, fetchpatch
, writeScript, xidel, common-updater-scripts, coreutils, gnused, gnugrep, curl
, runtimeShell
, cargo, rustc, rust-cbindgen, llvmPackages, nasm
, enableGTK3 ? false, gtk3, gnome3, wrapGAppsHook, makeWrapper
, enableCalendar ? true
, debugBuild ? false
, # If you want the resulting program to call itself "Thunderbird" instead
  # of "Earlybird" or whatever, enable this option.  However, those
  # binaries may not be distributed without permission from the
  # Mozilla Foundation, see
  # http://www.mozilla.org/foundation/trademarks/.
  enableOfficialBranding ? false
, makeDesktopItem
}:

let
  wrapperTool = if enableGTK3 then wrapGAppsHook else makeWrapper;
  gcc = if stdenv.cc.isGNU then stdenv.cc.cc else stdenv.cc.cc.gcc;
in stdenv.mkDerivation rec {
  pname = "thunderbird";
  version = "68.2.2";

  src = fetchurl {
    url = "mirror://mozilla/thunderbird/releases/${version}/source/thunderbird-${version}.source.tar.xz";
    sha512 = "3mvanjfc35f14lsfa4zjlhsvwij1n9dz9xmisd5s376r5wp9y33sva5ly914b2hmdl85ypdwv90zyi6whj7jb2f2xmqk480havxgjcn";
  };

  # from firefox, but without sound libraries
  buildInputs =
    [ gtk2 zip libIDL libjpeg zlib bzip2
      dbus dbus-glib pango freetype fontconfig xorg.libXi
      xorg.libX11 xorg.libXrender xorg.libXft xorg.libXt file
      nspr nss libnotify xorg.pixman yasm libGLU_combined
      xorg.libXScrnSaver xorg.xorgproto
      xorg.libXext sqlite unzip
      libevent libstartup_notification /* cairo */
      icu libpng jemalloc nasm
    ]
    ++ lib.optionals enableGTK3 [ gtk3 gnome3.adwaita-icon-theme ];

  # from firefox + m4 + wrapperTool
  # llvm is for llvm-objdump
  nativeBuildInputs = [ m4 autoconf213 which gnused pkgconfig perl python2 python3 nodejs wrapperTool cargo rustc rust-cbindgen llvmPackages.llvm ];

  patches = [
    # Remove buildconfig.html to prevent a dependency on clang etc.
    ./no-buildconfig.patch
  ]
  ++ lib.optional (lib.versionOlder version "69")
    (fetchpatch { # https://bugzilla.mozilla.org/show_bug.cgi?id=1500436#c29
      name = "write_error-parallel_make.diff";
      url = "https://hg.mozilla.org/mozilla-central/raw-diff/562655fe/python/mozbuild/mozbuild/action/node.py";
      sha256 = "11d7rgzinb4mwl7yzhidjkajynmxgmffr4l9isgskfapyax9p88y";
    });

  configureFlags =
    [ # from firefox, but without sound libraries (alsa, libvpx, pulseaudio)
      "--enable-application=comm/mail"
      "--disable-alsa"
      "--disable-pulseaudio"

      "--with-system-jpeg"
      "--with-system-zlib"
      "--with-system-bz2"
      "--with-system-nspr"
      "--with-system-nss"
      "--with-system-libevent"
      "--with-system-png" # needs APNG support
      "--with-system-icu"
      #"--enable-rust-simd" # not supported since rustc 1.32.0 -> 1.33.0; TODO: probably OK since 68.0.0
      "--enable-system-ffi"
      "--enable-system-pixman"
      "--enable-system-sqlite"
      #"--enable-system-cairo"
      "--enable-startup-notification"
      "--disable-crashreporter"
      "--disable-tests"
      "--disable-necko-wifi" # maybe we want to enable this at some point
      "--disable-updater"
      "--enable-jemalloc"
      "--disable-gconf"
      "--enable-default-toolkit=cairo-gtk${if enableGTK3 then "3" else "2"}"
      "--enable-js-shell"
    ]
      ++ lib.optional enableCalendar "--enable-calendar"
      ++ (if debugBuild then [ "--enable-debug" "--enable-profiling"]
                        else [ "--disable-debug" "--enable-release"
                               "--disable-debug-symbols"
                               "--enable-optimize" "--enable-strip" ])
      ++ lib.optional enableOfficialBranding "--enable-official-branding"
      ++ lib.optionals (lib.versionAtLeast version "56" && !stdenv.hostPlatform.isi686) [
        # on i686-linux: --with-libclang-path is not available in this configuration
        "--with-libclang-path=${llvmPackages.libclang}/lib"
        "--with-clang-path=${llvmPackages.clang}/bin/clang"
      ];

  enableParallelBuilding = true;

  preConfigure =
    ''
      cxxLib=$( echo -n ${gcc}/include/c++/* )
      archLib=$cxxLib/$( ${gcc}/bin/gcc -dumpmachine )

      test -f layout/style/ServoBindings.toml && sed -i -e '/"-DRUST_BINDGEN"/ a , "-cxx-isystem", "'$cxxLib'", "-isystem", "'$archLib'"' layout/style/ServoBindings.toml

      configureScript="$(realpath ./configure)"
      mkdir ../objdir
      cd ../objdir

      # AS=as in the environment causes build failure https://bugzilla.mozilla.org/show_bug.cgi?id=1497286
      unset AS
    '';

  dontWrapGApps = true; # we do it ourselves
  postInstall =
    ''
      # TODO: Move to a dev output?
      rm -rf $out/include $out/lib/thunderbird-devel-* $out/share/idl

      # $binary is a symlink to $target.
      # We wrap $target by replacing the $binary symlink.
      local target="$out/lib/thunderbird/thunderbird"
      local binary="$out/bin/thunderbird"

      # Wrap correctly, this is needed to
      # 1) find Mozilla runtime, because argv0 must be the real thing,
      #    or a symlink thereto. It cannot be the wrapper itself
      # 2) detect itself as the default mailreader across builds
      gappsWrapperArgs+=(
        --argv0 "$target"
        --set MOZ_APP_LAUNCHER thunderbird
        # See commit 87e261843c4236c541ee0113988286f77d2fa1ee
        --set MOZ_LEGACY_PROFILES 1
        --set MOZ_ALLOW_DOWNGRADE 1
        # https://github.com/NixOS/nixpkgs/pull/61980
        --set SNAP_NAME "thunderbird"
      )
      ${
        # We wrap manually because wrapGAppsHook does not detect the symlink
        # To mimic wrapGAppsHook, we run it with dontWrapGApps, so
        # gappsWrapperArgs gets defined correctly
        lib.optionalString enableGTK3 "wrapGAppsHook"
      }

      # "$binary" is a symlink, replace it by the wrapper
      rm "$binary"
      makeWrapper "$target" "$binary" "''${gappsWrapperArgs[@]}"

      ${ let desktopItem = makeDesktopItem {
          name = "thunderbird";
          exec = "thunderbird %U";
          desktopName = "Thunderbird";
          icon = "$out/lib/thunderbird/chrome/icons/default/default256.png";
          genericName = "Mail Reader";
          categories = "Application;Network";
          mimeType = stdenv.lib.concatStringsSep ";" [
            # Email
            "x-scheme-handler/mailto"
            "message/rfc822"
            # Newsgroup
            "x-scheme-handler/news"
            "x-scheme-handler/snews"
            "x-scheme-handler/nntp"
            # Feed
            "x-scheme-handler/feed"
            "application/rss+xml"
            "application/x-extension-rss"
          ];
        }; in desktopItem.buildCommand
      }
    '';

  postFixup =
    # Fix notifications. LibXUL uses dlopen for this, unfortunately; see #18712.
    ''
      patchelf --set-rpath "${lib.getLib libnotify
        }/lib:$(patchelf --print-rpath "$out"/lib/thunderbird*/libxul.so)" \
          "$out"/lib/thunderbird*/libxul.so
    '';

  doInstallCheck = true;
  installCheckPhase =
    ''
      # Some basic testing
      "$out/bin/thunderbird" --version
    '';

  disallowedRequisites = [ stdenv.cc ];

  meta = with stdenv.lib; {
    description = "A full-featured e-mail client";
    homepage = http://www.mozilla.org/thunderbird/;
    license =
      # Official branding implies thunderbird name and logo cannot be reuse,
      # see http://www.mozilla.org/foundation/licensing.html
      if enableOfficialBranding then licenses.proprietary else licenses.mpl11;
    maintainers = [ maintainers.pierron maintainers.eelco ];
    platforms = platforms.linux;
  };

  passthru.updateScript = import ./../../browsers/firefox/update.nix {
    attrPath = "thunderbird";
    baseUrl = "http://archive.mozilla.org/pub/thunderbird/releases/";
    inherit writeScript lib common-updater-scripts xidel coreutils gnused gnugrep curl runtimeShell;
  };
}

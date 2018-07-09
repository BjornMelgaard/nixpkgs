{ stdenv, fetchurl, fetchFromGitHub, fetchpatch, makeWrapper
, docutils, perl, pkgconfig, python3, which, ffmpeg_4
, freefont_ttf, freetype, libass, libpthreadstubs
, lua, luasocket, libuchardet, libiconv ? null, darwin

, x11Support ? true,
    libGLU_combined       ? null,
    libX11     ? null,
    libXext    ? null,
    libXxf86vm ? null,
    libXrandr  ? null

, waylandSupport ? false
  , wayland           ? null
  , wayland-protocols ? null
  , libxkbcommon      ? null

, rubberbandSupport  ? true,  rubberband    ? null
, xineramaSupport    ? true,  libXinerama   ? null
, xvSupport          ? true,  libXv         ? null
, sdl2Support        ? true,  SDL2          ? null
, alsaSupport        ? true,  alsaLib       ? null
, screenSaverSupport ? true,  libXScrnSaver ? null
, vdpauSupport       ? true,  libvdpau      ? null
, dvdreadSupport     ? true,  libdvdread    ? null
, dvdnavSupport      ? true,  libdvdnav     ? null
, bluraySupport      ? true,  libbluray     ? null
, speexSupport       ? true,  speex         ? null
, theoraSupport      ? true,  libtheora     ? null
, pulseSupport       ? true,  libpulseaudio ? null
, bs2bSupport        ? true,  libbs2b       ? null
, cacaSupport        ? true,  libcaca       ? null
, libpngSupport      ? true,  libpng        ? null
, youtubeSupport     ? true,  youtube-dl    ? null
, vaapiSupport       ? true,  libva         ? null
, drmSupport         ? true,  libdrm        ? null
, openalSupport      ? true,  openalSoft   ? null
, vapoursynthSupport ? false, vapoursynth   ? null
, archiveSupport     ? false, libarchive    ? null
, jackaudioSupport   ? false, libjack2      ? null

# scripts you want to be loaded by default
, scripts ? []
}:

with stdenv.lib;

let
  available = x: x != null;
in
assert x11Support         -> all available [libGLU_combined libX11 libXext libXxf86vm libXrandr];
assert waylandSupport     -> all available [wayland wayland-protocols libxkbcommon];
assert rubberbandSupport  -> available rubberband;
assert xineramaSupport    -> x11Support && available libXinerama;
assert xvSupport          -> x11Support && available libXv;
assert sdl2Support        -> available SDL2;
assert alsaSupport        -> available alsaLib;
assert screenSaverSupport -> available libXScrnSaver;
assert vdpauSupport       -> available libvdpau;
assert dvdreadSupport     -> available libdvdread;
assert dvdnavSupport      -> available libdvdnav;
assert bluraySupport      -> available libbluray;
assert speexSupport       -> available speex;
assert theoraSupport      -> available libtheora;
assert openalSupport      -> available openalSoft;
assert pulseSupport       -> available libpulseaudio;
assert bs2bSupport        -> available libbs2b;
assert cacaSupport        -> available libcaca;
assert libpngSupport      -> available libpng;
assert youtubeSupport     -> available youtube-dl;
assert vapoursynthSupport -> available vapoursynth;
assert jackaudioSupport   -> available libjack2;
assert archiveSupport     -> available libarchive;
assert vaapiSupport       -> available libva;
assert drmSupport         -> available libdrm;

let
  # Purity: Waf is normally downloaded by bootstrap.py, but
  # for purity reasons this behavior should be avoided.
  wafVersion = "1.9.15";
  waf = fetchurl {
    urls = [ "https://waf.io/waf-${wafVersion}"
             "http://www.freehackers.org/~tnagy/release/waf-${wafVersion}" ];
    sha256 = "0qrnlv91cb0v221w8a0fi4wxm99q2hpz10rkyyk4akcsvww6xrw5";
  };
in stdenv.mkDerivation rec {
  name = "mpv-${version}";
  version = "0.28.2";

  src = fetchFromGitHub {
    owner = "mpv-player";
    repo  = "mpv";
    rev    = "v${version}";
    sha256 = "0bldxhqjz7z9fgvx4k40l49awpay17fscp8ypswb459yicy8npmg";
  };

  postPatch = ''
    patchShebangs ./TOOLS/
  '';

  NIX_LDFLAGS = optionalString x11Support "-lX11 -lXext";

  configureFlags = [
    "--enable-libmpv-shared"
    "--enable-manpage-build"
    "--enable-zsh-comp"
    "--disable-libmpv-static"
    "--disable-static-build"
    "--disable-build-date" # Purity
    (enableFeature archiveSupport "libarchive")
    (enableFeature dvdreadSupport "dvdread")
    (enableFeature dvdnavSupport "dvdnav")
    (enableFeature openalSupport "openal")
    (enableFeature vaapiSupport "vaapi")
    (enableFeature waylandSupport "wayland")
    (enableFeature stdenv.isLinux "dvbin")
  ];

  configurePhase = ''
    python3 ${waf} configure --prefix=$out $configureFlags
  '';

  nativeBuildInputs = [
    docutils makeWrapper perl
    pkgconfig python3 which
  ];

  buildInputs = [
    ffmpeg_4 freetype libass libpthreadstubs
    lua luasocket libuchardet
  ] ++ optional alsaSupport        alsaLib
    ++ optional xvSupport          libXv
    ++ optional theoraSupport      libtheora
    ++ optional xineramaSupport    libXinerama
    ++ optional dvdreadSupport     libdvdread
    ++ optional bluraySupport      libbluray
    ++ optional jackaudioSupport   libjack2
    ++ optional pulseSupport       libpulseaudio
    ++ optional rubberbandSupport  rubberband
    ++ optional screenSaverSupport libXScrnSaver
    ++ optional vdpauSupport       libvdpau
    ++ optional speexSupport       speex
    ++ optional bs2bSupport        libbs2b
    ++ optional openalSupport      openalSoft
    ++ optional (openalSupport && stdenv.isDarwin) darwin.apple_sdk.frameworks.OpenAL
    ++ optional libpngSupport      libpng
    ++ optional youtubeSupport     youtube-dl
    ++ optional sdl2Support        SDL2
    ++ optional cacaSupport        libcaca
    ++ optional vaapiSupport       libva
    ++ optional drmSupport         libdrm
    ++ optional vapoursynthSupport vapoursynth
    ++ optional archiveSupport     libarchive
    ++ optionals dvdnavSupport     [ libdvdnav libdvdnav.libdvdread ]
    ++ optionals x11Support        [ libX11 libXext libGLU_combined libXxf86vm libXrandr ]
    ++ optionals waylandSupport    [ wayland wayland-protocols libxkbcommon ]
    ++ optionals stdenv.isDarwin (with darwin.apple_sdk.frameworks; [
      libiconv Cocoa CoreAudio
    ]);

  enableParallelBuilding = true;

  buildPhase = ''
    python3 ${waf} build
  '';

  installPhase =
  let
    getPath  = type : "${luasocket}/lib/lua/${lua.luaversion}/?.${type};" +
                      "${luasocket}/share/lua/${lua.luaversion}/?.${type}";
    luaPath  = getPath "lua";
    luaCPath = getPath "so";
  in
  ''
    python3 ${waf} install

    # Use a standard font
    mkdir -p $out/share/mpv
    ln -s ${freefont_ttf}/share/fonts/truetype/FreeSans.ttf $out/share/mpv/subfont.ttf
    # Ensure youtube-dl is available in $PATH for MPV
    wrapProgram $out/bin/mpv \
      --add-flags "--scripts=${concatStringsSep "," scripts}" \
      --prefix LUA_PATH : "${luaPath}" \
      --prefix LUA_CPATH : "${luaCPath}" \
  '' + optionalString youtubeSupport ''
      --prefix PATH : "${youtube-dl}/bin" \
  '' + optionalString vapoursynthSupport ''
      --prefix PYTHONPATH : "${vapoursynth}/lib/${python3.libPrefix}/site-packages:$PYTHONPATH"
  '' + ''

    cp TOOLS/umpv $out/bin
    wrapProgram $out/bin/umpv \
      --set MPV "$out/bin/mpv"
  '';

  meta = with stdenv.lib; {
    description = "A media player that supports many video formats (MPlayer and mplayer2 fork)";
    homepage = https://mpv.io;
    license = licenses.gpl2Plus;
    maintainers = with maintainers; [ AndersonTorres fuuzetsu fpletz ];
    platforms = platforms.darwin ++ platforms.linux;

    longDescription = ''
      mpv is a free and open-source general-purpose video player,
      based on the MPlayer and mplayer2 projects, with great
      improvements above both.
    '';
  };
}

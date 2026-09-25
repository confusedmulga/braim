{{flutter_js}}
{{flutter_build_config}}

// Fallback fonts (Roboto, emoji, symbols, other scripts) come from this
// origin — tool/fetch_web_fonts.py puts them in fonts/gstatic/ — never from
// Google, so text renders with no internet (the phone's hotspot, say).
const engineConfig = {
  fontFallbackBaseUrl: new URL('fonts/gstatic/', document.baseURI).href,
};

_flutter.loader.load({
  config: engineConfig,
  onEntrypointLoaded: async function (engineInitializer) {
    const appRunner = await engineInitializer.initializeEngine(engineConfig);
    await appRunner.runApp();
    const splash = document.getElementById('splash');
    if (splash) {
      splash.style.opacity = '0';
      setTimeout(() => splash.remove(), 200);
    }
  },
});

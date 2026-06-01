package com.talentbridge.offline_navigator

import android.content.Context
import android.util.Log
import com.valhalla.valhalla.ValhallaActor
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * MethodChannel bridge to the native Valhalla engine (valhalla-mobile).
 *
 * Region-aware: each call carries an optional `regionDir` (the active region's
 * directory, holding `valhalla_tiles.tar` + `admins.sqlite`). The plugin writes a
 * `valhalla.json` into that dir (paths rewritten to it) and caches one
 * `ValhallaActor` per dir, so switching regions just builds/reuses another actor.
 * A null `regionDir` uses a legacy dir seeded from the bundled assets.
 */
class ValhallaPlugin(private val context: Context) {
    companion object {
        const val CHANNEL = "offline_navigator/valhalla"
    }

    // One actor per routing directory, keyed by absolute path.
    private val actors = HashMap<String, ValhallaActor>()

    fun register(engine: FlutterEngine) {
        MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    // Catch Throwable, not just Exception: a native-library load
                    // failure (e.g. UnsatisfiedLinkError / ExceptionInInitializerError
                    // when libvalhalla-wrapper.so can't load on this device) is an
                    // Error, not an Exception — without this it would crash the app
                    // instead of surfacing a readable reason on the trip panel.
                    "ensureReady" -> try {
                        actorFor(call.argument<String>("regionDir"))
                        result.success(null)
                    } catch (e: Throwable) {
                        result.error("ENSURE_FAILED", describe(e), stackOf(e))
                    }
                    "route" -> try {
                        val req = call.argument<String>("request")
                            ?: return@setMethodCallHandler result.error(
                                "BAD_ARGS", "missing request", null)
                        val actor = actorFor(call.argument<String>("regionDir"))
                        result.success(actor.route(req))
                    } catch (e: Throwable) {
                        result.error("ROUTE_FAILED", describe(e), stackOf(e))
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /**
     * Construct + cache (once) the actor for a routing directory. [regionDir] =
     * the active region's dir (already holding `valhalla_tiles.tar` +
     * `admins.sqlite`); null = a legacy dir seeded from bundled assets on first
     * use. A `valhalla.json` is (re)written so its `__APPDIR__` paths resolve
     * inside the chosen dir.
     */
    private fun actorFor(regionDir: String?): ValhallaActor {
        val dir = if (regionDir != null) File(regionDir) else legacyDir()
        actors[dir.absolutePath]?.let { return it }
        prepareDir(dir, isLegacy = regionDir == null)
        return ValhallaActor(File(dir, "valhalla.json").absolutePath).also {
            actors[dir.absolutePath] = it
        }
    }

    private fun legacyDir(): File =
        File(context.filesDir, "routing").apply { mkdirs() }

    /**
     * Ensure [dir] has the routing tiles + admins + a `valhalla.json`. A region
     * dir already holds the tiles/admins (downloaded or seeded by the region
     * store); the legacy dir is seeded from the bundled assets. The config is
     * always (re)written so its paths point at [dir].
     */
    private fun prepareDir(dir: File, isLegacy: Boolean) {
        dir.mkdirs()
        if (isLegacy) {
            val tar = File(dir, "valhalla_tiles.tar")
            if (!tar.exists()) copyAsset(assetPath("valhalla_tiles.tar"), tar)
            val admins = File(dir, "admins.sqlite")
            if (!admins.exists()) copyAsset(assetPath("admins.sqlite"), admins)
        }
        val template = context.assets.open(assetPath("valhalla.json"))
            .bufferedReader().use { it.readText() }
        File(dir, "valhalla.json")
            .writeText(template.replace("__APPDIR__", dir.absolutePath))
    }

    /**
     * A readable one-line reason that names the throwable type (and its cause
     * type), so the trip panel shows e.g. "UnsatisfiedLinkError: dlopen failed…"
     * or "FileNotFoundException: flutter_assets/assets/routing/…" rather than a
     * bare or null message. Also logs the full stack to logcat under
     * "ValhallaPlugin".
     */
    private fun describe(e: Throwable): String {
        Log.e("ValhallaPlugin", "Valhalla call failed", e)
        val cause = e.cause?.let {
            " (cause: ${it.javaClass.simpleName}: ${it.message})"
        } ?: ""
        return "${e.javaClass.simpleName}: ${e.message}$cause"
    }

    private fun stackOf(e: Throwable): String = Log.getStackTraceString(e)

    /**
     * Flutter bundles assets under `flutter_assets/` in the Android asset
     * namespace, so a `pubspec.yaml` asset at `assets/routing/x` is opened via
     * `flutter_assets/assets/routing/x` from AssetManager — NOT `assets/...`.
     */
    private fun assetPath(name: String): String =
        "flutter_assets/assets/routing/$name"

    private fun copyAsset(assetPath: String, dest: File) {
        context.assets.open(assetPath).use { input ->
            dest.outputStream().use { output -> input.copyTo(output) }
        }
    }
}

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
 * ensureReady: copies the bundled tiles tar + admins.sqlite from Flutter assets
 * into app files storage (once, version-stamped), writes a valhalla.json whose
 * mjolnir paths point at that storage, and constructs a ValhallaActor.
 * route: forwards a Valhalla request JSON string to ValhallaActor.route().
 */
class ValhallaPlugin(private val context: Context) {
    companion object {
        const val CHANNEL = "offline_navigator/valhalla"
        // Bump when bundled tiles change OR the native engine changes so the
        // on-device storage (and the actor) start fresh. Bumped to "2" with the
        // valhalla-mobile 0.1.0 -> 0.3.0 engine upgrade.
        const val VERSION = "2"
    }

    private var actor: ValhallaActor? = null

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
                        ensureReady(); result.success(null)
                    } catch (e: Throwable) {
                        result.error("ENSURE_FAILED", describe(e), stackOf(e))
                    }
                    "route" -> try {
                        val req = call.argument<String>("request")
                            ?: return@setMethodCallHandler result.error(
                                "BAD_ARGS", "missing request", null)
                        result.success(route(req))
                    } catch (e: Throwable) {
                        result.error("ROUTE_FAILED", describe(e), stackOf(e))
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun routingDir(): File =
        File(context.filesDir, "routing").apply { mkdirs() }

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

    private fun ensureReady() {
        if (actor != null) return
        val dir = routingDir()
        val stamp = File(dir, ".version")
        val fresh = !stamp.exists() || stamp.readText().trim() != VERSION
        if (fresh) {
            copyAsset(assetPath("valhalla_tiles.tar"), File(dir, "valhalla_tiles.tar"))
            copyAsset(assetPath("admins.sqlite"), File(dir, "admins.sqlite"))
            // Read the bundled config template and rewrite __APPDIR__.
            val template = context.assets.open(assetPath("valhalla.json"))
                .bufferedReader().use { it.readText() }
            val config = template.replace("__APPDIR__", dir.absolutePath)
            File(dir, "valhalla.json").writeText(config)
            stamp.writeText(VERSION)
        }
        actor = ValhallaActor(File(dir, "valhalla.json").absolutePath)
    }

    /**
     * Flutter bundles assets under `flutter_assets/` in the Android asset
     * namespace, so a `pubspec.yaml` asset at `assets/routing/x` is opened via
     * `flutter_assets/assets/routing/x` from AssetManager — NOT `assets/...`.
     */
    private fun assetPath(name: String): String =
        "flutter_assets/assets/routing/$name"

    private fun route(request: String): String {
        ensureReady()
        return actor!!.route(request)
    }

    private fun copyAsset(assetPath: String, dest: File) {
        context.assets.open(assetPath).use { input ->
            dest.outputStream().use { output -> input.copyTo(output) }
        }
    }
}

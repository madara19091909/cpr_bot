package com.mcmanger.android

import android.app.Activity
import android.content.Intent
import android.net.Uri
import androidx.documentfile.provider.DocumentFile
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Storage Access Framework bridge. Only READS from the picked tree; every
 * write goes to an app-private destination chosen by Dart.
 */
class MainActivity : FlutterActivity() {
    private val channelName = "mcmanger/saf"
    private val pickCode = 4101
    private var pending: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "pickTree" -> {
                        if (pending != null) {
                            result.error("busy", "A picker is already open", null)
                        } else {
                            pending = result
                            val i = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).addFlags(
                                Intent.FLAG_GRANT_READ_URI_PERMISSION or
                                    Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION
                            )
                            @Suppress("DEPRECATION")
                            startActivityForResult(i, pickCode)
                        }
                    }
                    "hasPermission" -> {
                        val uri = call.argument<String>("uri")
                        result.success(contentResolver.persistedUriPermissions.any {
                            it.uri.toString() == uri && it.isReadPermission
                        })
                    }
                    "treeName" -> {
                        val uri = call.argument<String>("uri")
                        val doc = uri?.let { DocumentFile.fromTreeUri(this, Uri.parse(it)) }
                        result.success(doc?.name)
                    }
                    "copyTree" -> {
                        val uri = call.argument<String>("uri")
                        val dest = call.argument<String>("dest")
                        if (uri == null || dest == null) {
                            result.error("args", "uri and dest required", null)
                        } else {
                            Thread {
                                val errors = ArrayList<String>()
                                var count = 0
                                try {
                                    val root = DocumentFile.fromTreeUri(this, Uri.parse(uri))
                                    if (root == null) errors.add("Cannot open tree (permission lost?)")
                                    else count = copyDir(root, File(dest), errors)
                                } catch (e: Exception) {
                                    errors.add(e.toString())
                                }
                                runOnUiThread {
                                    result.success(mapOf("files" to count, "errors" to errors))
                                }
                            }.start()
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun safeName(n: String) =
        n.isNotEmpty() && n != "." && n != ".." && !n.contains('/') && !n.contains('\u0000')

    private fun copyDir(src: DocumentFile, dest: File, errors: MutableList<String>): Int {
        dest.mkdirs()
        var count = 0
        for (child in src.listFiles()) {
            val name = child.name
            if (name == null || !safeName(name)) {
                errors.add("Skipped unsafe or unnamed entry: ${name ?: "<null>"}")
                continue
            }
            if (child.isDirectory) {
                count += copyDir(child, File(dest, name), errors)
            } else if (child.isFile) {
                try {
                    val input = contentResolver.openInputStream(child.uri)
                    if (input == null) {
                        errors.add("Cannot open $name")
                    } else {
                        input.use { i -> File(dest, name).outputStream().use { o -> i.copyTo(o) } }
                        count++
                    }
                } catch (e: Exception) {
                    errors.add("$name: $e")
                }
            }
        }
        return count
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != pickCode) return
        val r = pending ?: return
        pending = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            r.success(null)
        } else {
            try {
                contentResolver.takePersistableUriPermission(
                    uri, Intent.FLAG_GRANT_READ_URI_PERMISSION
                )
            } catch (_: SecurityException) { /* some providers refuse persistence */ }
            r.success(uri.toString())
        }
    }
}

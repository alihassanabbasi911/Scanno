package com.example.docuscan

import android.content.Intent
import android.database.Cursor
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.util.UUID

class MainActivity : FlutterActivity() {
    private val pendingIntents = mutableListOf<Intent>()
    private val mainHandler = Handler(Looper.getMainLooper())
    private var incomingSink: EventChannel.EventSink? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            INCOMING_EVENT_CHANNEL,
        ).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(
                    arguments: Any?,
                    events: EventChannel.EventSink,
                ) {
                    incomingSink = events
                    pendingIntents.toList().forEach(::dispatchIntent)
                    pendingIntents.clear()
                }

                override fun onCancel(arguments: Any?) {
                    incomingSink = null
                }
            },
        )
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            INCOMING_METHOD_CHANNEL,
        ).setMethodCallHandler { call, result ->
            if (call.method != "copyIncomingUri") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val arguments = call.arguments as? Map<*, *>
            val uriText = arguments?.get("uri") as? String
            val name = arguments?.get("name") as? String ?: ""
            val mimeType = arguments?.get("mimeType") as? String ?: ""
            if (uriText.isNullOrBlank()) {
                result.success(
                    mapOf("success" to false, "error" to "The document URI is missing."),
                )
                return@setMethodCallHandler
            }
            Thread {
                val response = try {
                    copyIncomingUri(Uri.parse(uriText), name, mimeType)
                } catch (error: Exception) {
                    mapOf(
                        "success" to false,
                        "error" to (error.message
                            ?: "Scanno could not read this shared document."),
                    )
                }
                mainHandler.post { result.success(response) }
            }.start()
        }
        enqueueIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        enqueueIntent(intent)
    }

    private fun enqueueIntent(intent: Intent) {
        if (intent.action != Intent.ACTION_VIEW &&
            intent.action != Intent.ACTION_SEND &&
            intent.action != Intent.ACTION_SEND_MULTIPLE
        ) {
            return
        }
        val sink = incomingSink
        if (sink == null) {
            pendingIntents.add(intent)
        } else {
            dispatchIntent(intent)
        }
    }

    private fun dispatchIntent(intent: Intent) {
        if (intent.action == Intent.ACTION_SEND_MULTIPLE) {
            incomingSink?.success(
                mapOf("error" to "Scanno can open one shared document at a time."),
            )
            return
        }
        val clip = intent.clipData
        if (clip != null && clip.itemCount > 1) {
            incomingSink?.success(
                mapOf("error" to "Scanno can open one shared document at a time."),
            )
            return
        }
        val uri = if (intent.action == Intent.ACTION_VIEW) {
            intent.data
        } else {
            sharedUri(intent) ?: clip?.getItemAt(0)?.uri
        }
        if (uri == null) {
            incomingSink?.success(
                mapOf(
                    "error" to
                        "The sending app did not provide a readable document.",
                ),
            )
            return
        }
        val reportedMimeType = contentMimeType(uri) ?: intent.type ?: ""
        val displayName = queryDisplayName(uri)
            ?: uri.lastPathSegment?.substringAfterLast('/')
            ?: defaultFileName(reportedMimeType)
        incomingSink?.success(
            mapOf(
                "uri" to uri.toString(),
                "name" to (
                    safeFileName(displayName)
                        .takeIf { it.isNotEmpty() && it != "." && it != ".." }
                        ?: defaultFileName(reportedMimeType)
                    ),
                "mimeType" to reportedMimeType,
            ),
        )
    }

    @Suppress("DEPRECATION")
    private fun sharedUri(intent: Intent): Uri? =
        if (Build.VERSION.SDK_INT >= 33) {
            intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
        } else {
            intent.getParcelableExtra(Intent.EXTRA_STREAM) as? Uri
        }

    private fun queryDisplayName(uri: Uri): String? {
        if (uri.scheme != "content") return null
        var cursor: Cursor? = null
        return try {
            cursor = contentResolver.query(
                uri,
                arrayOf(OpenableColumns.DISPLAY_NAME),
                null,
                null,
                null,
            )
            if (cursor?.moveToFirst() == true) {
                cursor.getString(
                    cursor.getColumnIndexOrThrow(OpenableColumns.DISPLAY_NAME),
                )
            } else {
                null
            }
        } catch (_: SecurityException) {
            null
        } catch (_: IllegalArgumentException) {
            null
        } finally {
            cursor?.close()
        }
    }

    private fun copyIncomingUri(
        uri: Uri,
        requestedName: String,
        requestedMimeType: String,
    ): Map<String, Any> {
        val name = safeFileName(
            queryDisplayName(uri)
                ?: requestedName
                ?: defaultFileName(requestedMimeType),
        ).takeIf { it.isNotEmpty() && it != "." && it != ".." }
            ?: defaultFileName(requestedMimeType)
        val extension = name.substringAfterLast('.', "").lowercase()
            .takeIf { it.matches(Regex("[a-z0-9]{1,12}")) }
            ?: extensionForMime(contentMimeType(uri) ?: requestedMimeType)
        val cacheDirectory = File(cacheDir, "incoming").apply { mkdirs() }
        val destination = File(
            cacheDirectory,
            "${UUID.randomUUID()}${if (extension.isEmpty()) "" else ".$extension"}",
        )
        val input = when (uri.scheme) {
            "content" -> contentResolver.openInputStream(uri)
            "file" -> uri.path?.let(::File)?.inputStream()
            else -> null
        } ?: throw IllegalArgumentException(
            "The sending app's document is no longer accessible.",
        )
        try {
            input.use { source ->
                FileOutputStream(destination).use { target ->
                    source.copyTo(target, bufferSize = 64 * 1024)
                    target.fd.sync()
                }
            }
            if (destination.length() == 0L) {
                throw IllegalArgumentException("The selected document is empty.")
            }
            return mapOf(
                "success" to true,
                "path" to destination.absolutePath,
                "name" to name,
                "mimeType" to (contentMimeType(uri) ?: requestedMimeType),
                "sizeBytes" to destination.length(),
            )
        } catch (error: Exception) {
            destination.delete()
            throw error
        }
    }

    private fun safeFileName(value: String): String =
        value.replace('\\', '/').substringAfterLast('/').trim()

    private fun contentMimeType(uri: Uri): String? =
        try {
            contentResolver.getType(uri)
        } catch (_: SecurityException) {
            null
        }

    private fun defaultFileName(mimeType: String): String {
        val extension = extensionForMime(mimeType)
        return if (extension.isEmpty()) "shared-document" else "shared-document.$extension"
    }

    private fun extensionForMime(mimeType: String): String =
        when (mimeType.substringBefore(';').lowercase()) {
            "application/pdf", "application/x-pdf" -> "pdf"
            "application/msword" -> "doc"
            "application/vnd.openxmlformats-officedocument.wordprocessingml.document" ->
                "docx"
            "application/vnd.ms-excel", "application/msexcel" -> "xls"
            "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" ->
                "xlsx"
            "application/vnd.ms-powerpoint" -> "ppt"
            "application/vnd.openxmlformats-officedocument.presentationml.presentation" ->
                "pptx"
            "text/plain" -> "txt"
            "text/csv", "application/csv", "text/x-csv" -> "csv"
            "text/markdown", "text/x-markdown" -> "md"
            "application/rtf", "text/rtf" -> "rtf"
            "image/jpeg", "image/jpg" -> "jpg"
            "image/png" -> "png"
            "image/webp" -> "webp"
            "image/bmp" -> "bmp"
            "image/gif" -> "gif"
            "image/tiff" -> "tif"
            else -> ""
        }

    private companion object {
        const val INCOMING_EVENT_CHANNEL = "scanno/incoming_documents"
        const val INCOMING_METHOD_CHANNEL = "scanno/incoming_documents/methods"
    }
}

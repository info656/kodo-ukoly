package com.yoshi.todark

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.provider.DocumentsContract
import androidx.annotation.NonNull
import androidx.documentfile.provider.DocumentFile
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.FileOutputStream
import java.io.OutputStream

class MainActivity: FlutterActivity() {
    private var shareChannel: MethodChannel? = null
    private var pendingShare: Map<String,String>? = null
    private var receiverReady = false
    private fun receiveShare(intent: Intent?) {
        if (intent?.action != Intent.ACTION_SEND || intent.type != "text/plain") return
        val text=intent.getStringExtra(Intent.EXTRA_TEXT) ?: return
        if (text.isBlank() || text.length > 15000) return
        val payload=mapOf("text" to text,"title" to (intent.getStringExtra(Intent.EXTRA_SUBJECT) ?: "").take(200))
        if(receiverReady) shareChannel?.invokeMethod("share",payload) else pendingShare=payload
        intent.action = null
    }
    override fun onNewIntent(intent: Intent) { super.onNewIntent(intent); setIntent(intent); receiveShare(intent) }
    private val CHANNEL = "directory_picker"
    private val REQUEST_CODE = 1001
    private var result: MethodChannel.Result? = null
    private var pickedDirectoryUri: Uri? = null

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        shareChannel=MethodChannel(flutterEngine.dartExecutor.binaryMessenger,"cz.kodo.ukoly/share")
        shareChannel?.setMethodCallHandler { call,result ->
            if(call.method=="takePending") { receiverReady=true;result.success(pendingShare);pendingShare=null }
            else if(call.method=="pauseReceiver"){receiverReady=false;result.success(null)}
            else result.notImplemented()
        }
        receiveShare(intent)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "pickDirectory" -> {
                    this.result = result
                    val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE)
                    intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or
                            Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                            Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
                    startActivityForResult(intent, REQUEST_CODE)
                }
                "writeFile" -> {
                    val uriString = call.argument<String>("directoryUri")
                    val fileName = call.argument<String>("fileName")
                    val fileContent = call.argument<ByteArray>("fileContent")

                    if (uriString != null && fileName != null && fileContent != null) {
                        val uri = Uri.parse(uriString)
                        val success = writeFileToDirectory(uri, fileName, fileContent)
                        result.success(success)
                    } else {
                        result.error("INVALID_ARGUMENTS", "Missing required arguments", null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQUEST_CODE && resultCode == Activity.RESULT_OK) {
            val uri: Uri? = data?.data
            if (uri != null) {
                contentResolver.takePersistableUriPermission(uri,
                    Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
                pickedDirectoryUri = uri
                result?.success(uri.toString()) // Return URI to Flutter
            } else {
                result?.success(null)
            }
        }
    }

    private fun writeFileToDirectory(directoryUri: Uri, fileName: String, fileContent: ByteArray): Boolean {
        val tree = DocumentFile.fromTreeUri(this, directoryUri)
        if (tree == null || !tree.isDirectory) return false

        val newFile = tree.createFile("application/octet-stream", fileName)
        if (newFile == null) return false

        try {
            contentResolver.openOutputStream(newFile.uri)?.use { outputStream ->
                outputStream.write(fileContent)
            }
            return true
        } catch (e: Exception) {
            e.printStackTrace()
            return false
        }
    }
}

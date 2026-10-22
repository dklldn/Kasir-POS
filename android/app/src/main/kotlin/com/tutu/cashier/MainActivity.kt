package com.tutu.cashier

import android.content.Context
import android.os.Bundle
import android.os.Build
import android.Manifest
import android.content.pm.PackageManager
import android.os.CancellationSignal
import android.os.ParcelFileDescriptor
import android.print.PageRange
import android.print.PrintAttributes
import android.print.PrintDocumentAdapter
import android.print.PrintDocumentInfo
import android.print.PrintManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.FileInputStream
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {
    private val channelName = "cashier/printer"
    private val bluetoothPermissionRequestCode = 7101
    private var pendingBluetoothPermissionResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "requestBluetoothPermissions" -> {
                        requestBluetoothPermissions(result)
                        return@setMethodCallHandler
                    }
                    "printPdf" -> Unit
                    else -> {
                        result.notImplemented()
                        return@setMethodCallHandler
                    }
                }
                val bytes = call.arguments as? ByteArray
                if (bytes == null || bytes.isEmpty()) {
                    result.error("EMPTY_PDF", "Data struk kosong", null)
                    return@setMethodCallHandler
                }
                val printManager = getSystemService(Context.PRINT_SERVICE) as PrintManager
                printManager.print(
                    "Cashier Mobile - Struk",
                    PdfPrintAdapter(bytes),
                    PrintAttributes.Builder()
                        .setMediaSize(PrintAttributes.MediaSize.ISO_A5)
                        .setMinMargins(PrintAttributes.Margins.NO_MARGINS)
                        .build()
                )
                result.success(true)
            }
    }


    private fun requestBluetoothPermissions(result: MethodChannel.Result) {
        if (pendingBluetoothPermissionResult != null) {
            result.error("PERMISSION_BUSY", "Permintaan izin Bluetooth sedang diproses.", null)
            return
        }

        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
        result.success(true)
        return
    }

    val required = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            arrayOf(
                Manifest.permission.BLUETOOTH_SCAN,
                Manifest.permission.BLUETOOTH_CONNECT
            )
        } else {
            arrayOf(
                Manifest.permission.BLUETOOTH,
                Manifest.permission.BLUETOOTH_ADMIN,
                Manifest.permission.ACCESS_FINE_LOCATION
            )
        }

        val missing = required.filter {
            checkSelfPermission(it) != PackageManager.PERMISSION_GRANTED
        }

        if (missing.isEmpty()) {
            result.success(true)
            return
        }

        pendingBluetoothPermissionResult = result
        requestPermissions(missing.toTypedArray(), bluetoothPermissionRequestCode)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)

        if (requestCode != bluetoothPermissionRequestCode) return

        val pending = pendingBluetoothPermissionResult
        pendingBluetoothPermissionResult = null

        val granted = grantResults.isNotEmpty() &&
            grantResults.all { it == PackageManager.PERMISSION_GRANTED }

        if (granted) {
            pending?.success(true)
        } else {
            pending?.success(false)
        }
    }

    private class PdfPrintAdapter(private val bytes: ByteArray) : PrintDocumentAdapter() {
        override fun onLayout(
            oldAttributes: PrintAttributes?,
            newAttributes: PrintAttributes,
            cancellationSignal: CancellationSignal,
            callback: LayoutResultCallback,
            extras: Bundle?
        ) {
            if (cancellationSignal.isCanceled) {
                callback.onLayoutCancelled()
                return
            }
            val info = PrintDocumentInfo.Builder("cashier-receipt.pdf")
                .setContentType(PrintDocumentInfo.CONTENT_TYPE_DOCUMENT)
                .setPageCount(1)
                .build()
            callback.onLayoutFinished(info, true)
        }

        override fun onWrite(
            pages: Array<out PageRange>,
            destination: ParcelFileDescriptor,
            cancellationSignal: CancellationSignal,
            callback: WriteResultCallback
        ) {
            if (cancellationSignal.isCanceled) {
                callback.onWriteCancelled()
                return
            }
            try {
                FileOutputStream(destination.fileDescriptor).use { output ->
                    output.write(bytes)
                    output.flush()
                }
                callback.onWriteFinished(arrayOf(PageRange.ALL_PAGES))
            } catch (e: Exception) {
                callback.onWriteFailed(e.message)
            } finally {
                destination.close()
            }
        }
    }
}

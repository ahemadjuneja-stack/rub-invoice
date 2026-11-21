package com.rubyinvoice.ruby_invoice

import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.pdf.PdfRenderer
import android.os.ParcelFileDescriptor
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {
    /// Renders PDF pages to plain JPEG images so bills can be shared the
    /// way shops actually need: the party sees the bill directly inside
    /// WhatsApp - no PDF viewer, no extra tap (v0.3.1).
    private val channelName = "ruby_invoice/pdf"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "renderPdfToImages" -> {
                        val path = call.argument<String>("path") ?: ""
                        Thread {
                            try {
                                val files = renderPdfToImages(path)
                                runOnUiThread { result.success(files) }
                            } catch (e: Exception) {
                                runOnUiThread {
                                    result.error("render_failed", e.message, null)
                                }
                            }
                        }.start()
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /// Opens the PDF with Android's built-in PdfRenderer (available since
    /// API 21, no external dependency) and writes one JPEG per page into
    /// cache/pdf_images/. Returns the absolute file paths.
    private fun renderPdfToImages(path: String): List<String> {
        val file = File(path)
        if (!file.exists()) throw IllegalArgumentException("PDF file not found")
        val outDir = File(cacheDir, "pdf_images")
        if (!outDir.exists()) outDir.mkdirs()
        val out = mutableListOf<String>()
        val fd = ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY)
        val renderer = PdfRenderer(fd)
        try {
            for (i in 0 until renderer.pageCount) {
                val page = renderer.openPage(i)
                try {
                    // ~2.4x scale: A4 (595x842 pt) -> ~1430x2020 px, sharp
                    // enough to read every item line, small enough for
                    // WhatsApp (JPEG 88 keeps a page around 250-400 KB).
                    val scale = 2.4f
                    val w = (page.width * scale).toInt()
                    val h = (page.height * scale).toInt()
                    val bmp = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
                    bmp.eraseColor(Color.WHITE)
                    page.render(bmp, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
                    val f = File(outDir, "${file.nameWithoutExtension}_p${i + 1}.jpg")
                    val fos = FileOutputStream(f)
                    try {
                        bmp.compress(Bitmap.CompressFormat.JPEG, 88, fos)
                    } finally {
                        fos.close()
                    }
                    bmp.recycle()
                    out.add(f.absolutePath)
                } finally {
                    page.close()
                }
            }
        } finally {
            renderer.close()
            fd.close()
        }
        return out
    }
}

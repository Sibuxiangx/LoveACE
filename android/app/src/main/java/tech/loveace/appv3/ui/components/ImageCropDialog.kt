package tech.loveace.appv3.ui.components

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.net.Uri
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.gestures.detectTransformGestures
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Crop
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.*
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File
import java.io.FileOutputStream
import kotlin.math.max
import kotlin.math.min
/**
 * 裁切形状：Circle 为圆形，Custom 为自定义宽高比矩形
 */
sealed class CropShape {
    data object Circle : CropShape()
    /** @param aspectRatio 宽/高比，如 16f/9f、9f/16f、1f 等 */
    data class Custom(val aspectRatio: Float) : CropShape()

    companion object {
        val Square = Custom(1f)
        val Landscape = Custom(16f / 9f)
        val Portrait = Custom(9f / 16f)
    }
}

/**
 * M3E 图片裁切对话框
 * 裁切框固定居中，图片在框下拖动/缩放，不能拖出裁切框。
 *
 * @param imageUri 待裁切图片
 * @param cropShape 裁切形状（Circle 或 Custom(宽高比)）
 * @param onCropped 裁切完成回调
 * @param onDismiss 取消回调
 */

@Composable
fun ImageCropDialog(
    imageUri: Uri,
    cropShape: CropShape = CropShape.Circle,
    onCropped: (Uri) -> Unit,
    onDismiss: () -> Unit,
) {
    val context = LocalContext.current
    var bitmap by remember { mutableStateOf<ImageBitmap?>(null) }
    var isSaving by remember { mutableStateOf(false) }
    var scale by remember { mutableFloatStateOf(1f) }
    var offset by remember { mutableStateOf(Offset.Zero) }
    var containerSize by remember { mutableStateOf(IntSize.Zero) }

    LaunchedEffect(imageUri) {
        bitmap = withContext(Dispatchers.IO) {
            loadAndDecodeBitmap(context, imageUri)?.asImageBitmap()
        }
    }

    Dialog(
        onDismissRequest = onDismiss,
        properties = DialogProperties(usePlatformDefaultWidth = false),
    ) {
        Surface(
            modifier = Modifier.fillMaxSize(),
            color = MaterialTheme.colorScheme.scrim.copy(alpha = 0.95f),
        ) {
            Column(Modifier.fillMaxSize()) {
                // 顶栏
                Row(
                    modifier = Modifier.fillMaxWidth().statusBarsPadding()
                        .padding(horizontal = 8.dp, vertical = 4.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    IconButton(onClick = onDismiss) {
                        Icon(Icons.Default.Close, "取消", tint = Color.White)
                    }
                    Spacer(Modifier.weight(1f))
                    Icon(Icons.Default.Crop, null, tint = Color.White.copy(alpha = 0.7f), modifier = Modifier.size(20.dp))
                    Spacer(Modifier.width(6.dp))
                    Text(
                        if (cropShape is CropShape.Circle) "裁切头像" else "裁切图片",
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.Medium,
                        color = Color.White,
                    )
                    Spacer(Modifier.weight(1f))
                    FilledTonalButton(
                        onClick = { if (bitmap != null) isSaving = true },
                        enabled = bitmap != null && !isSaving,
                        shape = RoundedCornerShape(50),
                    ) {
                        if (isSaving) {
                            AppCircularProgressIndicator(modifier = Modifier.size(18.dp))
                        } else {
                            Icon(Icons.Default.Check, null, modifier = Modifier.size(18.dp))
                            Spacer(Modifier.width(6.dp))
                            Text("完成")
                        }
                    }
                }

                Text(
                    "双指缩放和拖动调整",
                    style = MaterialTheme.typography.bodySmall,
                    color = Color.White.copy(alpha = 0.5f),
                    modifier = Modifier.align(Alignment.CenterHorizontally).padding(bottom = 8.dp),
                )

                // 裁切画布
                Box(
                    modifier = Modifier
                        .weight(1f).fillMaxWidth().clipToBounds()
                        .onSizeChanged { containerSize = it }
                        .pointerInput(Unit) {
                            detectTransformGestures { _, pan, zoom, _ ->
                                scale = (scale * zoom).coerceIn(1f, 5f)
                                offset = Offset(offset.x + pan.x, offset.y + pan.y)
                            }
                        },
                    contentAlignment = Alignment.Center,
                ) {
                    val img = bitmap
                    if (img != null) {
                        Canvas(modifier = Modifier.fillMaxSize()) {
                            val cw = size.width
                            val ch = size.height
                            val cropRect = calcCropRect(cw, ch, cropShape)

                            // 图片 fill 裁切框的基础缩放
                            val imgW = img.width.toFloat()
                            val imgH = img.height.toFloat()
                            val baseScale = max(cropRect.width / imgW, cropRect.height / imgH)
                            val totalScale = baseScale * scale
                            val drawW = imgW * totalScale
                            val drawH = imgH * totalScale

                            // 图片中心 = 裁切框中心 + offset，约束边界
                            var drawX = cropRect.center.x + offset.x - drawW / 2f
                            var drawY = cropRect.center.y + offset.y - drawH / 2f
                            val minX = min(cropRect.right - drawW, cropRect.left)
                            val maxX = max(cropRect.right - drawW, cropRect.left)
                            val minY = min(cropRect.bottom - drawH, cropRect.top)
                            val maxY = max(cropRect.bottom - drawH, cropRect.top)
                            drawX = drawX.coerceIn(minX, maxX)
                            drawY = drawY.coerceIn(minY, maxY)

                            // 回写约束后的 offset
                            offset = Offset(
                                drawX + drawW / 2f - cropRect.center.x,
                                drawY + drawH / 2f - cropRect.center.y,
                            )

                            drawImage(
                                image = img,
                                dstOffset = IntOffset(drawX.toInt(), drawY.toInt()),
                                dstSize = IntSize(drawW.toInt(), drawH.toInt()),
                            )
                            drawCropOverlay(cw, ch, cropRect, cropShape)
                        }
                    } else {
                        AppCircularProgressIndicator(color = Color.White)
                    }
                }

                Spacer(Modifier.navigationBarsPadding().height(16.dp))
            }
        }
    }

    if (isSaving && bitmap != null) {
        val img = bitmap!!
        val cs = containerSize
        val s = scale
        val o = offset
        val shape = cropShape
        LaunchedEffect(Unit) {
            val resultUri = withContext(Dispatchers.IO) {
                performCrop(context, img, cs, s, o, shape)
            }
            isSaving = false
            if (resultUri != null) onCropped(resultUri)
        }
    }
}

// ── 裁切框计算：居中，最大化填充画布但保留 padding ──

private fun calcCropRect(canvasW: Float, canvasH: Float, shape: CropShape): Rect {
    val padding = 32f
    val availW = canvasW - padding * 2
    val availH = canvasH - padding * 2

    return when (shape) {
        is CropShape.Circle -> {
            val side = min(availW, availH)
            val left = (canvasW - side) / 2f
            val top = (canvasH - side) / 2f
            Rect(left, top, left + side, top + side)
        }
        is CropShape.Custom -> {
            val ratio = shape.aspectRatio // w/h
            // 在可用区域内按比例最大化
            val w: Float
            val h: Float
            if (availW / availH > ratio) {
                // 高度受限
                h = availH
                w = h * ratio
            } else {
                // 宽度受限
                w = availW
                h = w / ratio
            }
            val left = (canvasW - w) / 2f
            val top = (canvasH - h) / 2f
            Rect(left, top, left + w, top + h)
        }
    }
}

// ── 遮罩 ──

private fun DrawScope.drawCropOverlay(canvasW: Float, canvasH: Float, cropRect: Rect, shape: CropShape) {
    val overlayPath = Path().apply {
        addRect(Rect(0f, 0f, canvasW, canvasH))
        when (shape) {
            is CropShape.Circle -> addOval(cropRect)
            is CropShape.Custom -> addRect(cropRect)
        }
        fillType = PathFillType.EvenOdd
    }
    drawPath(overlayPath, Color.Black.copy(alpha = 0.6f))

    when (shape) {
        is CropShape.Circle -> {
            drawOval(
                color = Color.White,
                topLeft = Offset(cropRect.left, cropRect.top),
                size = Size(cropRect.width, cropRect.height),
                style = Stroke(width = 2f),
            )
        }
        is CropShape.Custom -> {
            drawRect(
                color = Color.White,
                topLeft = Offset(cropRect.left, cropRect.top),
                size = Size(cropRect.width, cropRect.height),
                style = Stroke(width = 2f),
            )
            val cornerLen = 24f
            val cornerW = 4f
            val corners = listOf(
                cropRect.topLeft, Offset(cropRect.right, cropRect.top),
                cropRect.bottomLeft, Offset(cropRect.right, cropRect.bottom),
            )
            for (c in corners) {
                val isRight = c.x > canvasW / 2
                val isBottom = c.y > canvasH / 2
                val dx = if (isRight) -cornerLen else cornerLen
                val dy = if (isBottom) -cornerLen else cornerLen
                drawLine(Color.White, c, Offset(c.x + dx, c.y), strokeWidth = cornerW)
                drawLine(Color.White, c, Offset(c.x, c.y + dy), strokeWidth = cornerW)
            }
        }
    }
}

// ── 图片加载 ──

private fun loadAndDecodeBitmap(context: Context, uri: Uri): Bitmap? {
    return try {
        val input = context.contentResolver.openInputStream(uri) ?: return null
        val opts = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeStream(input, null, opts)
        input.close()
        val maxDim = 2048
        var sampleSize = 1
        while (opts.outWidth / sampleSize > maxDim || opts.outHeight / sampleSize > maxDim) sampleSize *= 2
        val input2 = context.contentResolver.openInputStream(uri) ?: return null
        val bmp = BitmapFactory.decodeStream(input2, null, BitmapFactory.Options().apply { inSampleSize = sampleSize })
        input2.close()
        if (bmp == null) return null
        handleExifRotation(context, uri, bmp)
    } catch (_: Exception) {
        null
    }
}

private fun handleExifRotation(context: Context, uri: Uri, bitmap: Bitmap): Bitmap {
    return try {
        val input = context.contentResolver.openInputStream(uri) ?: return bitmap
        val exif = androidx.exifinterface.media.ExifInterface(input)
        val orientation = exif.getAttributeInt(
            androidx.exifinterface.media.ExifInterface.TAG_ORIENTATION,
            androidx.exifinterface.media.ExifInterface.ORIENTATION_NORMAL,
        )
        input.close()
        val rotation = when (orientation) {
            androidx.exifinterface.media.ExifInterface.ORIENTATION_ROTATE_90 -> 90f
            androidx.exifinterface.media.ExifInterface.ORIENTATION_ROTATE_180 -> 180f
            androidx.exifinterface.media.ExifInterface.ORIENTATION_ROTATE_270 -> 270f
            else -> 0f
        }
        if (rotation == 0f) return bitmap
        val matrix = Matrix().apply { postRotate(rotation) }
        Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, matrix, true)
    } catch (_: Exception) { bitmap }
}

// ── 裁切执行 ──

private fun performCrop(
    context: Context,
    imageBitmap: ImageBitmap,
    containerSize: IntSize,
    scale: Float,
    offset: Offset,
    shape: CropShape,
): Uri? {
    val bitmap: Bitmap
    try {
        bitmap = imageBitmap.asAndroidBitmap()
    } catch (_: Exception) {
        return null
    }

    val cw = containerSize.width.toFloat()
    val ch = containerSize.height.toFloat()
    if (cw <= 0 || ch <= 0) return null

    val cropRect = calcCropRect(cw, ch, shape)
    val imgW = bitmap.width.toFloat()
    val imgH = bitmap.height.toFloat()
    val baseScale = max(cropRect.width / imgW, cropRect.height / imgH)
    val totalScale = baseScale * scale
    val drawW = imgW * totalScale
    val drawH = imgH * totalScale

    var drawX = cropRect.center.x + offset.x - drawW / 2f
    var drawY = cropRect.center.y + offset.y - drawH / 2f
    drawX = drawX.coerceIn(min(cropRect.right - drawW, cropRect.left), max(cropRect.right - drawW, cropRect.left))
    drawY = drawY.coerceIn(min(cropRect.bottom - drawH, cropRect.top), max(cropRect.bottom - drawH, cropRect.top))

    val srcLeft = ((cropRect.left - drawX) / totalScale).coerceIn(0f, imgW)
    val srcTop = ((cropRect.top - drawY) / totalScale).coerceIn(0f, imgH)
    val srcRight = ((cropRect.right - drawX) / totalScale).coerceIn(0f, imgW)
    val srcBottom = ((cropRect.bottom - drawY) / totalScale).coerceIn(0f, imgH)

    val srcX = srcLeft.toInt().coerceIn(0, bitmap.width - 1)
    val srcY = srcTop.toInt().coerceIn(0, bitmap.height - 1)
    val srcW = (srcRight - srcLeft).toInt().coerceIn(1, bitmap.width - srcX)
    val srcH = (srcBottom - srcTop).toInt().coerceIn(1, bitmap.height - srcY)

    return try {
        val cropped = Bitmap.createBitmap(bitmap, srcX, srcY, srcW, srcH)
        val result = if (shape is CropShape.Circle) {
            val side = min(cropped.width, cropped.height)
            val output = Bitmap.createBitmap(side, side, Bitmap.Config.ARGB_8888)
            val canvas = android.graphics.Canvas(output)
            val paint = android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG)
            canvas.drawCircle(side / 2f, side / 2f, side / 2f, paint)
            paint.xfermode = android.graphics.PorterDuffXfermode(android.graphics.PorterDuff.Mode.SRC_IN)
            canvas.drawBitmap(cropped, 0f, 0f, paint)
            output
        } else cropped

        val dir = File(context.filesDir, "cropped_images")
        if (!dir.exists()) dir.mkdirs()
        val file = File(dir, "crop_${System.currentTimeMillis()}.png")
        FileOutputStream(file).use { result.compress(Bitmap.CompressFormat.PNG, 95, it) }
        Uri.fromFile(file)
    } catch (_: Exception) {
        null
    }
}

package chat.schildi.revenge.compose.destination.conversation.event.reaction

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Favorite
import androidx.compose.material.icons.rounded.ThumbDown
import androidx.compose.material.icons.rounded.ThumbUp
import androidx.compose.material3.Icon
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.unit.Dp

private val KiteReactionHeart = Color(0xFFE84D69)
private val KiteReactionYellow = Color(0xFFFFC83D)
private val KiteReactionDetail = Color(0xFF6D4818)
private val KiteReactionTear = Color(0xFF69C8F2)
private val KiteReactionTongue = Color(0xFFE56C6C)
private val KiteReactionBlush = Color(0xFFE89B75)

enum class KiteReactionFace {
    LAUGH,
    SURPRISE,
    SAD,
}

fun kiteReactionFace(reaction: String): KiteReactionFace? = when (reaction) {
    "😂", "🤣" -> KiteReactionFace.LAUGH
    "😮", "😲" -> KiteReactionFace.SURPRISE
    "😢", "😭" -> KiteReactionFace.SAD
    else -> null
}

fun isKiteDesignedReaction(reaction: String): Boolean =
    reaction == "❤️" ||
            reaction == "❤" ||
            reaction.startsWith("👍") ||
            reaction.startsWith("👎") ||
            kiteReactionFace(reaction) != null

/**
 * Native equivalent of Kite's compact reaction glyphs.
 *
 * This is intentionally stateless and allocation-light: the reaction key fully determines the
 * painter path, and callers continue to own all Matrix reaction state/toggling.
 */
@Composable
fun KiteReactionGlyph(
    reaction: String,
    size: Dp,
    modifier: Modifier = Modifier,
) {
    when {
        reaction == "❤️" || reaction == "❤" -> {
            Icon(
                imageVector = Icons.Rounded.Favorite,
                contentDescription = null,
                tint = KiteReactionHeart,
                modifier = modifier.size(size),
            )
        }

        reaction.startsWith("👍") -> {
            Icon(
                imageVector = Icons.Rounded.ThumbUp,
                contentDescription = null,
                tint = KiteReactionYellow,
                modifier = modifier.size(size),
            )
        }

        reaction.startsWith("👎") -> {
            Icon(
                imageVector = Icons.Rounded.ThumbDown,
                contentDescription = null,
                tint = KiteReactionYellow,
                modifier = modifier.size(size),
            )
        }

        else -> {
            val face = kiteReactionFace(reaction) ?: return
            val highlight = Color.White.copy(alpha = 0.37f)
            Canvas(modifier.size(size)) {
                val unit = minOf(this.size.width, this.size.height)
                val center = Offset(this.size.width / 2f, this.size.height / 2f)
                val strokeWidth = unit * 0.065f
                val faceStroke = Stroke(width = strokeWidth, cap = StrokeCap.Round)

                drawCircle(
                    color = KiteReactionYellow,
                    radius = unit * 0.47f,
                    center = center,
                )
                drawCircle(
                    color = highlight,
                    radius = unit * 0.11f,
                    center = Offset(center.x - unit * 0.15f, center.y - unit * 0.17f),
                )

                when (face) {
                    KiteReactionFace.LAUGH -> {
                        val leftEye = Path().apply {
                            moveTo(unit * 0.23f, unit * 0.40f)
                            quadraticTo(unit * 0.31f, unit * 0.31f, unit * 0.39f, unit * 0.40f)
                        }
                        val rightEye = Path().apply {
                            moveTo(unit * 0.61f, unit * 0.40f)
                            quadraticTo(unit * 0.69f, unit * 0.31f, unit * 0.77f, unit * 0.40f)
                        }
                        drawPath(leftEye, KiteReactionDetail, style = faceStroke)
                        drawPath(rightEye, KiteReactionDetail, style = faceStroke)

                        drawRoundRect(
                            color = KiteReactionDetail,
                            topLeft = Offset(unit * 0.27f, unit * 0.52f),
                            size = Size(unit * 0.46f, unit * 0.26f),
                            cornerRadius = CornerRadius(unit * 0.15f),
                        )
                        drawRoundRect(
                            color = Color.White.copy(alpha = 0.93f),
                            topLeft = Offset(unit * 0.33f, unit * 0.54f),
                            size = Size(unit * 0.34f, unit * 0.07f),
                            cornerRadius = CornerRadius(unit * 0.035f),
                        )

                        val leftTear = Path().apply {
                            moveTo(unit * 0.15f, unit * 0.48f)
                            quadraticTo(unit * 0.06f, unit * 0.63f, unit * 0.18f, unit * 0.68f)
                            quadraticTo(unit * 0.29f, unit * 0.61f, unit * 0.15f, unit * 0.48f)
                            close()
                        }
                        val rightTear = Path().apply {
                            moveTo(unit * 0.85f, unit * 0.48f)
                            quadraticTo(unit * 0.94f, unit * 0.63f, unit * 0.82f, unit * 0.68f)
                            quadraticTo(unit * 0.71f, unit * 0.61f, unit * 0.85f, unit * 0.48f)
                            close()
                        }
                        drawPath(leftTear, KiteReactionTear)
                        drawPath(rightTear, KiteReactionTear)
                    }

                    KiteReactionFace.SURPRISE -> {
                        drawCircle(
                            color = KiteReactionDetail,
                            radius = unit * 0.072f,
                            center = Offset(unit * 0.34f, unit * 0.41f),
                        )
                        drawCircle(
                            color = KiteReactionDetail,
                            radius = unit * 0.072f,
                            center = Offset(unit * 0.66f, unit * 0.41f),
                        )
                        drawCircle(
                            color = KiteReactionDetail,
                            radius = unit * 0.115f,
                            center = Offset(unit * 0.5f, unit * 0.66f),
                        )
                        drawCircle(
                            color = KiteReactionTongue,
                            radius = unit * 0.052f,
                            center = Offset(unit * 0.5f, unit * 0.64f),
                        )
                    }

                    KiteReactionFace.SAD -> {
                        val browStroke = Stroke(width = unit * 0.055f, cap = StrokeCap.Round)
                        drawLine(
                            color = KiteReactionDetail,
                            start = Offset(unit * 0.25f, unit * 0.35f),
                            end = Offset(unit * 0.40f, unit * 0.29f),
                            strokeWidth = browStroke.width,
                            cap = StrokeCap.Round,
                        )
                        drawLine(
                            color = KiteReactionDetail,
                            start = Offset(unit * 0.60f, unit * 0.29f),
                            end = Offset(unit * 0.75f, unit * 0.35f),
                            strokeWidth = browStroke.width,
                            cap = StrokeCap.Round,
                        )
                        drawOval(
                            color = KiteReactionDetail,
                            topLeft = Offset(unit * 0.2975f, unit * 0.4075f),
                            size = Size(unit * 0.085f, unit * 0.105f),
                        )
                        drawOval(
                            color = KiteReactionDetail,
                            topLeft = Offset(unit * 0.6175f, unit * 0.4075f),
                            size = Size(unit * 0.085f, unit * 0.105f),
                        )
                        val mouth = Path().apply {
                            moveTo(unit * 0.34f, unit * 0.72f)
                            quadraticTo(unit * 0.50f, unit * 0.59f, unit * 0.66f, unit * 0.72f)
                        }
                        drawPath(mouth, KiteReactionDetail, style = faceStroke)

                        val tear = Path().apply {
                            moveTo(unit * 0.73f, unit * 0.51f)
                            quadraticTo(unit * 0.66f, unit * 0.63f, unit * 0.73f, unit * 0.70f)
                            quadraticTo(unit * 0.82f, unit * 0.64f, unit * 0.73f, unit * 0.51f)
                            close()
                        }
                        drawPath(tear, KiteReactionTear)
                        drawOval(
                            color = KiteReactionBlush.copy(alpha = 0.47f),
                            topLeft = Offset(unit * 0.44f, unit * 0.7625f),
                            size = Size(unit * 0.12f, unit * 0.035f),
                        )
                    }
                }
            }
        }
    }
}

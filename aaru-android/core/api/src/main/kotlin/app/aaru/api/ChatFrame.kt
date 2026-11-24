package app.aaru.api

import app.aaru.api.generated.models.ChatComponentsFrame
import app.aaru.api.generated.models.ChatDoneFrame
import app.aaru.api.generated.models.ChatErrorFrame
import app.aaru.api.generated.models.ChatTextFrame
import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer
import java.nio.charset.CharacterCodingException
import java.nio.charset.CodingErrorAction
import java.util.UUID
import kotlinx.serialization.SerializationException

/** One frame of the assistant's server-sent event stream (ASK-009). */
public sealed interface ChatFrame {
    public data class Status(val text: String) : ChatFrame

    public data class Delta(val text: String) : ChatFrame

    public data class Components(val frame: ChatComponentsFrame) : ChatFrame

    public data class Done(val turnId: UUID) : ChatFrame

    public data class Error(val code: ChatErrorFrame.Code, val message: String) : ChatFrame
}

/**
 * Turns the raw bytes of a chat turn's `text/event-stream` body into frames.
 *
 * Splits on `\n` at byte level and decodes UTF-8 only from a whole line, so a character split
 * across chunks stays intact. Heartbeat comments, unknown events, a line that is not UTF-8 and
 * malformed JSON are skipped without disturbing later frames. Not safe to share between threads.
 */
public class ChatFrameParser {
    private val line = ByteArrayOutputStream()
    private var event: String? = null
    private val data = mutableListOf<String>()

    public fun consume(bytes: ByteArray, length: Int = bytes.size): List<ChatFrame> {
        val frames = mutableListOf<ChatFrame>()
        for (index in 0 until length) {
            val byte = bytes[index]
            if (byte != NEWLINE) {
                line.write(byte.toInt())
                continue
            }
            val text = decode(line.toByteArray())
            line.reset()
            if (text != null) handle(text.removeSuffix("\r"))?.let(frames::add)
        }
        return frames
    }

    private fun handle(text: String): ChatFrame? = when {
        text.isEmpty() -> {
            dispatch()
        }

        text.startsWith(":") -> {
            null
        }

        else -> {
            field(text)
            null
        }
    }

    private fun dispatch(): ChatFrame? {
        val name = event
        val payload = data.joinToString("\n")
        val complete = name != null && data.isNotEmpty()
        event = null
        data.clear()
        return if (complete) frame(name.orEmpty(), payload) else null
    }

    private fun field(text: String) {
        val colon = text.indexOf(':')
        val name = if (colon < 0) text else text.substring(0, colon)
        val value = if (colon < 0) "" else text.substring(colon + 1).removePrefix(" ")
        when (name) {
            "event" -> event = value
            "data" -> data.add(value)
        }
    }

    private companion object {
        const val NEWLINE: Byte = 0x0A

        fun decode(bytes: ByteArray): String? = try {
            Charsets.UTF_8
                .newDecoder()
                .onMalformedInput(CodingErrorAction.REPORT)
                .onUnmappableCharacter(CodingErrorAction.REPORT)
                .decode(ByteBuffer.wrap(bytes))
                .toString()
        } catch (_: CharacterCodingException) {
            null
        }

        fun frame(event: String, data: String): ChatFrame? = try {
            when (event) {
                "status" -> {
                    ChatFrame.Status(AaruJson.decodeFromString<ChatTextFrame>(data).text)
                }

                "delta" -> {
                    ChatFrame.Delta(AaruJson.decodeFromString<ChatTextFrame>(data).text)
                }

                "components" -> {
                    ChatFrame.Components(AaruJson.decodeFromString<ChatComponentsFrame>(data))
                }

                "done" -> {
                    ChatFrame.Done(AaruJson.decodeFromString<ChatDoneFrame>(data).turnId)
                }

                "error" -> {
                    AaruJson.decodeFromString<ChatErrorFrame>(data).let {
                        ChatFrame.Error(it.code, it.message)
                    }
                }

                else -> {
                    null
                }
            }
        } catch (_: SerializationException) {
            null
        } catch (_: IllegalArgumentException) {
            null
        }
    }
}

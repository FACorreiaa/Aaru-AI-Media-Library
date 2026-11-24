package app.aaru.api

import app.aaru.api.generated.models.ChatErrorFrame
import java.util.UUID
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class ChatFrameParserTest {
    private fun ChatFrameParser.feed(text: String) = consume(text.toByteArray())

    @Test
    fun `reads status, delta, done and error frames`() {
        val turn = UUID.randomUUID()
        val frames =
            ChatFrameParser().feed(
                "event: status\ndata: {\"text\":\"Looking\"}\n\n" +
                    "event: delta\ndata: {\"text\":\"Hello\"}\n\n" +
                    "event: error\ndata: {\"code\":\"try_again\",\"message\":\"Busy\"}\n\n" +
                    "event: done\ndata: {\"turnId\":\"$turn\"}\n\n"
            )
        assertEquals(
            listOf(
                ChatFrame.Status("Looking"),
                ChatFrame.Delta("Hello"),
                ChatFrame.Error(ChatErrorFrame.Code.tryAgain, "Busy"),
                ChatFrame.Done(turn)
            ),
            frames
        )
    }

    @Test
    fun `keeps a character split across chunks whole`() {
        val bytes = "event: delta\ndata: {\"text\":\"café 🦉\"}\n\n".toByteArray()
        val parser = ChatFrameParser()
        val frames = bytes.flatMap { parser.consume(byteArrayOf(it)) }
        assertEquals(listOf<ChatFrame>(ChatFrame.Delta("café 🦉")), frames)
    }

    @Test
    fun `accepts CRLF line endings and a value without a space`() {
        val frames = ChatFrameParser().feed("event:delta\r\ndata:{\"text\":\"a\"}\r\n\r\n")
        assertEquals(listOf<ChatFrame>(ChatFrame.Delta("a")), frames)
    }

    @Test
    fun `skips heartbeats, unknown events and malformed JSON without losing later frames`() {
        val frames =
            ChatFrameParser().feed(
                ": ping\n\n" +
                    "event: mystery\ndata: {}\n\n" +
                    "event: delta\ndata: {not json\n\n" +
                    "event: delta\ndata: {\"text\":\"ok\"}\n\n"
            )
        assertEquals(listOf<ChatFrame>(ChatFrame.Delta("ok")), frames)
    }

    @Test
    fun `skips a line that is not UTF-8`() {
        val parser = ChatFrameParser()
        val bad = "event: delta\ndata: ".toByteArray() + byteArrayOf(0xC3.toByte(), 0x28) + "\n\n".toByteArray()
        assertTrue(parser.consume(bad).isEmpty())
        assertEquals(listOf<ChatFrame>(ChatFrame.Delta("ok")), parser.feed("event: delta\ndata: {\"text\":\"ok\"}\n\n"))
    }

    @Test
    fun `an event with no data is not a frame`() {
        assertTrue(ChatFrameParser().feed("event: delta\n\n").isEmpty())
    }

    @Test
    fun `reads a components frame`() {
        val frames = ChatFrameParser().feed("event: components\ndata: {\"actionSummary\":\"Added\"}\n\n")
        assertEquals("Added", (frames.single() as ChatFrame.Components).frame.actionSummary)
    }
}

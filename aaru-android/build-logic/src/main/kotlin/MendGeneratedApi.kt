import org.gradle.api.Transformer
import java.io.Serializable

/**
 * Mends three slips of the Kotlin OpenAPI generator, line by line and the same
 * way on every run: an import of a body type it never writes (the capture
 * upload's multipart form is sent by hand), HTML-escaped backticks around names
 * made from keywords, and the reaction emoji, which it cannot turn into names.
 */
class MendGeneratedApi : Transformer<String?, String>, Serializable {
    override fun transform(line: String): String {
        if (line.endsWith(".CreateCaptureImportRequest1")) return ""
        val emoji = reactionNames.entries.firstOrNull { line.contains("@SerialName(value = \"${it.key}\")") }
        if (emoji != null) {
            val end = line.trimEnd().takeLast(1)
            return "        @SerialName(value = \"${emoji.key}\") ${emoji.value}(\"${emoji.key}\")$end"
        }
        return line.replace(escapedName, "$1").replace("&#x60;", "`")
    }

    private companion object {
        private const val serialVersionUID = 1L
        val escapedName = Regex("&#x60;(\\w+)&#x60;(?=\\w)")
        val reactionNames = mapOf(
            "❤️" to "heart",
            "😂" to "laugh",
            "😮" to "wow",
            "😭" to "cry",
            "🔥" to "fire",
            "👏" to "clap",
        )
    }
}

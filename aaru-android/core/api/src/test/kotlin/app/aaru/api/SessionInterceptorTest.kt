package app.aaru.api

import java.time.ZoneId
import mockwebserver3.MockResponse
import mockwebserver3.MockWebServer
import okhttp3.OkHttpClient
import okhttp3.Request
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Before
import org.junit.Test

class SessionInterceptorTest {
    private val server = MockWebServer()
    private var token: String? = "first"
    private var rejections = 0
    private lateinit var http: OkHttpClient

    @Before
    fun start() {
        server.start()
        http =
            AaruClient.http(
                token = { token },
                onUnauthorized = { rejections++ },
                zone = { ZoneId.of("Europe/Lisbon") }
            )
    }

    @After
    fun stop() = server.close()

    private fun get(code: Int): Int {
        server.enqueue(MockResponse.Builder().code(code).build())
        return http.newCall(Request.Builder().url(server.url("/v1/me")).build()).execute().use { it.code }
    }

    @Test
    fun `sends the bearer token and the time zone`() {
        get(200)
        val request = server.takeRequest()
        assertEquals("Bearer first", request.headers["Authorization"])
        assertEquals("Europe/Lisbon", request.headers["X-Timezone"])
    }

    @Test
    fun `sends no authorization when signed out`() {
        token = null
        get(401)
        assertNull(server.takeRequest().headers["Authorization"])
        assertEquals(0, rejections)
    }

    @Test
    fun `reports a rejected token once, and a new token again`() {
        assertEquals(401, get(401))
        get(401)
        assertEquals(1, rejections)
        token = "second"
        get(401)
        assertEquals(2, rejections)
    }

    @Test
    fun `another status is not a rejection`() {
        get(403)
        get(500)
        assertEquals(0, rejections)
    }
}

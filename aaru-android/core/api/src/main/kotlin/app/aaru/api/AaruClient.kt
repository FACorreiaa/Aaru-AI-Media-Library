package app.aaru.api

import app.aaru.api.generated.DefaultApi
import java.time.ZoneId
import kotlinx.serialization.json.Json
import okhttp3.HttpUrl
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import retrofit2.Retrofit
import retrofit2.converter.kotlinx.serialization.asConverterFactory

/**
 * Builds the `/v1` client the way `Client.aaru(...)` does for the Apple apps: the session's
 * bearer token, then the time zone.
 *
 * There is no retry interceptor. The Apple client sends a read again once when a pooled
 * connection turned out to be dead; OkHttp already does that itself
 * (`retryOnConnectionFailure`), and only for requests that never reached the server.
 */
public object AaruClient {
    public fun http(
        token: () -> String?,
        onUnauthorized: () -> Unit,
        zone: () -> ZoneId = { ZoneId.systemDefault() },
        base: OkHttpClient = OkHttpClient()
    ): OkHttpClient = base
        .newBuilder()
        .addInterceptor(SessionInterceptor(token, onUnauthorized))
        .addInterceptor(TimeZoneInterceptor(zone))
        .build()

    public fun api(baseUrl: HttpUrl, http: OkHttpClient, json: Json = AaruJson): DefaultApi = Retrofit
        .Builder()
        .baseUrl(baseUrl)
        .client(http)
        .addConverterFactory(json.asConverterFactory("application/json".toMediaType()))
        .build()
        .create(DefaultApi::class.java)
}

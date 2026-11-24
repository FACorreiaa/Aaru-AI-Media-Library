package app.aaru.api

import java.time.ZoneId
import okhttp3.Interceptor
import okhttp3.Response

/**
 * Sends the device's time zone as `X-Timezone` on every request, so points and streak days are
 * dated on the user's local calendar (GAM-003). Read per request: travelling moves it.
 */
public class TimeZoneInterceptor(private val zone: () -> ZoneId = { ZoneId.systemDefault() }) : Interceptor {
    override fun intercept(chain: Interceptor.Chain): Response = chain.proceed(
        chain
            .request()
            .newBuilder()
            .header("X-Timezone", zone().id)
            .build()
    )
}

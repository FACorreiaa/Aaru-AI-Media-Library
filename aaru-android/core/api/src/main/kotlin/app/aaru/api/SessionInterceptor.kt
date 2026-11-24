package app.aaru.api

import java.net.HttpURLConnection
import java.util.concurrent.atomic.AtomicReference
import okhttp3.Interceptor
import okhttp3.Response

/**
 * Puts the session's bearer token on every request and reports a rejected token once.
 *
 * A 401 for a token calls [onUnauthorized] the first time only, however many requests were in
 * flight with that token, so the app routes to sign-in once instead of once per request.
 * Nothing is retried: a rejected session stays rejected until the user signs in again.
 */
public class SessionInterceptor(private val token: () -> String?, private val onUnauthorized: () -> Unit) :
    Interceptor {
    private val lastRejected = AtomicReference<String?>(null)

    override fun intercept(chain: Interceptor.Chain): Response {
        val current = token()
        val request =
            if (current == null) {
                chain.request()
            } else {
                chain
                    .request()
                    .newBuilder()
                    .header("Authorization", "Bearer $current")
                    .build()
            }
        val response = chain.proceed(request)
        if (response.code == HttpURLConnection.HTTP_UNAUTHORIZED && current != null) {
            if (lastRejected.getAndSet(current) != current) onUnauthorized()
        }
        return response
    }
}

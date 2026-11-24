package app.aaru.navigation

import androidx.annotation.DrawableRes
import androidx.annotation.StringRes
import app.aaru.R

/**
 * The top-level places, in the order the Apple app has them on a phone (`AppTab` in
 * `aaru-ios/Aaru/Navigation/AppRouter.swift`): Home, Discover, Library, Calendar, More.
 */
enum class AppTab(@param:StringRes val label: Int, @param:DrawableRes val icon: Int) {
    Home(R.string.tab_home, R.drawable.ic_tab_home),
    Discover(R.string.tab_discover, R.drawable.ic_tab_discover),
    Library(R.string.tab_library, R.drawable.ic_tab_library),
    Calendar(R.string.tab_calendar, R.drawable.ic_tab_calendar),
    More(R.string.tab_more, R.drawable.ic_tab_more)
}

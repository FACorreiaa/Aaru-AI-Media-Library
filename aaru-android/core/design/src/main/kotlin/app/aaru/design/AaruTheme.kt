package app.aaru.design

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.ColorScheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Shapes
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.ReadOnlyComposable
import androidx.compose.runtime.staticCompositionLocalOf

/**
 * Aaru's look on Material 3 (DESIGN.md "Brand"). The colours are the tokens and nothing else:
 * no dynamic colour, so the wallpaper never repaints the app. Type is the system sans, which is
 * Material's default, so no typography is set.
 */
@Composable
public fun AaruTheme(dark: Boolean = isSystemInDarkTheme(), content: @Composable () -> Unit) {
    val colors = if (dark) AaruDarkColors else AaruLightColors
    CompositionLocalProvider(LocalAaruColors provides colors) {
        MaterialTheme(
            colorScheme = colors.toMaterial(dark),
            shapes = AaruShapes,
            content = content
        )
    }
}

public object AaruTheme {
    /** The tokens themselves, for anything Material's roles do not name (gold, medallion, night). */
    public val colors: AaruColors
        @Composable
        @ReadOnlyComposable
        get() = LocalAaruColors.current
}

private val LocalAaruColors = staticCompositionLocalOf { AaruLightColors }

private val AaruShapes = Shapes(
    extraSmall = RoundedCornerShape(AaruRadius.thumb),
    small = RoundedCornerShape(AaruRadius.row),
    medium = RoundedCornerShape(AaruRadius.field),
    large = RoundedCornerShape(AaruRadius.panel),
    extraLarge = RoundedCornerShape(AaruRadius.card)
)

/** Every Material role is given a token, so no component falls back to Material's own palette. */
private fun AaruColors.toMaterial(dark: Boolean): ColorScheme {
    val scheme = if (dark) darkColorScheme() else lightColorScheme()
    return scheme.copy(
        primary = accent,
        onPrimary = onAccent,
        primaryContainer = medallion,
        onPrimaryContainer = ink,
        inversePrimary = accent,
        secondary = accent,
        onSecondary = onAccent,
        secondaryContainer = medallion,
        onSecondaryContainer = ink,
        tertiary = gold,
        onTertiary = paper,
        tertiaryContainer = surface,
        onTertiaryContainer = ink,
        background = paper,
        onBackground = ink,
        surface = paper,
        onSurface = ink,
        surfaceVariant = surface,
        onSurfaceVariant = muted,
        surfaceTint = paper,
        inverseSurface = ink,
        inverseOnSurface = paper,
        error = danger,
        onError = paper,
        errorContainer = surface,
        onErrorContainer = danger,
        outline = lineStrong,
        outlineVariant = line,
        scrim = scrim,
        surfaceBright = surface,
        surfaceDim = stone,
        surfaceContainerLowest = stone,
        surfaceContainerLow = paper,
        surfaceContainer = surface,
        surfaceContainerHigh = surface,
        surfaceContainerHighest = medallion
    )
}

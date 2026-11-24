package app.aaru.navigation

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.adaptive.navigationsuite.NavigationSuiteScaffold
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.tooling.preview.PreviewScreenSizes
import app.aaru.design.AaruTheme

/**
 * The signed-in frame: a bottom bar on a phone, a rail or drawer on a wider window, chosen by
 * the window's size as the Apple app's `.sidebarAdaptable` tabs are. Each tab's screens arrive
 * with its milestone; until then a tab shows its name.
 */
@Composable
fun AaruShell(modifier: Modifier = Modifier) {
    var selected by rememberSaveable { mutableStateOf(AppTab.Home) }
    NavigationSuiteScaffold(
        modifier = modifier,
        navigationSuiteItems = {
            AppTab.entries.forEach { tab ->
                item(
                    selected = tab == selected,
                    onClick = { selected = tab },
                    icon = { Icon(painterResource(tab.icon), contentDescription = null) },
                    label = { Text(stringResource(tab.label)) }
                )
            }
        }
    ) {
        Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            Text(stringResource(selected.label), style = MaterialTheme.typography.headlineMedium)
        }
    }
}

@PreviewScreenSizes
@Preview
@Composable
private fun AaruShellPreview() {
    AaruTheme {
        AaruShell()
    }
}

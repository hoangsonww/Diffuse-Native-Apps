package com.diffuse.android

import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.ArrowForward
import androidx.compose.material.icons.automirrored.filled.CompareArrows
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Assessment
import androidx.compose.material.icons.filled.CameraAlt
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Devices
import androidx.compose.material.icons.filled.Error
import androidx.compose.material.icons.filled.FileOpen
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.PushPin
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Share
import androidx.compose.material.icons.filled.Timeline
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.AssistChip
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Checkbox
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Divider
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExtendedFloatingActionButton
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.NavigationRail
import androidx.compose.material3.NavigationRailItem
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.diffuse.android.core.AndroidPreferences
import com.diffuse.android.domain.Change
import com.diffuse.android.domain.ChangeSeverity
import com.diffuse.android.domain.DiffResult
import com.diffuse.android.domain.Privacy
import com.diffuse.android.domain.RedactionPolicy
import com.diffuse.android.domain.Snapshot
import com.diffuse.android.domain.SnapshotEntity
import com.diffuse.android.domain.SnapshotSection
import com.diffuse.android.domain.SnapshotSummary
import com.diffuse.android.ui.DiffuseTheme
import com.diffuse.android.ui.DiffuseUiState
import com.diffuse.android.ui.DiffuseViewModel
import java.text.DateFormat
import java.time.Instant
import java.util.Date
import kotlin.math.abs

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent { DiffuseTheme { DiffuseApp() } }
    }
}

private enum class AppTab(val label: String, val icon: ImageVector) {
    OVERVIEW("Overview", Icons.Default.Home),
    SNAPSHOTS("Snapshots", Icons.Default.Timeline),
    COMPARE("Compare", Icons.AutoMirrored.Filled.CompareArrows),
    SETTINGS("Settings", Icons.Default.Settings),
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun DiffuseApp(model: DiffuseViewModel = viewModel()) {
    val state by model.state.collectAsStateWithLifecycle()
    val context = LocalContext.current
    var tab by rememberSaveable { mutableStateOf(AppTab.OVERVIEW) }
    val snackbar = remember { SnackbarHostState() }
    val importLauncher = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        uri?.let { context.contentResolver.openInputStream(it)?.bufferedReader()?.use { reader -> model.importSnapshot(reader.readText()) } }
    }

    LaunchedEffect(state.error) { state.error?.let { snackbar.showSnackbar(it); model.dismissError() } }
    LaunchedEffect(state.selection) { if (state.selection.size == 2) tab = AppTab.COMPARE }

    Surface(Modifier.fillMaxSize()) {
        if (state.selectedSnapshot != null) {
            SnapshotDetail(state.selectedSnapshot!!, model, onShare = { shareText(context, "Diffuse snapshot", it) })
        } else BoxWithConstraints {
            val expanded = maxWidth >= 720.dp
            Scaffold(
                topBar = {
                    TopAppBar(
                        title = { Text(if (tab == AppTab.OVERVIEW) "Diffuse" else tab.label) },
                        actions = {
                            IconButton(onClick = model::refresh) { Icon(Icons.Default.Refresh, "Refresh") }
                            if (tab == AppTab.SETTINGS) IconButton(onClick = { importLauncher.launch(arrayOf("application/json", "text/json")) }) {
                                Icon(Icons.Default.FileOpen, "Import snapshot")
                            }
                        },
                    )
                },
                bottomBar = {
                    if (!expanded) NavigationBar {
                        AppTab.entries.forEach { item ->
                            NavigationBarItem(
                                tab == item,
                                { tab = item },
                                { Icon(item.icon, null) },
                                Modifier.testTag("tab_${item.name.lowercase()}"),
                                label = { Text(item.label) },
                            )
                        }
                    }
                },
                floatingActionButton = {
                    if (tab == AppTab.OVERVIEW || tab == AppTab.SNAPSHOTS) {
                        ExtendedFloatingActionButton(
                            onClick = model::capture,
                            icon = { if (state.capturing) CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp) else Icon(Icons.Default.CameraAlt, null) },
                            text = { Text(if (state.capturing) "Capturing…" else "Take snapshot") },
                        )
                    }
                },
                snackbarHost = { SnackbarHost(snackbar) },
            ) { padding ->
                Row(Modifier.fillMaxSize().padding(padding)) {
                    if (expanded) NavigationRail {
                        Spacer(Modifier.height(8.dp))
                        AppTab.entries.forEach { item ->
                            NavigationRailItem(
                                tab == item,
                                { tab = item },
                                { Icon(item.icon, null) },
                                Modifier.testTag("tab_${item.name.lowercase()}"),
                                label = { Text(item.label) },
                            )
                        }
                    }
                    Box(Modifier.weight(1f).fillMaxHeight()) {
                        when (tab) {
                            AppTab.OVERVIEW -> OverviewScreen(state, model, { tab = AppTab.COMPARE })
                            AppTab.SNAPSHOTS -> SnapshotsScreen(state, model)
                            AppTab.COMPARE -> CompareScreen(state, model) { shareText(context, "Diffuse report", it) }
                            AppTab.SETTINGS -> SettingsScreen(state, model)
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun OverviewScreen(state: DiffuseUiState, model: DiffuseViewModel, onCompare: () -> Unit) {
    LazyColumn(Modifier.fillMaxSize().testTag("screen_overview").padding(horizontal = 18.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        item { Spacer(Modifier.height(4.dp)) }
        if (state.loading) item { Box(Modifier.fillMaxWidth().height(320.dp), contentAlignment = Alignment.Center) { CircularProgressIndicator() } }
        else if (state.summaries.isEmpty()) item {
            EmptyCard(
                Icons.Default.CameraAlt,
                "No snapshots yet",
                "Take one now, use your device, then take another. Diffuse will show what changed.",
                actionLabel = "Take snapshot",
                action = model::capture,
            )
        } else {
            state.overview?.diff?.let { diff ->
                val topChanges = state.overview.topChanges
                item {
                    Card(
                        modifier = Modifier.fillMaxWidth(),
                        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.primaryContainer),
                    ) {
                        Column(Modifier.padding(22.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                            Text(diff.summary.totalChanges.toString(), style = MaterialTheme.typography.displayMedium, fontWeight = FontWeight.Bold)
                            Text("changes since the previous snapshot", style = MaterialTheme.typography.titleMedium)
                            SeverityRow(diff)
                            OutlinedButton(onClick = { model.compareLatest(); onCompare() }) { Icon(Icons.AutoMirrored.Filled.CompareArrows, null); Spacer(Modifier.width(8.dp)); Text("Open comparison") }
                        }
                    }
                }
                if (topChanges.isNotEmpty()) {
                    item { SectionTitle("Most significant", "Changes most likely to explain a difference in behaviour") }
                    items(topChanges, key = { it.id }) { ChangeCard(it) }
                }
            } ?: item {
                EmptyCard(
                    Icons.Default.Assessment,
                    "One snapshot so far",
                    "Take another later and Diffuse will compare them.",
                    actionLabel = "Take snapshot",
                    action = model::capture,
                )
            }
            val problems = state.summaries.firstOrNull()?.hasProblems == true
            if (problems) item { EmptyCard(Icons.Default.Error, "Some collectors had trouble", "Open the latest snapshot for diagnostics and partial results.") }
        }
        item { Spacer(Modifier.height(100.dp)) }
    }
}

@Composable
private fun SnapshotsScreen(state: DiffuseUiState, model: DiffuseViewModel) {
    LazyColumn(Modifier.fillMaxSize().testTag("screen_snapshots"), verticalArrangement = Arrangement.spacedBy(6.dp)) {
        item {
            OutlinedTextField(
                state.searchQuery, model::search, Modifier.fillMaxWidth().testTag("snapshot_search").padding(horizontal = 16.dp, vertical = 8.dp),
                leadingIcon = { Icon(Icons.Default.Search, null) }, label = { Text("Search snapshots and observations") }, singleLine = true,
            )
        }
        if (state.searchQuery.isNotBlank()) {
            if (state.searchResults.isEmpty()) item { EmptyCard(Icons.Default.Search, "No matches", "Try a device, capability, or observed value.", Modifier.padding(16.dp)) }
            items(state.searchResults) { result ->
                ListItem(
                    headlineContent = { Text(result.title) }, supportingContent = { Text(result.detail) },
                    modifier = Modifier.padding(horizontal = 8.dp), trailingContent = { TextButton(onClick = { model.openSnapshot(result.snapshotID) }) { Text("Open") } },
                )
            }
        } else if (state.summaries.isEmpty() && !state.loading) item { EmptyCard(Icons.Default.Timeline, "No snapshots", "Snapshots you take will appear here.", Modifier.padding(16.dp)) }
        else {
            items(state.summaries, key = { it.id }) { summary -> SnapshotRow(summary, model) }
        }
        item { Spacer(Modifier.height(100.dp)) }
    }
}

@Composable
private fun SnapshotRow(summary: SnapshotSummary, model: DiffuseViewModel) {
    Card(onClick = { model.openSnapshot(summary.id) }, modifier = Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 3.dp)) {
        Row(Modifier.padding(14.dp), verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text(summary.label ?: formatDate(summary.capturedAt), fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                Text("${summary.entityCount} observations · ${summary.platform}", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            if (summary.isPinned) Icon(Icons.Default.PushPin, "Pinned", tint = MaterialTheme.colorScheme.primary)
        }
    }
}

/**
 * Chooses the two snapshots a comparison runs over, on the Compare screen
 * itself.
 *
 * Selection used to live on the timeline, which made Compare a screen you
 * could only fill from somewhere else. Roles are labelled by capture time
 * rather than tap order, because the diff always runs oldest to newest.
 */
@Composable
private fun SnapshotPairPicker(state: DiffuseUiState, model: DiffuseViewModel) {
    val chosen = state.summaries.filter { it.id in state.selection }.sortedBy { it.capturedAt }
    val base = chosen.firstOrNull()
    val target = chosen.getOrNull(1)

    Card(Modifier.fillMaxWidth().testTag("pair_picker")) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                PairSlot("Base", base, Modifier.weight(1f))
                Icon(Icons.AutoMirrored.Filled.ArrowForward, null, Modifier.padding(horizontal = 8.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
                PairSlot("Compared with", target, Modifier.weight(1f))
            }
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    when (state.selection.size) {
                        0 -> "Choose any two snapshots below."
                        1 -> "Choose one more."
                        else -> "Compared oldest to newest."
                    },
                    style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.weight(1f),
                )
                TextButton(onClick = { model.compareLatest() }) { Text("Latest two") }
                if (state.selection.isNotEmpty()) TextButton(onClick = { model.clearSelection() }) { Text("Clear") }
            }
            HorizontalDivider()
            state.summaries.forEach { summary ->
                val order = chosen.indexOfFirst { it.id == summary.id }
                Row(
                    Modifier.fillMaxWidth().clickable { model.toggleSelection(summary.id) }.padding(vertical = 8.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Checkbox(summary.id in state.selection, { model.toggleSelection(summary.id) })
                    Column(Modifier.weight(1f)) {
                        Text(summary.label ?: formatDate(summary.capturedAt), fontWeight = FontWeight.Medium, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        Text("${summary.entityCount} observations · ${summary.platform}", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                    if (order >= 0) {
                        Text(
                            if (order == 0) "Base" else "New",
                            style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.primary,
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun PairSlot(title: String, summary: SnapshotSummary?, modifier: Modifier = Modifier) {
    Column(modifier) {
        Text(title, style = MaterialTheme.typography.labelSmall, color = if (summary == null) MaterialTheme.colorScheme.onSurfaceVariant else MaterialTheme.colorScheme.primary)
        Text(
            summary?.let { it.label ?: formatDate(it.capturedAt) } ?: "Not chosen",
            style = MaterialTheme.typography.bodyMedium,
            maxLines = 2, overflow = TextOverflow.Ellipsis,
            color = if (summary == null) MaterialTheme.colorScheme.onSurfaceVariant else MaterialTheme.colorScheme.onSurface,
        )
    }
}

@Composable
private fun CompareScreen(state: DiffuseUiState, model: DiffuseViewModel, onShare: (String) -> Unit) {
    val diff = state.comparison
    if (state.summaries.size < 2) {
        Box(Modifier.fillMaxSize().testTag("screen_compare").padding(20.dp), contentAlignment = Alignment.Center) {
            EmptyCard(
                Icons.AutoMirrored.Filled.CompareArrows,
                "Take another snapshot",
                "Diffuse needs two snapshots before it can compare anything.",
            )
        }
        return
    }
    // Collapse the picker once there is a result, the way the Apple clients do.
    // Left expanded it pushes the comparison off the bottom of the screen, so
    // choosing a pair would appear to do nothing.
    var pickerExpanded by rememberSaveable { mutableStateOf(diff == null) }
    LaunchedEffect(diff?.base?.id, diff?.target?.id) { pickerExpanded = diff == null }

    LazyColumn(Modifier.fillMaxSize().testTag("screen_compare").padding(horizontal = 16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        item {
            if (pickerExpanded) {
                SnapshotPairPicker(state, model)
            } else {
                OutlinedButton(
                    onClick = { pickerExpanded = true },
                    modifier = Modifier.fillMaxWidth().testTag("change_pair"),
                ) {
                    Icon(Icons.AutoMirrored.Filled.CompareArrows, null)
                    Spacer(Modifier.width(8.dp))
                    Text("Change the pair")
                }
            }
        }
        if (diff == null) {
            item {
                EmptyCard(
                    Icons.AutoMirrored.Filled.CompareArrows,
                    "Pick two snapshots",
                    "Choose any two above and the differences appear here.",
                    Modifier.padding(vertical = 12.dp),
                )
            }
            item { Spacer(Modifier.height(80.dp)) }
            return@LazyColumn
        }
        item {
            Card(Modifier.fillMaxWidth().testTag("comparison_summary")) {
                Column(Modifier.padding(18.dp)) {
                    Text("${diff.summary.totalChanges} changes", style = MaterialTheme.typography.headlineMedium, fontWeight = FontWeight.Bold)
                    Text("${diff.base.label ?: formatDate(diff.base.capturedAt)} → ${diff.target.label ?: formatDate(diff.target.capturedAt)}", color = MaterialTheme.colorScheme.onSurfaceVariant)
                    SeverityRow(diff)
                    TextButton(onClick = { model.report(onShare) }) { Icon(Icons.Default.Share, null); Spacer(Modifier.width(8.dp)); Text("Share redacted report") }
                }
            }
        }
        if (diff.summary.totalChanges == 0) item { EmptyCard(Icons.Default.Check, "Nothing changed", "These snapshots match.") }
        diff.sectionDiffs.filter { it.changes.isNotEmpty() }.forEach { section ->
            item { SectionTitle(section.displayName, "${section.changes.size} change${if (section.changes.size == 1) "" else "s"}") }
            items(section.changes, key = { it.id }) { ChangeCard(it) }
        }
        item { Spacer(Modifier.height(24.dp)) }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun SeverityRow(diff: DiffResult) {
    FlowRow(
        modifier = Modifier.fillMaxWidth().testTag("severity_chips").padding(vertical = 8.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        ChangeSeverity.entries.forEach { severity ->
            val count = diff.summary.countsBySeverity[severity] ?: 0
            if (count > 0) AssistChip(
                onClick = {},
                label = {
                    Text(
                        "$count ${severity.name.lowercase()}",
                        maxLines = 1,
                        softWrap = false,
                    )
                },
            )
        }
    }
}

@Composable
private fun ChangeCard(change: Change) {
    val color = when (change.severity) {
        ChangeSeverity.CRITICAL -> MaterialTheme.colorScheme.error
        ChangeSeverity.SIGNIFICANT -> MaterialTheme.colorScheme.tertiary
        ChangeSeverity.NOTABLE -> MaterialTheme.colorScheme.primary
        ChangeSeverity.INFORMATIONAL -> MaterialTheme.colorScheme.onSurfaceVariant
    }
    Card(Modifier.fillMaxWidth()) {
        Row(Modifier.padding(14.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            Box(Modifier.size(8.dp).padding(top = 8.dp))
            Column(Modifier.weight(1f)) {
                Text(change.summary, fontWeight = FontWeight.Medium)
                Text(change.sectionName, style = MaterialTheme.typography.labelMedium, color = color)
                change.detail?.let { Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant) }
            }
        }
    }
}

@Composable
private fun SettingsScreen(state: DiffuseUiState, model: DiffuseViewModel) {
    var confirmDelete by remember { mutableStateOf(false) }
    var showPrivacy by remember { mutableStateOf(false) }
    val cadence = state.cadence
    val redaction = state.redaction
    LazyColumn(Modifier.fillMaxSize().testTag("screen_settings"), verticalArrangement = Arrangement.spacedBy(4.dp)) {
        item { SettingsHeader("Capture") }
        item {
            ListItem(
                headlineContent = { Text("Automatic capture") },
                supportingContent = { Text(cadence.name.lowercase().replace('_', ' ').replaceFirstChar(Char::uppercase)) },
                trailingContent = { TextButton(onClick = {
                    val next = AndroidPreferences.Cadence.entries[(cadence.ordinal + 1) % AndroidPreferences.Cadence.entries.size]
                    model.setCadence(next)
                }) { Text("Change") } },
            )
        }
        item {
            ListItem(
                headlineContent = { Text("Skip unchanged automatic snapshots") },
                supportingContent = { Text("Manual snapshots are always saved") },
                trailingContent = { Switch(state.skipUnchanged, model::setSkipUnchanged) },
            )
        }
        item { SettingsHeader("Capabilities") }
        items(state.capabilities, key = { it.metadata.id }) { item ->
            ListItem(
                headlineContent = { Text(item.metadata.displayName) },
                supportingContent = { Text(item.metadata.summary) },
                trailingContent = { Switch(item.enabled, { model.setCapability(item.metadata.id, it) }) },
            )
        }
        item { SettingsHeader("Privacy and export") }
        item {
            ListItem(
                headlineContent = { Text("Export redaction") },
                supportingContent = { Text(redaction.name.lowercase().replaceFirstChar(Char::uppercase)) },
                trailingContent = { TextButton(onClick = {
                    model.setRedaction(RedactionPolicy.entries[(redaction.ordinal + 1) % RedactionPolicy.entries.size])
                }) { Text("Change") } },
            )
        }
        item {
            ListItem(
                headlineContent = { Text("Privacy ledger") }, supportingContent = { Text("What Diffuse reads—and never reads") },
                leadingContent = { Icon(Icons.Default.Lock, null) }, trailingContent = { TextButton(onClick = { showPrivacy = true }) { Text("Open") } },
            )
        }
        item { SettingsHeader("Library") }
        item { ListItem(headlineContent = { Text("Snapshots") }, trailingContent = { Text(state.summaries.size.toString()) }) }
        item { ListItem(headlineContent = { Text("On disk") }, trailingContent = { Text(formatBytes(state.storageBytes)) }) }
        item {
            ListItem(
                headlineContent = { Text("Retention") }, supportingContent = { Text("${state.retentionDays} days · newest, pinned, and labelled protected") },
                trailingContent = { TextButton(onClick = {
                    val values = listOf(30, 90, 180, 365, 0)
                    val current = values.indexOf(state.retentionDays).coerceAtLeast(0)
                    model.setRetentionDays(values[(current + 1) % values.size])
                }) { Text("Change") } },
            )
        }
        item {
            TextButton(onClick = { confirmDelete = true }, modifier = Modifier.fillMaxWidth().padding(12.dp)) {
                Icon(Icons.Default.Delete, null, tint = MaterialTheme.colorScheme.error); Spacer(Modifier.width(8.dp)); Text("Delete all snapshots", color = MaterialTheme.colorScheme.error)
            }
        }
        item { Text("Snapshots never leave this device unless you explicitly share an export. There is no account, cloud, telemetry, or network upload.", Modifier.padding(20.dp), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant) }
    }
    if (confirmDelete) AlertDialog(
        onDismissRequest = { confirmDelete = false }, title = { Text("Delete every snapshot?") },
        text = { Text("This permanently removes the local history, including pinned snapshots.") },
        confirmButton = { TextButton(onClick = { confirmDelete = false; model.deleteAll() }) { Text("Delete", color = MaterialTheme.colorScheme.error) } },
        dismissButton = { TextButton(onClick = { confirmDelete = false }) { Text("Cancel") } },
    )
    if (showPrivacy) AlertDialog(
        onDismissRequest = { showPrivacy = false }, title = { Text("Privacy ledger") },
        text = {
            LazyColumn {
                item { Text("Collected locally", fontWeight = FontWeight.Bold); Spacer(Modifier.height(8.dp)) }
                items(state.capabilities) { Text("• ${it.metadata.collectionDescription}", Modifier.padding(vertical = 4.dp)) }
                item { Spacer(Modifier.height(12.dp)); Text("Never collected", fontWeight = FontWeight.Bold) }
                items(Privacy.neverCollected) { Text("• $it", Modifier.padding(vertical = 3.dp)) }
            }
        }, confirmButton = { TextButton(onClick = { showPrivacy = false }) { Text("Done") } },
    )
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun SnapshotDetail(snapshot: Snapshot, model: DiffuseViewModel, onShare: (String) -> Unit) {
    var label by remember(snapshot.id) { mutableStateOf(snapshot.label.orEmpty()) }
    var confirmDelete by remember { mutableStateOf(false) }
    Scaffold(
        modifier = Modifier.testTag("screen_snapshot_detail"),
        topBar = {
            TopAppBar(
                title = { Text(snapshot.label ?: "Snapshot", maxLines = 1, overflow = TextOverflow.Ellipsis) },
                navigationIcon = { IconButton(onClick = model::closeSnapshot) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Back") } },
                actions = {
                    IconButton(onClick = { model.pin(snapshot.id, !snapshot.isPinned) }) { Icon(Icons.Default.PushPin, "Pin") }
                    IconButton(onClick = { model.exportSnapshot(snapshot.id, onShare) }) { Icon(Icons.Default.Share, "Share") }
                    IconButton(onClick = { confirmDelete = true }) { Icon(Icons.Default.Delete, "Delete") }
                },
            )
        },
    ) { padding ->
        LazyColumn(Modifier.fillMaxSize().padding(padding).padding(horizontal = 16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            item {
                OutlinedTextField(
                    label, { label = it }, Modifier.fillMaxWidth(), label = { Text("Snapshot name") },
                    trailingIcon = { IconButton(onClick = { model.label(snapshot.id, label) }) { Icon(Icons.Default.Check, "Save label") } },
                )
                Text(formatDate(snapshot.capturedAt), Modifier.padding(top = 6.dp), style = MaterialTheme.typography.bodySmall)
            }
            snapshot.sections.sortedBy { it.schema.displayOrder }.forEach { section ->
                item { SectionTitle(section.schema.displayName, section.schema.summary) }
                if (!section.status.hasData) item { EmptyCard(Icons.Default.Error, section.status.displayName, section.diagnostics.firstOrNull()?.message ?: "No observations available") }
                items(section.entities, key = { it.identity.token }) { EntityCard(it, section) }
            }
            item { Spacer(Modifier.height(20.dp)) }
        }
    }
    if (confirmDelete) AlertDialog(
        onDismissRequest = { confirmDelete = false }, title = { Text("Delete this snapshot?") },
        confirmButton = { TextButton(onClick = { confirmDelete = false; model.delete(snapshot.id) }) { Text("Delete", color = MaterialTheme.colorScheme.error) } },
        dismissButton = { TextButton(onClick = { confirmDelete = false }) { Text("Cancel") } },
    )
}

@Composable
private fun EntityCard(entity: SnapshotEntity, section: SnapshotSection) {
    Card(Modifier.fillMaxWidth()) {
        Column(Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Text(entity.displayName, fontWeight = FontWeight.SemiBold)
            entity.subtitle?.let { Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant) }
            val descriptor = section.schema.kind(entity.kind)
            descriptor?.properties?.sortedBy { it.displayOrder }?.forEach { property ->
                val value = entity.property(property.key)
                if (!value.isAbsent) Row(
                    Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                    verticalAlignment = Alignment.Top,
                ) {
                    Text(property.displayName, Modifier.weight(0.4f), style = MaterialTheme.typography.bodySmall)
                    Text(
                        value.formatted(),
                        Modifier.weight(0.6f),
                        style = MaterialTheme.typography.bodySmall,
                        fontWeight = FontWeight.Medium,
                        textAlign = TextAlign.End,
                    )
                }
            }
        }
    }
}

@Composable
private fun SectionTitle(title: String, subtitle: String) {
    Column(Modifier.padding(top = 8.dp)) {
        Text(title, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
        Text(subtitle, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@Composable
private fun SettingsHeader(text: String) {
    Text(text.uppercase(), Modifier.padding(start = 20.dp, top = 18.dp, bottom = 4.dp), style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.primary)
}

@Composable
private fun EmptyCard(
    icon: ImageVector,
    title: String,
    message: String,
    modifier: Modifier = Modifier,
    actionLabel: String = "Compare latest two",
    action: (() -> Unit)? = null,
) {
    Card(modifier.fillMaxWidth()) {
        Column(Modifier.fillMaxWidth().padding(28.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Icon(icon, null, Modifier.size(38.dp), tint = MaterialTheme.colorScheme.primary)
            Text(title, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
            Text(message, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            action?.let { Button(onClick = it) { Text(actionLabel) } }
        }
    }
}

private fun formatDate(value: String): String = runCatching {
    DateFormat.getDateTimeInstance(DateFormat.MEDIUM, DateFormat.SHORT).format(Date.from(Instant.parse(value)))
}.getOrDefault(value)

private fun formatBytes(bytes: Long): String = when {
    abs(bytes) < 1024 -> "$bytes B"
    abs(bytes) < 1024L * 1024 -> "%.1f KB".format(bytes / 1024.0)
    abs(bytes) < 1024L * 1024 * 1024 -> "%.1f MB".format(bytes / 1024.0 / 1024.0)
    else -> "%.2f GB".format(bytes / 1024.0 / 1024.0 / 1024.0)
}

private fun shareText(context: android.content.Context, title: String, text: String) {
    context.startActivity(Intent.createChooser(Intent(Intent.ACTION_SEND).apply {
        type = "text/plain"
        putExtra(Intent.EXTRA_SUBJECT, title)
        putExtra(Intent.EXTRA_TEXT, text)
    }, title))
}

package com.diffuse.android.ui

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.diffuse.android.collectors.CapabilityMetadata
import com.diffuse.android.core.AndroidPreferences
import com.diffuse.android.core.CaptureSchedule
import com.diffuse.android.core.DiffuseService
import com.diffuse.android.core.Overview
import com.diffuse.android.core.SnapshotWorker
import com.diffuse.android.domain.DiffResult
import com.diffuse.android.domain.RedactionPolicy
import com.diffuse.android.domain.SearchResult
import com.diffuse.android.domain.Snapshot
import com.diffuse.android.domain.SnapshotSummary
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.time.Instant

data class CapabilityItem(val metadata: CapabilityMetadata, val enabled: Boolean)
data class DiffuseUiState(
    val loading: Boolean = true,
    val capturing: Boolean = false,
    val summaries: List<SnapshotSummary> = emptyList(),
    val overview: Overview? = null,
    val comparison: DiffResult? = null,
    val selection: List<String> = emptyList(),
    val selectedSnapshot: Snapshot? = null,
    val capabilities: List<CapabilityItem> = emptyList(),
    val searchQuery: String = "",
    val searchResults: List<SearchResult> = emptyList(),
    val storageBytes: Long = 0,
    val cadence: AndroidPreferences.Cadence = AndroidPreferences.Cadence.FOUR_HOURS,
    val skipUnchanged: Boolean = true,
    val retentionDays: Int = 90,
    val redaction: RedactionPolicy = RedactionPolicy.STANDARD,
    val error: String? = null,
)

class DiffuseViewModel(application: Application) : AndroidViewModel(application) {
    private val service = DiffuseService(application)
    private var searchJob: Job? = null
    val preferences: AndroidPreferences get() = service.preferences
    private val mutableState = MutableStateFlow(DiffuseUiState())
    val state: StateFlow<DiffuseUiState> = mutableState.asStateFlow()

    init {
        viewModelScope.launch {
            refreshInternal()
            captureOnOpenIfDue()
        }
    }

    fun refresh() = viewModelScope.launch { refreshInternal() }

    private suspend fun refreshInternal() {
        runCatching {
            val summaries = service.summaries()
            val selection = mutableState.value.selection.filter { id -> summaries.any { it.id == id } }
            mutableState.update {
                it.copy(
                    loading = false,
                    summaries = summaries,
                    overview = service.overview(),
                    selection = selection,
                    comparison = if (selection.size == 2) service.diff(selection[0], selection[1]) else null,
                    capabilities = service.registry.collectors.map { collector ->
                        CapabilityItem(collector.metadata, preferences.isEnabled(collector.metadata.id, collector.metadata.enabledByDefault))
                    },
                    storageBytes = service.storageSize(),
                    cadence = preferences.cadence,
                    skipUnchanged = preferences.skipUnchanged,
                    retentionDays = preferences.retentionDays,
                    redaction = preferences.redaction,
                    error = null,
                )
            }
        }.onFailure { error -> mutableState.update { it.copy(loading = false, error = error.message ?: "Could not load snapshots") } }
    }

    fun capture() = viewModelScope.launch {
        if (mutableState.value.capturing) return@launch
        mutableState.update { it.copy(capturing = true, error = null) }
        runCatching { service.capture() }
            .onFailure { error -> mutableState.update { it.copy(error = error.message ?: "Capture failed") } }
        mutableState.update { it.copy(capturing = false) }
        refreshInternal()
    }

    private suspend fun captureOnOpenIfDue() {
        if (preferences.cadence.hours == null) return
        val latest = mutableState.value.summaries.firstOrNull()
        val due = CaptureSchedule.isDue(preferences.cadence, latest?.capturedAt?.let(Instant::parse), Instant.now())
        if (due) {
            mutableState.update { it.copy(capturing = true) }
            runCatching { service.capture(Snapshot.Origin.TRIGGERED, skipIfUnchanged = preferences.skipUnchanged) }
                .onFailure { error -> mutableState.update { it.copy(error = error.message ?: "Automatic capture failed") } }
            mutableState.update { it.copy(capturing = false) }
            refreshInternal()
        }
    }

    fun toggleSelection(id: String) {
        val current = mutableState.value.selection.toMutableList()
        if (id in current) current.remove(id) else { current += id; if (current.size > 2) current.removeAt(0) }
        mutableState.update { it.copy(selection = current) }
        if (current.size == 2) viewModelScope.launch {
            mutableState.update { it.copy(comparison = service.diff(current[0], current[1])) }
        } else mutableState.update { it.copy(comparison = null) }
    }

    fun compareLatest() {
        val summaries = mutableState.value.summaries
        if (summaries.size < 2) return
        val selected = listOf(summaries[1].id, summaries[0].id)
        mutableState.update { it.copy(selection = selected) }
        viewModelScope.launch { mutableState.update { it.copy(comparison = service.diff(selected[0], selected[1])) } }
    }

    fun openSnapshot(id: String) = viewModelScope.launch { mutableState.update { it.copy(selectedSnapshot = service.snapshot(id)) } }
    fun closeSnapshot() = mutableState.update { it.copy(selectedSnapshot = null) }
    fun pin(id: String, pinned: Boolean) = viewModelScope.launch {
        service.annotate(id, pinned = pinned)
        mutableState.update { it.copy(selectedSnapshot = service.snapshot(id)) }
        refreshInternal()
    }
    fun label(id: String, label: String) = viewModelScope.launch {
        service.setLabel(id, label.trim().takeIf(String::isNotEmpty))
        mutableState.update { it.copy(selectedSnapshot = service.snapshot(id)) }
        refreshInternal()
    }
    fun delete(id: String) = viewModelScope.launch { service.delete(id); mutableState.update { it.copy(selectedSnapshot = null) }; refreshInternal() }
    fun deleteAll() = viewModelScope.launch { service.deleteAll(); refreshInternal() }

    fun search(query: String) {
        searchJob?.cancel()
        mutableState.update { state ->
            state.copy(searchQuery = query, searchResults = if (query.isBlank()) emptyList() else state.searchResults)
        }
        if (query.isBlank()) return
        searchJob = viewModelScope.launch {
            delay(150)
            val results = runCatching { service.search(query) }
                .getOrElse { error ->
                    if (mutableState.value.searchQuery == query) {
                        mutableState.update { it.copy(error = error.message ?: "Search failed") }
                    }
                    return@launch
                }
            if (mutableState.value.searchQuery == query) {
                mutableState.update { it.copy(searchResults = results) }
            }
        }
    }

    fun setCapability(id: String, enabled: Boolean) {
        preferences.setEnabled(id, enabled)
        mutableState.update { state -> state.copy(capabilities = state.capabilities.map { if (it.metadata.id == id) it.copy(enabled = enabled) else it }) }
    }

    fun setCadence(value: AndroidPreferences.Cadence) {
        preferences.cadence = value
        SnapshotWorker.schedule(getApplication(), value)
        mutableState.update { it.copy(cadence = value) }
    }

    fun setSkipUnchanged(value: Boolean) {
        preferences.skipUnchanged = value
        mutableState.update { it.copy(skipUnchanged = value) }
    }

    fun setRedaction(value: RedactionPolicy) {
        preferences.redaction = value
        mutableState.update { it.copy(redaction = value) }
    }

    fun setRetentionDays(value: Int) {
        val normalized = value.coerceAtLeast(0)
        preferences.retentionDays = normalized
        mutableState.update { it.copy(retentionDays = normalized) }
    }

    fun report(onReady: (String) -> Unit) = viewModelScope.launch {
        val selection = mutableState.value.selection
        if (selection.size == 2) service.exportReport(selection[0], selection[1])?.let(onReady)
    }

    fun exportSnapshot(id: String, onReady: (String) -> Unit) = viewModelScope.launch { service.exportSnapshot(id)?.let(onReady) }

    fun importSnapshot(text: String) = viewModelScope.launch {
        runCatching { service.importSnapshot(text) }
            .onFailure { error -> mutableState.update { it.copy(error = error.message ?: "Import failed") } }
        refreshInternal()
    }

    fun dismissError() = mutableState.update { it.copy(error = null) }
}

package com.healthmd.presentation.common

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.DatePicker
import androidx.compose.material3.DatePickerState
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.DisplayMode
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.KeyboardType
import com.healthmd.R
import com.healthmd.presentation.theme.GeistSpacing
import com.healthmd.presentation.theme.GeistType
import com.healthmd.presentation.theme.LocalGeistColors
import java.time.Instant
import java.time.ZoneOffset

/** Keeps the Material calendar, with strict text entry instead of its lenient day resolver. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun HealthDatePicker(state: DatePickerState) {
    val colors = LocalGeistColors.current
    Column {
        if (state.displayMode == DisplayMode.Input) {
            var input by rememberSaveable {
                mutableStateOf(state.selectedDateMillis?.let {
                    Instant.ofEpochMilli(it).atZone(ZoneOffset.UTC).toLocalDate().toString()
                }.orEmpty())
            }
            Column(Modifier.padding(GeistSpacing.space6)) {
                Text(stringResource(R.string.date_picker_enter_date), style = GeistType.heading20, color = colors.primary)
                OutlinedTextField(
                    value = input,
                    onValueChange = { value ->
                        input = value
                        val date = parseDatePickerInput(value, state.yearRange)
                        state.selectedDateMillis = date?.let {
                            val millis = it.atStartOfDay(ZoneOffset.UTC).toInstant().toEpochMilli()
                            millis.takeIf { _ ->
                                state.selectableDates.isSelectableYear(date.year) && state.selectableDates.isSelectableDate(millis)
                            }
                        }
                    },
                    label = { Text(stringResource(R.string.date_picker_input_label)) },
                    supportingText = {
                        if (state.selectedDateMillis == null) Text(stringResource(R.string.date_picker_invalid_date))
                    },
                    isError = state.selectedDateMillis == null,
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Ascii, autoCorrectEnabled = false),
                    textStyle = GeistType.label16,
                    modifier = Modifier.fillMaxWidth().padding(top = GeistSpacing.space4).testTag("datePicker.input"),
                )
            }
            TextButton(
                onClick = { state.displayMode = DisplayMode.Picker },
                modifier = Modifier.padding(horizontal = GeistSpacing.space4),
            ) { Text(stringResource(R.string.date_picker_show_calendar)) }
        } else {
            DatePicker(state = state)
        }
    }
}

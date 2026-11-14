package com.healthmd.data.scheduler

import com.healthmd.domain.model.ExportProfile

/** Native row identity, not its mutable display name or current output preferences. */
internal fun scheduledAPIProfileBinding(profile: ExportProfile): String =
    "profile-v1\n${profile.id}\n${profile.createdAtEpochMillis}"

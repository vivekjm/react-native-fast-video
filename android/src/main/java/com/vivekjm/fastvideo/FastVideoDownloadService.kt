package com.vivekjm.fastvideo

import android.app.Notification
import androidx.annotation.OptIn
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.offline.Download
import androidx.media3.exoplayer.offline.DownloadManager
import androidx.media3.exoplayer.offline.DownloadNotificationHelper
import androidx.media3.exoplayer.offline.DownloadService
import androidx.media3.exoplayer.scheduler.Requirements
import androidx.media3.exoplayer.scheduler.Scheduler

@OptIn(UnstableApi::class)
class FastVideoDownloadService : DownloadService(
  7314,
  DEFAULT_FOREGROUND_NOTIFICATION_UPDATE_INTERVAL,
  "react_native_fast_video_downloads",
  androidx.media3.exoplayer.R.string.exo_download_notification_channel_name,
  0
) {
  override fun getDownloadManager(): DownloadManager = FastVideoDownloadRuntime.manager(this)

  override fun getScheduler(): Scheduler? = null

  override fun getForegroundNotification(
    downloads: List<Download>,
    notMetRequirements: Int
  ): Notification {
    return DownloadNotificationHelper(this, "react_native_fast_video_downloads")
      .buildProgressNotification(
        this,
        android.R.drawable.stat_sys_download,
        null,
        null,
        downloads,
        notMetRequirements
      )
  }
}

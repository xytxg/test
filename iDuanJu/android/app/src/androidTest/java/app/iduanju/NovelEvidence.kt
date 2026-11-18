package app.iduanju

import androidx.test.platform.app.InstrumentationRegistry
import android.os.ParcelFileDescriptor

/** Export via shell stdin: scoped app storage may disappear when Gradle uninstalls the test app. */
internal fun saveNovelEvidence(name:String, bytes:ByteArray) {
    require(name.matches(Regex("[a-z0-9.-]+")))
    val automation=InstrumentationRegistry.getInstrumentation().uiAutomation
    ParcelFileDescriptor.AutoCloseInputStream(automation.executeShellCommand("mkdir -p /sdcard/Download/novel-qa")).use{it.readBytes()}
    val pipes=automation.executeShellCommandRw("dd of=/sdcard/Download/novel-qa/$name status=none")
    ParcelFileDescriptor.AutoCloseOutputStream(pipes[1]).use{it.write(bytes)}
    ParcelFileDescriptor.AutoCloseInputStream(pipes[0]).use{it.readBytes()}
}

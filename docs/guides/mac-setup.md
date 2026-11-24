# Setting up your Mac

You do this once. It takes an hour or two, most of it waiting for a download. Nothing here needs any coding.

You need: your Mac, your iPhone, your iPad, a cable for each, and your Apple account password.

## 1. Update macOS

1. Open the Apple menu and choose **System Settings**.
2. Choose **General**, then **Software Update**.
3. If it offers macOS Tahoe 26.6 or anything later, install it. If it already says you are on 26.6 or later, carry on.

## 2. Install Xcode

Xcode is Apple's free tool for building apps. It is a large download.

1. Open the **App Store** on the Mac and search for **Xcode**.
2. Click **Get**, then **Install**. Wait for it to finish.
3. Open Xcode once. Agree to the licence when asked.
4. When it asks which platforms to install, make sure **iOS** is ticked, then let it finish.

## 3. Sign in to Xcode

1. In Xcode, open the **Xcode** menu and choose **Settings**.
2. Choose **Accounts**.
3. Click the **+** at the bottom left, choose **Apple Account**, and sign in.

The free account is enough. You do not need to pay for the developer programme.

## 4. Prepare the iPhone and the iPad

Do this for the iPhone, then again for the iPad. Xcode has to see the device before the device offers Developer Mode, so open Xcode first.

1. Open Xcode on the Mac and leave it open.
2. Connect the device to the Mac with a cable and unlock it.
3. On the device, tap **Trust** when it asks whether to trust this computer.
4. Wait a minute. Then on the device, open **Settings**, then **Privacy & Security**, then **Developer Mode**. Turn it on. The device restarts.
5. After the restart, confirm that you want Developer Mode on.

## 5. Open the project in Claude on the Mac

The builds have to run on your Mac, so Claude needs to be working there.

1. Open the Claude app on the Mac and start a Claude Code session.
2. Ask Claude to download this project from GitHub (`MaquisChat/AlexandrineScrivner`) into a folder on the Mac and to switch to the branch named `stage-0-spike`.
3. Ask Claude to carry on with the plan in `docs/superpowers/plans/`.

From here Claude runs the builds. The remaining sections are things it will ask you to do at the right moment. Section 8 comes up first, then section 6, then section 7.

The first time the app is built for a device, the Mac asks for your Mac login password so the build can use your signing certificate. Enter it and choose **Always Allow**.

## 6. The first time an app is installed

The first time the test app lands on a device, the device will refuse to open it until you say you trust it. Claude's install will say "The app is installed but could not be opened". That is expected the first time.

1. Make sure the device is connected to the internet.
2. On the device, open **Settings**, then **General**, then **VPN & Device Management**.
3. Under **Developer App**, tap your Apple account.
4. Tap **Trust**.
5. Tell Claude it is done, so it can run the install again.

You do this once for each device.

## 7. The seven-day limit

With a free account, an app installed from your Mac stops opening after seven days. Nothing is lost when that happens: its recordings and reports stay on the device.

To get it going again, connect the device to the Mac and ask Claude to install the app again.

Plan your test runs so they all happen within seven days of an install.

## 8. Choosing the signing team (once)

Claude will ask you to do this when the project is first ready, before anything is installed on a device.

1. Open `spike/Spike.xcodeproj` in Xcode.
2. In the left-hand list, click the blue **Spike** item at the top, then select **Spike** under Targets.
3. Open the **Signing & Capabilities** tab.
4. In the **Team** menu, choose the one that ends in **(Personal Team)**.
5. Close Xcode.
6. Tell Claude it is done. It then runs `tools/mac-bootstrap.sh --capture-team`, which remembers your choice on this Mac only.

## 9. Checking a session folder from the phone

Once the app is recording sessions, each one is a folder. After copying a session folder (or a folder of them) from the phone to the Mac, check it before importing it into the research workbench:

```bash
tools/mac-check-session.sh ~/Desktop/Sessions
```

The checker reads each session and prints, in plain sentences, anything that is wrong: a file that is missing or has changed since the session was finished, or a photo, clip or recording whose time, time zone or place inside the file does not match the session's own record. The last line is `SESSION CHECK OK` or `SESSION CHECK FAILED`. Warnings do not fail the check; problems do.

One thing the checker cannot fix: until the research workbench itself is corrected, it shows the time of an imported **audio** recording wrong by your time-zone offset (photos and clips are right). The recording and the session's own record are not affected. The details and the fix are in `docs/compatibility/workbench-check.md`.

The first run fetches ExifTool, the program that reads the tags inside media files, into the project's `.tools` folder. It is the same build the workbench uses.

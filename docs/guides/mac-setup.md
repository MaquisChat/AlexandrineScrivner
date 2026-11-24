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

Do this for the iPhone, then again for the iPad.

1. Connect the device to the Mac with a cable.
2. On the device, tap **Trust** when it asks whether to trust this computer.
3. On the device, open **Settings**, then **Privacy & Security**, then **Developer Mode**. Turn it on. The device restarts.
4. After the restart, confirm that you want Developer Mode on.

If you cannot see Developer Mode, open Xcode on the Mac with the device still connected, wait a minute, and look again.

## 5. Open the project in Claude on the Mac

The builds have to run on your Mac, so Claude needs to be working there.

1. Open the Claude app on the Mac and start a session in the folder that holds this project.
2. Ask Claude to carry on with the plan in `docs/superpowers/plans/`.

From here Claude runs the builds. The remaining steps are things it will ask you to do at the right moment.

## 6. The first time an app is installed

The first time the test app lands on a device, the device will refuse to open it until you say you trust it.

1. On the device, open **Settings**, then **General**, then **VPN & Device Management**.
2. Under **Developer App**, tap your Apple account.
3. Tap **Trust**.

You do this once for each device.

## 7. The seven-day limit

With a free account, an app installed from your Mac stops opening after seven days. Nothing is lost when that happens: its recordings and reports stay on the device.

To get it going again, connect the device to the Mac and ask Claude to install the app again.

Plan your test runs so they all happen within seven days of an install.

## 8. Choosing the signing team (once)

Claude will ask you to do this when the project is first ready.

1. Open `spike/Spike.xcodeproj` in Xcode.
2. In the left-hand list, click the blue **Spike** item at the top, then select **Spike** under Targets.
3. Open the **Signing & Capabilities** tab.
4. In the **Team** menu, choose the one that ends in **(Personal Team)**.
5. Close Xcode.
6. Tell Claude it is done. It then runs `tools/mac-bootstrap.sh --capture-team`, which remembers your choice on this Mac only.

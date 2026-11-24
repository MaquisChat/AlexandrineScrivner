# Test runs for the recording test app

These are the runs that decide how the real app records audio. Each run is a short, exact routine. The test app ("Spike") writes a report for each one, and those reports are what the decisions are made from.

Allow about two hours, most of it waiting. Run R11 takes an hour on its own.

## Before you start

1. Charge the iPhone above 50 percent.
2. Turn off Low Power Mode (Settings, Battery).
3. Do every run within seven days of the app being installed. After seven days the app will not open until it is installed again.
4. Have a second phone, or someone who can call you, ready for run R8.
5. Have Bluetooth headphones ready for run R9.

## How every run works

1. Open **Spike** and stay on the **Audio test** tab.
2. Choose the run's label (R1, R2 and so on) in the **Run** picker.
3. Tap **Start**. Recording begins.
4. Do what the run says.
5. Tap **Stop**. The report is saved under the **Reports** tab.

Do not talk about anything private during the runs. The recordings stay on your devices, but you will listen to a few of them.

## The runs on the iPhone

### R1. Plain recording

1. Start.
2. Leave the phone on the table with the screen on for 3 minutes.
3. Stop.

Pass: the report says `VERDICT continuous: YES`.

### R2. Locked

1. Start.
2. Press the side button to lock the phone. Leave it for 5 minutes.
3. Unlock the phone.
4. Stop.

Pass: `VERDICT continuous: YES`.

### R3. In the background

1. Start.
2. Go to the home screen.
3. Open Safari and browse for 2 minutes.
4. Return to Spike.
5. Stop.

Pass: `VERDICT continuous: YES`.

### R4. Photos

1. Start.
2. Turn **Camera** on. Leave **Quiet shutter** off.
3. Tap **Photo** five times, about 10 seconds apart.
4. Turn **Quiet shutter** on.
5. Tap **Photo** five more times, about 10 seconds apart.
6. Stop.

Afterwards, listen to this run's audio and note whether you can hear the shutter in the first half, and in the second half.

Pass: `VERDICT continuous: YES`.

### R5. Video clips, sound added afterwards

1. Start.
2. Turn **Camera** on. Set **Clip sound** to **mux**.
3. Tap **Clip**. Point the camera at your hands and clap three times, slowly. After about 20 seconds tap **Stop clip**.
4. Do step 3 once more.
5. Stop.

Afterwards, watch both clips whose names end in `-muxed`. Note whether each clap is heard at the moment your hands meet.

Pass: `VERDICT continuous: YES`, and the claps match the picture in both clips.

### R6. Video clips, sound from the camera's own microphone

1. Start.
2. Turn **Camera** on. Set **Clip sound** to **session-mic**.
3. Record two 20-second clips with three claps each, as in R5.
4. Stop.

Afterwards, watch both clips and note whether they have sound.

Pass: `VERDICT continuous: YES`, and both clips have sound.

### R7. Leaving the app during a clip

1. Start.
2. Turn **Camera** on.
3. Tap **Clip**.
4. After 10 seconds, go to the home screen.
5. After 30 seconds, return to Spike.
6. Stop.

Pass: `VERDICT continuous: YES`; the clip plays up to the moment you left; the report lists a `camera-interrupted` event.

### R8. A phone call

1. Start.
2. Have someone call you. **Decline** the call.
3. Have them call again. **Answer**, talk for 20 seconds, and hang up.
4. Do not touch Spike. Wait 30 seconds.
5. Stop.

Pass: the report lists `engine-restart-ok` after the call, and any gaps are only around the call you answered.

### R9. Headphones connecting

1. Start.
2. After 30 seconds, connect your Bluetooth headphones.
3. After another 30 seconds, disconnect them.
4. After another 30 seconds, Stop.

Pass: `VERDICT continuous: YES`.

### R10. The app being closed by force

1. Start.
2. After 60 seconds, open the app switcher and swipe Spike away.
3. Open Spike again and look under **Reports**.

Pass: there is a report marked `status: UNFINISHED` with a `recovered-at-launch` event showing `readable-seconds` of 55 or more.

### R11. A long recording

1. Write down the battery percentage.
2. Take the phone off the charger.
3. Start.
4. Lock the phone and leave it for 60 minutes.
5. Unlock and Stop.
6. Write down the battery percentage again.

Pass: `VERDICT continuous: YES`.

## The runs on the iPad

### R12. Locked, on the iPad

Do run R2 on the iPad, with the label R12.

Pass: `VERDICT continuous: YES`.

### S1. The stylus

1. Open Spike on the iPad and go to the **Stylus** tab.
2. In the top half, touch the screen with a finger, then with the stylus. Watch the counts change.
3. In the bottom half, with the mode on **Pencil only**, rest your hand on the screen and write a sentence with the stylus.
4. Switch the mode to **Any input**, tap **Clear**, rest your hand on the screen and write the sentence again.
5. Answer the two questions on the screen.
6. Tap **Save stylus report**.

There is no pass or fail. This run tells us how the iPad sees your stylus.

## What to write down

| Question | Your answer |
|---|---|
| R4: shutter heard with Quiet shutter off? | |
| R4: shutter heard with Quiet shutter on? | |
| R5: claps match the picture in clip 1? | |
| R5: claps match the picture in clip 2? | |
| R6: clip 1 has sound? | |
| R6: clip 2 has sound? | |
| R11: battery percentage before | |
| R11: battery percentage after | |

## Afterwards

Connect each device to the Mac and tell Claude the runs are done. It copies the reports off the devices. The recordings themselves are never added to the project.

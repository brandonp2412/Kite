# Kite 1.0.110 rendered message-spacing verification — 2026-11-25

- Environment: Glass, isolated emulator-5580, Android x86_64, 1080 × 2160 capture, density override 420 dpi (2.625 px/dp). Signed app.kite versionCode 110 installed and launched; source commit 5376152a. Fictional Matrix fixture Friday Plans, signed in as Alex. Samsung not used for verification.
- Acceptance: 8 dp (21 px) between ordinary adjacent message surfaces; allow 1 px rasterization rounding. A reaction may overlap its parent bubble but must have the same clearance below the chip. Group sender names are intentional content and are not part of the ordinary gap.
- Method: inspected Android compositor screenshots; measured outgoing bubble runs from the exact solid fill RGB (58,49,82) in native-size PNG, requiring at least 12 matching pixels per row to reject antialiasing noise. Gap = next first occupied row minus preceding last occupied row minus 1.
- consecutive.png: five outgoing spans [1243–1343, 1365–1464, 1487–1587, 1609–1762, 1784–1883]; gaps 21, 22, 21, 21 px. Includes one wrapped bubble. PASS.
- reaction.png: parent ends y=1401; reaction outline ends y=1464; next bubble begins y=1487 (22 px clearance). Ordinary gaps 21 px. PASS.
- airplane.png: airplane mode + Wi-Fi disabled in emulator only, sent fictional local echo, clock visibly present; outgoing spans [[935, 1035], [1057, 1156], [1243, 1343], [1365, 1517], [1540, 1640], [1662, 1762], [1784, 1883]]; preceding bubble to pending bubble 21 px. PASS. Connectivity restored afterwards.
- group.png: visually inspected incoming names, sender changes and outgoing message; no collision. Sender-name height is intentional, not asserted as 8 dp between bubble edges.
- Limitations: not the user's original SMS room, not Samsung; no direct-room replay, deliberate hidden SDK marker insertion or light-mode/media geometry verification. This does not establish that every spacing case is resolved.
- The earlier emulator app was an old perfdebug build with invalid fixture credentials; it was not a valid baseline. Only the installed 1.0.110 captures are acceptance evidence.

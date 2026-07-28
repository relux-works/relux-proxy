# TASK-260728-2mjju4: validate-two-concurrent-macos-tunnels

## Description
Independently validate the accepted implementation as a packaged macOS menu-bar application, emphasizing two concurrent profiles, SSH alias command resolution, failure isolation, port conflict behavior, persistence, and clean shutdown.

## Scope
Run focused and full Swift tests, package/application build, static inspection of produced ssh arguments, and deterministic test or controlled local fixtures for two simultaneous sessions. Verify the built bundle structure and document any physical external-SSH-host step that cannot be automated safely. No feature expansion or release signing/notarization.

## Acceptance Criteria
1. Automated evidence demonstrates two profile sessions may be active simultaneously on distinct local ports and stopping or failing one leaves the other unchanged. 2. IP/hostname and alias targets produce the documented argv, with account override precedence and no unsafe shell interpolation. 3. Persistence/migration, duplicate-port, occupied-port, editing/removal, diagnostic isolation, and shutdown cases pass. 4. make test and make app pass and the generated .app has the expected executable and Info.plist. 5. A concise installed-Mac usage check documents how to configure clients for 127.0.0.1:<port> and how to verify exit identity through each tunnel.

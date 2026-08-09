# Biome Music

Put one audio file per environment in this folder. Filenames must match the biome cue (the `EnvironmentID` raw value).

| Environment   | Filename stem   | Example          |
|---------------|-----------------|------------------|
| Ember Run     | `emberRun`      | `emberRun.m4a`   |
| Summit Step   | `summitStep`    | `summitStep.m4a` |
| Ghost Glass   | `ghostGlass`    | `ghostGlass.m4a` |
| Low Crawl     | `lowCrawl`      | `lowCrawl.m4a`   |
| Storm Pass    | `stormPass`     | `stormPass.m4a`  |
| Crystal Cave  | `crystalCave`   | `crystalCave.m4a`|

Supported extensions (first match wins): `.m4a`, `.mp3`, `.wav`, `.caf`, `.aiff`.

## Notes

- Aim for roughly **45 seconds** per track (a few seconds shorter/longer is fine). The run stays in that biome for the track length, then crossfades to the next.
- Prefer **AAC `.m4a`** for size/quality on Apple platforms.
- Do not nest files in subfolders; keep them directly in `Music/`.
- This `Music` folder is an Xcode **folder reference**, so new files here are copied into the app bundle on the next build without editing the project file.

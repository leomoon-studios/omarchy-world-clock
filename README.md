# Omarchy World Clock

An offline world clock and timezone converter for the Omarchy 4 bar.

The bar stays minimal with a single world glyph. Clicking it opens a native,
theme-aware Omarchy panel where you can view clocks, convert a future meeting
time, and manage locations.

## Features

- Live clocks for up to 20 configured IANA timezones
- Today, Tomorrow, and Yesterday labels
- 12-hour and 24-hour display
- Optional timezone abbreviations and UTC offsets
- Reorder, remove, and rename saved locations
- Future date/time conversion using the system timezone database
- Searchable timezone pickers covering every installed IANA timezone; searches
  match timezone IDs, countries (including Iran), and regional descriptions
- Validation for nonexistent spring-forward wall times
- Completely offline with no telemetry or additional package

## Install

```bash
omarchy plugin add https://github.com/leomoon-studios/omarchy-world-clock --enable --yes
```

The manifest places the widget in the right bar section by default. Move it if
desired:

```bash
omarchy bar move io.github.leomoon-studios.world-clock --section right --after omarchy.tray
```

## Automation

Locations and display settings live inline in `~/.config/omarchy/shell.json`.
They can also be managed through supported Omarchy commands:

```bash
omarchy bar set io.github.leomoon-studios.world-clock locations \
  '[{"label":"Vancouver","timezone":"America/Vancouver"},{"label":"London","timezone":"Europe/London"},{"label":"Tehran","timezone":"Asia/Tehran"}]' --json

omarchy bar set io.github.leomoon-studios.world-clock hourFormat 24
omarchy bar set io.github.leomoon-studios.world-clock showAbbreviation true --json
omarchy bar set io.github.leomoon-studios.world-clock showUtcOffset false --json
```

## Security and privacy

The plugin performs no network access and stores no secrets. It runs only fixed
command arrays using `/usr/bin/env`, `/usr/bin/date`, `/usr/bin/readlink`, and
`/usr/bin/cat`. It
does not invoke a shell interpreter, request root access, or accept a custom
executable path. Timezone data comes from the system's
`/usr/share/zoneinfo/iso3166.tab`, `zone.tab`, and `tzdata.zi` from installed
tzdata.

## Development

```bash
omarchy plugin validate .
qmllint -I /usr/share/omarchy/shell BarWidget.qml Panel.qml TimezoneService.qml
```

## License

MIT

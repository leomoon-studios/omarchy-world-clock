import QtQuick
import Quickshell.Io
import "Model.js" as Model

Item {
  id: root

  property var locations: []
  property var times: ({})
  property var validZones: ["UTC"]
  property var timezoneOptions: [{ value: "UTC", label: "UTC", description: "Coordinated Universal Time" }]
  property string systemTimezone: "UTC"
  property bool refreshing: false
  property bool active: false
  property string lastError: ""

  property var queue: []
  property var currentJob: null

  property bool converting: false
  property var conversionResults: []
  property string conversionError: ""
  property string conversionWarning: ""
  property string conversionSourceDate: ""

  signal refreshed()
  signal conversionFinished()

  function enqueue(command, callback) {
    var next = queue.slice()
    next.push({ command: command, callback: callback })
    queue = next
    runNext()
  }

  function runNext() {
    if (process.running || currentJob || queue.length === 0) return
    var next = queue.slice()
    currentJob = next.shift()
    queue = next
    process.command = currentJob.command
    process.running = true
  }

  function parseClock(text) {
    var fields = String(text || "").trim().split("\t")
    if (fields.length < 7) return null
    return {
      epoch: fields[0],
      date: fields[1],
      time24: fields[2],
      time12: fields[3],
      abbreviation: fields[4],
      offset: fields[5],
      weekday: fields[6]
    }
  }

  function clockCommand(timezone, dateArgument) {
    var command = ["/usr/bin/env", "TZ=" + timezone, "/usr/bin/date"]
    if (dateArgument) command.push("--date=" + dateArgument)
    command.push("+%s\t%Y-%m-%d\t%H:%M\t%I:%M %p\t%Z\t%:z\t%a")
    return command
  }

  function refresh() {
    if (refreshing) return
    refreshing = true
    lastError = ""
    var pending = locations.length
    if (pending === 0) {
      refreshing = false
      refreshed()
      return
    }
    for (var i = 0; i < locations.length; i++) {
      (function(location) {
        root.enqueue(root.clockCommand(location.timezone, ""), function(exitCode, stdout, stderr) {
          var parsed = exitCode === 0 ? root.parseClock(stdout) : null
          if (parsed) {
            var updated = Object.assign({}, root.times)
            updated[location.timezone] = parsed
            root.times = updated
          } else {
            root.lastError = String(stderr || "Unable to read " + location.timezone).trim()
          }
          pending -= 1
          if (pending === 0) {
            root.refreshing = false
            root.refreshed()
          }
        })
      })(locations[i])
    }
  }

  function loadZones() {
    enqueue(["/usr/bin/cat", "/usr/share/zoneinfo/iso3166.tab"], function(countryExit, countryOutput) {
      var countries = ({})
      if (countryExit === 0) {
        var countryLines = String(countryOutput || "").split("\n")
        for (var i = 0; i < countryLines.length; i++) {
          if (!countryLines[i] || countryLines[i].charAt(0) === "#") continue
          var countryFields = countryLines[i].split("\t")
          if (countryFields.length >= 2) countries[countryFields[0]] = countryFields[1]
        }
      }

      root.enqueue(["/usr/bin/cat", "/usr/share/zoneinfo/zone.tab"], function(zoneExit, zoneOutput) {
        var metadata = ({})
        if (zoneExit === 0) {
          var zoneLines = String(zoneOutput || "").split("\n")
          for (var j = 0; j < zoneLines.length; j++) {
            if (!zoneLines[j] || zoneLines[j].charAt(0) === "#") continue
            var zoneFields = zoneLines[j].split("\t")
            if (zoneFields.length < 3) continue
            var countryName = countries[zoneFields[0]] || zoneFields[0]
            metadata[zoneFields[2]] = {
              country: countryName,
              comment: zoneFields.length >= 4 ? zoneFields[3] : ""
            }
          }
        }

        root.enqueue(["/usr/bin/cat", "/usr/share/zoneinfo/tzdata.zi"], function(dataExit, dataOutput) {
          var all = ({ "UTC": true })
          var aliases = ({})
          if (dataExit === 0) {
            var dataLines = String(dataOutput || "").split("\n")
            for (var k = 0; k < dataLines.length; k++) {
              var fields = dataLines[k].trim().split(/\s+/)
              if (fields[0] === "Z" && fields.length >= 2 && Model.validTimezoneId(fields[1]))
                all[fields[1]] = true
              else if (fields[0] === "L" && fields.length >= 3 && Model.validTimezoneId(fields[2])) {
                all[fields[2]] = true
                aliases[fields[2]] = fields[1]
              }
            }
          }
          // zone.tab is also retained as a fallback for unusual tzdata builds.
          for (var zone in metadata) all[zone] = true

          var zones = Object.keys(all).sort()
          var options = []
          var searchAliases = ({
            "Asia/Kolkata": "Kolkata, Mumbai, New Delhi, Delhi, Chennai, Bengaluru, Hyderabad"
          })
          for (var z = 0; z < zones.length; z++) {
            var id = zones[z]
            var details = metadata[id] || metadata[aliases[id]] || null
            var description = details ? details.country : "IANA timezone"
            if (details && details.comment) description += " — " + details.comment
            if (aliases[id]) description += " · alias for " + aliases[id]
            if (searchAliases[id]) description += " · " + searchAliases[id]
            options.push({ value: id, label: id, description: description })
          }
          root.validZones = zones
          root.timezoneOptions = options
        })
      })
    })
  }

  function loadSystemTimezone() {
    enqueue(["/usr/bin/readlink", "-f", "/etc/localtime"], function(exitCode, stdout) {
      var path = String(stdout || "").trim()
      var marker = "/usr/share/zoneinfo/"
      if (exitCode === 0 && path.indexOf(marker) === 0) {
        var timezone = path.substring(marker.length)
        if (Model.validTimezoneId(timezone)) root.systemTimezone = timezone
      }
    })
  }

  function convert(sourceTimezone, dateText, timeText, destinations) {
    conversionError = ""
    conversionWarning = ""
    conversionResults = []
    conversionSourceDate = dateText
    if (converting) return
    if (validZones.indexOf(sourceTimezone) === -1) {
      conversionError = "Select a valid source timezone."
      return
    }
    if (!/^\d{4}-\d{2}-\d{2}$/.test(dateText) || !/^\d{2}:\d{2}$/.test(timeText)) {
      conversionError = "Enter a date as YYYY-MM-DD and time as HH:MM."
      return
    }

    converting = true
    var wallTime = dateText + "T" + timeText + ":00"
    enqueue(["/usr/bin/env", "TZ=" + sourceTimezone, "/usr/bin/date", "--date=" + wallTime, "+%s"],
      function(exitCode, stdout, stderr) {
        var epoch = String(stdout || "").trim()
        if (exitCode !== 0 || !/^\d+$/.test(epoch)) {
          root.converting = false
          root.conversionError = String(stderr || "Invalid date or time.").trim()
          return
        }
        root.enqueue(root.clockCommand(sourceTimezone, "@" + epoch), function(roundExit, roundOutput) {
          var roundTrip = roundExit === 0 ? root.parseClock(roundOutput) : null
          if (!roundTrip || roundTrip.date !== dateText || roundTrip.time24 !== timeText) {
            root.converting = false
            root.conversionError = "That local time does not exist because of a timezone transition."
            return
          }

          function formatDestinations() {
            var pending = destinations.length
            var results = []
            if (pending === 0) {
              root.converting = false
              root.conversionFinished()
              return
            }
            for (var i = 0; i < destinations.length; i++) {
              (function(location, index) {
                root.enqueue(root.clockCommand(location.timezone, "@" + epoch), function(destExit, destOutput, destError) {
                  var parsed = destExit === 0 ? root.parseClock(destOutput) : null
                  results[index] = {
                    label: location.label,
                    timezone: location.timezone,
                    result: parsed,
                    error: parsed ? "" : String(destError || "Conversion failed").trim()
                  }
                  pending -= 1
                  if (pending === 0) {
                    root.conversionResults = results
                    root.converting = false
                    root.conversionFinished()
                  }
                })
              })(destinations[i], i)
            }
          }

          var nearbyPending = 2
          var ambiguous = false
          function checkedNearby(result) {
            if (result && result.date === dateText && result.time24 === timeText) ambiguous = true
            nearbyPending -= 1
            if (nearbyPending === 0) {
              if (ambiguous)
                root.conversionWarning = "This wall time occurs twice during a daylight-saving transition; verify which occurrence you intend."
              formatDestinations()
            }
          }
          var numericEpoch = Number(epoch)
          root.enqueue(root.clockCommand(sourceTimezone, "@" + String(numericEpoch - 3600)), function(beforeExit, beforeOutput) {
            checkedNearby(beforeExit === 0 ? root.parseClock(beforeOutput) : null)
          })
          root.enqueue(root.clockCommand(sourceTimezone, "@" + String(numericEpoch + 3600)), function(afterExit, afterOutput) {
            checkedNearby(afterExit === 0 ? root.parseClock(afterOutput) : null)
          })
        })
      })
  }

  function sourceNow(timezone, callback) {
    enqueue(clockCommand(timezone, ""), function(exitCode, stdout) {
      callback(exitCode === 0 ? parseClock(stdout) : null)
    })
  }

  Process {
    id: process
    command: []
    stdout: StdioCollector { id: output; waitForEnd: true }
    stderr: StdioCollector { id: errorOutput; waitForEnd: true }
    onExited: function(exitCode) {
      var finished = root.currentJob
      root.currentJob = null
      if (finished && finished.callback)
        finished.callback(exitCode, output.text, errorOutput.text)
      Qt.callLater(root.runNext)
    }
  }

  Timer {
    id: minuteTimer
    interval: 60000 - (Date.now() % 60000) + 100
    repeat: false
    running: false
    onTriggered: {
      root.refresh()
      interval = 60000
      restart()
    }
  }

  onActiveChanged: {
    if (active) {
      minuteTimer.interval = 60000 - (Date.now() % 60000) + 100
      minuteTimer.restart()
    } else {
      minuteTimer.stop()
    }
  }

  Component.onCompleted: {
    loadSystemTimezone()
    loadZones()
  }
}

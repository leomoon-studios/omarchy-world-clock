function validTimezoneId(value) {
  var zone = String(value || "").trim()
  if (zone === "UTC") return true
  if (!/^[A-Za-z0-9_+\/-]+$/.test(zone) || zone.charAt(0) === "/") return false
  if (zone.indexOf("posix/") === 0 || zone.indexOf("right/") === 0) return false
  var parts = zone.split("/")
  for (var i = 0; i < parts.length; i++)
    if (parts[i] === "" || parts[i] === "." || parts[i] === "..") return false
  return true
}

function defaultLocations(systemTimezone) {
  return [{ label: "UTC", timezone: "UTC" }]
}

function sanitizeLocations(value, validZones, systemTimezone) {
  var source = Array.isArray(value) ? value : []
  var result = []
  for (var i = 0; i < source.length && result.length < 20; i++) {
    var item = source[i] || {}
    // Pre-release builds automatically inserted a redundant Home location.
    if (item.home === true) continue
    var label = String(item.label || "").trim()
    var timezone = String(item.timezone || "").trim()
    if (!label || !validTimezoneId(timezone)) continue
    if (validZones && validZones.length > 0 && validZones.indexOf(timezone) === -1) continue
    result.push({ label: label, timezone: timezone })
  }
  if (result.length === 0) result = defaultLocations(systemTimezone)
  return result
}

function cloneLocations(value) {
  var result = []
  var source = Array.isArray(value) ? value : []
  for (var i = 0; i < source.length; i++)
    result.push({ label: source[i].label, timezone: source[i].timezone })
  return result
}

function dateDifference(fromDate, toDate) {
  var from = new Date(String(fromDate) + "T12:00:00Z")
  var to = new Date(String(toDate) + "T12:00:00Z")
  if (isNaN(from.getTime()) || isNaN(to.getTime())) return 0
  return Math.round((to.getTime() - from.getTime()) / 86400000)
}

function relativeDay(systemDate, locationDate, includeTodayDate) {
  var delta = dateDifference(systemDate, locationDate)
  if (delta === 0) return includeTodayDate ? "Today · " + locationDate : "Today"
  if (delta === 1) return "Tomorrow · " + locationDate
  if (delta === -1) return "Yesterday · " + locationDate
  return locationDate
}

function conversionDay(sourceDate, destinationDate) {
  var delta = dateDifference(sourceDate, destinationDate)
  if (delta === 0) return "Same day"
  if (delta === 1) return "Next day"
  if (delta === -1) return "Previous day"
  return (delta > 0 ? "+" : "−") + Math.abs(delta) + " days"
}

function formatOffset(value) {
  var offset = String(value || "")
  if (!offset) return ""
  return "UTC" + offset.replace("-", "−")
}

function formatClock(result, hourFormat) {
  if (!result) return "--:--"
  return hourFormat === "12" ? String(result.time12 || result.time24 || "--:--") : String(result.time24 || "--:--")
}

if (typeof module !== "undefined") {
  module.exports = {
    validTimezoneId: validTimezoneId,
    defaultLocations: defaultLocations,
    sanitizeLocations: sanitizeLocations,
    cloneLocations: cloneLocations,
    dateDifference: dateDifference,
    relativeDay: relativeDay,
    conversionDay: conversionDay,
    formatOffset: formatOffset,
    formatClock: formatClock
  }
}

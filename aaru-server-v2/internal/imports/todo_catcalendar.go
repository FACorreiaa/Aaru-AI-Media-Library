package imports

import "strings"

// TODO(parsers): placeholder until the CAT parser port lands; it replaces this file.

// IsCATCalendar is whether the text is an iCal file.
func IsCATCalendar(text string) bool { return strings.Contains(text, "BEGIN:VCALENDAR") }

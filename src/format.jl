# Formatting utilities for human-readable output

using TimeZones: UTC
using Dates

"""
    format_relative_time(dt::DateTime) -> String

Format a DateTime as a human-readable relative time string.
Assumes the input DateTime is in UTC.

# Examples
```julia
format_relative_time(now(UTC) - Day(2))  # "2 days ago"
format_relative_time(now(UTC) - Hour(3))  # "3 hours ago"
```
"""
function format_relative_time(dt::DateTime)
    now_time = now(UTC)
    diff = now_time - dt

    # Convert to various time units
    seconds = Dates.value(diff) / 1000
    minutes = seconds / 60
    hours = minutes / 60
    days = hours / 24
    weeks = days / 7
    months = days / 30.44  # Average month length
    years = days / 365.25

    if seconds < 60
        n = round(Int, seconds)
        return "$n $(n == 1 ? "second" : "seconds") ago"
    elseif minutes < 60
        n = round(Int, minutes)
        return "$n $(n == 1 ? "minute" : "minutes") ago"
    elseif hours < 24
        n = round(Int, hours)
        return "$n $(n == 1 ? "hour" : "hours") ago"
    elseif days < 7
        n = round(Int, days)
        return "$n $(n == 1 ? "day" : "days") ago"
    elseif weeks < 4
        n = round(Int, weeks)
        return "$n $(n == 1 ? "week" : "weeks") ago"
    elseif months < 12
        n = round(Int, months)
        return "$n $(n == 1 ? "month" : "months") ago"
    else
        n = round(Int, years)
        return "$n $(n == 1 ? "year" : "years") ago"
    end
end

"""
    format_when_output(package_name::String, version::String, timestamp::DateTime, yanked::Bool=false) -> String

Format the output for the REPL command.
The timestamp is assumed to be in UTC.
"""
function format_when_output(package_name::String, version::String, timestamp::DateTime, yanked::Bool=false)
    relative = format_relative_time(timestamp)
    absolute = Dates.format(timestamp, "yyyy-mm-dd HH:MM:SS")
    yanked_str = yanked ? " [YANKED]" : ""
    return "$package_name@$version registered $relative ($absolute UTC)$yanked_str"
end

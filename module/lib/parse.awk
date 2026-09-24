function valid(d,    n, i, parts, lab) {
    if (d == "" || length(d) > 253) return 0
    if (d ~ /^[0-9.]+$/) return 0
    if (d ~ /:/) return 0
    if (d !~ /^[a-z0-9._-]+$/) return 0
    if (d ~ /^[.-]/ || d ~ /[.-]$/) return 0
    if (d ~ /\.\./) return 0
    n = split(d, parts, ".")
    if (n < 2) return 0
    for (i = 1; i <= n; i++) {
        lab = parts[i]
        if (lab == "" || length(lab) > 63) return 0
        if (lab ~ /^-/ || lab ~ /-$/) return 0
    }
    if (d == "localhost" || d == "localhost.localdomain" || d == "local" || d == "broadcasthost") return 0
    if (d ~ /\.local$/ || d ~ /\.localdomain$/ || d ~ /\.arpa$/ || d ~ /\.onion$/) return 0
    return 1
}

function norm(d) {
    d = tolower(d)
    sub(/^\*\./, "", d)
    sub(/\.$/, "", d)
    sub(/^www\.\*\./, "", d)
    return d
}

function emit(d) {
    d = norm(d)
    if (valid(d)) print d
}

function allow(d) {
    d = norm(d)
    if (!valid(d)) return
    if (ALLOWMODE) { print d; return }
    if (ALLOW != "") print d >> ALLOW
}

BEGIN { FS = "[ \t]+" }

{
    sub(/\r$/, "")
    sub(/^[^ -~]+/, "")
    gsub(/^[ \t]+|[ \t]+$/, "")
    line = $0
}

line ~ /^[ \t]*$/ { next }
line ~ /^[ \t]*[#!;]/ { next }
line ~ /^\[/ { next }

line ~ /^@@\|\|/ {
    s = line
    sub(/^@@\|\|/, "", s)
    sub(/[\^\$\/].*$/, "", s)
    allow(s)
    next
}

line ~ /^\|\|/ {
    s = line
    sub(/^\|\|/, "", s)
    if (s ~ /[\/*]/) next
    mod = ""
    if (s ~ /\$/) {
        mod = s
        sub(/^[^$]*\$/, "", mod)
        sub(/\$.*$/, "", s)
        if (mod !~ /^(all|important|doc|popup|third-party|3p|document)$/) next
    }
    sub(/\^$/, "", s)
    if (s ~ /[\^|]/) next
    emit(s)
    next
}

line ~ /^(address|server|local)=\// {
    s = line
    sub(/^[a-z]+=\//, "", s)
    sub(/\/.*$/, "", s)
    emit(s)
    next
}

line ~ /^local-zone:/ {
    s = line
    if (s !~ /always_nxdomain|always_refuse|redirect|static/) next
    gsub(/"/, "", s)
    split(s, z, "[ \t]+")
    emit(z[2])
    next
}

line ~ /^[a-z0-9.*_-]+[ \t]+CNAME[ \t]+\.[ \t]*$/ {
    emit($1)
    next
}

line ~ /^(0\.0\.0\.0|127\.0\.0\.1|255\.255\.255\.255|::1|::|0:0:0:0:0:0:0:0|fe80::1%lo0)[ \t]/ {
    for (i = 2; i <= NF; i++) {
        f = $i
        if (f ~ /^[#!]/) break
        emit(f)
    }
    next
}

line ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+[ \t]/ { next }

NF == 1 { emit($1); next }

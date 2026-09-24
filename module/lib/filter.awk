BEGIN {
    nre = 0
    if (WL != "") {
        while ((getline l < WL) > 0) {
            sub(/\r$/, "", l)
            gsub(/^[ \t]+|[ \t]+$/, "", l)
            if (l == "" || l ~ /^[#!;]/) continue
            sub(/[ \t]+[#!;].*$/, "", l)
            if (l ~ /^re:/) {
                sub(/^re:/, "", l)
                re[nre++] = l
                continue
            }
            if (l ~ /^=/) {
                sub(/^=/, "", l)
                exact[tolower(l)] = 1
                continue
            }
            if (l ~ /^@@\|\|/) {
                sub(/^@@\|\|/, "", l)
                sub(/[\^\$\/].*$/, "", l)
            }
            if (l ~ /^\|\|/) {
                sub(/^\|\|/, "", l)
                sub(/[\^\$\/].*$/, "", l)
            }
            if (l ~ /^[0-9.]+[ \t]/) sub(/^[0-9.]+[ \t]+/, "", l)
            sub(/^\*\./, "", l)
            sub(/\.$/, "", l)
            l = tolower(l)
            if (l == "") continue
            suffix[l] = 1
        }
        close(WL)
    }
}

{
    d = $0
    if (d == "") next
    if (d in exact) next
    if (d in suffix) next
    p = d
    skip = 0
    while (1) {
        i = index(p, ".")
        if (i == 0) break
        p = substr(p, i + 1)
        if (p == "") break
        if (p in suffix) { skip = 1; break }
    }
    if (skip) next
    for (i = 0; i < nre; i++) {
        if (d ~ re[i]) { skip = 1; break }
    }
    if (skip) next
    print d
}

function esc(s) {
    gsub(/\\/, "\\\\", s)
    gsub(/"/, "\\\"", s)
    gsub(/\t/, " ", s)
    return s
}

function emit(id, kind, cat, name, url, note, state, count, result) {
    if (!first) printf ","
    first = 0
    printf "{\"id\":\"%s\",\"kind\":\"%s\",\"cat\":\"%s\",\"name\":\"%s\",\"url\":\"%s\",\"note\":\"%s\",\"state\":\"%s\",\"count\":%s,\"result\":\"%s\"}",
        esc(id), esc(kind), esc(cat), esc(name), esc(url), esc(note), state, count + 0, esc(result)
}

BEGIN {
    first = 1
    printf "["
}

FILENAME == SRCS {
    if ($0 == "") next
    n = split($0, a, "|")
    if (n < 3) next
    id = a[3]
    state[id] = a[1]
    kind[id] = a[2]
    url[id] = a[4]
    label[id] = a[5]
    if (!(id in seen)) {
        seen[id] = 1
        order[++nord] = id
    }
    next
}

FILENAME == STAT {
    if ($0 == "") next
    n = split($0, b, "|")
    if (n < 3) next
    cnt[b[1]] = b[2]
    res[b[1]] = b[3]
    next
}

{
    if ($0 == "" || substr($0, 1, 1) == "#") next
    n = split($0, c, "\t")
    if (n < 6) next
    id = c[1]
    incat[id] = 1
    st = (id in state) ? state[id] : "off"
    emit(id, c[2], c[3], c[4], c[6], c[7], st, cnt[id], res[id])
}

END {
    for (i = 1; i <= nord; i++) {
        id = order[i]
        if (id in incat) continue
        emit(id, kind[id], "custom", label[id], url[id], "", state[id], cnt[id], res[id])
    }
    printf "]\n"
}

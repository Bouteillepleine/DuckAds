BEGIN {
    first = 1
    if (EX != "") {
        while ((getline l < EX) > 0) {
            sub(/\r$/, "", l)
            if (l != "") ex[l] = 1
        }
        close(EX)
    }
    printf "["
}

{
    p = $0
    sub(/^package:/, "", p)
    sub(/\r$/, "", p)
    if (p == "") next
    if (p !~ /^[A-Za-z0-9._]+$/) next
    if (p !~ /\./) next
    if (p ~ /\.overlay$/) next
    if (p ~ /auto_generated_rro/) next
    if (p ~ /^com\.android\.cts\./) next
    if (!first) printf ","
    first = 0
    printf "{\"pkg\":\"%s\",\"exempt\":%s}", p, (p in ex) ? 1 : 0
}

END { printf "]\n" }

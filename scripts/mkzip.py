import os
import sys
import zipfile

src = os.path.abspath(sys.argv[1])
out = os.path.abspath(sys.argv[2])
skip = {"system/etc/hosts", ".DS_Store"}
exec_bits = (".sh",)

if os.path.exists(out):
    os.remove(out)

with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as z:
    for root, dirs, files in os.walk(src):
        dirs.sort()
        for name in sorted(files):
            full = os.path.join(root, name)
            rel = os.path.relpath(full, src).replace(os.sep, "/")
            if rel in skip or rel.endswith("/.DS_Store"):
                continue
            info = zipfile.ZipInfo(rel)
            info.compress_type = zipfile.ZIP_DEFLATED
            info.date_time = (2026, 1, 1, 0, 0, 0)
            mode = 0o755 if (rel.endswith(exec_bits) or "update-binary" in rel) else 0o644
            info.external_attr = (mode << 16) | 0o100000
            with open(full, "rb") as f:
                z.writestr(info, f.read())

print("wrote", out, os.path.getsize(out), "bytes")

#!/usr/bin/env python3
from pathlib import Path
import os

out_dir = Path(".")/"out"
out_dir.mkdir(exist_ok=True)
for path in Path(".").glob("*.png"):
    out_path = out_dir/path.name
    os.system(f"PvrTexToolCli -l -i {path} -d {out_path} -noout")

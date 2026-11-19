# -*- coding: utf-8 -*-
"""已废弃的兼容入口。

图标处理逻辑与资源清单统一放在仓库根目录的 make_icons.py，避免 tools/ 下
这份旧副本漏掉后来新增的「本命法宝」「凝练衍天珠」图标，或生成不同版本的
预览图。

注意：不能在 tools/ 里直接 import/runpy 根脚本 —— Python 的 sys.path[0]
是本目录，tools/bisect.py 会遮蔽标准库 bisect，导致 Pillow 导入失败。
因此这里用独立子进程、cwd 设为仓库根来转调。
"""
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

subprocess.run([sys.executable, os.path.join(ROOT, "make_icons.py")], cwd=ROOT, check=True)

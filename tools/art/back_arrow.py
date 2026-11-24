#!/usr/bin/env python3
"""返回按钮的弯箭头（原版也是弯箭头，照同样的姿态用脚本重画）。

画布 311×316，图形落在原版的范围里（x 81..222，y 72..227），纯白实心。
姿态和原版一样：一根从左下绕过右边、转到上面的粗弧线，顶上是一个指向左边的箭头。
用在两处：各页左下角的"返回"按钮（图标宽 70 像素，zoom 约 0.225，图形只有 32×35 屏幕像素，线条要粗），
以及棋盘上标记"上一格"的小精灵（3D，会抖）。

用法: python3 -I back_arrow.py [输出目录]      不给输出目录就写在工程的 assets/sprites/ui/actions/back.png
"""
import importlib.util
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
_spec = importlib.util.spec_from_file_location("doodle", os.path.join(HERE, "doodle.py"))
doodle = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(doodle)

REL = "assets/sprites/ui/actions/back.png"
CANVAS = (311, 316)
W, H = 141, 155                 # 设计范围 = 原版的图形范围，原点在它的左上角

# 弧线：圆心、中线半径、线宽（都是从原版上量出来的，略有取舍）
CX, CY, R, LW = 71.0, 85.0, 58.5, 22.0


def draw():
    d = doodle.Mask(W, H)
    # 粗弧线：从上面（箭头底下）往右、往下绕，到左下角收一个圆头。
    # doodle.arc 的框是弧线的外沿（线是朝里加粗的），所以要按"中线半径 + 线宽的一半"给框
    ro = R + LW / 2
    d.arc((CX - ro, CY - ro, CX + ro, CY + ro), 262, 152 + 360, LW)
    # 箭头：左边的尖指向左，上面一翼翘起，右下那一翼压在弧线的头上
    head = doodle.Mask(W, H)
    head.polygon([(4, 70), (33, 0), (56, 29), (75, 81), (44, 91)])
    head.soften(5.0)
    d.union(head)
    return d.alpha()


def build():
    return doodle.place(draw(), CANVAS, doodle.orig_box(REL))


if __name__ == "__main__":
    out_dir = sys.argv[1] if len(sys.argv) > 1 else ROOT
    path = os.path.join(out_dir, REL)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    build().save(path)
    print("已写出", path)

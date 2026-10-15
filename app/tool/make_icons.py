#!/usr/bin/env python3
"""Draws every HelpHive icon as a PNG (requires Pillow).

    python3 tool/make_icons.py

UI icons are single-colour masks (96x96) that the app tints at runtime, so one
file serves every state. Reactions, the Google mark and the bee logo are full
colour. Everything is drawn 8x larger and scaled down for clean edges.
"""
import math
import os
import sys

from PIL import Image, ImageChops, ImageDraw, ImageFilter

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'assets', 'icons')
os.makedirs(OUT, exist_ok=True)

N = 768          # working canvas for UI icons
FINAL = 96       # exported size
INK = (58, 46, 36, 255)


# --------------------------------------------------------------------------- helpers
def arc_pts(cx, cy, rx, ry, a0, a1, n=48):
    return [(cx + rx * math.cos(math.radians(a0 + (a1 - a0) * i / n)),
             cy + ry * math.sin(math.radians(a0 + (a1 - a0) * i / n))) for i in range(n + 1)]


def bez(p0, p1, p2, p3, n=32):
    pts = []
    for i in range(n + 1):
        t = i / n
        u = 1 - t
        pts.append((u ** 3 * p0[0] + 3 * u * u * t * p1[0] + 3 * u * t * t * p2[0] + t ** 3 * p3[0],
                    u ** 3 * p0[1] + 3 * u * u * t * p1[1] + 3 * u * t * t * p2[1] + t ** 3 * p3[1]))
    return pts


class Ic:
    """A one-colour icon: an 'L' mask we add strokes to and cut holes out of."""

    def __init__(self, w=56):
        self.m = Image.new('L', (N, N), 0)
        self.w = w

    def _tmp(self):
        t = Image.new('L', (N, N), 0)
        return t, ImageDraw.Draw(t)

    def _stroke(self, d, pts, w, closed=False):
        seq = list(pts) + ([pts[0]] if closed else [])
        d.line(seq, fill=255, width=w, joint='curve')
        for x, y in pts:
            d.ellipse([x - w / 2, y - w / 2, x + w / 2, y + w / 2], fill=255)

    def line(self, pts, w=None, closed=False):
        t, d = self._tmp()
        self._stroke(d, pts, w or self.w, closed)
        self.m = ImageChops.lighter(self.m, t)
        return self

    def poly(self, pts, w=None):
        """Filled polygon; w (optional) rounds its corners with a stroke."""
        t, d = self._tmp()
        d.polygon(pts, fill=255)
        if w:
            self._stroke(d, pts, w, closed=True)
        self.m = ImageChops.lighter(self.m, t)
        return self

    def disc(self, cx, cy, r):
        t, d = self._tmp()
        d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=255)
        self.m = ImageChops.lighter(self.m, t)
        return self

    def ring(self, cx, cy, r, w=None):
        w = w or self.w
        t, d = self._tmp()
        d.ellipse([cx - r - w / 2, cy - r - w / 2, cx + r + w / 2, cy + r + w / 2], fill=255)
        d.ellipse([cx - r + w / 2, cy - r + w / 2, cx + r - w / 2, cy + r - w / 2], fill=0)
        self.m = ImageChops.lighter(self.m, t)
        return self

    def rrect(self, box, r, w=None, filled=False):
        w = w or self.w
        t, d = self._tmp()
        x0, y0, x1, y1 = box
        d.rounded_rectangle([x0 - w / 2, y0 - w / 2, x1 + w / 2, y1 + w / 2], radius=r + w / 2, fill=255)
        if not filled:
            d.rounded_rectangle([x0 + w / 2, y0 + w / 2, x1 - w / 2, y1 - w / 2],
                                radius=max(r - w / 2, 1), fill=0)
        self.m = ImageChops.lighter(self.m, t)
        return self

    def cut_disc(self, cx, cy, r):
        t, d = self._tmp()
        d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=255)
        self.m = ImageChops.subtract(self.m, t)
        return self

    def cut_rect(self, box, r=0):
        t, d = self._tmp()
        d.rounded_rectangle(box, radius=r, fill=255)
        self.m = ImageChops.subtract(self.m, t)
        return self

    def cut_line(self, pts, w):
        t, d = self._tmp()
        self._stroke(d, pts, w)
        self.m = ImageChops.subtract(self.m, t)
        return self

    def cut_mask(self, other):
        self.m = ImageChops.subtract(self.m, other.m)
        return self

    def merge(self, other):
        self.m = ImageChops.lighter(self.m, other.m)
        return self

    def png(self, name, color=INK):
        small = self.m.resize((FINAL, FINAL), Image.LANCZOS)
        img = Image.new('RGBA', (FINAL, FINAL), color)
        img.putalpha(small)
        img.save(os.path.join(OUT, name + '.png'))


ICONS = {}


def icon(fn):
    ICONS[fn.__name__] = fn
    return fn


# --------------------------------------------------------------------------- people-shaped
def person(ic, cx, head_cy, hr, sh_cy, srx, sry, filled, extra=0):
    """Head + shoulders. extra widens everything (used to cut a halo)."""
    w = ic.w + extra
    ic_head = Ic(ic.w)
    if filled or extra:
        ic_head.disc(cx, head_cy, hr + extra / 2)
    else:
        ic_head.ring(cx, head_cy, hr, w)
    body = [(cx - srx, sh_cy)] + arc_pts(cx, sh_cy, srx, sry, 180, 360) + [(cx + srx, sh_cy)]
    if filled or extra:
        ic_head.poly(body, w)
    else:
        ic_head.line(body, w, closed=True)
    ic.merge(ic_head)


@icon
def user(): return _user(False)
@icon
def user_fill(): return _user(True)


def _user(filled):
    ic = Ic()
    person(ic, 384, 238, 112, 650, 255, 190, filled)
    return ic


@icon
def people(): return _people(False)
@icon
def people_fill(): return _people(True)


def _people(filled):
    ic = Ic(52)
    back = Ic(52)
    back.ring(528, 222, 78, 52) if not filled else back.disc(528, 222, 78 + 26)
    sh = arc_pts(548, 560, 150, 125, 215, 360) + [(698, 650)]
    if filled:
        back.poly(sh + [(548 - 100, 650)], 52)
    else:
        back.line(sh, 52)
    halo = Ic(52)
    person(halo, 290, 250, 98, 650, 205, 165, True, extra=70)
    back.cut_mask(halo)
    ic.merge(back)
    person(ic, 290, 250, 98, 650, 205, 165, filled)
    return ic


def _with_badge(kind):
    ic = Ic(50)
    person(ic, 292, 235, 98, 650, 205, 165, False)
    ic.w = 50
    cx, cy = 610, 520
    halo = Ic()
    halo.disc(cx, cy, 130)
    ic.cut_mask(halo)
    if kind == 'add':
        ic.line([(cx - 70, cy), (cx + 70, cy)], 46).line([(cx, cy - 70), (cx, cy + 70)], 46)
    elif kind == 'check':
        ic.line([(cx - 72, cy + 6), (cx - 18, cy + 58), (cx + 74, cy - 52)], 46)
    elif kind == 'x':
        ic.line([(cx - 60, cy - 60), (cx + 60, cy + 60)], 46).line([(cx - 60, cy + 60), (cx + 60, cy - 60)], 46)
    return ic


@icon
def user_add(): return _with_badge('add')
@icon
def user_check(): return _with_badge('check')
@icon
def user_x(): return _with_badge('x')


# --------------------------------------------------------------------------- navigation
@icon
def home(): return _home(False)
@icon
def home_fill(): return _home(True)


def _home(filled):
    ic = Ic()
    house = [(384, 112), (668, 338), (668, 650), (100, 650), (100, 338)]
    if filled:
        ic.poly(house, ic.w)
        ic.cut_rect((322, 478, 446, 720), 20)
    else:
        ic.line(house, closed=True)
        ic.line([(300, 650), (300, 490), (468, 490), (468, 650)])
    return ic


@icon
def bell(): return _bell(False)
@icon
def bell_fill(): return _bell(True)


def _bell(filled):
    ic = Ic()
    left = bez((120, 590), (178, 530), (176, 450), (182, 340))
    top = arc_pts(384, 340, 202, 215, 180, 360)
    right = bez((586, 340), (592, 450), (590, 530), (648, 590))
    outline = left + top[1:-1] + right
    if filled:
        ic.poly(outline, ic.w)
    else:
        ic.line(outline, closed=True)
    ic.line(arc_pts(384, 612, 82, 70, 10, 170))
    ic.disc(384, 128, 38)
    return ic


@icon
def chat(): return _bubble(False, True)
@icon
def chat_fill(): return _bubble(True, True)
@icon
def comment(): return _bubble(False, False)
@icon
def comment_fill(): return _bubble(True, False)


def _bubble(filled, dots):
    ic = Ic()
    box = (110, 120, 658, 560)
    if filled:
        ic.rrect(box, 150, filled=True)
        ic.poly([(190, 520), (182, 690), (360, 560)], 40)
    else:
        ic.rrect(box, 150)
        ic.cut_rect((190, 520, 390, 640))
        ic.line([(206, 548), (196, 684), (352, 572)], closed=False)
    if dots:
        for x in (270, 384, 498):
            if filled:
                ic.cut_disc(x, 340, 34)
            else:
                ic.disc(x, 340, 30)
    return ic


# --------------------------------------------------------------------------- actions
@icon
def search():
    ic = Ic()
    ic.ring(324, 324, 206)
    ic.line([(478, 478), (664, 664)])
    return ic


@icon
def plus():
    return Ic(64).line([(384, 120), (384, 648)]).line([(120, 384), (648, 384)])


@icon
def close():
    return Ic(60).line([(156, 156), (612, 612)]).line([(612, 156), (156, 612)])


@icon
def check():
    return Ic(66).line([(120, 400), (300, 576), (650, 188)])


@icon
def check_circle():
    ic = Ic().ring(384, 384, 276)
    ic.line([(250, 392), (352, 494), (524, 292)])
    return ic


@icon
def back():
    return Ic(62).line([(470, 120), (214, 384), (470, 648)])


@icon
def chevron_right():
    return Ic(62).line([(298, 120), (554, 384), (298, 648)])


@icon
def more():
    ic = Ic()
    for x in (150, 384, 618):
        ic.disc(x, 384, 52)
    return ic


@icon
def image():
    ic = Ic()
    ic.rrect((110, 140, 658, 628), 90)
    ic.disc(484, 288, 52)
    ic.line([(130, 560), (290, 396), (396, 500), (480, 424), (640, 580)], 50)
    return ic


@icon
def camera():
    ic = Ic()
    ic.line([(110, 232), (222, 232), (276, 150), (492, 150), (546, 232), (658, 232)], 56)
    ic.rrect((110, 232, 658, 640), 80)
    ic.ring(384, 436, 108, 52)
    return ic


@icon
def heart(): return _heart(False)
@icon
def heart_fill(): return _heart(True)


def _heart_pts():
    left = bez((384, 650), (260, 560), (110, 450), (110, 300), 30)
    lobe_l = bez((110, 300), (110, 190), (190, 120), (270, 120), 20)
    mid = bez((270, 120), (330, 120), (370, 160), (384, 215), 20)
    lobe_r = [(768 - x, y) for x, y in reversed(lobe_l)]
    mid_r = [(768 - x, y) for x, y in reversed(mid)]
    right = [(768 - x, y) for x, y in reversed(left)]
    return left + lobe_l[1:] + mid[1:] + mid_r[1:] + lobe_r[1:] + right[1:]


def _heart(filled):
    ic = Ic()
    pts = _heart_pts()
    if filled:
        ic.poly(pts, 30)
    else:
        ic.line(pts, closed=True)
    return ic


@icon
def send(): return _send(False)
@icon
def send_fill(): return _send(True)


def _send(filled):
    ic = Ic(52)
    plane = [(104, 372), (664, 104), (520, 664), (384, 480)]
    if filled:
        ic.poly(plane, 52)
        ic.cut_line([(384, 480), (664, 104)], 26)
    else:
        ic.line(plane, closed=True)
        ic.line([(384, 480), (664, 104)])
    return ic


@icon
def edit():
    ic = Ic(54)
    ic.line([(124, 650), (180, 470), (520, 130), (638, 248), (298, 588), (124, 650)])
    ic.line([(430, 220), (548, 338)])
    return ic


@icon
def trash():
    ic = Ic(54)
    ic.line([(130, 222), (638, 222)])
    ic.line([(296, 222), (296, 128), (472, 128), (472, 222)])
    ic.line([(190, 222), (214, 650), (554, 650), (578, 222)])
    ic.line([(320, 340), (326, 540)], 46).line([(448, 340), (442, 540)], 46)
    return ic


@icon
def logout():
    ic = Ic(54)
    ic.line([(330, 130), (130, 130), (130, 640), (330, 640)])
    ic.line([(250, 385), (650, 385)])
    ic.line([(520, 252), (652, 385), (520, 518)])
    return ic


@icon
def reply():
    ic = Ic(54)
    ic.line([(300, 170), (140, 330), (300, 490)])
    path = [(140, 330)] + bez((250, 330), (500, 320), (620, 380), (628, 560), 30)
    ic.line(path)
    return ic


@icon
def mail():
    ic = Ic(54)
    ic.rrect((100, 170, 668, 598), 80)
    ic.line([(150, 240), (384, 426), (618, 240)])
    return ic


@icon
def lock():
    ic = Ic(54)
    ic.rrect((150, 328, 618, 650), 70)
    ic.line(arc_pts(384, 300, 150, 170, 180, 360) + [(534, 340)])
    ic.line([(234, 340), (234, 300)])
    ic.disc(384, 486, 40)
    return ic


def _eye(ic):
    top = bez((84, 384), (170, 230), (300, 190), (384, 190))
    top2 = bez((384, 190), (468, 190), (598, 230), (684, 384))
    bot = bez((684, 384), (598, 538), (468, 578), (384, 578))
    bot2 = bez((384, 578), (300, 578), (170, 538), (84, 384))
    ic.line(top + top2[1:] + bot[1:] + bot2[1:], closed=False)
    ic.ring(384, 384, 74, 50)


@icon
def eye():
    ic = Ic(50)
    _eye(ic)
    return ic


@icon
def eye_off():
    ic = Ic(50)
    _eye(ic)
    ic.cut_line([(150, 640), (640, 128)], 100)
    ic.line([(150, 640), (640, 128)], 50)
    return ic


@icon
def pin():
    ic = Ic(54)
    outline = bez((384, 676), (250, 540), (150, 450), (150, 320), 30) \
        + arc_pts(384, 320, 234, 234, 180, 360)[1:] \
        + bez((618, 320), (618, 450), (518, 540), (384, 676), 30)[1:]
    ic.line(outline, closed=True)
    ic.disc(384, 320, 70)
    return ic


@icon
def cat_request():          # lifebuoy
    ic = Ic(50)
    ic.ring(384, 384, 262, 54)
    ic.ring(384, 384, 100, 50)
    for a in (45, 135, 225, 315):
        x, y = math.cos(math.radians(a)), math.sin(math.radians(a))
        ic.line([(384 + x * 130, 384 + y * 130), (384 + x * 238, 384 + y * 238)], 74)
    # carve the ring gaps between bars so it reads as a buoy
    for a in (0, 90, 180, 270):
        x, y = math.cos(math.radians(a)), math.sin(math.radians(a))
        pass
    return ic


@icon
def cat_offer():            # gift
    ic = Ic(50)
    ic.rrect((110, 290, 658, 650), 40)
    ic.rrect((84, 190, 684, 290), 36)
    ic.line([(384, 190), (384, 650)])
    ic.line(arc_pts(300, 130, 90, 62, 20, 200, 20)[::-1] + [(384, 190)])
    ic.line(arc_pts(468, 130, 90, 62, -20, -200, 20)[::-1] + [(384, 190)])
    return ic


@icon
def cat_general():          # one hive cell
    ic = Ic(54)
    pts = [(384 + 270 * math.cos(math.radians(60 * i - 90)), 384 + 270 * math.sin(math.radians(60 * i - 90))) for i in range(6)]
    ic.line(pts, closed=True)
    ic.disc(384, 384, 62)
    return ic


@icon
def hex_cell():
    ic = Ic(54)
    pts = [(384 + 280 * math.cos(math.radians(60 * i - 90)), 384 + 280 * math.sin(math.radians(60 * i - 90))) for i in range(6)]
    ic.line(pts, closed=True)
    return ic


@icon
def settings():             # sliders
    ic = Ic(50)
    for y, x in ((190, 250), (384, 520), (578, 330)):
        ic.line([(110, y), (658, y)], 46)
        ic.cut_disc(x, y, 92)
        ic.ring(x, y, 62, 48)
    return ic


# --------------------------------------------------------------------------- colour art
def disc_layer(size, color, hi=(255, 255, 255), lo=None):
    """A soft clay-looking ball: base colour, lit top-left, shaded bottom-right."""
    s = size
    base = Image.new('RGBA', (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(base)
    d.ellipse([0, 0, s - 1, s - 1], fill=color + (255,))
    mask = base.split()[3]
    lo = lo or tuple(max(int(c * 0.78), 0) for c in color)

    shade = Image.new('RGBA', (s, s), (0, 0, 0, 0))
    ImageDraw.Draw(shade).ellipse([-s * 0.1, -s * 0.1, s * 0.82, s * 0.82], fill=lo + (0,))
    sh = Image.new('L', (s, s), 0)
    ImageDraw.Draw(sh).ellipse([s * 0.18, s * 0.28, s * 1.12, s * 1.12], fill=150)
    sh = sh.filter(ImageFilter.GaussianBlur(s * 0.12))
    dark = Image.new('RGBA', (s, s), lo + (255,))
    base = Image.composite(dark, base, ImageChops.multiply(sh, mask))

    li = Image.new('L', (s, s), 0)
    ImageDraw.Draw(li).ellipse([s * 0.14, s * 0.1, s * 0.62, s * 0.46], fill=120)
    li = li.filter(ImageFilter.GaussianBlur(s * 0.07))
    light = Image.new('RGBA', (s, s), hi + (255,))
    base = Image.composite(light, base, ImageChops.multiply(li, mask))
    base.putalpha(mask)
    return base


def reaction(name, painter, color):
    S = 1024
    img = disc_layer(S, color)
    d = ImageDraw.Draw(img)
    painter(d, S)
    img.resize((128, 128), Image.LANCZOS).save(os.path.join(OUT, f'reaction_{name}.png'))


BROWN = (74, 48, 28, 255)
WHITE = (255, 255, 255, 255)


def _line(d, pts, w, fill=BROWN):
    d.line(pts, fill=fill, width=w, joint='curve')
    for x, y in (pts[0], pts[-1]):
        d.ellipse([x - w / 2, y - w / 2, x + w / 2, y + w / 2], fill=fill)


def paint_haha(d, S):
    _line(d, arc_pts(330, 400, 78, 60, 200, 340, 20), 40)
    _line(d, arc_pts(694, 400, 78, 60, 200, 340, 20), 40)
    mouth = [(250, 560)] + arc_pts(512, 560, 262, 270, 0, 180, 40) + [(774, 560)]
    d.polygon(mouth, fill=BROWN)
    d.pieslice([362, 700, 662, 900], 180, 360, fill=(231, 108, 96, 255))
    d.rectangle([300, 548, 724, 600], fill=WHITE)


def paint_wow(d, S):
    for x in (336, 688):
        d.ellipse([x - 52, 360, x + 52, 480], fill=BROWN)
        d.ellipse([x - 20, 380, x + 6, 408], fill=WHITE)
    _line(d, arc_pts(336, 330, 90, 40, 205, 335, 14), 30)
    _line(d, arc_pts(688, 330, 90, 40, 205, 335, 14), 30)
    d.ellipse([430, 600, 594, 790], fill=BROWN)


def paint_sad(d, S):
    for x in (336, 688):
        d.ellipse([x - 44, 420, x + 44, 520], fill=BROWN)
        d.ellipse([x - 16, 436, x + 6, 460], fill=WHITE)
    _line(d, [(250, 360), (410, 322)], 30)
    _line(d, [(774, 360), (614, 322)], 30)
    _line(d, arc_pts(512, 800, 150, 110, 205, 335, 30), 36)
    d.polygon([(250, 560), (300, 650), (200, 650)], fill=(120, 190, 235, 255))
    d.ellipse([200, 620, 300, 720], fill=(120, 190, 235, 255))


def paint_love(d, S):
    pts = [(x * 1.0 + 128 - 0, y * 1.0 + 120) for x, y in _heart_pts()]
    big = [((x - 384) * 1.05 + 512, (y - 384) * 1.05 + 520) for x, y in _heart_pts()]
    d.polygon(big, fill=WHITE)
    w = 28
    d.line(big + [big[0]], fill=WHITE, width=w, joint='curve')


def paint_like(d, S):
    k = 1.15
    def T(x, y):
        return ((x - 384) * k + 512, (y - 384) * k + 540)
    cuff = [(150, 340), (260, 340), (260, 650), (150, 650)]
    hand = [(290, 350), (380, 210), (400, 130), (470, 120), (500, 160), (470, 300),
            (640, 300), (676, 340), (650, 400), (676, 450), (640, 520), (660, 560), (620, 620), (570, 650), (290, 650)]
    d.polygon([T(*p) for p in cuff], fill=WHITE)
    d.polygon([T(*p) for p in hand], fill=WHITE)
    for poly in (cuff, hand):
        pts = [T(*p) for p in poly]
        d.line(pts + [pts[0]], fill=WHITE, width=34, joint='curve')
        for x, y in pts:
            d.ellipse([x - 17, y - 17, x + 17, y + 17], fill=WHITE)
    # finger creases, so the hand reads as a hand and not a mitten
    crease = (226, 146, 42, 255)
    for y in (385, 455, 525):
        a, b = T(470 if y == 385 else 440, y), T(668, y)
        d.line([a, b], fill=crease, width=20)
        d.ellipse([a[0] - 10, a[1] - 10, a[0] + 10, a[1] + 10], fill=crease)


def make_reactions():
    reaction('like', paint_like, (242, 167, 59))
    reaction('love', paint_love, (232, 110, 92))
    reaction('haha', paint_haha, (255, 208, 99))
    reaction('wow', paint_wow, (255, 208, 99))
    reaction('sad', paint_sad, (255, 208, 99))


# --------------------------------------------------------------------------- brand
HONEY = (242, 167, 59)
HONEY_DEEP = (217, 134, 26)
CREAM = (246, 239, 228)


def hexagon(cx, cy, r, rot=-90):
    return [(cx + r * math.cos(math.radians(60 * i + rot)), cy + r * math.sin(math.radians(60 * i + rot))) for i in range(6)]


def bee(size, body_scale=1.0):
    """Little bee on a transparent square canvas."""
    S = size * 2
    im = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    c = S / 2
    u = S / 100 * body_scale

    # wings
    wing = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    wd = ImageDraw.Draw(wing)
    wd.ellipse([c - 30 * u, c - 38 * u, c - 2 * u, c - 6 * u], fill=(255, 255, 255, 235))
    wd.ellipse([c + 2 * u, c - 38 * u, c + 30 * u, c - 6 * u], fill=(255, 255, 255, 235))
    wing = wing.rotate(0)
    im = Image.alpha_composite(im, wing)
    d = ImageDraw.Draw(im)
    for sx in (-1, 1):
        x0, x1 = (c - 30 * u, c - 2 * u) if sx < 0 else (c + 2 * u, c + 30 * u)
        d.ellipse([x0, c - 38 * u, x1, c - 6 * u], outline=(58, 46, 36, 90), width=int(1.6 * u))

    # body
    body = Image.new('L', (S, S), 0)
    ImageDraw.Draw(body).ellipse([c - 27 * u, c - 17 * u, c + 27 * u, c + 33 * u], fill=255)
    fill = Image.new('RGBA', (S, S), (255, 214, 120, 255))
    stripes = ImageDraw.Draw(fill)
    for y0 in (c - 2 * u, c + 15 * u):
        stripes.rectangle([0, y0, S, y0 + 8 * u], fill=(58, 46, 36, 255))
    body_img = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    body_img.paste(fill, (0, 0), body)
    im = Image.alpha_composite(im, body_img)
    d = ImageDraw.Draw(im)

    # head, eyes, antennae, stinger
    d.ellipse([c - 17 * u, c - 33 * u, c + 17 * u, c - 3 * u], fill=(58, 46, 36, 255))
    for sx in (-1, 1):
        d.ellipse([c + sx * 8 * u - 3.4 * u, c - 22 * u, c + sx * 8 * u + 3.4 * u, c - 14 * u], fill=(255, 255, 255, 255))
        d.line([(c + sx * 6 * u, c - 31 * u), (c + sx * 14 * u, c - 42 * u)], fill=(58, 46, 36, 255), width=int(2.4 * u))
        d.ellipse([c + sx * 14 * u - 2.4 * u, c - 42 * u - 2.4 * u, c + sx * 14 * u + 2.4 * u, c - 42 * u + 2.4 * u], fill=(58, 46, 36, 255))
    d.polygon([(c - 3.5 * u, c + 31 * u), (c + 3.5 * u, c + 31 * u), (c, c + 40 * u)], fill=(58, 46, 36, 255))
    return im.resize((size, size), Image.LANCZOS)


def clay_hex(size, color=HONEY):
    """A puffy honey hexagon with the highlight/shadow pair that makes it clay."""
    S = size * 2
    mask = Image.new('L', (S, S), 0)
    ImageDraw.Draw(mask).polygon(hexagon(S / 2, S / 2, S * 0.47), fill=255)
    mask = mask.filter(ImageFilter.GaussianBlur(S * 0.012))
    # round the corners: blur then threshold
    mask = mask.filter(ImageFilter.GaussianBlur(S * 0.03)).point(lambda v: 255 if v > 128 else 0).filter(ImageFilter.GaussianBlur(S * 0.004))
    base = Image.new('RGBA', (S, S), color + (255,))
    dark = Image.new('RGBA', (S, S), HONEY_DEEP + (255,))
    sh = Image.new('L', (S, S), 0)
    ImageDraw.Draw(sh).ellipse([S * 0.2, S * 0.3, S * 1.15, S * 1.2], fill=170)
    sh = sh.filter(ImageFilter.GaussianBlur(S * 0.1))
    base = Image.composite(dark, base, ImageChops.multiply(sh, mask))
    li = Image.new('L', (S, S), 0)
    ImageDraw.Draw(li).ellipse([S * 0.1, S * 0.06, S * 0.6, S * 0.4], fill=150)
    li = li.filter(ImageFilter.GaussianBlur(S * 0.07))
    base = Image.composite(Image.new('RGBA', (S, S), (255, 232, 168, 255)), base, ImageChops.multiply(li, mask))
    base.putalpha(mask)
    return base.resize((size, size), Image.LANCZOS)


def logo(size, bg=None, scale=1.0, shadow=True):
    img = Image.new('RGBA', (size, size), bg + (255,) if bg else (0, 0, 0, 0))
    hsize = int(size * scale)
    hx = clay_hex(hsize)
    off = ((size - hsize) // 2, (size - hsize) // 2)
    if shadow:
        sh = Image.new('RGBA', (size, size), (0, 0, 0, 0))
        a = hx.split()[3].point(lambda v: int(v * 0.28))
        tint = Image.new('RGBA', hx.size, (150, 110, 60, 255))
        tint.putalpha(a)
        sh.paste(tint, (off[0] + int(size * 0.012), off[1] + int(size * 0.03)), tint)
        sh = sh.filter(ImageFilter.GaussianBlur(size * 0.02))
        img = Image.alpha_composite(img, sh)
    img.alpha_composite(hx, off)
    b = bee(int(hsize * 0.62))
    img.alpha_composite(b, ((size - b.width) // 2, (size - b.height) // 2 + int(size * 0.01)))
    return img


def make_brand():
    logo(512, scale=0.88).save(os.path.join(OUT, 'logo.png'))
    logo(1024, bg=CREAM, scale=0.8).save(os.path.join(OUT, 'launcher.png'))
    # adaptive icon foreground: art stays inside the central ~60%
    logo(1024, scale=0.58, shadow=False).save(os.path.join(OUT, 'launcher_foreground.png'))
    bee(256).save(os.path.join(OUT, 'bee.png'))


def make_google():
    S = 768
    im = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    bbox = [60, 60, S - 60, S - 60]
    w = 150
    d.arc(bbox, 200, 318, fill=(234, 67, 53, 255), width=w)     # red, top
    d.arc(bbox, 138, 202, fill=(251, 188, 5, 255), width=w)     # yellow, left
    d.arc(bbox, 40, 140, fill=(52, 168, 83, 255), width=w)      # green, bottom
    d.arc(bbox, -4, 42, fill=(66, 133, 244, 255), width=w)      # blue, right
    d.rectangle([S / 2 - 6, S / 2 - 70, S - 60, S / 2 + 70], fill=(66, 133, 244, 255))
    im.resize((FINAL, FINAL), Image.LANCZOS).save(os.path.join(OUT, 'google.png'))


# --------------------------------------------------------------------------- run
def main():
    for name, fn in ICONS.items():
        fn().png(name)
    make_reactions()
    make_brand()
    make_google()
    print(f'wrote {len(os.listdir(OUT))} icons to {os.path.abspath(OUT)}')


if __name__ == '__main__':
    sys.exit(main())

#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Build the Experiment 1 & 2 PDF documentation reports for the
V-SPACE FPGA Build Challenge 2026 (Team Mahasena / Lead: Manaswi).

Parses the hand-authored report_source.md files (a known, consistent
format we control) and renders a clean technical-report PDF with
ReportLab, including a natively-drawn (vector) block diagram for
each experiment -- no external SVG rasterizer required.
"""
import re
import sys
from pathlib import Path

from reportlab.lib.pagesizes import LETTER
from reportlab.lib.units import inch
from reportlab.lib import colors
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.lib.enums import TA_CENTER, TA_LEFT
from reportlab.platypus import (
    SimpleDocTemplate, Paragraph, Spacer, Table, TableStyle,
    Preformatted, PageBreak, Flowable, KeepTogether, HRFlowable
)
from reportlab.graphics.shapes import Drawing, Rect, String, Line
from reportlab.pdfgen import canvas as pdfcanvas


# ----------------------------------------------------------------
# Shared styles
# ----------------------------------------------------------------
styles = getSampleStyleSheet()

TITLE = ParagraphStyle('TitleX', parent=styles['Title'], fontSize=20,
                        spaceAfter=4, textColor=colors.HexColor('#1a1a2e'))
SUBTITLE = ParagraphStyle('SubtitleX', parent=styles['Normal'], fontSize=11,
                           alignment=TA_CENTER, textColor=colors.HexColor('#444444'),
                           spaceAfter=3)
H1 = ParagraphStyle('H1X', parent=styles['Heading1'], fontSize=15,
                     spaceBefore=16, spaceAfter=8, textColor=colors.HexColor('#1a1a2e'),
                     borderWidth=0, borderColor=colors.HexColor('#4338ca'))
H2 = ParagraphStyle('H2X', parent=styles['Heading2'], fontSize=12,
                     spaceBefore=10, spaceAfter=6, textColor=colors.HexColor('#333355'))
BODY = ParagraphStyle('BodyX', parent=styles['Normal'], fontSize=10.3,
                       leading=15, spaceAfter=7, alignment=TA_LEFT)
CODE = ParagraphStyle('CodeX', parent=styles['Code'], fontSize=8.3,
                       leading=11, backColor=colors.HexColor('#f4f4f8'),
                       borderColor=colors.HexColor('#d0d0de'), borderWidth=0.6,
                       borderPadding=6, spaceAfter=10, spaceBefore=4)
TRANSCRIPT = ParagraphStyle('TranscriptX', parent=CODE,
                             backColor=colors.HexColor('#0f172a'),
                             textColor=colors.HexColor('#e2e8f0'))
TODO = ParagraphStyle('TodoX', parent=styles['Normal'], fontSize=9.5,
                       leading=13, backColor=colors.HexColor('#fff7e6'),
                       borderColor=colors.HexColor('#d97706'), borderWidth=0.8,
                       borderPadding=8, spaceAfter=10, spaceBefore=4,
                       textColor=colors.HexColor('#7c2d12'))
FOOTNOTE = ParagraphStyle('FootX', parent=styles['Italic'], fontSize=8.5,
                           alignment=TA_CENTER, textColor=colors.HexColor('#777777'))


def inline(text):
    """Minimal markdown inline -> reportlab mini-markup converter."""
    text = text.replace('&', '&amp;')
    # restore intentional entities we embed ourselves (e.g. non-breaking space markers)
    text = text.replace('&amp;nbsp;', '&nbsp;')
    text = re.sub(r'`([^`]+)`', r'<font face="Courier" color="#a21caf">\1</font>', text)
    text = re.sub(r'\*\*([^*]+)\*\*', r'<b>\1</b>', text)
    text = re.sub(r'\[([^\]]+)\]\(([^)]+)\)', r'<font color="#2563eb"><u>\1</u></font>', text)
    return text


def parse_markdown(md_text):
    """Very small parser tuned to our own report_source.md structure."""
    lines = md_text.split('\n')
    blocks = []
    i = 0
    n = len(lines)
    while i < n:
        line = lines[i]

        if line.startswith('```'):
            i += 1
            code_lines = []
            while i < n and not lines[i].startswith('```'):
                code_lines.append(lines[i])
                i += 1
            i += 1  # skip closing ```
            blocks.append(('code', '\n'.join(code_lines)))
            continue

        if line.strip() == '---':
            blocks.append(('hr', None))
            i += 1
            continue

        if line.startswith('# '):
            blocks.append(('title', line[2:].strip()))
            i += 1
            continue

        if line.startswith('## '):
            blocks.append(('h1', line[3:].strip()))
            i += 1
            continue

        if line.startswith('### '):
            blocks.append(('h2', line[4:].strip()))
            i += 1
            continue

        if line.strip().startswith('[ TODO') or line.strip().startswith('**[ TODO'):
            todo_lines = [line.strip()]
            i += 1
            while i < n and lines[i].strip() and not lines[i].startswith('#') and not lines[i].startswith('|') and not lines[i].startswith('```'):
                if lines[i].strip() == '---':
                    break
                todo_lines.append(lines[i].strip())
                i += 1
            blocks.append(('todo', ' '.join(todo_lines)))
            continue

        if line.strip().startswith('|'):
            table_lines = []
            while i < n and lines[i].strip().startswith('|'):
                table_lines.append(lines[i].strip())
                i += 1
            blocks.append(('table', table_lines))
            continue

        if line.strip() == '':
            i += 1
            continue

        # paragraph (collect until blank line / special marker)
        para_lines = [line]
        i += 1
        while i < n and lines[i].strip() != '' and not lines[i].startswith('#') \
                and not lines[i].startswith('```') and not lines[i].strip().startswith('|') \
                and lines[i].strip() != '---':
            para_lines.append(lines[i])
            i += 1
        blocks.append(('p', ' '.join(para_lines)))

    return blocks


def render_table(table_lines):
    rows = []
    for idx, tl in enumerate(table_lines):
        cells = [c.strip() for c in tl.strip('|').split('|')]
        if idx == 1 and all(re.match(r'^:?-+:?$', c) for c in cells):
            continue  # separator row
        rows.append(cells)
    header = rows[0]
    body = rows[1:]
    data = [[Paragraph(inline(c), ParagraphStyle('th', parent=BODY, fontSize=9,
                                                  textColor=colors.white)) for c in header]]
    for r in body:
        data.append([Paragraph(inline(c), ParagraphStyle('td', parent=BODY, fontSize=9)) for c in r])
    t = Table(data, hAlign='LEFT', repeatRows=1)
    t.setStyle(TableStyle([
        ('BACKGROUND', (0, 0), (-1, 0), colors.HexColor('#4338ca')),
        ('GRID', (0, 0), (-1, -1), 0.5, colors.HexColor('#cccccc')),
        ('ROWBACKGROUNDS', (0, 1), (-1, -1), [colors.white, colors.HexColor('#f6f6fb')]),
        ('VALIGN', (0, 0), (-1, -1), 'TOP'),
        ('LEFTPADDING', (0, 0), (-1, -1), 6),
        ('RIGHTPADDING', (0, 0), (-1, -1), 6),
        ('TOPPADDING', (0, 0), (-1, -1), 4),
        ('BOTTOMPADDING', (0, 0), (-1, -1), 4),
    ]))
    return t


# ----------------------------------------------------------------
# Native (vector) block diagrams -- one function per experiment
# ----------------------------------------------------------------
def box(d, x, y, w, h, fill, stroke, label_lines, title_size=8.5, body_size=7):
    d.add(Rect(x, y, w, h, fillColor=colors.HexColor(fill),
               strokeColor=colors.HexColor(stroke), strokeWidth=1.2, rx=4, ry=4))
    ty = y + h - 13
    for idx, (txt, bold, size) in enumerate(label_lines):
        d.add(String(x + w / 2.0, ty, txt, fontSize=size,
                      fontName='Helvetica-Bold' if bold else 'Helvetica',
                      fillColor=colors.HexColor('#1a1a2e') if bold else colors.HexColor('#444444'),
                      textAnchor='middle'))
        ty -= (size + 4)


def arrow(d, x1, y1, x2, y2):
    d.add(Line(x1, y1, x2, y2, strokeColor=colors.HexColor('#666666'), strokeWidth=1))


def diagram_experiment1():
    W, H = 480, 300
    d = Drawing(W, H)
    d.add(Rect(0, 0, W, H, fillColor=colors.white, strokeColor=colors.white))

    box(d, 10, 220, 95, 38, '#eef2ff', '#4338ca', [('BTN0 (rst)', True, 7.5), ('sync reset', False, 6.5)])
    box(d, 10, 170, 95, 38, '#eef2ff', '#4338ca', [('BTN1 (start)', True, 7.5), ('edge pulse', False, 6.5)])
    box(d, 10, 120, 95, 38, '#eef2ff', '#4338ca', [('clk (H16)', True, 7.5), ('125 MHz', False, 6.5)])

    box(d, 130, 120, 90, 38, '#fef3c7', '#b45309', [('Clock Divider', True, 7.5), ('tick ~5 Hz', False, 6.5)])

    box(d, 250, 150, 110, 90, '#dcfce7', '#15803d',
        [('FSM Controller', True, 8), ('IDLE->RUN->DONE', False, 6.5),
         ('idx 0..7', False, 6.5), ('fail_flag/idx', False, 6.5)])

    box(d, 250, 255, 110, 40, '#fae8ff', '#a21caf', [('Test ROM', True, 7.5), ('8 vectors', False, 6.5)])

    box(d, 390, 230, 80, 55, '#fee2e2', '#b91c1c', [('DUT', True, 8), ('alu4', True, 7.5), ('ADD/SUB/AND/OR', False, 6)])

    box(d, 390, 150, 80, 55, '#e0f2fe', '#0369a1', [('Comparator', True, 7.5), ('result==exp', False, 6.5)])

    box(d, 250, 40, 110, 55, '#fff7ed', '#c2410c',
        [('LED Display', True, 8), ('RUN: heartbeat|idx', False, 6.3), ('DONE: pass|fail_idx', False, 6.3)])

    arrow(d, 105, 239, 250, 200)
    arrow(d, 105, 189, 250, 190)
    arrow(d, 105, 139, 130, 139)
    arrow(d, 220, 139, 250, 170)
    arrow(d, 305, 255, 305, 240)
    arrow(d, 360, 275, 390, 258)
    arrow(d, 360, 190, 390, 257)
    arrow(d, 430, 230, 430, 205)
    arrow(d, 390, 177, 305, 195)
    arrow(d, 305, 150, 305, 95)

    d.add(String(W/2, H-16, "Automated Digital Circuit Tester -- Block Diagram",
                  fontSize=10.5, fontName='Helvetica-Bold', textAnchor='middle',
                  fillColor=colors.HexColor('#1a1a2e')))
    return d


def diagram_experiment2():
    W, H = 480, 330
    d = Drawing(W, H)
    d.add(Rect(0, 0, W, H, fillColor=colors.white, strokeColor=colors.white))

    box(d, 10, 220, 110, 55, '#fef3c7', '#b45309',
        [('Base Value Gen.', True, 7.5), ('triangle wave', False, 6.5), ('SW0 = freeze', False, 6.5)])

    box(d, 150, 260, 95, 30, '#eef2ff', '#4338ca', [('sensor1=base', True, 6.8)])
    box(d, 150, 225, 95, 30, '#eef2ff', '#4338ca', [('sensor2=base+3', True, 6.8)])
    box(d, 150, 190, 95, 30, '#eef2ff', '#4338ca', [('sensor3=base-3', True, 6.8)])

    box(d, 270, 260, 100, 30, '#fee2e2', '#b91c1c', [('BTN1 -> 0xFF', True, 6.8)])
    box(d, 270, 225, 100, 30, '#fee2e2', '#b91c1c', [('BTN2 -> 0x00', True, 6.8)])
    box(d, 270, 190, 100, 30, '#fee2e2', '#b91c1c', [('BTN3 -> +60 sat', True, 6.8)])

    box(d, 390, 190, 85, 100, '#e0f2fe', '#0369a1',
        [('Pairwise', True, 7.5), ('Deviation', True, 7.5), ('d12,d13,d23', False, 6.3),
         ('agreeX', False, 6.3), ('trust1/2/3', False, 6.3)])

    box(d, 150, 60, 150, 70, '#dcfce7', '#15803d',
        [('Trust Level +', True, 7.5), ('Bad-ID Logic', True, 7.5), ('NONE/LOW/MED/HIGH', False, 6.3)])

    box(d, 330, 60, 145, 70, '#fae8ff', '#a21caf',
        [('Priority Fusion', True, 7.5), ('fused_value =', False, 6.3), ('1st trusted sensor', False, 6.3)])

    box(d, 60, 10, 190, 38, '#fff7ed', '#c2410c', [('LED[3:0] Display', True, 7.5), ('trust|bad_id', False, 6.5)])

    arrow(d, 120, 260, 150, 275)
    arrow(d, 120, 247, 150, 240)
    arrow(d, 120, 235, 150, 205)
    arrow(d, 245, 275, 270, 275)
    arrow(d, 245, 240, 270, 240)
    arrow(d, 245, 205, 270, 205)
    arrow(d, 370, 275, 390, 260)
    arrow(d, 370, 240, 390, 245)
    arrow(d, 370, 205, 390, 230)
    arrow(d, 420, 190, 280, 110)
    arrow(d, 440, 190, 400, 130)
    arrow(d, 220, 60, 160, 48)

    d.add(String(W/2, H-16, "TrustFuse -- Block Diagram",
                  fontSize=10.5, fontName='Helvetica-Bold', textAnchor='middle',
                  fillColor=colors.HexColor('#1a1a2e')))
    return d


def diagram_experiment3():
    W, H = 480, 300
    d = Drawing(W, H)
    d.add(Rect(0, 0, W, H, fillColor=colors.white, strokeColor=colors.white))

    box(d, 10, 210, 110, 55, '#fef3c7', '#b45309', [('Temperature Model', True, 7.5), ('triangle wave', False, 6.5)])
    box(d, 150, 210, 100, 55, '#eef2ff', '#4338ca', [('Band Classifier', True, 7.5), ('LOW/MID/HIGH', False, 6.5)])
    box(d, 10, 130, 110, 65, '#fee2e2', '#b91c1c',
        [('Inputs', True, 7.5), ('BTN1-3=events', False, 6.3), ('SW1:0=mode', False, 6.3)])

    box(d, 280, 90, 190, 150, '#dcfce7', '#15803d',
        [('Fixed-Priority', True, 8), ('Rule Table', True, 8), ('R0 ALERT', False, 6.3),
         ('R1 THROTTLE', False, 6.3), ('R2 SAFE_MODE', False, 6.3), ('R3 CALIBRATE', False, 6.3),
         ('R4 BOOST', False, 6.3), ('R5 ECO_BOOST', False, 6.3), ('R6 LOG_EVENT', False, 6.3),
         ('R7 NONE (default)', False, 6.3)])

    box(d, 280, 20, 190, 50, '#fff7ed', '#c2410c', [('LED Display', True, 7.5), ('heartbeat + action', False, 6.5)])

    arrow(d, 120, 237, 150, 237)
    arrow(d, 120, 162, 280, 180)
    arrow(d, 250, 237, 280, 200)
    arrow(d, 375, 90, 375, 70)

    d.add(String(W/2, H-16, "CPU-FPGA Decision Engine -- Block Diagram",
                  fontSize=10.5, fontName='Helvetica-Bold', textAnchor='middle',
                  fillColor=colors.HexColor('#1a1a2e')))
    return d


def diagram_experiment4():
    W, H = 480, 310
    d = Drawing(W, H)
    d.add(Rect(0, 0, W, H, fillColor=colors.white, strokeColor=colors.white))

    box(d, 10, 230, 110, 50, '#fae8ff', '#a21caf', [('Test ROM', True, 7.5), ('8 vectors (Exp.1)', False, 6.3)])
    box(d, 160, 230, 130, 45, '#dcfce7', '#15803d', [('alu4 golden', True, 7.5), ('clean reference', False, 6.3)])
    box(d, 160, 160, 130, 50, '#fee2e2', '#b91c1c', [('Fault Wrapper', True, 7.5), ('a/b injection', False, 6.3)])
    box(d, 160, 95, 130, 45, '#fee2e2', '#b91c1c', [('alu4 faulted_core', True, 7.2), ('same DUT core', False, 6.3)])
    box(d, 10, 95, 110, 70, '#eef2ff', '#4338ca',
        [('Fault Config', True, 7.5), ('BTN1-3=target', False, 6.3), ('SW1:0=type', False, 6.3)])

    box(d, 330, 160, 140, 70, '#e0f2fe', '#0369a1', [('Comparator', True, 7.5), ('mismatch_count', False, 6.3)])
    box(d, 330, 70, 140, 70, '#fff7ed', '#c2410c',
        [('Free-running FSM', True, 7.3), ('RUN->DONE->RUN', False, 6.3), ('LED display', False, 6.3)])

    arrow(d, 120, 95+35, 160, 180)
    arrow(d, 120, 250, 160, 250)
    arrow(d, 290, 250, 320, 200)
    arrow(d, 290, 118, 320, 185)
    arrow(d, 400, 160, 400, 140)

    d.add(String(W/2, H-16, "FAULTX -- Block Diagram",
                  fontSize=10.5, fontName='Helvetica-Bold', textAnchor='middle',
                  fillColor=colors.HexColor('#1a1a2e')))
    return d


def diagram_experiment5():
    W, H = 480, 300
    d = Drawing(W, H)
    d.add(Rect(0, 0, W, H, fillColor=colors.white, strokeColor=colors.white))

    box(d, 10, 210, 140, 65, '#fef3c7', '#b45309',
        [('raw_bit_fn', True, 8), ('(PLACEHOLDER)', True, 6.8), ('see honest scope note', False, 6.3)])
    box(d, 175, 210, 130, 65, '#eef2ff', '#4338ca',
        [('K=5 Sampler', True, 7.5), ('1 bit/tick', False, 6.3), ('BTN3=noise', False, 6.3)])
    box(d, 330, 210, 140, 65, '#dcfce7', '#15803d',
        [('Majority Vote', True, 7.5), ('>=3-of-5', False, 6.3), ('"Adaptive" stage', False, 6.3)])

    box(d, 30, 110, 170, 65, '#fae8ff', '#a21caf',
        [('Enrollment Store', True, 7.5), ('storage_bits[4]', False, 6.3), ('BTN1=enroll', False, 6.3)])
    box(d, 240, 110, 170, 65, '#e0f2fe', '#0369a1',
        [('Auth Comparator', True, 7.5), ('vote==stored?', False, 6.3), ('BTN2=auth', False, 6.3)])

    box(d, 130, 30, 220, 55, '#fff7ed', '#c2410c',
        [('LED Display', True, 7.5), ('match | enrolled? | challenge', False, 6.3), ('SW1:0=challenge', False, 6.3)])

    arrow(d, 150, 242, 175, 242)
    arrow(d, 305, 242, 330, 242)
    arrow(d, 400, 210, 115, 175)
    arrow(d, 400, 210, 325, 175)
    arrow(d, 115, 110, 220, 85)
    arrow(d, 325, 110, 260, 85)

    d.add(String(W/2, H-16, "Adaptive PUF Authentication -- Block Diagram",
                  fontSize=10.5, fontName='Helvetica-Bold', textAnchor='middle',
                  fillColor=colors.HexColor('#1a1a2e')))
    return d


DIAGRAMS = {
    1: diagram_experiment1,
    2: diagram_experiment2,
    3: diagram_experiment3,
    4: diagram_experiment4,
    5: diagram_experiment5,
}


# ----------------------------------------------------------------
# Page decorations: header/footer with page numbers
# ----------------------------------------------------------------
def make_footer(team_line):
    def _footer(c: pdfcanvas.Canvas, doc):
        c.saveState()
        c.setFont('Helvetica', 8)
        c.setFillColor(colors.HexColor('#888888'))
        c.drawString(0.75 * inch, 0.5 * inch, team_line)
        c.drawRightString(LETTER[0] - 0.75 * inch, 0.5 * inch, f"Page {doc.page}")
        c.restoreState()
    return _footer


def build_pdf(md_path: Path, out_path: Path, exp_num: int):
    text = md_path.read_text(encoding='utf-8')
    blocks = parse_markdown(text)

    story = []
    title_done = False

    for kind, content in blocks:
        if kind == 'title':
            story.append(Paragraph(inline(content), TITLE))
            title_done = True
        elif kind == 'h1':
            if re.match(r'^\d+\.\s', content):
                story.append(HRFlowable(width="100%", thickness=0.6,
                                         color=colors.HexColor('#dddddd'), spaceBefore=2, spaceAfter=2))
            story.append(Paragraph(inline(content), H1))
            # inject the diagram right after the "Block Diagram" heading
            if content.strip().lower().startswith('2. block diagram'):
                story.append(Spacer(1, 4))
                story.append(DIAGRAMS[exp_num]())
                story.append(Spacer(1, 6))
        elif kind == 'h2':
            story.append(Paragraph(inline(content), H2))
        elif kind == 'p':
            if title_done and ('Team:' in content or '**Team:**' in content):
                story.append(Paragraph(inline(content), SUBTITLE))
            else:
                story.append(Paragraph(inline(content), BODY))
        elif kind == 'code':
            story.append(Preformatted(content, CODE))
        elif kind == 'table':
            story.append(render_table(content))
            story.append(Spacer(1, 8))
        elif kind == 'todo':
            cleaned = content.replace('**[ TODO', '[ TODO').replace(' ]**', ' ]')
            story.append(Paragraph('<b>&#9888; TO DO:</b> ' + inline(cleaned.lstrip('[').rstrip(']').replace('TODO', '', 1).strip(' -')), TODO))
        elif kind == 'hr':
            story.append(Spacer(1, 4))

    doc = SimpleDocTemplate(str(out_path), pagesize=LETTER,
                             topMargin=0.85 * inch, bottomMargin=0.85 * inch,
                             leftMargin=0.8 * inch, rightMargin=0.8 * inch,
                             title=md_path.stem)
    footer = make_footer("V-SPACE FPGA Build Challenge 2026 - Team Mahasena (Lead: Manaswi)")
    doc.build(story, onFirstPage=footer, onLaterPages=footer)
    print(f"Built: {out_path}")


if __name__ == '__main__':
    root = Path(r"C:\Users\siddh\FPGA-Build-Challenge-Manaswi")

    build_pdf(
        root / "Experiment-1-Beginner" / "Documentation" / "report_source.md",
        root / "Experiment-1-Beginner" / "Documentation" / "Experiment1_Automated_Digital_Circuit_Tester.pdf",
        1
    )
    build_pdf(
        root / "Experiment-2-Beginner" / "Documentation" / "report_source.md",
        root / "Experiment-2-Beginner" / "Documentation" / "Experiment2_TrustFuse_Hardware_Sensor_Trust.pdf",
        2
    )
    build_pdf(
        root / "Experiment-3-Intermediate" / "Documentation" / "report_source.md",
        root / "Experiment-3-Intermediate" / "Documentation" / "Experiment3_CPU_FPGA_Decision_Engine.pdf",
        3
    )
    build_pdf(
        root / "Experiment-4-Intermediate" / "Documentation" / "report_source.md",
        root / "Experiment-4-Intermediate" / "Documentation" / "Experiment4_FAULTX_HIL_Fault_Injection.pdf",
        4
    )
    build_pdf(
        root / "Experiment-5-Advanced" / "Documentation" / "report_source.md",
        root / "Experiment-5-Advanced" / "Documentation" / "Experiment5_Adaptive_PUF_Authentication.pdf",
        5
    )

from pathlib import Path

from reportlab.lib.pagesizes import A4, landscape
from reportlab.lib import colors
from reportlab.lib.units import mm
from reportlab.platypus import SimpleDocTemplate, Table, TableStyle, Paragraph, Spacer
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.lib.enums import TA_CENTER

OUTPUT_PATH = Path(__file__).with_name("llm_cheatsheet.pdf")

doc = SimpleDocTemplate(
    str(OUTPUT_PATH),
    pagesize=landscape(A4),
    leftMargin=10*mm, rightMargin=10*mm,
    topMargin=9*mm, bottomMargin=8*mm,
)

styles = getSampleStyleSheet()

BLACK = colors.HexColor('#222222')
GREY = colors.HexColor('#888888')
HEADER_BG = colors.HexColor('#333333')
SECTION_BG = colors.HexColor('#e0e0e0')
TASK_BG = colors.HexColor('#efefef')
RULE = colors.HexColor('#dddddd')
SECTION_RULE = colors.HexColor('#888888')
DESC_COLOR = '#666666'

title_style = ParagraphStyle('T', parent=styles['Title'], fontSize=16, spaceAfter=1*mm,
    textColor=BLACK, fontName='Helvetica-Bold')
subtitle_style = ParagraphStyle('Sub', parent=styles['Normal'], fontSize=8, spaceAfter=4*mm,
    textColor=GREY, alignment=TA_CENTER, fontName='Helvetica')
header_style = ParagraphStyle('H', parent=styles['Normal'], fontSize=10, fontName='Helvetica-Bold',
    textColor=colors.white, alignment=TA_CENTER, leading=13)
section_style = ParagraphStyle('Sec', parent=styles['Normal'], fontSize=9, fontName='Helvetica-Bold',
    textColor=colors.HexColor('#333333'), leading=12)

task_name_style = ParagraphStyle('TN', parent=styles['Normal'], fontSize=9, fontName='Helvetica-Bold',
    textColor=BLACK, leading=12)

model_style = ParagraphStyle('M', parent=styles['Normal'], fontSize=9, fontName='Helvetica',
    leading=12, textColor=colors.HexColor('#333333'))

footer_style = ParagraphStyle('F', parent=styles['Normal'], fontSize=8, fontName='Helvetica',
    textColor=colors.HexColor('#666666'), leading=10, alignment=TA_CENTER)

def P(text, style=model_style):
    return Paragraph(text, style)

def mc(model, effort="", detail=""):
    parts = f"{model}"
    if effort:
        parts += f" <i>{effort}</i>"
    if detail:
        parts += f"<br/><font size=8 color='{DESC_COLOR}'>{detail}</font>"
    return Paragraph(parts, model_style)

def pb(plan_model, plan_effort, build_model, build_effort, detail=""):
    text = f"{plan_model} <i>{plan_effort}</i> \u2192 {build_model} <i>{build_effort}</i>"
    if detail:
        text += f"<br/><font size=8 color='{DESC_COLOR}'>{detail}</font>"
    return Paragraph(text, model_style)

def tc(name, desc):
    return Paragraph(f"<b>{name}</b><br/><font size=8 color='{DESC_COLOR}'><i>{desc}</i></font>", task_name_style)

def section_row(label):
    return [Paragraph(label, section_style), P(""), P(""), P("")]

story = []

story.append(Paragraph("LLM Model Cheatsheet", title_style))
story.append(Paragraph("Plan \u2192 Build where shown", subtitle_style))

col_w = [62*mm, 70*mm, 64*mm, 74*mm]

headers = [
    P("", header_style),
    Paragraph("Volume", header_style),
    Paragraph("Balanced", header_style),
    Paragraph("Max", header_style),
]

data = [headers]

RUST_SEC = 1
data.append(section_row("RUST"))

data.append([
    tc("Code Changes", "refactors, bug fixes, simple features"),
    mc("DeepSeek V3.2", "", "tests, boilerplate, typed errors, existing patterns"),
    mc("Sonnet 4.6", "high", "ownership, generics, non-obvious bugs"),
    pb("Opus 4.6", "max", "GPT-5.4", "high", "soundness, perf, hard-to-diagnose failures"),
])

data.append([
    tc("Feature Impl", "multi-file, cross-module, new types/traits"),
    mc("DeepSeek V3.2", "", "existing patterns, config, CLI wiring"),
    pb("Sonnet 4.6", "high", "GPT-5.4", "medium", "most new features"),
    pb("Opus 4.6", "max", "GPT-5.4", "high", "cross-crate, unsafe, async + lifetimes"),
])

data.append([
    tc("Repo Maintenance", "Cargo.toml, deps, git, CI/CD, Dockerfile"),
    mc("DeepSeek V3.2", "", ""),
    P(""),
    P(""),
])

data.append([
    tc("Architecture / API", "crates, traits, modules, public API"),
    mc("DeepSeek V3.2", "", "brainstorming"),
    pb("Sonnet 4.6", "high", "GPT-5.4", "medium", "trait design, error types, module boundaries"),
    mc("GPT-5.4", "high", "multi-crate, plugin systems, semver"),
])

OPS_SEC = 6
data.append(section_row("OPS"))

data.append([
    tc("Linux / macOS Admin", "Nix, Arch, shell, Homebrew"),
    mc("DeepSeek V3.2"),
    mc("GPT-5.4", "medium", "complex Nix flakes, debugging subtle failures"),
    P(""),
])

data.append([
    tc("Investigate Alerts", "VictoriaMetrics, vmalert"),
    mc("DeepSeek V3.2", "", "rules, MetricsQL, routine troubleshooting"),
    mc("Sonnet 4.6", "high", "non-obvious root causes"),
    mc("Opus 4.6", "max", "after initial investigation fails"),
])

GEN_SEC = 9
data.append(section_row("GENERAL"))

data.append([
    tc("Research / Browsing", "docs, RFCs, crate eval"),
    mc("DeepSeek V3.2", "", "faster"),
    P(""),
    mc("ChatGPT Deep Research", "", "complex multi-source research; make Opus write the prompts "),
])

data.append([
    tc("Advice / Discussion", "rubber-ducking, tradeoffs"),
    mc("DeepSeek V3.2", "", "planning, brainstorming"),
    mc("GPT-5.4", "low/med", "assembling facts, rundowns"),
    mc("Opus 4.6", "max", "infers intent, challenges your thinking"),
])

table = Table(data, colWidths=col_w, repeatRows=1)

section_rows = {RUST_SEC, OPS_SEC, GEN_SEC}
last_before_section = {5, 8}

style_cmds = [
    # Header row
    ('BACKGROUND', (0, 0), (-1, 0), HEADER_BG),
    ('TEXTCOLOR', (0, 0), (-1, 0), colors.white),
    ('ALIGN', (0, 0), (-1, 0), 'CENTER'),
    ('TOPPADDING', (0, 0), (-1, 0), 8),
    ('BOTTOMPADDING', (0, 0), (-1, 0), 8),
    ('LEFTPADDING', (0, 0), (-1, 0), 6),
    ('RIGHTPADDING', (0, 0), (-1, 0), 6),

    # All body cells
    ('VALIGN', (0, 0), (-1, -1), 'MIDDLE'),
    ('LEFTPADDING', (0, 1), (-1, -1), 6),
    ('RIGHTPADDING', (0, 1), (-1, -1), 6),

    # Uniform outer box and inner grid
    ('BOX', (0, 0), (-1, -1), 0.75, colors.HexColor('#aaaaaa')),
    ('INNERGRID', (0, 0), (-1, -1), 0.25, RULE),

    # Strong line below header
    ('LINEBELOW', (0, 0), (-1, 0), 0.75, HEADER_BG),
    # Header outer edges match header bg (override BOX)
    ('LINEABOVE', (0, 0), (-1, 0), 0.75, HEADER_BG),
    ('LINEBEFORE', (0, 0), (0, 0), 0.75, HEADER_BG),
    ('LINEAFTER', (-1, 0), (-1, 0), 0.75, HEADER_BG),
    # Header inner verticals match header bg
    ('LINEAFTER', (0, 0), (2, 0), 0.25, HEADER_BG),

    # Stronger vertical line between task and model columns
    ('LINEAFTER', (0, 1), (0, -1), 0.75, colors.HexColor('#aaaaaa')),

    # Section header rows
    ('SPAN', (0, RUST_SEC), (-1, RUST_SEC)),
    ('SPAN', (0, OPS_SEC), (-1, OPS_SEC)),
    ('SPAN', (0, GEN_SEC), (-1, GEN_SEC)),

    ('BACKGROUND', (0, RUST_SEC), (-1, RUST_SEC), SECTION_BG),
    ('BACKGROUND', (0, OPS_SEC), (-1, OPS_SEC), SECTION_BG),
    ('BACKGROUND', (0, GEN_SEC), (-1, GEN_SEC), SECTION_BG),

    ('TOPPADDING', (0, RUST_SEC), (-1, RUST_SEC), 5),
    ('BOTTOMPADDING', (0, RUST_SEC), (-1, RUST_SEC), 5),
    ('TOPPADDING', (0, OPS_SEC), (-1, OPS_SEC), 5),
    ('BOTTOMPADDING', (0, OPS_SEC), (-1, OPS_SEC), 5),
    ('TOPPADDING', (0, GEN_SEC), (-1, GEN_SEC), 5),
    ('BOTTOMPADDING', (0, GEN_SEC), (-1, GEN_SEC), 5),

    ('LINEABOVE', (0, OPS_SEC), (-1, OPS_SEC), 0.75, SECTION_RULE),
    ('LINEABOVE', (0, GEN_SEC), (-1, GEN_SEC), 0.75, SECTION_RULE),
    ('LINEBELOW', (0, RUST_SEC), (-1, RUST_SEC), 0.5, SECTION_RULE),
    ('LINEBELOW', (0, OPS_SEC), (-1, OPS_SEC), 0.5, SECTION_RULE),
    ('LINEBELOW', (0, GEN_SEC), (-1, GEN_SEC), 0.5, SECTION_RULE),

    # Merged cells
    ('SPAN', (1, 4), (3, 4)),   # Repo Maintenance: Volume spans all
    ('SPAN', (2, 7), (3, 7)),   # Linux Admin: Balanced spans into Max
    ('SPAN', (1, 10), (2, 10)), # Research: Volume spans into Balanced
]

for i in range(1, len(data)):
    if i in section_rows:
        continue
    style_cmds.append(('BACKGROUND', (0, i), (0, i), TASK_BG))
    style_cmds.append(('BACKGROUND', (1, i), (-1, i), colors.white))
    style_cmds.append(('TOPPADDING', (0, i), (-1, i), 7))
    if i in last_before_section:
        style_cmds.append(('BOTTOMPADDING', (0, i), (-1, i), 10))
    else:
        style_cmds.append(('BOTTOMPADDING', (0, i), (-1, i), 7))

table.setStyle(TableStyle(style_cmds))
story.append(table)

# Footer as a clean horizontal table
story.append(Spacer(1, 5*mm))

foot_cell = ParagraphStyle('FC', parent=styles['Normal'], fontSize=8, fontName='Helvetica',
    textColor=colors.HexColor('#666666'), leading=10, alignment=TA_CENTER)

footer_data = [[
    Paragraph("Claude Pro $20/mo \u2022 resets every 5h", foot_cell),
    Paragraph("ChatGPT Plus $20/mo \u2022 weekly quota", foot_cell),
    Paragraph("DeepSeek V3.2 API \u2022 ~$3\u20135/mo", foot_cell),
]]

footer_table = Table(footer_data, colWidths=[90*mm, 90*mm, 90*mm])
footer_table.setStyle(TableStyle([
    ('ALIGN', (0, 0), (-1, -1), 'CENTER'),
    ('VALIGN', (0, 0), (-1, -1), 'MIDDLE'),
    ('TOPPADDING', (0, 0), (-1, 0), 3),
    ('BOTTOMPADDING', (0, 0), (-1, 0), 0),
]))
story.append(footer_table)

doc.build(story)
print(f"Done! Wrote {OUTPUT_PATH}")

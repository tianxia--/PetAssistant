#!/usr/bin/env python3
"""把文件解析成纯文本,供二蛋喂给模型分析。
用法:file_extract.py <文件路径>   → stdout 打印提取到的文本(截断)。
支持:纯文本/代码/日志/csv/json/md 直接读;pdf(pypdf);docx(python-docx)。
图片不在这里处理(由 Swift 走 base64 image_url)。
"""
import sys, os

MAX_CHARS = 12000   # 截断,别把上下文撑爆

TEXT_EXT = {".txt", ".md", ".markdown", ".log", ".csv", ".tsv", ".json", ".yaml", ".yml",
            ".xml", ".html", ".htm", ".ini", ".conf", ".toml", ".sql",
            ".py", ".js", ".ts", ".tsx", ".jsx", ".swift", ".java", ".kt", ".kts",
            ".c", ".h", ".cpp", ".cc", ".hpp", ".m", ".mm", ".go", ".rs", ".rb",
            ".php", ".sh", ".zsh", ".bash", ".gradle", ".properties", ".env"}


def extract(path):
    if not os.path.isfile(path):
        return f"[读取失败:文件不存在 {path}]"
    ext = os.path.splitext(path)[1].lower()
    try:
        if ext == ".pdf":
            from pypdf import PdfReader
            r = PdfReader(path)
            return "\n".join((pg.extract_text() or "") for pg in r.pages)
        if ext == ".docx":
            import docx
            d = docx.Document(path)
            return "\n".join(p.text for p in d.paragraphs)
        if ext in TEXT_EXT or ext == "":
            with open(path, "r", encoding="utf-8", errors="replace") as f:
                return f.read()
        # 其它:尝试当文本读,读不了就明确报错(交给上层提示用户)
        with open(path, "rb") as f:
            head = f.read(4096)
        if b"\x00" in head:
            return f"[不支持的文件类型 {ext or '(无扩展名)'}:看起来是二进制,无法当文本分析]"
        with open(path, "r", encoding="utf-8", errors="replace") as f:
            return f.read()
    except Exception as e:
        return f"[解析失败:{type(e).__name__}: {e}]"


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("usage: file_extract.py <path>", file=sys.stderr)
        sys.exit(1)
    text = extract(sys.argv[1]).strip()
    if len(text) > MAX_CHARS:
        text = text[:MAX_CHARS] + f"\n\n[…内容较长,已截断,共约 {len(text)} 字]"
    print(text if text else "[文件为空或无可提取文本]")

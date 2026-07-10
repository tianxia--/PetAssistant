#!/usr/bin/env python3
"""二蛋的向量记忆服务(本地、无 torch)。
后端:fastembed(onnxruntime)做多语言向量 + Zvec 存储/检索(FLAT+COSINE)。

用法:
  mem_service.py ingest              # 增量把 pet-data 里的记忆建进索引
  mem_service.py recall "问题" [k]   # 打印 top-k 相关记忆(JSON)
  mem_service.py serve [port]        # 常驻:HTTP 服务 /recall /ingest(模型只加载一次)

记忆来源:about-you.md / tasks.md / inbox.md / daily/*.md
"""
import sys, os, json, hashlib, glob, re

HERE = os.path.dirname(os.path.abspath(__file__))
PET_DATA = os.path.abspath(os.path.join(HERE, "..", "..", "pet-data"))
INDEX_DIR = os.path.join(HERE, "index")
MANIFEST = os.path.join(HERE, "index_manifest.json")
MODEL = "jinaai/jina-embeddings-v2-base-zh"   # 中英双语专门优化(768维)

_emb = None
_col = None


def log(*a):
    print(*a, file=sys.stderr, flush=True)


def get_emb():
    global _emb
    if _emb is None:
        from fastembed import TextEmbedding
        _emb = TextEmbedding(model_name=MODEL)
    return _emb


def embed(texts):
    return [list(map(float, v)) for v in get_emb().embed(list(texts))]


def _sources():
    """产出 (src标签, 文本) 列表。每条记忆一小块。"""
    out = []

    def add(src, text):
        text = text.strip()
        if len(text) >= 4:
            out.append((src, text))

    # 注意:inbox 是原始流水(含大量碎话/情绪句),信息密度低,不进语义索引——
    # 只索引已沉淀的记忆(tasks / about-you / daily)。最近几句由对话历史兜底。
    # tasks:每个条目一块
    p = os.path.join(PET_DATA, "tasks.md")
    if os.path.exists(p):
        for line in open(p, encoding="utf-8"):
            s = line.strip()
            if s.startswith("- "):
                add("任务", s[2:])
    # about-you:每个要点一块
    p = os.path.join(PET_DATA, "about-you.md")
    if os.path.exists(p):
        for line in open(p, encoding="utf-8"):
            s = line.strip()
            if s.startswith("- "):
                add("关于你", s[2:])
    # daily:每行有内容的一块
    for p in sorted(glob.glob(os.path.join(PET_DATA, "daily", "*.md"))):
        date = os.path.basename(p)[:-3]
        for line in open(p, encoding="utf-8"):
            s = line.strip().lstrip("#-* ").strip()
            if len(s) >= 6 and not s.startswith(">"):
                add(f"日报{date}", s)
    return out


def _doc_id(src, text):
    return hashlib.sha1((src + ":" + text).encode("utf-8")).hexdigest()[:16]


def open_col(create_ok=True):
    global _col
    if _col is not None:
        return _col
    import zvec
    coll_path = os.path.join(INDEX_DIR, "mem.zvec")
    if os.path.exists(coll_path):
        _col = zvec.open(coll_path)
        return _col
    if not create_ok:
        return None
    os.makedirs(INDEX_DIR, exist_ok=True)
    dim = len(embed(["维度探测"])[0])
    schema = zvec.CollectionSchema(
        name="mem",
        fields=[zvec.FieldSchema("text", zvec.DataType.STRING,
                                 index_param=zvec.FtsIndexParam(tokenizer_name="jieba")),  # 关键词/全文(中文 jieba 分词)
                zvec.FieldSchema("src", zvec.DataType.STRING)],
        vectors=[zvec.VectorSchema("vec", zvec.DataType.VECTOR_FP32, dimension=dim,
                 index_param=zvec.FlatIndexParam(metric_type=zvec.MetricType.COSINE))],
    )
    _col = zvec.create_and_open(coll_path, schema)
    return _col


def load_manifest():
    if os.path.exists(MANIFEST):
        try:
            return set(json.load(open(MANIFEST)))
        except Exception:
            return set()
    return set()


def save_manifest(ids):
    json.dump(sorted(ids), open(MANIFEST, "w"))


def ingest():
    import zvec
    col = open_col()
    seen = load_manifest()
    items = _sources()
    fresh = [(s, t) for (s, t) in items if _doc_id(s, t) not in seen]
    if not fresh:
        log(f"索引已最新,共 {len(seen)} 条,无新增")
        return {"total": len(seen), "added": 0}
    vecs = embed([f"{s}: {t}" for (s, t) in fresh])
    docs = []
    for (s, t), v in zip(fresh, vecs):
        did = _doc_id(s, t)
        docs.append(zvec.Doc(id=did, vectors={"vec": v}, fields={"text": t, "src": s}))
        seen.add(did)
    col.upsert(docs)
    col.flush()
    save_manifest(seen)
    log(f"新增 {len(fresh)} 条,索引共 {len(seen)} 条")
    return {"total": len(seen), "added": len(fresh)}


def recall(query, k=5):
    import zvec
    query = (query or "").strip()
    if not query:
        return []
    col = open_col(create_ok=False)
    if col is None:
        return []
    qv = embed([query])[0]
    # 混合检索:向量(语义)+ FTS(关键词/专有名词),用 RRF 融合两路排名
    vq = zvec.Query(field_name="vec", vector=qv)
    fq = zvec.Query(field_name="text", fts=zvec.Fts(match_string=query))
    res = col.query(queries=[vq, fq], topk=int(k), output_fields=["text", "src"],
                    reranker=zvec.RrfReRanker())
    out = []
    for d in res:
        out.append({"src": d.fields.get("src", ""), "text": d.fields.get("text", ""),
                    "score": round(float(d.score), 4)})   # RRF 分,越大越相关
    return out


def serve(port=8790):
    from http.server import BaseHTTPRequestHandler, HTTPServer
    get_emb(); open_col()      # 预热:模型+索引只加载一次
    ingest()

    class H(BaseHTTPRequestHandler):
        def log_message(self, *a):
            pass

        def _json(self, obj, code=200):
            b = json.dumps(obj, ensure_ascii=False).encode("utf-8")
            self.send_response(code)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Content-Length", str(len(b)))
            self.end_headers()
            self.wfile.write(b)

        def do_POST(self):
            n = int(self.headers.get("Content-Length", 0))
            body = json.loads(self.rfile.read(n) or b"{}")
            try:
                if self.path == "/recall":
                    self._json({"results": recall(body.get("query", ""), body.get("k", 5))})
                elif self.path == "/ingest":
                    self._json(ingest())
                else:
                    self._json({"error": "unknown path"}, 404)
            except Exception as e:
                self._json({"error": str(e)}, 500)

    log(f"记忆服务已就绪 http://127.0.0.1:{port}")
    HTTPServer(("127.0.0.1", int(port)), H).serve_forever()


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else "recall"
    if cmd == "ingest":
        print(json.dumps(ingest(), ensure_ascii=False))
    elif cmd == "recall":
        q = sys.argv[2] if len(sys.argv) > 2 else ""
        k = sys.argv[3] if len(sys.argv) > 3 else 5
        print(json.dumps(recall(q, k), ensure_ascii=False))
    elif cmd == "serve":
        serve(sys.argv[2] if len(sys.argv) > 2 else 8790)
    else:
        print("usage: mem_service.py [ingest|recall <q> [k]|serve [port]]", file=sys.stderr)
        sys.exit(1)
